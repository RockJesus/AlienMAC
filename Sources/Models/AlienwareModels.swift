//
//  AlienwareModels.swift
//  AlienMAC
//
//  Alienware 机型 / 协议目录与识别
//  协议划分参考 AlienFX 协议族（APIv1 ~ APIv4），本 App 直接驱动的是 APIv3（12 字节 HID Report）
//

import Foundation

/// AlienFX 协议世代
enum AlienFXProtocol: String, Codable, CaseIterable {
    case apiV0 = "APIv0"
    case apiV1 = "APIv1"
    case apiV2 = "APIv2"
    case apiV3 = "APIv3"
    case apiV4 = "APIv4"
    case apiV5 = "APIv5"
    case apiV8 = "APIv8"
    case unknown = "未知"

    /// 已接入下发通道的协议：v3（12 字节 SET_REPORT）、v4（33 字节无 Report ID）、v8（65 字节 Feature + Report）
    var supportsControl: Bool {
        switch self {
        case .apiV3, .apiV4, .apiV8: return true
        default: return false
        }
    }

    var summary: String {
        switch self {
        case .apiV0: return "ACPI 4 字节，Aurora R7 等早期台式"
        case .apiV1: return "HID 8 字节，极早期笔记本"
        case .apiV2: return "HID 9 字节 / 4-bit 色深，M11x / 13 R2 / 17 R3"
        case .apiV3: return "HID 12 字节 / 8-bit 色深，17 R4 / 17 R5 等"
        case .apiV4: return "AW-ELC 34 字节，m/x 系列、新的 Aurora 与 G 系列"
        case .apiV5: return "HID Feature 64 字节，逐键 RGB 键盘机型"
        case .apiV8: return "USB Interrupt 65 字节，AW768 / AW410K 外设"
        case .unknown: return "未能判断"
        }
    }
}

/// 机型条目
struct AlienwareModel: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let shortName: String
    let category: String        // 笔记本 / 台式 / 外设
    let generation: String
    let `protocol`: AlienFXProtocol
    let zones: Int?             // 已知灯区数
    let zonesVerified: Bool     // 是否本机实测
    /// 设备产品字符串（USB product string）里可能出现的关键词，用于自动匹配
    let productTokens: [String]

    var zoneDescription: String {
        guard let zones else { return "未知（以设备回报为准）" }
        return "\(zones) 个" + (zonesVerified ? "（实测）" : "")
    }
}

enum AlienwareCatalog {
    /// 已知机型。协议字段来自 AlienFX 协议族公开资料与实测，灯区数仅在实测过的机型填写。
    static let models: [AlienwareModel] = [
        AlienwareModel(id: "17r4", name: "Alienware 17 R4", shortName: "17 R4",
                       category: "笔记本", generation: "2016 · AW1517",
                       protocol: .apiV3, zones: 13, zonesVerified: true,
                       productTokens: ["aw1517", "17 r4"]),
        AlienwareModel(id: "17r5", name: "Alienware 17 R5", shortName: "17 R5",
                       category: "笔记本", generation: "2018",
                       protocol: .apiV3, zones: nil, zonesVerified: false,
                       productTokens: ["aw1518", "17 r5"]),
        AlienwareModel(id: "15r3", name: "Alienware 15 R3", shortName: "15 R3",
                       category: "笔记本", generation: "2016",
                       protocol: .apiV3, zones: nil, zonesVerified: false,
                       productTokens: ["aw1515", "15 r3"]),
        AlienwareModel(id: "15r4", name: "Alienware 15 R4", shortName: "15 R4",
                       category: "笔记本", generation: "2018",
                       protocol: .apiV3, zones: nil, zonesVerified: false,
                       productTokens: ["aw1519", "15 r4"]),
        AlienwareModel(id: "13r2", name: "Alienware 13 R2", shortName: "13 R2",
                       category: "笔记本", generation: "2015",
                       protocol: .apiV2, zones: nil, zonesVerified: false,
                       productTokens: ["aw1315", "13 r2"]),
        AlienwareModel(id: "15r2", name: "Alienware 15 R2", shortName: "15 R2",
                       category: "笔记本", generation: "2015",
                       protocol: .apiV2, zones: nil, zonesVerified: false,
                       productTokens: ["aw1513", "15 r2"]),
        AlienwareModel(id: "m14x", name: "Alienware M14x", shortName: "M14x",
                       category: "笔记本", generation: "2011",
                       protocol: .apiV1, zones: nil, zonesVerified: false,
                       productTokens: ["m14x"]),
        AlienwareModel(id: "m15r1", name: "Alienware m15 R1 / R2 / R3 / R6", shortName: "m15",
                       category: "笔记本", generation: "2018-2021 · 4 区键盘",
                       protocol: .apiV4, zones: nil, zonesVerified: false,
                       productTokens: ["m15"]),
        AlienwareModel(id: "m15r4", name: "Alienware m15 R4 / R5", shortName: "m15 R4",
                       category: "笔记本", generation: "2021",
                       protocol: .apiV4, zones: nil, zonesVerified: false,
                       productTokens: ["m15 r4"]),
        AlienwareModel(id: "m17r1", name: "Alienware m17 R1", shortName: "m17",
                       category: "笔记本", generation: "2019 · 4 区键盘",
                       protocol: .apiV4, zones: nil, zonesVerified: false,
                       productTokens: ["m17"]),
        AlienwareModel(id: "m17r3", name: "Alienware m17 R3", shortName: "m17 R3",
                       category: "笔记本", generation: "2020",
                       protocol: .apiV4, zones: nil, zonesVerified: false,
                       productTokens: ["m17 r3"]),
        AlienwareModel(id: "x15r2", name: "Alienware x15 R2", shortName: "x15 R2",
                       category: "笔记本", generation: "2022",
                       protocol: .apiV4, zones: nil, zonesVerified: false,
                       productTokens: ["x15"]),
        AlienwareModel(id: "x17r2", name: "Alienware x17 R2", shortName: "x17 R2",
                       category: "笔记本", generation: "2022",
                       protocol: .apiV4, zones: nil, zonesVerified: false,
                       productTokens: ["x17"]),
        AlienwareModel(id: "a51mr2", name: "Alienware Area-51m R2", shortName: "A51m R2",
                       category: "笔记本", generation: "2020",
                       protocol: .apiV4, zones: nil, zonesVerified: false,
                       productTokens: ["area-51m", "area51m"]),
        AlienwareModel(id: "ac16251", name: "Alienware 16X Aurora (AC16251)", shortName: "16X Aurora",
                       category: "笔记本", generation: "2025",
                       protocol: .apiV4, zones: 4, zonesVerified: false,
                       productTokens: ["ac16251", "aw-elc"]),
        AlienwareModel(id: "aurora-r7", name: "Alienware Aurora R7", shortName: "Aurora R7",
                       category: "台式", generation: "2017",
                       protocol: .apiV0, zones: nil, zonesVerified: false,
                       productTokens: ["aurora r7"]),
        AlienwareModel(id: "aurora-r10", name: "Alienware Aurora R10 / R12 / R14", shortName: "Aurora R10+",
                       category: "台式", generation: "2020-2022",
                       protocol: .apiV4, zones: nil, zonesVerified: false,
                       productTokens: ["aurora r10", "aurora r12", "aurora r14"]),
        AlienwareModel(id: "g5", name: "Dell G5 / G7 系列", shortName: "G5 / G7",
                       category: "笔记本", generation: "2019-2021",
                       protocol: .apiV4, zones: nil, zonesVerified: false,
                       productTokens: ["g5 15", "g7"]),
        AlienwareModel(id: "aw768", name: "Alienware AW768 / AW410K 键盘", shortName: "AW768",
                       category: "外设", generation: "2018",
                       protocol: .apiV8, zones: nil, zonesVerified: false,
                       productTokens: ["aw768", "aw410k"]),
        AlienwareModel(id: "aw610m", name: "Alienware AW610M 鼠标", shortName: "AW610M",
                       category: "外设", generation: "2019",
                       protocol: .unknown, zones: nil, zonesVerified: false,
                       productTokens: ["aw610m"])
    ]

    /// 型号匹配：先看产品字符串关键词，再退回 PID 已知映射
    static func match(productName: String, productID: UInt32) -> AlienwareModel? {
        let lowered = productName.lowercased()
        if let hit = models.first(where: { model in
            model.productTokens.contains { lowered.contains($0) }
        }) {
            return hit
        }
        if productID == 0x0530 {
            return models.first { $0.id == "17r4" }
        }
        return nil
    }

    /// 未识别机型时的占位条目
    static func placeholder(productName: String) -> AlienwareModel {
        AlienwareModel(id: "unknown", name: productName.isEmpty ? "未识别 Alienware 设备" : productName,
                       shortName: productName.isEmpty ? "Alienware" : productName,
                       category: "未知", generation: "—",
                       protocol: .unknown, zones: nil, zonesVerified: false,
                       productTokens: [])
    }
}
