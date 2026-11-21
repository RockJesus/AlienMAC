//
//  CustomPreset.swift
//  AlienMAC
//
//  用户自定义灯光预设，可持久化保存
//

import Foundation
import SwiftUI

/// 一个完整的灯区配置快照
struct ZoneSnapshot: Codable, Equatable {
    var primary: RGBColor
    var secondary: RGBColor
    var effectCode: String
    var tempo: UInt16

    var effect: LightEffect {
        LightEffect(code: effectCode)
    }
}

/// 用户自定义预设
struct CustomPreset: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    /// 预设名称
    var name: String
    /// 作用范围（0 表示全部灯区）
    var zonesRaw: UInt32
    /// 灯光配置
    var snapshot: ZoneSnapshot
    /// 创建时间
    var createdAt: Date = Date()

    var color: Color { snapshot.primary.swiftUIColor }
    var secondaryColor: Color { snapshot.secondary.swiftUIColor }
    var effect: LightEffect { snapshot.effect }

    /// 范围描述
    var scopeDescription: String {
        if zonesRaw == 0 || zonesRaw == LightZone.all.rawValue {
            return "全部灯区"
        }
        let zones = LightZone.allIndividual.filter { zonesRaw & $0.rawValue != 0 }
        if zones.count == 1 { return zones[0].displayName }
        return "\(zones.count) 个灯区"
    }

    /// 从当前 UI 状态创建一个预设
    static func make(name: String, zones: LightZone, primary: RGBColor, secondary: RGBColor, effect: LightEffect, tempo: UInt16) -> CustomPreset {
        CustomPreset(
            name: name,
            zonesRaw: zones.rawValue,
            snapshot: ZoneSnapshot(primary: primary, secondary: secondary, effectCode: effect.code, tempo: tempo)
        )
    }
}

/// 预设列表的磁盘格式
struct CustomPresetFile: Codable {
    var presets: [CustomPreset]
}
