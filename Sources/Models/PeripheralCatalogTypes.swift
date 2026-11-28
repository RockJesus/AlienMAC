//
//  PeripheralCatalogTypes.swift
//  AlienMAC
//
//  外设全量设备库的数据结构：225 条授权设备 + 11 款带元数据的外设 + 343 条灯区
//

import Foundation

/// 灯效协议族（按 VID/PID 分派，不按「外星人」统一处理）
enum PeripheralFamily: String, Codable, CaseIterable {
    /// 鼠标族：64 字节 0x5A 载荷，reportID 0，走 Output Report
    case mouse5A
    /// 外接键盘：65 字节 Feature Report，reportID 1
    case keyboardV8
    /// 内置逐键 RGB 键盘控制器：64 字节 Feature，reportID 0xCC
    case keyboardV5
    /// 整机 FX 控制器：34 字节
    case chassisV4
    /// 显示器：65 字节中断
    case displayV6
    /// 无灯效（耳机、USB 桥）
    case none

    var title: String {
        switch self {
        case .mouse5A:   return "鼠标 0x5A · 64B"
        case .keyboardV8: return "键盘 v8 · 65B"
        case .keyboardV5: return "内置键盘 v5"
        case .chassisV4: return "整机 v4 · 34B"
        case .displayV6: return "显示器 v6 · 65B"
        case .none:      return "无灯效"
        }
    }

    /// 灯效是否可以由本 App 下发（只有已硬件验证的族才放开）
    var canSend: Bool {
        switch self {
        case .mouse5A: return true
        default: return false
        }
    }
}

/// 一条授权设备（AWCC 允许接入的 VID/PID）
struct CatalogDevice: Codable, Identifiable, Hashable {
    var vid: Int
    var pid: Int
    var model: String
    var codeName: String
    var opStore: String
    var metadataRequired: Bool
    var version: String
    var vendor: String
    var category: String
    var family: PeripheralFamily
    var reportID: Int
    var payload: Int
    var brightnessScale: Int

    var id: String { String(format: "%04X:%04X", vid, pid) }
}

/// 一个灯的官方条目
struct CatalogLed: Codable, Hashable {
    var id: Int
    var name: String
    var switchable: Bool
    var pseudo: Int
}

/// 有完整元数据的外设
struct CatalogModelProfile: Codable, Hashable {
    var vid: Int
    var pid: Int
    var category: String
    var keys: [String]
    var profileSlots: Int
    var leds: [CatalogLed]
    var metaFile: String
}

/// 整个目录文件
struct PeripheralCatalogFile: Codable {
    var schema: String
    var generated: String
    var source: String
    var devices: [CatalogDevice]
    var models: [String: CatalogModelProfile]
}
