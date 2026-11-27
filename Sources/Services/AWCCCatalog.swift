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

    /// 名字切词：KeyboardLeft / LCD Panel Left → {keyboard, left}
    private static func tokens(_ text: String) -> Set<String> {
        var out = Set<String>()
        var current = ""
        for ch in text.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ") {
            if ch == " " {
                if !current.isEmpty { out.insert(current.lowercased()); current = "" }
            } else if ch.isUppercase {
                if !current.isEmpty { out.insert(current.lowercased()) }
                current = String(ch)
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { out.insert(current.lowercased()) }
        return out
    }

    /// zone 名与 LED 描述做双向词集匹配（LCD Left ↔ LCD Panel Left），完全同名最优
    private func wireLed(for zoneName: String) -> AWCCLedInfo? {
        let zt = Self.tokens(zoneName)
        guard !zt.isEmpty else { return nil }
        var best: (Int, AWCCLedInfo)?
        for led in leds {
            let lt = Self.tokens(led.description)
            guard !lt.isEmpty else { continue }
            guard lt.isSubset(of: zt) || zt.isSubset(of: lt) else { continue }
            let score = (lt == zt ? 0 : 1) * 100 + lt.symmetricDifference(zt).count
            if best == nil || score < best!.0 { best = (score, led) }
        }
        return best?.1
    }

    /// 灯区表：`chain = ZoneID`、`mask = 1 << LedID`（USBPcap 抓包确认的寻址规则）
    var zoneRows: [AWCCZoneRow] {
        let groupNames: [Int: String] = groups.reduce(into: [:]) { result, group in
            let digits = group.groupID.filter { $0.isNumber }
            if let number = Int(digits) { result[number] = group.name }
        }

        return zones
            .compactMap { zone -> AWCCZoneRow? in
                guard let zoneID = Int(zone.zoneID), zoneID >= 1, zoneID <= 12 else { return nil }
                // 官方组名按 ZonesGroups 映射（ZoneID 2 → Group01），不是 ZoneID 直接当组号
                let groupNumber = zoneGroups[zone.zoneID].flatMap { Int($0) }
                let officialName = groupNumber.flatMap { groupNames[$0] } ?? zone.name
                let led = wireLed(for: zone.name) ?? wireLed(for: officialName)
                var mask: UInt32?
                if let led, zoneID >= 2 {
                    mask = UInt32(1) << UInt32(led.ledID)
                }
                let localized = ATHThemeImporter.zoneMap[zoneID]?.displayName ?? officialName
                return AWCCZoneRow(
                    zoneID: zoneID,
                    name: localized,
                    officialName: officialName,
                    group: zoneID,                 // chain 就是 ZoneID
                    mask: mask,
                    brightnessOnly: (led?.brightnessOnly ?? false)
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

// MARK: - 本机可控制性（能力声明）

/// 一个机型的灯控在本 App 里实际能做到什么。只按证据分级，不按“应该支持”推测：
/// - `.verifiedControl`：本机 17 R4 实抓报文逐条核对（chain/mask 与设备一致）
/// - `.sameProtocolUnverified`：同代 12 字节 APIv3 协议族，灯表来自官方资源但未上机
/// - `.needsOtherProtocol`：走 APIv1/v2（8–9 字节、4-bit 色深）或 APIv4/v8（34/65 字节），本 App 未实现
/// - `.noUserChannel`：台式/一体机灯经 ACPI/WMI，macOS 用户态没有通道
/// - `.unknown`：AWCC 内部代号，缺实物和协议证据
enum AWCCControlSupport: String, CaseIterable {
    case verifiedControl
    case sameProtocolUnverified
    case needsOtherProtocol
    case noUserChannel
    case unknown

    /// 列表里用的短标签
    var shortTitle: String {
        switch self {
        case .verifiedControl:        return "可控制"
        case .sameProtocolUnverified: return "同协议"
        case .needsOtherProtocol:     return "他协议"
        case .noUserChannel:          return "无通道"
        case .unknown:                return "未知"
        }
    }

    /// 详情里的一句话结论
    var reason: String {
        switch self {
        case .verifiedControl:
            return "12 字节 APIv3，PID 0x0530，本机实抓 11 条颜色帧逐条对上，可控制全部 11 个可设色灯区。"
        case .sameProtocolUnverified:
            return "同属 12 字节 APIv3，灯表与寻址规则按同一套推导，但没在真机上逐盏核对过；连上后能否点亮要以实测为准。"
        case .needsOtherProtocol:
            return "这一代走别的协议（8–9 字节 4-bit 色深的 APIv1/v2，或 34/65 字节的 APIv4/v8），本 App 只实现了 12 字节这一支，连上也发不出颜色。"
        case .noUserChannel:
            return "台式/一体机的中控灯走 ACPI/WMI，macOS 用户态没有下发通道；灯表可以展示，但点不动，需要一个内核扩展或 Windows 侧代理。"
        case .unknown:
            return "AWCC 资源里的内部代号，没找到对应实机与协议证据，先按不可控处理。"
        }
    }
}

/// 机型 → 可控制性对照表。依据：AWCC 4.8 机型资源（31 个）、LightFX 设备清单、
/// 17 R4 实抓报文，以及 AlienFX 协议族公开资料里的按代际划分。
enum AWCCControlTable {

    /// 本机实测
    static let verified: Set<String> = ["Alienware17R4"]

    /// 同代 12 字节，未上机
    static let sameProtocol: Set<String> = ["Alienware15R3", "Alienware13R3"]

    /// 4-bit 色深的 APIv1/v2（2011–2014 那批）
    static let olderNotebooks: Set<String> = [
        "Alienware14", "Alienware17", "Alienware18",
        "M11x", "M11xR3", "M14x", "M15x", "M17x", "M17xR3", "M18x"
    ]

    /// 台式与一体机：ACPI/WMI
    static let desktops: Set<String> = [
        "Aurora", "AuroraALX", "AuroraR5", "AuroraR6", "AuroraR7",
        "Area51", "Area51ALX", "Area51R2", "Area51R3", "Area51R4",
        "X51R3", "GraphicsAmplifier", "ASM100", "ASM200", "ASM201", "Andromeda"
    ]

    /// 内部代号，证据不足
    static let unknownCodename: Set<String> = ["Merciless", "Tanaris"]

    static func support(for id: String) -> AWCCControlSupport {
        if verified.contains(id) { return .verifiedControl }
        if sameProtocol.contains(id) { return .sameProtocolUnverified }
        if olderNotebooks.contains(id) { return .needsOtherProtocol }
        if desktops.contains(id) { return .noUserChannel }
        return .unknown
    }
}

extension AWCCModelInfo {
    /// 本机可控制性
    var controlSupport: AWCCControlSupport { AWCCControlTable.support(for: id) }
    /// 详情里的一句话结论
    var controlReason: String { controlSupport.reason }
}
