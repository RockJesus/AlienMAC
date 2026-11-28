//
//  PeripheralOverrideTypes.swift
//  AlienMAC
//
//  用户自定义的外设协议档案：没有官方元数据的设备，也能靠自检结果接入。
//  纯数据结构，方便单测。
//

import Foundation

/// 一台设备的协议档案（用户侧可编辑）
struct PeripheralOverride: Codable, Identifiable, Hashable {
    var vid: Int
    var pid: Int
    /// 设备显示名，空则用系统产品名
    var name: String
    var family: PeripheralFamily
    var reportID: Int
    var payload: Int
    var brightnessScale: Int
    /// 是否通过自检（收到设备回应）
    var verified: Bool
    var note: String
    var updatedAt: String
    /// 档案命中后要自动选中的灯区（LightZone.rawValue），空表示不自动落位
    var zones: [Int]? = nil
    /// 档案命中后要自动套用的效果（LightEffect.code）
    var effect: String? = nil
    /// 档案命中后要自动套用的颜色，形如 "#FF006E"
    var colorHex: String? = nil

    var id: String { String(format: "%04X:%04X", vid, pid) }

    init(vid: Int, pid: Int, name: String, family: PeripheralFamily,
         reportID: Int, payload: Int, brightnessScale: Int,
         verified: Bool, note: String, updatedAt: String,
         zones: [Int]? = nil, effect: String? = nil, colorHex: String? = nil) {
        self.vid = vid
        self.pid = pid
        self.name = name
        self.family = family
        self.reportID = reportID
        self.payload = payload
        self.brightnessScale = brightnessScale
        self.verified = verified
        self.note = note
        self.updatedAt = updatedAt
        self.zones = zones
        self.effect = effect
        self.colorHex = colorHex
    }
}

/// 档案文件
struct PeripheralOverrideFile: Codable {
    var schema: String
    var items: [PeripheralOverride]
}

/// 自检结论
enum ProbeVerdict: String, Codable {
    /// 写入成功且设备有回应
    case replied = "有回应"
    /// 写入成功但没等到回应（部分固件不回 query 帧）
    case written = "已写入·无回应"
    /// 设备打开失败或被占用
    case blocked = "被占用"
    /// 输出报表长度不足，无法写入
    case tooSmall = "报表不足"
    /// 没有可用的灯控接口
    case noInterface = "无接口"
    /// 只读到了属性，未写入
    case readonly = "仅属性"

    var tone: String {
        switch self {
        case .replied:   return "ok"
        case .written:   return "warn"
        default:         return "bad"
        }
    }
}

/// 一次自检的结果
struct ProbeReport: Codable, Identifiable, Hashable {
    var vid: Int
    var pid: Int
    var product: String
    var usagePage: Int
    var usage: Int
    var maxOutput: Int
    var maxFeature: Int
    var featureHex: String
    var responseHex: String
    var verdict: ProbeVerdict
    var detail: String
    var familyGuess: PeripheralFamily
    var elapsedMS: Int

    var id: String { String(format: "%04X:%04X-%02X%02X", vid, pid, usagePage, usage) }
}

/// 纯规则：根据接口能力推断协议族，避免瞎写
enum PeripheralProbeRules {
    /// 0x5A 鼠标 query 帧的回应判定：返回报文里带 0x5A 即视为同一族
    static func looksLikeMouseReply(_ bytes: [UInt8]) -> Bool {
        bytes.contains(0x5A) || bytes.contains(0xA5)
    }

    static func family(usagePage: Int, usage: Int, maxOutput: Int, maxFeature: Int, vid: Int) -> PeripheralFamily {
        // 先认已知厂商：内置逐键键盘的灯控接口与鼠标形状相同，不能只看接口
        if vid == 0x0D62 { return .keyboardV5 }
        if vid == 0x04F2 { return .keyboardV8 }
        if vid == 0x0424 { return .displayV6 }
        // 再认接口形状：64 字节、Vendor-Defined 灯控接口就是 0x5A 族
        if usagePage == 0x0C && usage == 0x01 && maxOutput >= 64 {
            return .mouse5A
        }
        switch vid {
        case 0x04CA, 0x0461:
            return .mouse5A
        case 0x187C, 0x413C:
            return maxOutput >= 34 ? .chassisV4 : .none
        default:
            break
        }
        if maxFeature >= 65 { return .keyboardV8 }
        return .none
    }

    /// 判定结论：有回应 → replied；写入成功无回应 → written
    static func verdict(writeOK: Bool, responseEmpty: Bool, maxOutput: Int, payload: Int) -> ProbeVerdict {
        if maxOutput < payload { return .tooSmall }
        if !writeOK { return .blocked }
        return responseEmpty ? .written : .replied
    }

    static func hex(_ bytes: [UInt8], limit: Int = 24) -> String {
        bytes.prefix(limit).map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }
}
