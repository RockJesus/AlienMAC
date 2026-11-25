//
//  PeripheralProtocol.swift
//  AlienMAC
//
//  外设灯效协议归属：先按型号归到 alienfx 已知的 API 版本，未验证的不允许下发
//

import Foundation

/// 外设灯效走的协议族
enum PeripheralLightProtocol: String {
    /// 笔记本内置灯控，已经用 APIv3 12 字节报文验证过
    case builtinV3 = "APIv3"
    /// AW768 / AW410K 这类键盘：65 字节 HID Feature
    case keyboardV8 = "APIv8"
    /// AW610M / AW958 这类鼠标：65 字节 USB 中断
    case mouseV7 = "APIv7"
    /// 还没确认报文的外设
    case unknown = "待确认"

    var title: String {
        switch self {
        case .builtinV3:  return "APIv3 · 12B HID"
        case .keyboardV8: return "APIv8 · 65B Feature"
        case .mouseV7:    return "APIv7 · 65B 中断"
        case .unknown:    return "协议待确认"
        }
    }

    /// 本机能不能直接下发灯效
    var canSendFromApp: Bool {
        self == .builtinV3
    }

    var note: String {
        switch self {
        case .builtinV3:
            return "已验证：12 盏灯的掩码与亮度都在真机上跑过。"
        case .keyboardV8:
            return "AW768 / AW410K 属于这一类，但报文还没在真机上比对过，先只做识别。"
        case .mouseV7:
            return "AW610M / AW958 属于这一类，灯区掩码偶有偏差，先只做识别。"
        case .unknown:
            return "型号不在已知表里，等抓到 AWCC 的输出报文再补。"
        }
    }
}

enum PeripheralLightingMap {
    /// 已知型号关键字 → 协议
    private static let nameTable: [(String, PeripheralLightProtocol)] = [
        ("aw768", .keyboardV8),
        ("aw410k", .keyboardV8),
        ("aw420k", .keyboardV8),
        ("aw510k", .keyboardV8),
        ("aw310k", .keyboardV8),
        ("aw610m", .mouseV7),
        ("aw958", .mouseV7),
        ("aw959", .mouseV7),
        ("aw558", .mouseV7),
        ("aw568", .keyboardV8)
    ]

    static func `protocol`(for device: PeripheralDevice) -> PeripheralLightProtocol {
        if device.isBuiltIn { return .builtinV3 }
        let name = device.product.lowercased()
        for (keyword, proto) in nameTable where name.contains(keyword) {
            return proto
        }
        return .unknown
    }

    /// 导出诊断时用的字典
    static func describe(_ device: PeripheralDevice) -> [String: Any] {
        let proto = `protocol`(for: device)
        return [
            "product": device.product,
            "manufacturer": device.manufacturer,
            "vendorID": String(format: "0x%04X", device.vendorID),
            "productID": String(format: "0x%04X", device.productID),
            "usagePage": String(format: "0x%02X", device.usagePage),
            "usage": String(format: "0x%02X", device.usage),
            "maxInputReportSize": device.maxInputReportSize,
            "transport": device.transport,
            "builtIn": device.isBuiltIn,
            "category": device.category,
            "lightProtocol": proto.rawValue
        ]
    }
}
