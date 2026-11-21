//
//  LaunchAtLogin.swift
//  AlienMAC
//
//  登录项管理：优先使用 macOS 13+ 的 SMAppService，
//  在 Ad-hoc 签名 / 未放入 /Applications / 系统未登记的情况下回退到 LaunchAgent。
//

import Foundation
import ServiceManagement

enum LaunchAtLogin {

    static let agentLabel = "com.alienmac.AlienMAC.launcher"

    /// LaunchAgent 描述文件位置
    static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    /// 是否已设置为登录自启（系统登录项或 LaunchAgent 任一成立即视为已启用）
    static var isEnabled: Bool {
        if SMAppService.mainApp.status == .enabled { return true }
        return FileManager.default.fileExists(atPath: agentURL.path)
    }

    /// 系统登录项是否需要用户在「系统设置」里批准
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// 界面展示用的状态描述
    static var statusDescription: String {
        if FileManager.default.fileExists(atPath: agentURL.path) {
            return "已启用（LaunchAgent）"
        }
        switch SMAppService.mainApp.status {
        case .enabled:          return "已启用"
        case .requiresApproval: return "需要在系统设置里批准"
        case .notRegistered:    return "未启用"
        case .notFound:         return "未启用"
        @unknown default:       return "未启用"
        }
    }

    /// 打开「系统设置 → 通用 → 登录项」
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// 设置登录自启，返回错误描述（nil 表示成功）
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        enabled ? enable() : disable()
    }

    private static func enable() -> String? {
        if isEnabled { return nil }

        // 1) 首选系统原生登录项
        if SMAppService.mainApp.status != .enabled {
            do {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .enabled { return nil }
            } catch {
                // 签名不完整或不在 /Applications 时会走到这里，继续回退
            }
        }

        // 2) 回退：写入用户级 LaunchAgent，下次登录由 launchd 读取
        return installAgent()
    }

    private static func disable() -> String? {
        var errorText: String?

        if SMAppService.mainApp.status != .notRegistered {
            try? SMAppService.mainApp.unregister()
        }

        if FileManager.default.fileExists(atPath: agentURL.path) {
            let uid = String(getuid())
            runLaunchctl(["bootout", "gui/\(uid)/\(agentLabel)"])
            do {
                try FileManager.default.removeItem(at: agentURL)
            } catch {
                errorText = "无法删除 LaunchAgent：\(error.localizedDescription)"
            }
        }
        return errorText
    }

    private static func installAgent() -> String? {
        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": [Bundle.main.bundlePath + "/Contents/MacOS/AlienMAC"],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive"
        ]

        let dir = agentURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: agentURL, options: .atomic)
            return nil
        } catch {
            return "写入登录项失败：\(error.localizedDescription)。可手动在「系统设置 → 通用 → 登录项」添加 AlienMAC。"
        }
    }

    private static func runLaunchctl(_ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        try? process.run()
        process.waitUntilExit()
    }
}
