//
//  ModelCatalogExport.swift
//  AlienMAC
//  v2.7.6：机型库的可核对产物 —— 逐键 LED 索引体检 + 机型导出（JSON / TSV）。
//  体检只做算术（占用、共用、空洞、越界上限），不改数据；导出原样输出内置机型库字段。
//

import Foundation

/// 一颗被多个键共用的 LED
struct ModelSharedLed: Hashable {
    let index: Int
    let keys: [String]
}

/// 逐键 LED 索引体检结果
struct ModelLedAudit: Hashable {
    /// 键 → LED 引用的总条数（含重复）
    let referenced: Int
    /// 去重后真正被占用的 LED 数
    let unique: Int
    let minIndex: Int
    let maxIndex: Int
    /// 被两个以上键指向的 LED
    let shared: [ModelSharedLed]
    /// 索引区间里没被任何键占用的位置
    let gaps: [Int]

    var span: Int { unique == 0 ? 0 : maxIndex - minIndex + 1 }
    var isEmpty: Bool { unique == 0 }

    /// 一行可核对摘要
    var summary: String {
        guard !isEmpty else { return "没有逐键 LED 索引" }
        var parts = ["索引 \(minIndex)–\(maxIndex)（\(span) 个位置）", "占用 \(unique) 颗"]
        parts.append(shared.isEmpty ? "共用 0 处" : "共用 \(shared.count) 处")
        parts.append(gaps.isEmpty ? "无空洞" : "空洞 \(gaps.count) 个")
        return parts.joined(separator: " · ")
    }
}

extension ModelEntry {
    /// 逐键 LED 索引体检：不做任何推断，只统计表里写了什么
    var ledAudit: ModelLedAudit {
        guard hasPerKey else {
            return ModelLedAudit(referenced: 0, unique: 0, minIndex: 0, maxIndex: 0, shared: [], gaps: [])
        }
        var owners: [Int: [String]] = [:]
        var referenced = 0
        for key in keys {
            for led in key.leds {
                referenced += 1
                owners[led, default: []].append(key.name)
            }
        }
        let indexes = owners.keys.sorted()
        guard let minIndex = indexes.first, let maxIndex = indexes.last else {
            return ModelLedAudit(referenced: referenced, unique: 0, minIndex: 0, maxIndex: 0, shared: [], gaps: [])
        }
        let shared = indexes
            .filter { (owners[$0]?.count ?? 0) > 1 }
            .map { ModelSharedLed(index: $0, keys: owners[$0] ?? []) }
        var gaps: [Int] = []
        for i in minIndex...maxIndex where owners[i] == nil { gaps.append(i) }
        return ModelLedAudit(referenced: referenced, unique: indexes.count,
                             minIndex: minIndex, maxIndex: maxIndex,
                             shared: shared, gaps: gaps)
    }
}

/// v4「选灯」帧试排结果：只生成 hex，不发硬件
struct SelectFramePreview: Hashable {
    struct Frame: Hashable {
        let ids: [UInt8]
        let bytes: [UInt8]
        var hex: String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }
    }
    let frames: [Frame]
    let oversized: Bool      // 有索引超过 UInt8 或分帧失败
    let note: String
}

enum ModelExportError: Error {
    case encodeFailed
}

/// 机型库导出：JSON（可再读回）与 TSV（贴进表格里核对）
enum ModelExport {

    static func jsonData(_ model: ModelEntry) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(model) else { throw ModelExportError.encodeFailed }
        return data
    }

    static func jsonData(models: [ModelEntry], generatedAt: String) throws -> Data {
        let doc = ModelCatalogExportFile(schema: "alienmac.models.export/1",
                                         generatedAt: generatedAt,
                                         models: models)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(doc) else { throw ModelExportError.encodeFailed }
        return data
    }

    /// 灯区 + 逐键两段，制表符分隔；直接从表里读到的字段，不加工
    static func tsv(_ model: ModelEntry) -> String {
        var lines: [String] = []
        lines.append("# \(model.name) · 类型码 \(model.typeCode) · \(model.controllersText)")
        if let p = model.protocolRule {
            lines.append("# 协议：Tron \(p.tron) / 键盘 \(p.keyboard) / 风扇 \(p.fan)"
                         + (p.source.map { "（12 表行：\($0)）" } ?? ""))
        }
        lines.append(["索引", "灯区名", "LED数", "控制器"].joined(separator: "\t"))
        for z in model.zones {
            lines.append(["\(z.index)", z.name, "\(z.leds)", z.controller].joined(separator: "\t"))
        }
        guard model.hasPerKey else {
            lines.append("# 该机型没有逐键 LED 索引")
            return lines.joined(separator: "\n")
        }
        lines.append("")
        lines.append(["键ID", "键名", "LED索引"].joined(separator: "\t"))
        for k in model.keys {
            lines.append(["\(k.id)", k.name, k.leds.map(String.init).joined(separator: ",")].joined(separator: "\t"))
        }
        return lines.joined(separator: "\n")
    }

    /// 选中若干键后的 LED 索引集合；索引按原表直录，不做映射、不生成帧
    static func keySelection(_ model: ModelEntry, keyIDs: Set<Int>, generatedAt: String) throws -> Data {
        let picked = model.keys.filter { keyIDs.contains($0.id) }
        var owners: [Int: Int] = [:]
        for k in picked {
            for led in k.leds { owners[led, default: 0] += 1 }
        }
        let indices = owners.keys.sorted()
        let shared = indices.filter { (owners[$0] ?? 0) > 1 }
        let doc = KeyLedSelectionFile(
            schema: "alienmac.keyleds/1",
            generatedAt: generatedAt,
            model: model.name,
            controllers: model.controllers.map { $0.key },
            typeCode: model.typeCode,
            selected: picked.map { .init(id: $0.id, name: $0.name, leds: $0.leds) },
            ledIndices: indices,
            sharedIndices: shared,
            note: "LED 索引取自社区实测 devices.csv，未做映射；本文件不是帧，也不会触发发送"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(doc) else { throw ModelExportError.encodeFailed }
        return data
    }

    /// 把选中的 LED 索引按 v4「选灯」命令试排成帧：每帧最多 28 个 LightID，
    /// 用 FXv4Codec.selectLights + pad。索引直接当 LightID 属于试排，未在真机验证。
    static func selectFramePreview(indices: [Int], maxPerFrame: Int = 28) -> SelectFramePreview {
        let sorted = indices.sorted()
        guard !sorted.isEmpty else {
            return SelectFramePreview(frames: [], oversized: false, note: "没有选中任何 LED 索引")
        }
        var frames: [SelectFramePreview.Frame] = []
        var oversized = false
        var cursor = 0
        while cursor < sorted.count {
            let chunk = Array(sorted[cursor..<min(cursor + maxPerFrame, sorted.count)])
            cursor += chunk.count
            guard chunk.allSatisfy({ $0 >= 0 && $0 <= 255 }) else { oversized = true; continue }
            let ids = chunk.map { UInt8($0) }
            guard let raw = FXv4Codec.selectLights(loop: false, ids: ids),
                  let padded = FXv4Codec.pad(raw) else {
                oversized = true
                continue
            }
            frames.append(.init(ids: ids, bytes: padded))
        }
        return SelectFramePreview(frames: frames, oversized: oversized,
                                  note: "按 v4「03 23」选灯命令试排，每帧 ≤28 个 LightID；索引直接当 LightID 未在真机验证，只生成不发送")
    }

    /// 12 表里还没对上的协议行导成 aliases 模板：协议值带出来，targets 留空等填
    static func aliasTemplate(unmatched: [ModelUnmatchedProtocol]) throws -> Data {
        let rules = unmatched.map { row in
            ExternalAliasRule(source: row.model,
                              targets: [],
                              basis: "待填：这条协议行对应 11 表哪款机型（填进 targets 才能生效）",
                              tron: row.tron, keyboard: row.keyboard, fan: row.fan,
                              note: row.note.isEmpty ? nil : row.note)
        }
        let doc = ExternalAliasFile(schema: "alienmac.aliases/1",
                                    note: "由 AlienMAC 机型库导出：12 表未对上的 \(rules.count) 行，填好 targets 后重新导入",
                                    aliases: rules)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(doc) else { throw ModelExportError.encodeFailed }
        return data
    }

    static func keySelectionFileName(for model: ModelEntry) -> String {
        fileName(for: model).replacingOccurrences(of: ".json", with: "-选区.json")
    }

    static func fileName(for model: ModelEntry) -> String {
        let safe = model.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        return "AlienMAC-机型-\(safe).json"
    }
}

/// 选中的键 → LED 索引集合（供后续帧编码/调查使用，本身不是帧）
struct KeyLedSelectionFile: Codable {
    struct SelectedKey: Codable {
        let id: Int
        let name: String
        let leds: [Int]
    }
    let schema: String
    let generatedAt: String
    let model: String
    let controllers: [String]
    let typeCode: Int
    let selected: [SelectedKey]
    let ledIndices: [Int]
    /// 被两个以上选中键同时指向的索引
    let sharedIndices: [Int]
    let note: String
}

struct ModelCatalogExportFile: Codable {
    let schema: String
    let generatedAt: String
    let models: [ModelEntry]
}
