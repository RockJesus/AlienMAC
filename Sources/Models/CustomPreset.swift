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

/// 预设文件里的灯区表条目：id 是位掩码里的那一位，name 只用于跨版本比对
struct PresetZoneMeta: Codable, Equatable {
    var id: UInt32
    var name: String
}

/// 预设列表的磁盘格式
///
/// schema 从 1 起：老文件没有 `schema` 字段，解码时按 1 处理，仍可导入；
/// `zones` 用来发现“导出端和导入端灯区表不一致”，不静默跳过。
struct CustomPresetFile: Codable {
    static let currentSchema = 1

    var schema: Int = 1
    var appVersion: String? = nil
    var exportedAt: Date? = nil
    var zones: [PresetZoneMeta]? = nil
    var presets: [CustomPreset]

    init(presets: [CustomPreset],
         zones: [PresetZoneMeta]? = nil,
         appVersion: String? = nil,
         exportedAt: Date? = nil) {
        self.schema = Self.currentSchema
        self.appVersion = appVersion
        self.exportedAt = exportedAt
        self.zones = zones
        self.presets = presets
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(Int.self, forKey: .schema) ?? 1
        appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion)
        exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt)
        zones = try c.decodeIfPresent([PresetZoneMeta].self, forKey: .zones)
        presets = try c.decodeIfPresent([CustomPreset].self, forKey: .presets) ?? []
    }

    /// 当前 App 的灯区表，导出时一并写出，导入端据此发现差异
    static var currentZoneTable: [PresetZoneMeta] {
        LightZone.allIndividual.map { PresetZoneMeta(id: $0.rawValue, name: $0.displayName) }
    }
}
