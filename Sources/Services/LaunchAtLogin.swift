//
//  LaunchAtLogin.swift
//  AlienMAC
//
//  登录项管理（macOS 13+ 使用 SMAppService）
//

import Foundation
import ServiceManagement

enum LaunchAtLogin {

    /// 当前是否已注册为登录启动项
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 状态描述，用于界面展示
    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:              return "已启用"
        case .requiresApproval:     return "需要在系统设置中批准"
        case .notRegistered:        return "未启用"
        case .notFound:             return "系统未找到登录项"
        @unknown default:           return "未知状态"
        }
    }

    /// 设置登录启动项，返回错误描述（nil 表示成功）
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
