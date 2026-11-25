//
//  MacroBinding.swift
//  AlienMAC
//
//  TactX 宏键绑定：17 R4 左侧 5 个宏键 + 顶部宏键
//

import Foundation

/// 宏键可执行的动作
enum MacroAction: String, Codable, CaseIterable, Identifiable {
    case none
    case launchApp
    case openURL
    case runScript
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:      return "未绑定"
        case .launchApp: return "启动应用"
        case .openURL:   return "打开网址 / 文件"
        case .runScript: return "运行脚本"
        case .system:    return "系统动作"
        }
    }
}

/// 系统动作
enum MacroSystemAction: String, Codable, CaseIterable, Identifiable {
    case lock, sleep, lightsOff, lightsOn, muteToggle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lock:       return "锁定屏幕"
        case .sleep:      return "进入睡眠"
        case .lightsOff:  return "关闭灯光"
        case .lightsOn:   return "打开灯光"
        case .muteToggle: return "静音切换"
        }
    }
}

/// 一个宏键槽位的定义
struct MacroBinding: Codable, Equatable, Identifiable {
    /// m1…m5 为左侧宏键，top 为顶部宏键
    var slot: String
    var actionCode: String = MacroAction.none.rawValue
    /// 应用名 / 网址 / 脚本路径
    var target: String = ""
    /// 系统动作
    var systemCode: String = MacroSystemAction.lock.rawValue
    /// 界面展示名
    var label: String = ""
    /// 绑定的物理按键 usage page / usage（0 表示没绑物理键）
    var keyUsagePage: Int = 0
    var keyUsage: Int = 0

    /// 是否已经绑定了物理按键
    var hasPhysicalKey: Bool { keyUsage != 0 }

    var keyText: String {
        guard hasPhysicalKey else { return "" }
        return String(format: "0x%02X / 0x%02X", keyUsagePage, keyUsage)
    }

    var id: String { slot }

    init(slot: String) { self.slot = slot }

    /// 老版本设置里没有 keyUsagePage / keyUsage，缺字段时兜 0，避免整份设置解码失败
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slot = try c.decode(String.self, forKey: .slot)
        actionCode = (try? c.decodeIfPresent(String.self, forKey: .actionCode)) ?? MacroAction.none.rawValue
        target = (try? c.decodeIfPresent(String.self, forKey: .target)) ?? ""
        systemCode = (try? c.decodeIfPresent(String.self, forKey: .systemCode)) ?? MacroSystemAction.lock.rawValue
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? ""
        keyUsagePage = (try? c.decodeIfPresent(Int.self, forKey: .keyUsagePage)) ?? 0
        keyUsage = (try? c.decodeIfPresent(Int.self, forKey: .keyUsage)) ?? 0
    }
    var action: MacroAction { MacroAction(rawValue: actionCode) ?? .none }
    var systemAction: MacroSystemAction { MacroSystemAction(rawValue: systemCode) ?? .lock }

    /// 槽位显示名
    static func slotTitle(_ slot: String) -> String {
        switch slot {
        case "top": return "顶部宏键"
        default:
            if slot.hasPrefix("m"), let n = Int(slot.dropFirst()) {
                return "宏键 Δ\(n)"
            }
            return slot
        }
    }

    var summary: String {
        switch action {
        case .none:      return "未绑定"
        case .launchApp: return "启动 \(target.isEmpty ? "应用" : target)"
        case .openURL:   return target.isEmpty ? "打开网址" : target
        case .runScript: return target.isEmpty ? "运行脚本" : (target as NSString).lastPathComponent
        case .system:    return systemAction.title
        }
    }

    static let allSlots = ["m1", "m2", "m3", "m4", "m5", "top"]

    static var defaults: [MacroBinding] {
        var list: [MacroBinding] = []
        for slot in allSlots {
            var b = MacroBinding(slot: slot)
            if slot == "top" {
                b.actionCode = MacroAction.system.rawValue
                b.systemCode = MacroSystemAction.lightsOff.rawValue
            }
            list.append(b)
        }
        return list
    }
}
