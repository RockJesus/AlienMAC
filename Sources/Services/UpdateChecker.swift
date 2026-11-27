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

    /// 点一下就把新版装上：下 dmg → 校验 → 解出 app → 校验签名/版本 → 替换正在运行的 bundle → 重启
    func installUpdate() {
        guard !isInstalling else { return }
        guard case .available(let version, _, _, let downloadURL?) = state else {
            installError = "这个版本没有可下载的 dmg，请到发布页手动下载"
            return
        }
        isInstalling = true
        installError = nil
        installStage = "准备下载 v\(version)"
        installProgress = 0
        pendingVersion = version

        var request = URLRequest(url: downloadURL)
        request.timeoutInterval = 60
        request.setValue("AlienMAC/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        installSession = session
        session.downloadTask(with: request).resume()
    }

    private func fail(_ message: String) {
        DispatchQueue.main.async {
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
            guard verify == 0 else { return self.fail("安装包校验失败（hdiutil verify）") }

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
            # 等旧进程彻底退出
            for i in $(seq 1 80); do pgrep -x AlienMAC >/dev/null || break; sleep 0.25; done
            rm -rf "$TARGET.old"
            if [ -d "$TARGET" ]; then mv "$TARGET" "$TARGET.old" || { echo "move fail"; open -a "$TARGET"; exit 1; }; fi
            if ditto "$STAGE" "$TARGET" && codesign --verify --deep --strict "$TARGET" >/dev/null 2>&1; then
              xattr -cr "$TARGET"
              open -a "$TARGET"
              for i in $(seq 1 40); do sleep 0.5; pgrep -x AlienMAC >/dev/null && break; done
              if pgrep -x AlienMAC >/dev/null; then
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
            task.arguments = [script.path, target.path, stage.path]
            do { try task.run() } catch {
                return self.fail("启动替换脚本失败：\(error.localizedDescription)")
            }

            DispatchQueue.main.async {
                self.installStage = "正在重启到 v\(version)"
                self.installProgress = 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    NSApp.terminate(nil)
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
        DispatchQueue.main.async {
            self.installStage = "正在下载 \(ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: totalBytesExpectedToWrite, countStyle: .file))"
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
        installSession = nil
        stageAndInstall(dmg: keep, version: pendingVersion)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        fail("下载失败：\(error.localizedDescription)")
    }
}
