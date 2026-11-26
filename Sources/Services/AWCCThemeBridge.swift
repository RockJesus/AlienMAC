//
//  AWCCThemeBridge.swift
//  AlienMAC
//
//  把 AWCC 自带主题（ThemeDataset 的 Actions 序列）折成 AlienMAC 的「每区动作」。
//
//  AWCC 高级主题里同一区域会有多行动作（一条动画序列），AlienMAC 每区只存一条动作，因此：
//    * 有 Pulse(2)          → 脉冲，取首行颜色
//    * 有 Morph(1)          → 渐变，首色 → 末色
//    * 只有 SetColor(3) 且有多种颜色 → 当成渐变（首色 → 末色），等价于把序列压成两帧
//    * 只有 SetColor 且同色   → 常亮
//

import Foundation

enum AWCCThemeBridge {

    /// 主题折成每区动作
    static func zoneActions(from theme: AWCCThemeInfo) -> [LightZone: ZoneAction] {
        let tempo = UInt16(theme.tempo.flatMap { Int($0) } ?? 200)

        var rowsByZone: [Int: [AWCCActionInfo]] = [:]
        for action in theme.actions {
            guard let raw = action.zoneID, let zoneID = Int(raw) else { continue }
            guard let type = Int(action.actionTypeID) else { continue }
            // 只关心真正带颜色的三类：1 渐变 / 2 脉冲 / 3 常亮
            guard type == 1 || type == 2 || type == 3 else { continue }
            rowsByZone[zoneID, default: []].append(action)
        }

        var result: [LightZone: ZoneAction] = [:]
        for (zoneID, rows) in rowsByZone {
            guard let zone = ATHThemeImporter.zoneMap[zoneID] else { continue }
            let ordered = rows.sorted { (Int($0.actionID ?? "") ?? 0) < (Int($1.actionID ?? "") ?? 0) }
            guard let first = ordered.first else { continue }

            let firstColor = ATHThemeImporter.color(from: first.color1)
            let lastColor = ATHThemeImporter.color(from: ordered.last?.color1 ?? first.color1)
            let hasPulse = ordered.contains { $0.actionTypeID == "2" }
            let hasMorph = ordered.contains { $0.actionTypeID == "1" }
            let distinctColors = Set(ordered.map(\.color1)).count

            let effectCode: String
            let secondary: RGBColor
            if hasPulse {
                effectCode = "pulse"
                secondary = firstColor
            } else if hasMorph || distinctColors > 1 {
                effectCode = "morph"
                secondary = hasMorph
                    ? ATHThemeImporter.color(from: first.color2)
                    : lastColor
            } else {
                effectCode = "color"
                secondary = firstColor
            }

            result[zone] = ZoneAction(
                zone: zone,
                primary: firstColor,
                secondary: secondary,
                effectCode: effectCode,
                tempo: tempo
            )
        }
        return result
    }

    /// 主题的代表色（用于预设卡片上的一排色块）
    static func swatches(from theme: AWCCThemeInfo, limit: Int = 6) -> [RGBColor] {
        var seen = Set<String>()
        var colors: [RGBColor] = []
        for action in theme.actions {
            guard let raw = action.zoneID, let zoneID = Int(raw), ATHThemeImporter.zoneMap[zoneID] != nil else { continue }
            guard ["1", "2", "3"].contains(action.actionTypeID) else { continue }
            let key = action.color1
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let color = ATHThemeImporter.color(from: action.color1)
            if color != .off { colors.append(color) }
            if colors.count >= limit { break }
        }
        return colors
    }
}
