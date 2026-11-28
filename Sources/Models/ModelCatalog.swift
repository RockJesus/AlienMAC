//
//  ModelCatalog.swift
//  AlienMAC
//
//  内置机型库（AWCC 设备库 v3）：29 个具名机型 / 1954 条灯区 / 365 条逐键 LED 索引。
//  数据源为社区实测表（T-Troll devices.csv + 10/11/12 三张表），随 App 打包（Resources/ModelCatalog.json）。
//  口径：原表直录，没有逐键映射的机型 keys 为空 —— 不推断、不补空。
//

import Foundation
import Combine

struct ModelController: Codable, Hashable, Identifiable {
    let vid: String
    let pid: String
    let name: String

    var id: String { "\(vid):\(pid):\(name)" }
    /// 规范化成 "187C:0530"
    var key: String { "\(vid.uppercased()):\(pid.uppercased())" }
}

struct ModelZone: Codable, Hashable {
    let index: Int
    let name: String
    let leds: Int
    let controller: String
}

struct ModelKey: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let leds: [Int]
}

struct ModelProtocolRule: Codable, Hashable {
    let category: String
    let tron: String
    let keyboard: String
    let fan: String
    let note: String
    /// 12 表里那一行的原始机型名（可能与本机型名不同，靠别名对照归位）
    let source: String?
    /// 为什么能对上这一行（同名 / 合并行 / 连字符写法）
    let basis: String?
}

/// 12 表与 11 表机型名不一致时登记的一条对照
struct ModelProtocolAlias: Codable, Hashable {
    let source: String
    let targets: [String]
    let basis: String
}

/// 12 表里有、但 11 表没有对应机型的协议行
struct ModelUnmatchedProtocol: Codable, Hashable {
    let model: String
    let category: String
    let tron: String
    let keyboard: String
    let fan: String
    let note: String
}

struct ModelEntry: Codable, Hashable, Identifiable {
    let name: String
    let typeCode: Int
    let controllers: [ModelController]
    let zones: [ModelZone]
    let keys: [ModelKey]
    let protocolRule: ModelProtocolRule?
    let zoneCount: Int
    let zoneLedTotal: Int
    let perKeyCount: Int
    let keyLedTotal: Int
    let summaryZones: Int
    let summaryLedTotal: Int

    var id: String { name }

    private enum CodingKeys: String, CodingKey {
        case name, typeCode, controllers, zones, keys
        case protocolRule = "protocol"
        case zoneCount, zoneLedTotal, perKeyCount, keyLedTotal, summaryZones, summaryLedTotal
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        typeCode = try c.decodeIfPresent(Int.self, forKey: .typeCode) ?? 0
        controllers = try c.decodeIfPresent([ModelController].self, forKey: .controllers) ?? []
        zones = try c.decodeIfPresent([ModelZone].self, forKey: .zones) ?? []
        keys = try c.decodeIfPresent([ModelKey].self, forKey: .keys) ?? []
        protocolRule = try c.decodeIfPresent(ModelProtocolRule.self, forKey: .protocolRule)
        zoneCount = try c.decodeIfPresent(Int.self, forKey: .zoneCount) ?? zones.count
        zoneLedTotal = try c.decodeIfPresent(Int.self, forKey: .zoneLedTotal) ?? 0
        perKeyCount = try c.decodeIfPresent(Int.self, forKey: .perKeyCount) ?? keys.count
        keyLedTotal = try c.decodeIfPresent(Int.self, forKey: .keyLedTotal) ?? 0
        summaryZones = try c.decodeIfPresent(Int.self, forKey: .summaryZones) ?? zoneCount
        summaryLedTotal = try c.decodeIfPresent(Int.self, forKey: .summaryLedTotal) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(typeCode, forKey: .typeCode)
        try c.encode(controllers, forKey: .controllers)
        try c.encode(zones, forKey: .zones)
        try c.encode(keys, forKey: .keys)
        try c.encodeIfPresent(protocolRule, forKey: .protocolRule)
        try c.encode(zoneCount, forKey: .zoneCount)
        try c.encode(zoneLedTotal, forKey: .zoneLedTotal)
        try c.encode(perKeyCount, forKey: .perKeyCount)
        try c.encode(keyLedTotal, forKey: .keyLedTotal)
        try c.encode(summaryZones, forKey: .summaryZones)
        try c.encode(summaryLedTotal, forKey: .summaryLedTotal)
    }

    var hasPerKey: Bool { !keys.isEmpty }

    var controllersText: String {
        controllers.isEmpty ? "—" : controllers.map { $0.key }.joined(separator: " · ")
    }

    var protocolText: String {
        guard let p = protocolRule else { return "v3 表里没有这款的协议行" }
        return "\(p.tron) / \(p.keyboard) / \(p.fan)"
    }

    /// 该机型所有键引用到的 LED 索引上限（没有逐键映射时退回灯区总 LED）
    var ledIndexCeiling: Int {
        let fromKeys = keys.flatMap { $0.leds }.max() ?? -1
        return max(fromKeys, 0)
    }
}

struct ModelCatalogFile: Codable {
    let schema: String
    let source: String
    let provenance: String
    let generatedAt: String
    let models: [ModelEntry]
    let protocolAliases: [ModelProtocolAlias]?
    let unmatchedProtocols: [ModelUnmatchedProtocol]?
}

final class ModelCatalog: ObservableObject {
    static let shared = ModelCatalog()

    let models: [ModelEntry]
    let source: String
    let generatedAt: String
    let protocolAliases: [ModelProtocolAlias]
    let unmatchedProtocols: [ModelUnmatchedProtocol]

    var modelCount: Int { models.count }
    var zoneTotal: Int { models.reduce(0) { $0 + $1.zoneCount } }
    var perKeyModelCount: Int { models.filter { $0.hasPerKey }.count }
    var keyTotal: Int { models.reduce(0) { $0 + $1.perKeyCount } }
    var withProtocolCount: Int { models.filter { $0.protocolRule != nil }.count }

    private convenience init() {
        var parsed: ModelCatalogFile?
        if let url = Bundle.main.url(forResource: "ModelCatalog", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            parsed = try? JSONDecoder().decode(ModelCatalogFile.self, from: data)
        } else {
            NSLog("AlienMAC 机型库未找到 ModelCatalog.json")
        }
        self.init(file: parsed)
        NSLog("AlienMAC 机型库：\(models.count) 款机型 / \(zoneTotal) 条灯区 / \(keyTotal) 条逐键 LED / \(withProtocolCount) 款有协议行")
    }

    /// 供测试与外部文件构造（不读 Bundle）
    init(file: ModelCatalogFile?) {
        models = file?.models ?? []
        source = file?.source ?? ""
        generatedAt = file?.generatedAt ?? ""
        protocolAliases = file?.protocolAliases ?? []
        unmatchedProtocols = file?.unmatchedProtocols ?? []
    }

    // MARK: - 查询

    func model(named name: String) -> ModelEntry? {
        models.first { $0.name == name }
    }

    /// 按 VID/PID 反查机型（大小写与十六进制写法都容忍）
    func models(vid: String, pid: String) -> [ModelEntry] {
        let v = Self.normalizeHex(vid)
        let p = Self.normalizeHex(pid)
        guard !v.isEmpty, !p.isEmpty else { return [] }
        return models.filter { m in
            m.controllers.contains { Self.normalizeHex($0.vid) == v && Self.normalizeHex($0.pid) == p }
        }
    }

    func models(vid: UInt32, pid: UInt32) -> [ModelEntry] {
        models(vid: String(format: "%04X", vid), pid: String(format: "%04X", pid))
    }

    /// 同 VID 但 PID 不同的机型（用于「本机型号不在表里，但同厂控制器有这些」的提示）
    func models(vidOnly vid: String) -> [ModelEntry] {
        let v = Self.normalizeHex(vid)
        guard !v.isEmpty else { return [] }
        return models.filter { m in m.controllers.contains { Self.normalizeHex($0.vid) == v } }
    }

    func search(_ keyword: String) -> [ModelEntry] {
        let k = keyword.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return models }
        let lower = k.lowercased()
        return models.filter { m in
            m.name.lowercased().contains(lower)
                || m.controllersText.lowercased().contains(lower)
                || m.protocolText.lowercased().contains(lower)
        }
    }

    static func normalizeHex(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces).uppercased()
        if t.hasPrefix("0X") { t = String(t.dropFirst(2)) }
        t = t.replacingOccurrences(of: ":", with: "")
        return t
    }

    /// 一句话说明本机 VID:PID 在 v3 表里的位置（没有就直说没有）
    func coverageNote(vid: UInt32, pid: UInt32) -> String {
        Self.coverageNote(in: models, vid: vid, pid: pid)
    }

    static func coverageNote(in models: [ModelEntry], vid: UInt32, pid: UInt32) -> String {
        let v = String(format: "%04X", vid)
        let p = String(format: "%04X", pid)
        let exact = models.filter { m in
            m.controllers.contains { normalizeHex($0.vid) == v && normalizeHex($0.pid) == p }
        }
        if !exact.isEmpty {
            return "v3 表里有 \(exact.count) 款机型用这个控制器：\(exact.map { $0.name }.joined(separator: "、"))"
        }
        let sameVid = models.filter { m in m.controllers.contains { normalizeHex($0.vid) == v } }
        if sameVid.isEmpty {
            return String(format: "v3 表里没有 %04X:%04X 这个控制器", vid, pid)
        }
        return String(format: "v3 表里没有 %04X:%04X；同 VID %04X 的机型有 %d 款（PID 不同，不能直接套用）",
                      vid, pid, vid, sameVid.count)
    }
}
