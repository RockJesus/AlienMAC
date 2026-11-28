//
//  PeripheralAutoApply.swift
//  AlienMAC
//
//  档案命中后自动落位：插上已验证的设备，自动把上次存的灯区/效果/颜色选回去。
//  纯规则，不碰 SwiftUI，方便单测。
//

import Foundation

struct PeripheralRGB: Equatable {
    var r: Int
    var g: Int
    var b: Int
}

/// 一次自动落位要做的事
struct PeripheralAutoApplyPlan: Equatable {
    var vid: Int
    var pid: Int
    var deviceKey: String
    /// LightZone 的 rawValue 列表
    var zones: [Int]
    var effect: String?
    var rgb: PeripheralRGB?
    var note: String

    var vidPid: String { String(format: "%04X:%04X", vid, pid) }
}

enum PeripheralAutoApply {

    /// 解析 "#RRGGBB" / "RRGGBB"
    static func rgb(fromHex hex: String?) -> PeripheralRGB? {
        guard var text = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = Int(text, radix: 16) else { return nil }
        return PeripheralRGB(r: (value >> 16) & 0xFF, g: (value >> 8) & 0xFF, b: value & 0xFF)
    }

    /// 只有「已验证 + 至少指定了一个灯区」的档案才自动落位，没验证过的不替用户做主
    static func plans(connected: [(vid: Int, pid: Int, key: String)],
                      overrides: [PeripheralOverride]) -> [PeripheralAutoApplyPlan] {
        var result: [PeripheralAutoApplyPlan] = []
        for device in connected {
            guard let item = overrides.first(where: { $0.vid == device.vid && $0.pid == device.pid }) else { continue }
            guard item.verified, let zones = item.zones, !zones.isEmpty else { continue }
            result.append(PeripheralAutoApplyPlan(
                vid: device.vid,
                pid: device.pid,
                deviceKey: device.key,
                zones: zones,
                effect: item.effect,
                rgb: rgb(fromHex: item.colorHex),
                note: "按档案 \(item.id) 自动选中 \(zones.count) 个灯区"
            ))
        }
        return result
    }

    /// 落位后的提示语，面板直接显示
    static func summary(_ plans: [PeripheralAutoApplyPlan]) -> String {
        guard let first = plans.first else { return "" }
        let extra = plans.count > 1 ? "（另有 \(plans.count - 1) 台）" : ""
        return "\(first.vidPid) \(first.note)\(extra)"
    }
}
