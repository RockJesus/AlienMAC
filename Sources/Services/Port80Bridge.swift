//
//  Port80Bridge.swift
//  AlienMAC
//
//  「无端口访问」：把 80 端口借给 App 的 Web 服务，手机只输 alien.local 就能打开。
//  普通进程绑不了 1024 以下的端口，所以这里装一个 LaunchDaemon（root）跑极简转发器，
//  只在用户点「启用」时装一次，要输一次管理员密码；随时可以关掉。
//

import Foundation
import Combine

final class Port80Bridge: ObservableObject {

    static let shared = Port80Bridge()

    static let label = "com.alienmac.web80"
    static let plistPath = "/Library/LaunchDaemons/com.alienmac.web80.plist"
    static let helperName = "AlienMACPort80"

    /// 是否已装上转发守护（看 plist 在不在）
    @Published private(set) var enabled = false
    @Published private(set) var busy = false
    @Published private(set) var message = ""

    private init() {
        enabled = FileManager.default.fileExists(atPath: Self.plistPath)
    }

    var helperPath: String {
        Bundle.main.bundlePath + "/Contents/MacOS/" + Self.helperName
    }

    func refresh() {
        let on = FileManager.default.fileExists(atPath: Self.plistPath)
        if on != enabled { enabled = on }
    }

    // MARK: - 安装 / 卸载

    func enable() {
        guard !busy else { return }
        guard FileManager.default.fileExists(atPath: helperPath) else {
            message = "转发器缺失，请重新安装 AlienMAC"
            return
        }
        busy = true
        message = "正在申请管理员权限…"
        let script = installScript(helper: helperPath)
        runAdmin(script) { [weak self] ok, log in
            guard let self = self else { return }
            self.busy = false
            self.refresh()
            if ok {
                self.message = self.enabled ? "已启用：http://alien.local" : "写入成功但守护没起来：\(log)"
            } else {
                self.message = log.isEmpty ? "已取消或授权失败" : log
            }
        }
    }

    func disable() {
        guard !busy else { return }
        busy = true
        message = "正在停用…"
        let script = """
        launchctl bootout system/\(Self.label) >/dev/null 2>&1 || true
        rm -f "\(Self.plistPath)"
        launchctl print system/\(Self.label) >/dev/null 2>&1 && echo "still-running" || echo "stopped"
        """
        runAdmin(script) { [weak self] ok, log in
            guard let self = self else { return }
            self.busy = false
            self.refresh()
            self.message = ok ? (self.enabled ? "停用未完成" : "已停用，回到带端口的地址") : log
        }
    }

    // MARK: - 脚本

    private func installScript(helper: String) -> String {
        """
        set -e
        PLIST="\(Self.plistPath)"
        cat > "$PLIST" <<'PLISTEOF'
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(Self.label)</string>
            <key>ProgramArguments</key><array><string>\(helper)</string></array>
            <key>RunAtLoad</key><true/>
            <key>KeepAlive</key><true/>
            <key>ProcessType</key><string>Background</string>
            <key>StandardOutPath</key><string>/tmp/alienmac-web80.log</string>
            <key>StandardErrorPath</key><string>/tmp/alienmac-web80.log</string>
        </dict>
        </plist>
        PLISTEOF
        chown root:wheel "$PLIST"
        chmod 644 "$PLIST"
        launchctl bootout system/\(Self.label) >/dev/null 2>&1 || true
        launchctl bootstrap system "$PLIST"
        launchctl enable system/\(Self.label) >/dev/null 2>&1 || true
        scutil --set HostName alien
        scutil --set LocalHostName alien
        dscacheutil -flushcache >/dev/null 2>&1 || true
        launchctl print system/\(Self.label) >/dev/null 2>&1 && echo "daemon-ok" || echo "daemon-missing"
        """
    }

    /// 弹一次系统管理员授权框执行脚本
    private func runAdmin(_ script: String, completion: @escaping (Bool, String) -> Void) {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alienmac-admin-\(UUID().uuidString).sh")
        do {
            try script.write(to: tmp, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tmp.path)
        } catch {
            completion(false, "脚本写入失败：\(error.localizedDescription)")
            return
        }
        defer { try? FileManager.default.removeItem(at: tmp) }

        let command = "do shell script \"bash \(tmp.path)\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.terminationHandler = { proc in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let log = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                completion(proc.terminationStatus == 0, log)
            }
        }
        do {
            try process.run()
        } catch {
            completion(false, "无法调用 osascript：\(error.localizedDescription)")
        }
    }
}
