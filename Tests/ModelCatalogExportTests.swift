//
//  ModelCatalogExportTests.swift
//  AlienMAC
//  v2.7.6：逐键 LED 体检 / 机型导出 / 协议别名对照
//

import XCTest

final class ModelCatalogExportTests: XCTestCase {

    private lazy var catalog: ModelCatalog = {
        let bundle = Bundle(for: ModelCatalogExportTests.self)
        guard let url = bundle.url(forResource: "ModelCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ModelCatalogFile.self, from: data) else {
            fatalError("测试包里没有 ModelCatalog.json")
        }
        return ModelCatalog(file: file)
    }()

    private func model(_ name: String) -> ModelEntry {
        guard let m = catalog.model(named: name) else {
            fatalError("机型库缺少 \(name)")
        }
        return m
    }

    // MARK: - 逐键 LED 体检

    func testAW510kAudit() {
        let m = model("Alienware AW510k")
        let a = m.ledAudit
        XCTAssertEqual(a.referenced, 141, "原表 141 条键→LED 引用")
        XCTAssertEqual(a.unique, 141, "141 颗互不重复")
        XCTAssertEqual(a.minIndex, 0)
        XCTAssertEqual(a.maxIndex, 153, "索引上界是 153，不是 140")
        XCTAssertEqual(a.span, 154)
        XCTAssertTrue(a.shared.isEmpty)
        XCTAssertEqual(a.gaps.count, 13, "0–153 里空出 13 个位置")
        XCTAssertTrue(a.summary.contains("空洞 13"))
    }

    func testM18R2Audit() {
        let m = model("Alienware m18R2")
        let a = m.ledAudit
        XCTAssertEqual(a.unique, 119)
        XCTAssertEqual(a.maxIndex, 119)
        XCTAssertEqual(a.gaps.count, 1, "0–119 共 120 个位置，占用 119")
        XCTAssertTrue(a.summary.contains("索引 0–119"))
    }

    func testModelWithoutPerKeyHasEmptyAudit() {
        let m = model("Alienware 13")
        XCTAssertFalse(m.hasPerKey)
        XCTAssertTrue(m.ledAudit.isEmpty)
        XCTAssertEqual(m.ledAudit.unique, 0)
        XCTAssertTrue(m.ledAudit.summary.contains("没有逐键"))
    }

    // MARK: - 协议别名对照

    func testProtocolCoverageAfterAlias() {
        XCTAssertEqual(catalog.withProtocolCount, 12, "别名对照后 12 款机型拿到协议行")
        XCTAssertEqual(catalog.protocolAliases.count, 8, "登记 8 条写法差异")
        XCTAssertEqual(catalog.unmatchedProtocols.count, 14, "12 表 25 行 - 已对上 11 行")
        XCTAssertEqual(catalog.withProtocolCount + catalog.unmatchedProtocols.count, 26,
                       "25 行里 Dell G7/G5 一行拆给两款机型，所以是 26 个落点")
    }

    func testAliasedProtocolKeepsSourceAndBasis() {
        let m = model("Alienware x15/17R2")
        guard let p = m.protocolRule else { return XCTFail("x15/17R2 应有协议行") }
        XCTAssertEqual(p.tron, "APIv4")
        XCTAssertEqual(p.keyboard, "APIv5")
        XCTAssertNotNil(p.source)
        XCTAssertTrue(p.source == "Alienware x15R2" || p.source == "Alienware x17R2")
        XCTAssertTrue(p.basis?.contains("x15R2") ?? false, "依据必须写清是 11 表的合并行")
    }

    func testModelWithoutProtocolStaysEmpty() {
        let m = model("Dell G5 5515")
        XCTAssertNil(m.protocolRule)
        XCTAssertTrue(m.protocolText.contains("没有"))
    }

    // MARK: - 导出

    func testTSVShape() throws {
        let m = model("Alienware AW510k")
        let tsv = ModelExport.tsv(m)
        let lines = tsv.components(separatedBy: "\n")
        XCTAssertTrue(lines.contains("索引\t灯区名\tLED数\t控制器"), "第一条表头")
        XCTAssertTrue(lines.contains("键ID\t键名\tLED索引"), "逐键表头")
        // 机型注释 1 行（有协议时再多 1 行）+ 表头 + 灯区 + 空行 + 逐键表头 + 逐键
        let commentLines = 1 + (m.protocolRule == nil ? 0 : 1)
        XCTAssertEqual(lines.count, commentLines + 1 + m.zoneCount + 1 + 1 + m.perKeyCount)
        XCTAssertTrue(lines.contains { $0.hasPrefix("0\tMain\t") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("1\t") && $0.contains(",") } || m.keys.first?.leds.count == 1)
    }

    func testJSONRoundTrip() throws {
        let m = model("Alienware AW510k")
        let data = try ModelExport.jsonData(m)
        let back = try JSONDecoder().decode(ModelEntry.self, from: data)
        XCTAssertEqual(back.name, m.name)
        XCTAssertEqual(back.zoneCount, m.zoneCount)
        XCTAssertEqual(back.keys.count, m.keys.count)
        XCTAssertEqual(back.zoneLedTotal, m.zoneLedTotal)
        XCTAssertEqual(back.ledAudit.unique, m.ledAudit.unique)
    }

    func testJSONAllModels() throws {
        let data = try ModelExport.jsonData(models: catalog.models, generatedAt: catalog.generatedAt)
        let doc = try JSONDecoder().decode(ModelCatalogExportFile.self, from: data)
        XCTAssertEqual(doc.schema, "alienmac.models.export/1")
        XCTAssertEqual(doc.models.count, 29)
        XCTAssertEqual(doc.models.reduce(0) { $0 + $1.zoneCount }, 1954)
    }

    func testExportFileNameIsPathSafe() {
        XCTAssertEqual(ModelExport.fileName(for: model("Alienware Area-51m R2/m17R3/R4")),
                       "AlienMAC-机型-Alienware_Area-51m_R2-m17R3-R4.json")
        XCTAssertEqual(ModelExport.fileName(for: model("Alienware m16R1 (Brazil)")),
                       "AlienMAC-机型-Alienware_m16R1_Brazil.json")
    }

    // MARK: - 选区清单（v2.7.7）

    func testKeySelectionUnion() throws {
        let m = model("Alienware AW510k")
        let first = m.keys[0]
        let data = try ModelExport.keySelection(m, keyIDs: [first.id], generatedAt: "2026-11-28")
        let doc = try JSONDecoder().decode(KeyLedSelectionFile.self, from: data)
        XCTAssertEqual(doc.schema, "alienmac.keyleds/1")
        XCTAssertEqual(doc.model, "Alienware AW510k")
        XCTAssertEqual(doc.selected.count, 1)
        XCTAssertEqual(doc.ledIndices, first.leds.sorted())
        XCTAssertTrue(doc.sharedIndices.isEmpty)
        XCTAssertTrue(doc.note.contains("不是帧"), "导出物不能自称帧")
    }

    func testKeySelectionReportsSharedIndices() throws {
        let m = model("Alienware AW510k")
        let k1 = m.keys[0], k2 = m.keys[1]
        let data = try ModelExport.keySelection(m, keyIDs: [k1.id, k2.id], generatedAt: "2026-11-28")
        let doc = try JSONDecoder().decode(KeyLedSelectionFile.self, from: data)
        let union = Set(k1.leds).union(Set(k2.leds)).sorted()
        XCTAssertEqual(doc.ledIndices, union)
        let overlap = Set(k1.leds).intersection(Set(k2.leds)).sorted()
        XCTAssertEqual(doc.sharedIndices, overlap)
        XCTAssertEqual(doc.selected.count, 2)
    }

    func testKeySelectionFileName() {
        XCTAssertEqual(ModelExport.keySelectionFileName(for: model("Alienware AW510k")),
                       "AlienMAC-机型-Alienware_AW510k-选区.json")
    }

    // MARK: - 外部对照（v2.7.7）

    private func aliasRule() -> ExternalAliasRule {
        ExternalAliasRule(source: "Alienware Aurora R14", targets: ["Dell G5 5515"],
                          basis: "外部提交：Aurora R14 与 G5 5515 同为 APIv4 笔记本族",
                          tron: "APIv4", keyboard: "No", fan: "AMW1", note: nil)
    }

    func testExternalAliasOnlyFillsMissing() throws {
        let cat = catalog
        let before = cat.withProtocolCount
        XCTAssertEqual(cat.applyExternalAliases([aliasRule()]), 1)
        XCTAssertEqual(cat.withProtocolCount, before + 1)
        let m = try XCTUnwrap(cat.model(named: "Dell G5 5515"))
        XCTAssertEqual(m.protocolRule?.category, "外部对照")
        XCTAssertEqual(m.protocolRule?.tron, "APIv4")
        XCTAssertTrue((m.protocolRule?.basis ?? "").contains("未验证"))
        XCTAssertEqual(cat.builtInProtocolCount, before, "内置计数不能被外部对照算进去")
        // 再来一次不重复补
        XCTAssertEqual(cat.applyExternalAliases([aliasRule()]), 0)
        XCTAssertEqual(cat.externalAliases.count, 1)
    }

    func testExternalAliasFillsEmptyButNeverOverwritesBuiltIn() throws {
        let cat = catalog
        // AW510k 内置表里本来没有协议行，外部对照可以补，但必须带「未验证」
        let rule = ExternalAliasRule(source: "外部提交-AW510k", targets: ["Alienware AW510k"],
                                     basis: "外部提交", tron: "APIv4", keyboard: "APIv8", fan: "No", note: nil)
        XCTAssertEqual(cat.applyExternalAliases([rule]), 1)
        let filled = try XCTUnwrap(cat.model(named: "Alienware AW510k")?.protocolRule)
        XCTAssertEqual(filled.category, "外部对照")
        XCTAssertTrue((filled.basis ?? "").contains("未验证"))
        // 已经内置协议行的机型（Aurora R12）不能被外部改掉
        let before = try XCTUnwrap(cat.model(named: "Alienware Aurora R12")?.protocolRule)
        let overwrite = ExternalAliasRule(source: "外部提交-R12", targets: ["Alienware Aurora R12"],
                                          basis: "覆盖测试", tron: "APIv0", keyboard: "No", fan: "WMI2", note: nil)
        XCTAssertEqual(cat.applyExternalAliases([overwrite]), 0)
        XCTAssertEqual(cat.model(named: "Alienware Aurora R12")?.protocolRule, before)
    }
}
