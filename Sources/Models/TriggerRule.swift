//
//  TriggerRule.swift
//  AlienMAC
//
//  触发器规则：对齐 AWCC 高级模式的事件树（应用 / 电源 / 锁屏 / 定时）
//

import Foundation

/// 触发源
enum TriggerSource: String, Codable, CaseIterable, Identifiable {
    case app          // 某个应用切到前台
    case powerAC      // 接上电源
    case powerBattery // 拔掉电源用电池
    case unlock       // 解锁屏幕
    case lock         // 锁屏 / 屏幕休眠
    case daily        // 每天固定时间

    var id: String { rawValue }

    var title: String {
        switch self {
        case .app:          return "应用切到前台"
        case .powerAC:      return "接上电源"
        case .powerBattery: return "拔掉电源"
        case .unlock:       return "解锁屏幕"
        case .lock:          return "锁屏 / 屏幕休眠"
        case .daily:        return "每天定时"
        }
    }
}

/// 触发后执行的动作
enum TriggerAction: String, Codable, CaseIterable, Identifiable {
    case preset   // 套用自定义预设
    case lightsOn
    case lightsOff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preset:    return "套用预设"
        case .lightsOn:  return "开灯（恢复上次）"
        case .lightsOff: return "关灯"
        }
    }
}

/// 一条触发器
struct TriggerRule: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var sourceCode: String = TriggerSource.app.rawValue
    /// 应用触发源用的 Bundle ID（source == app 时有效）
    var appBundleID: String = ""
    /// 应用显示名（仅用于界面展示）
    var appName: String = ""
    /// 定时触发源用的分钟数（0…1439）
    var minuteOfDay: Int = 0
    /// 动作为 preset 时指向自定义预设
    var presetID: UUID?
    var actionCode: String = TriggerAction.preset.rawValue
    /// 动作里的预设名（用于界面展示，避免预设被删后显示空白）
    var presetName: String = ""
    var enabled: Bool = true

    var source: TriggerSource { TriggerSource(rawValue: sourceCode) ?? .app }
    var action: TriggerAction { TriggerAction(rawValue: actionCode) ?? .preset }

    /// 一句话描述
    var summary: String {
        switch source {
        case .app:
            return "\(appName.isEmpty ? "应用" : appName) → \(actionText)"
        case .daily:
            return String(format: "每天 %02d:%02d → %@", minuteOfDay / 60, minuteOfDay % 60, actionText)
        default:
            return "\(source.title) → \(actionText)"
        }
    }

    private var actionText: String {
        switch action {
        case .preset:    return presetName.isEmpty ? "套用预设" : presetName
        case .lightsOn:  return "开灯"
        case .lightsOff: return "关灯"
        }
    }
}
