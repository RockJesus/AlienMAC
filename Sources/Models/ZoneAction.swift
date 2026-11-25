//
//  ZoneAction.swift
//  AlienMAC
//
//  每区独立动作（对齐 AWCC 高级模式的“每区一行动作”）
//

import Foundation

/// 单个灯区自己的动作：独立颜色、效果、速度，可循环
struct ZoneAction: Codable, Equatable, Identifiable {
    /// 作用灯区的硬件掩码（用整数保存，避免 OptionSet 的编码歧义）
    var zoneRaw: UInt32
    /// 主色
    var primary: RGBColor
    /// 次色（渐变/呼吸用）
    var secondary: RGBColor
    /// 效果稳定标识（color / pulse / morph / breathing / spectrum / wave / scanner）
    var effectCode: String
    /// 效果速度（毫秒）
    var tempo: UInt16
    /// 持续时间（毫秒），0 表示常驻不自动结束
    var durationMs: Int = 0
    /// 循环标记（与 AWCC 每区动作行左侧的循环图标对应）
    var loop: Bool = true

    var id: UInt32 { zoneRaw }

    /// 灯区（由掩码还原）
    var zone: LightZone { LightZone(rawValue: zoneRaw) }

    var effect: LightEffect { LightEffect(code: effectCode) }

    /// 转成硬件快照
    var snapshot: ZoneSnapshot {
        ZoneSnapshot(primary: primary, secondary: secondary, effectCode: effectCode, tempo: tempo)
    }

    /// 面板上的简短描述
    var summary: String {
        var parts = [effect.rawValue]
        if tempo > 0 { parts.append("\(tempo) ms") }
        if durationMs > 0 { parts.append("持续 \(durationMs / 1000) s") }
        return parts.joined(separator: " · ")
    }

    init(zone: LightZone, primary: RGBColor, secondary: RGBColor,
         effectCode: String, tempo: UInt16, durationMs: Int = 0, loop: Bool = true) {
        self.zoneRaw = zone.rawValue
        self.primary = primary
        self.secondary = secondary
        self.effectCode = effectCode
        self.tempo = tempo
        self.durationMs = durationMs
        self.loop = loop
    }
}
