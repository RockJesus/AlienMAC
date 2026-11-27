//
//  UpdateChecker.swift
//  AlienMAC
//
//  检查 GitHub Releases 上的新版本，支持启动自动检查与手动检查
//

import Foundation
import AppKit

final class UpdateChecker: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate(String)
        case available(version: String, notes: String, pageURL: URL, downloadURL: URL?)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    /// 自动检查（默认开），间隔 12 小时
    @Published var autoCheckEnabled: Bool {
        didSet { UserDefaults.standard.set(autoCheckEnabled, forKey: Keys.autoCheck) }
    }

    private let repo = "RockJesus/AlienMAC"
    private let checkInterval: TimeInterval = 12 * 3600

    private enum Keys {
        static let autoCheck = "AlienMAC.autoCheckUpdate"
        static let lastCheck = "AlienMAC.lastUpdateCheck"
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    override init() {
        if UserDefaults.standard.object(forKey: Keys.autoCheck) == nil {
            autoCheckEnabled = true
        } else {
            autoCheckEnabled = UserDefaults.standard.bool(forKey: Keys.autoCheck)
        }
        super.init()
    }

    /// 启动时调用：自动检查开启且距上次检查超过 12 小时才发请求
    func checkOnLaunchIfNeeded() {
        guard autoCheckEnabled else { return }
        let last = UserDefaults.standard.double(forKey: Keys.lastCheck)
        guard Date().timeIntervalSince1970 - last > checkInterval else { return }
        check()
    }

    func check() {
        guard state != .checking else { return }
        state = .checking

        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AlienMAC/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            DispatchQueue.main.async {
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Keys.lastCheck)

                if let error {
                    self.state = .failed(error.localizedDescription)
                    return
                }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String else {
                    self.state = .failed("返回内容无法解析")
                    return
                }

                let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let notes = (json["body"] as? String) ?? ""
                let page = (json["html_url"] as? String).flatMap(URL.init(string:))
                    ?? URL(string: "https://github.com/\(self.repo)/releases")!

                var download: URL?
                if let assets = json["assets"] as? [[String: Any]] {
                    let dmg = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
                    download = (dmg?["browser_download_url"] as? String).flatMap(URL.init(string:))
                }

                if Self.isNewer(latest, than: Self.currentVersion) {
                    self.state = .available(version: latest, notes: notes, pageURL: page, downloadURL: download)
                } else {
                    self.state = .upToDate(latest)
                }
            }
        }.resume()
    }

    /// 语义化版本比较：1.2.3 > 1.2.2，1.3.0 > 1.2.9
    static func isNewer(_ remote: String, than local: String) -> Bool {
        let a = remote.split(separator: ".").map { Int($0) ?? 0 }
        let b = local.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    func openDownloadPage() {
        guard case .available(_, _, let page, let download) = state else { return }
        NSWorkspace.shared.open(download ?? page)
    }

    func openReleasePage() {
        guard case .available(_, _, let page, _) = state else { return }
        NSWorkspace.shared.open(page)
    }

    // MARK: - 一键自更新：下载 → 校验 → 替换 → 重启

    @Published private(set) var isInstalling = false
    @Published private(set) var installStage = ""
    @Published private(set) var installProgress: Double = 0
    @Published private(set) var installError: String?

    private var installSession: URLSession?
    private var pendingVersion = ""
    private var candidates: [URL] = []
    private var candidateIndex = 0
    private var lastProgressAt = Date()
    private var lastProgressBytes: Int64 = 0
    private var stallTimer: Timer?
    private var currentHost = ""

    /// 国内常见的 GitHub 加速前缀；直连优先参与测速，谁快用谁
    static let mirrorPrefixes = [
        "https://ghfast.top/",
        "https://gh-proxy.com/",
        "https://ghproxy.net/"
    ]

    /// 点一下就把新版装上：多线路测速 → 下 dmg → 校验 → 解出 app → 校验签名/版本 → 替换正在运行的 bundle → 重启
    func installUpdate() {
        guard !isInstalling else { return }
        guard case .available(let version, _, _, let downloadURL?) = state else {
            installError = "这个版本没有可下载的 dmg，请到发布页手动下载"
            return
        }
        isInstalling = true
        installError = nil
        installStage = "正在测速选择下载线路"
        installProgress = 0
        pendingVersion = version

        let urls = Self.candidateURLs(for: downloadURL)
        Task { [weak self] in
            let ranked = await Self.rankBySpeed(urls)
            await MainActor.run {
                guard let self, self.isInstalling else { return }
                self.candidates = ranked.isEmpty ? urls : ranked
                self.candidateIndex = 0
                self.startNextCandidate()
            }
        }
    }

    /// 候选下载地址：用户自定义镜像 > 直连 > 各加速站
    static func candidateURLs(for url: URL) -> [URL] {
        var list: [URL] = []
        if let custom = UserDefaults.standard.string(forKey: "AlienMAC.updateMirror"),
           !custom.isEmpty,
           let customURL = URL(string: custom + url.absoluteString) {
            list.append(customURL)
        }
        list.append(url)
        for prefix in mirrorPrefixes {
            if let u = URL(string: prefix + url.absoluteString), !list.contains(u) { list.append(u) }
        }
        return list
    }

    /// 并发测速：每个线路抓 ~1MB 看速度，按速度排序；全失败就保持原顺序
    static func rankBySpeed(_ urls: [URL]) async -> [URL] {
        let speeds: [(URL, Double)] = await withTaskGroup(of: (URL, Double).self) { group in
            for url in urls {
                group.addTask { (url, await probeSpeed(url) ?? 0) }
            }
            var out: [(URL, Double)] = []
            for await item in group { out.append(item) }
            return out
        }
        let alive = speeds.filter { $0.1 > 0 }
        guard !alive.isEmpty else { return [] }
        let direct = alive.filter { $0.0.host == "github.com" }
        let mirrors = alive.filter { $0.0.host != "github.com" }.sorted { $0.1 > $1.1 }
        // 加速站通常比直连快很多；直连只有快到 1.5 倍以上才压过镜像
        if let d = direct.first, d.1 > (mirrors.first?.1 ?? 0) * 1.5 {
            return [d.0] + mirrors.map { $0.0 }
        }
        return mirrors.map { $0.0 } + direct.map { $0.0 }
    }

    /// 抓 1MB 测速度（MB/s），失败返回 nil
    static func probeSpeed(_ url: URL) async -> Double? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue("bytes=0-786431", forHTTPHeaderField: "Range")
        request.setValue("AlienMAC/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let started = Date()
        do {
            let (stream, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 206 || http.statusCode == 200 else { return nil }
            var received = 0
            for try await _ in stream {
                received += 1
                if received >= 786_432 { break }
            }
            let dt = max(Date().timeIntervalSince(started), 0.05)
            guard received > 32_768 else { return nil }    // 只回了错误页/极少数据，算不可用
            return Double(received) / 1_000_000 / dt
        } catch {
            return nil
        }
    }

    private func startNextCandidate() {
        guard candidateIndex < candidates.count else {
            fail("所有下载线路都不可用，请点「下载 dmg 到浏览器」手动下载")
            return
        }
        let url = candidates[candidateIndex]
        candidateIndex += 1
        let host = url.host ?? "线路"
        currentHost = host
        installStage = "正在从 \(host) 下载 v\(pendingVersion)"
        lastProgressAt = Date()
        lastProgressBytes = 0

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("AlienMAC/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        installSession = session
        session.downloadTask(with: request).resume()
        startStallWatch()
    }

    /// 30 秒没进度就换下一条线路
    private func startStallWatch() {
        stallTimer?.invalidate()
        stallTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.isInstalling else { return }
            if Date().timeIntervalSince(self.lastProgressAt) > 30 {
                self.installSession?.invalidateAndCancel()
                self.installSession = nil
                self.startNextCandidate()
            }
        }
    }

    private func stopWatching() {
        stallTimer?.invalidate()
        stallTimer = nil
    }

    private func fail(_ message: String) {
        DispatchQueue.main.async {
            self.stopWatching()
            self.installError = message
            self.installStage = "更新失败"
            self.isInstalling = false
            self.installSession?.invalidateAndCancel()
            self.installSession = nil
        }
    }

    /// 下载完成后在后台做校验/替换
    private func stageAndInstall(dmg: URL, version: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            func report(_ text: String, _ progress: Double) {
                DispatchQueue.main.async {
                    self.installStage = text
                    self.installProgress = progress
                }
            }

            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("AlienMACUpdate", isDirectory: true)
            try? fm.createDirectory(at: work, withIntermediateDirectories: true)

            // 1. 整包校验
            report("正在校验安装包", 0.45)
            let verify = Self.run(["/usr/bin/hdiutil", "verify", dmg.path])
            guard verify == 0 else {
                // 这条线路给的不是完整 dmg（镜像返回了错误页之类），换下一条重下
                try? fm.removeItem(at: dmg)
                DispatchQueue.main.async {
                    if self.candidateIndex < self.candidates.count {
                        self.startNextCandidate()
                    } else {
                        self.fail("安装包校验失败（所有线路都试过了）")
                    }
                }
                return
            }

            // 2. 挂载
            report("正在挂载安装包", 0.55)
            let mount = work.appendingPathComponent("mnt")
            try? fm.removeItem(at: mount)
            guard Self.run(["/usr/bin/hdiutil", "attach", dmg.path, "-nobrowse", "-readonly", "-quiet", "-mountpoint", mount.path]) == 0 else {
                return self.fail("挂载安装包失败")
            }
            defer { _ = Self.run(["/usr/bin/hdiutil", "detach", mount.path, "-quiet"]) }

            let srcApp = mount.appendingPathComponent("AlienMAC.app")
            guard fm.fileExists(atPath: srcApp.path) else { return self.fail("安装包里没找到 AlienMAC.app") }

            // 3. 解到暂存目录
            report("正在准备新版本", 0.65)
            let stage = work.appendingPathComponent("AlienMAC.app")
            try? fm.removeItem(at: stage)
            guard Self.run(["/usr/bin/ditto", srcApp.path, stage.path]) == 0 else {
                return self.fail("解压新版本失败")
            }

            // 4. 版本 + 签名双校验，防止半截包
            report("正在校验新版本签名", 0.75)
            let plist = stage.appendingPathComponent("Contents/Info.plist")
            let stagedVersion = Self.runOutput(["/usr/libexec/PlistBuddy", "-c", "Print :CFBundleShortVersionString", plist.path])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard stagedVersion == version else {
                return self.fail("版本不符：包内 \(stagedVersion)，期望 \(version)")
            }
            guard Self.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", stage.path]) == 0 else {
                return self.fail("新版本签名无效，已中止（旧版本未动）")
            }

            // 5. 写替换脚本，脚本等本进程退出后换 bundle 再拉起
            report("正在替换并重启", 0.9)
            let target = Self.installTarget()
            let script = work.appendingPathComponent("selfupdate.sh")
            let scriptBody = """
            #!/bin/bash
            exec >>"\(work.path)/selfupdate.log" 2>&1
            TARGET="$1"
            STAGE="$2"
            echo "[$(date)] target=$TARGET"
            # 等旧进程彻底退出，最多 15 秒，之后就强杀
            for i in $(seq 1 60); do pgrep -x AlienMAC >/dev/null || break; sleep 0.25; done
            pgrep -x AlienMAC >/dev/null && pkill -9 -x AlienMAC
            sleep 1
            rm -rf "$TARGET.old"
            if [ -d "$TARGET" ]; then mv "$TARGET" "$TARGET.old" || { echo "move fail"; open -a "$TARGET"; exit 1; }; fi
            if ditto "$STAGE" "$TARGET" && codesign --verify --deep --strict "$TARGET" >/dev/null 2>&1; then
              xattr -cr "$TARGET"
              open -a "$TARGET"
              for i in $(seq 1 40); do sleep 0.5; pgrep -x AlienMAC >/dev/null && break; done
              GOT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$TARGET/Contents/Info.plist" 2>/dev/null)
              if pgrep -x AlienMAC >/dev/null && [ "$GOT" = "$3" ]; then
                rm -rf "$TARGET.old" "$STAGE"; echo "installed ok"
              else
                echo "new app not running, rollback"
                rm -rf "$TARGET"; [ -d "$TARGET.old" ] && mv "$TARGET.old" "$TARGET"; open -a "$TARGET"
              fi
            else
              echo "install failed, rollback"
              rm -rf "$TARGET"; [ -d "$TARGET.old" ] && mv "$TARGET.old" "$TARGET"; open -a "$TARGET"
            fi
            """
            do {
                try scriptBody.write(to: script, atomically: true, encoding: .utf8)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            } catch {
                return self.fail("写入替换脚本失败：\(error.localizedDescription)")
            }

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = [script.path, target.path, stage.path, version]
            do { try task.run() } catch {
                return self.fail("启动替换脚本失败：\(error.localizedDescription)")
            }

            DispatchQueue.main.async {
                self.installStage = "正在重启到 v\(version)"
                self.installProgress = 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    NSApp.terminate(nil)
                    // 万一 terminate 被别的窗口/面板挡住，3 秒后强退，保证替换脚本能干活
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
                }
            }
        }
    }

    /// 要替换的 bundle：正常在 /Applications 就地换；从 DMG / 只读位置跑就换 /Applications
    static func installTarget() -> URL {
        let current = Bundle.main.bundleURL
        if current.path.hasPrefix("/Applications/"), FileManager.default.isWritableFile(atPath: "/Applications") {
            return current
        }
        let fm = FileManager.default
        if fm.isWritableFile(atPath: "/Applications") {
            return URL(fileURLWithPath: "/Applications/AlienMAC.app")
        }
        return current
    }

    static func run(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: args[0])
        p.arguments = Array(args.dropFirst())
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    static func runOutput(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: args[0])
        p.arguments = Array(args.dropFirst())
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - 下载进度

extension UpdateChecker: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let ratio = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let now = Date()
        DispatchQueue.main.async {
            self.lastProgressAt = now
            self.lastProgressBytes = totalBytesWritten
            self.installStage = "正在从 \(self.currentHost) 下载 \(ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: totalBytesExpectedToWrite, countStyle: .file))"
            self.installProgress = min(ratio * 0.4, 0.4)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let keep = FileManager.default.temporaryDirectory
            .appendingPathComponent("AlienMAC-\(pendingVersion).dmg")
        try? FileManager.default.removeItem(at: keep)
        do { try FileManager.default.moveItem(at: location, to: keep) } catch {
            return fail("下载文件保存失败：\(error.localizedDescription)")
        }
        session.invalidateAndCancel()
        DispatchQueue.main.async { self.stopWatching() }
        installSession = nil
        stageAndInstall(dmg: keep, version: pendingVersion)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        // 已经换线路时，旧任务的取消回调直接忽略
        if let taskURL = task.originalRequest?.url,
           self.candidateIndex > 0,
           taskURL != self.candidates[self.candidateIndex - 1] { return }
        DispatchQueue.main.async {
            guard self.isInstalling else { return }
            self.installSession = nil
            // 这条线路挂了，还有候选就换下一条
            if self.candidateIndex < self.candidates.count {
                self.startNextCandidate()
            } else {
                self.fail("下载失败：\(error.localizedDescription)")
            }
        }
    }
}
