//
//  AWCCCatalog.swift
//  AlienMAC
//
//  AWCC 机型资源目录
//
//  数据来自 Windows 版 AWCC 4.8 安装目录里的 AlienFX.ModelResources.*.dll：
//  每个机型一份 .NET 资源 DLL，内嵌 ModelDataClass（能力开关）+ Leds（灯位掩码）
//  + ColorData（20 色官方调色板）+ ThemeDataset（该机型自带的默认主题）。
//  脚本 `scripts/extract-awcc-catalog.py` 把这些资源抽成 awcc-catalog.json，随 App 打包。
//
//  注意：只有 17 R4 的灯区表经过真机逐盏验证（verified = true），
//  其余机型的灯区/掩码来自官方资源、尚未上机核对，界面里一律标「未验证」。
//

import Foundation

// MARK: - 原始数据结构

struct AWCCPaletteEntry: Codable, Hashable, Identifiable {
    var name: String
    var argb: String
    var id: String { argb }
}

struct AWCCGroupInfo: Codable, Hashable {
    var groupID: String
    var name: String
}

struct AWCCLedInfo: Codable, Hashable {
    var ledIndex: Int
    var ledID: Int
    var description: String
    var position: String
    var brightnessOnly: Bool?
}

struct AWCCZoneInfo: Codable, Hashable {
    var zoneID: String
    var name: String
    var visualizationID: String?
    var loop: String?
}

struct AWCCActionInfo: Codable, Hashable {
    var zoneID: String?
    var actionID: String?
    var actionTypeID: String
    var color1: String
    var color2: String
    var duration: String?
}

struct AWCCThemeInfo: Codable, Hashable, Identifiable {
    var name: String
    var family: String?
    var file: String?
    var tempo: String?
    var actions: [AWCCActionInfo]

    var id: String { file ?? name }
}

struct AWCCDefaultTheme: Codable, Hashable {
    var name: String?
    var tempo: String?
    var actions: [AWCCActionInfo]
}

struct AWCCTempoCapability: Codable, Hashable {
    var support: Bool
    var min: Int?
    var max: Int?
    var `default`: Int?
}

struct AWCCBrightnessCapability: Codable, Hashable {
    var min: Int?
    var max: Int?
}

struct AWCCCapabilities: Codable, Hashable {
    var tempo: AWCCTempoCapability
    var extendedDuration: Bool?
    var preview: Bool?
    var goDark: Bool?
    var brightness: AWCCBrightnessCapability
    var goDarkShortcut: String?
    var keypad: Bool?
    var needALXCheck: Bool?
}

struct AWCCModelInfo: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var verified: Bool
    var capabilities: AWCCCapabilities
    var leds: [AWCCLedInfo]
    var groups: [AWCCGroupInfo]
    var zoneGroups: [String: String]
    var zones: [AWCCZoneInfo]
    var defaultTheme: AWCCDefaultTheme
    var palette: [AWCCPaletteEntry]
}

struct AWCCPIDModule: Codable, Hashable {
    var pid: String
    var models: [String]
}

struct AWCCCatalog: Codable {
    var schema: Int
    var source: String
    var modelCount: Int
    var models: [AWCCModelInfo]
    var themes: [AWCCThemeInfo]
    var pidModules: [AWCCPIDModule]?
}

// MARK: - 从目录推导出的灯区行

/// 一个机型的一行灯区：官方区域号 + 组号 + 3 字节掩码 + 灯名
struct AWCCZoneRow: Identifiable, Hashable {
    var zoneID: Int
    var name: String
    var officialName: String
    var group: Int?
    /// 规范化到 3 字节的掩码（报文里的 maskH/maskM/maskL）
    var mask: UInt32?
    var brightnessOnly: Bool

    var id: Int { zoneID }

    var maskHex: String {
        guard let mask else { return "—" }
        return String(format: "%02X %02X %02X", (mask >> 16) & 0xFF, (mask >> 8) & 0xFF, mask & 0xFF)
    }

    var groupHex: String {
        guard let group else { return "—" }
        return String(format: "%02X", group)
    }
}

extension AWCCModelInfo {

    private static func normalized(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: " ", with: "")
    }

    private var ledByDescription: [String: AWCCLedInfo] {
        var map: [String: AWCCLedInfo] = [:]
        for led in leds {
            map[Self.normalized(led.description)] = led
        }
        return map
    }

    /// 灯区表（区域号 1…12；1 是电源壳，没有颜色通道）
    var zoneRows: [AWCCZoneRow] {
        let ledMap = ledByDescription
        let groupNames: [Int: String] = groups.reduce(into: [:]) { result, group in
            let digits = group.groupID.filter { $0.isNumber }
            if let number = Int(digits) { result[number] = group.name }
        }

        return zones
            .compactMap { zone -> AWCCZoneRow? in
                guard let zoneID = Int(zone.zoneID), zoneID >= 1, zoneID <= 12,
                      let group = zoneGroups[zone.zoneID].flatMap({ Int($0) })
                else { return nil }

                let officialName = groupNames[group] ?? zone.name
                let led = ledMap[Self.normalized(officialName)]
                    ?? ledMap[Self.normalized(zone.name)]
                var mask: UInt32?
                if let position = led?.position, let raw = UInt32(position.dropFirst(2), radix: 16) {
                    // 官方 XML 里 Alienhead 写成 32 位 0x02000000，落报文是 3 字节 02 00 00
                    mask = raw > 0xFF_FFFF ? raw >> 8 : raw
                }
                if zoneID == 1 { mask = nil }   // 电源壳：走 0x08 状态块，不吃颜色掩码

                let localized = ATHThemeImporter.zoneMap[zoneID]?.displayName ?? officialName
                return AWCCZoneRow(
                    zoneID: zoneID,
                    name: localized,
                    officialName: officialName,
                    group: group,
                    mask: mask,
                    brightnessOnly: led?.brightnessOnly ?? false
                )
            }
            .sorted { $0.zoneID < $1.zoneID }
    }

    /// 可下发颜色的灯区数（不含电源壳与仅亮度位）
    var addressableZoneCount: Int {
        zoneRows.filter { $0.mask != nil && !$0.brightnessOnly }.count
    }
}

// MARK: - 目录单例

final class AWCCCatalogStore {

    static let shared = AWCCCatalogStore()

    let catalog: AWCCCatalog?

    private init() {
        catalog = Self.load()
    }

    private static func load() -> AWCCCatalog? {
        let bundle = Bundle.main
        let candidates: [URL?] = [
            bundle.url(forResource: "awcc-catalog", withExtension: "json"),
            bundle.url(forResource: "awcc-catalog", withExtension: "json", subdirectory: "AWCC"),
            bundle.url(forResource: "awcc-catalog", withExtension: "json", subdirectory: "Resources")
        ]
        for case let url? in candidates {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let decoded = try? JSONDecoder().decode(AWCCCatalog.self, from: data) {
                return decoded
            }
        }
        return nil
    }

    var models: [AWCCModelInfo] {
        guard let catalog else { return [] }
        return catalog.models.sorted { lhs, rhs in
            if lhs.verified != rhs.verified { return lhs.verified }
            return lhs.name < rhs.name
        }
    }

    var themes: [AWCCThemeInfo] { catalog?.themes ?? [] }

    /// 已验证的机型（目前只有 17 R4）
    var verifiedModels: [AWCCModelInfo] { models.filter(\.verified) }

    func model(id: String) -> AWCCModelInfo? {
        catalog?.models.first { $0.id == id }
    }

    func theme(named name: String) -> AWCCThemeInfo? {
        themes.first { $0.name == name }
    }

    /// 当前设备机型：优先按 USB 名称匹配资源名，匹配不到回落到已验证的 17 R4
    func model(matchingDeviceName deviceName: String?) -> AWCCModelInfo? {
        if let deviceName {
            let trimmed = deviceName.replacingOccurrences(of: " ", with: "")
            let exact = catalog?.models.first { $0.id.caseInsensitiveCompare(trimmed) == .orderedSame }
            if let exact { return exact }
            let loose = catalog?.models.first {
                $0.name.replacingOccurrences(of: " ", with: "").caseInsensitiveCompare(trimmed) == .orderedSame
            }
            if let loose { return loose }
        }
        return catalog?.models.first { $0.id == "Alienware17R4" }
    }
}
