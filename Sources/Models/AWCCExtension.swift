//
//  AWCCExtension.swift
//  AlienMAC
//
//  AWCC 6.x 提取结果接入的占位格式：只接结构，不填假数据。
//  提取脚本产出什么型号、灯区、按键，App 就显示什么；没有就继续标「6.x 待补」。
//

import Foundation

/// 一条灯区（提取脚本给的是序号 + 名称）
struct AWCCExtensionLED: Codable, Hashable {
    var index: Int
    var name: String

    init(index: Int, name: String) {
        self.index = index
        self.name = name
    }

    /// 允许写成 "名称" 或 {index,name} 两种形态
    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let name = try? single.decode(String.self) {
            self.index = 0
            self.name = name
            return
        }
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        self.index = try keyed.decodeIfPresent(Int.self, forKey: .index) ?? 0
        self.name = try keyed.decodeIfPresent(String.self, forKey: .name) ?? ""
    }

    enum CodingKeys: String, CodingKey { case index, name }
}

struct AWCCExtensionProfile: Codable, Identifiable, Hashable {
    var vid: Int
    var pid: Int
    var model: String
    var sourceVersion: String
    var leds: [AWCCExtensionLED]
    var keys: [String]

    var id: String { String(format: "%04X:%04X", vid, pid) }

    init(vid: Int, pid: Int, model: String, sourceVersion: String,
         leds: [AWCCExtensionLED], keys: [String]) {
        self.vid = vid
        self.pid = pid
        self.model = model
        self.sourceVersion = sourceVersion
        self.leds = leds
        self.keys = keys
    }
}

struct AWCCExtensionFile: Codable {
    var schema: String
    var sourceVersion: String?
    var profiles: [AWCCExtensionProfile]

    static let schemaVersion = "alienmac.awcc6/1"

    init(schema: String = AWCCExtensionFile.schemaVersion, sourceVersion: String? = nil,
         profiles: [AWCCExtensionProfile]) {
        self.schema = schema
        self.sourceVersion = sourceVersion
        self.profiles = profiles
    }
}

enum AWCCExtensionDecoder {
    static func decode(_ data: Data) -> AWCCExtensionFile? {
        guard let file = try? JSONDecoder().decode(AWCCExtensionFile.self, from: data),
              file.schema == AWCCExtensionFile.schemaVersion else { return nil }
        return file
    }
}

extension AWCCExtensionProfile {
    /// 一条设备库行的展示文本：有灯区就写灯区数，没灯区就如实写 0
    var displayDetail: String {
        "6.x 元数据 · \(leds.count) 灯区 · \(keys.count) 按键（\(sourceVersion)）"
    }
}
