//
//  ModelCatalogTests.swift
//  AlienMACTests
//
//  v2.7.5：机型库数据与查询的纯逻辑测试（不碰 IOKit、不碰界面）。
//

import XCTest

final class ModelCatalogTests: XCTestCase {

    private func loadFile() throws -> ModelCatalogFile {
        let bundle = Bundle(for: ModelCatalogTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "ModelCatalog", withExtension: "json"),
                               "测试包里没有 ModelCatalog.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ModelCatalogFile.self, from: data)
    }

    func testCatalogDecodes() throws {
        let file = try loadFile()
        XCTAssertEqual(file.schema, "alienmac.models/3")
        XCTAssertEqual(file.models.count, 29, "v3 表应有 29 款具名机型")
        XCTAssertEqual(file.models.reduce(0) { $0 + $1.zoneCount }, 1954, "灯区条数应与 v3 11 表一致")
        XCTAssertEqual(file.models.reduce(0) { $0 + $1.perKeyCount }, 365, "逐键条数应与 devices.csv 可解析部分一致")
    }

    func testAW510kPerKeyData() throws {
        let file = try loadFile()
        let m = try XCTUnwrap(file.models.first { $0.name == "Alienware AW510k" })
        XCTAssertEqual(m.zoneCount, 109)
        XCTAssertEqual(m.zoneLedTotal, 433)
        XCTAssertEqual(m.perKeyCount, 105)
        XCTAssertEqual(m.keyLedTotal, 141)
        XCTAssertTrue(m.hasPerKey)
        XCTAssertEqual(m.controllers.first?.key, "04F2:1830")
        XCTAssertGreaterThan(m.ledIndexCeiling, 100, "逐键 LED 索引应覆盖到 100 以上")
    }

    func testModelWithoutPerKeyStaysEmpty() throws {
        let file = try loadFile()
        let m = try XCTUnwrap(file.models.first { $0.name == "Alienware 13" })
        XCTAssertFalse(m.hasPerKey, "没有逐键映射的机型不能造键位")
        XCTAssertEqual(m.perKeyCount, 0)
        XCTAssertEqual(m.ledIndexCeiling, 0)
    }

    func testLookupByController() throws {
        let file = try loadFile()
        let models = file.models
        let hits = models.filter { m in
            m.controllers.contains { ModelCatalog.normalizeHex($0.vid) == "187C" && ModelCatalog.normalizeHex($0.pid) == "0550" }
        }
        XCTAssertGreaterThan(hits.count, 4, "187C:0550 是多个机型的整机控制器")
    }

    func testUncoveredControllerIsHonest() throws {
        let file = try loadFile()
        // 本机 AW1517 是 187C:0530，v3 表里没有这条
        let note = ModelCatalog.coverageNote(in: file.models, vid: 0x187C, pid: 0x0530)
        XCTAssertTrue(note.contains("没有"), "表里没有就必须直说，不能拿相近 PID 顶上：\(note)")
        XCTAssertTrue(note.contains("同 VID"), "同 VID 不同 PID 要明确警告：\(note)")
        let none = ModelCatalog.coverageNote(in: file.models, vid: 0x1234, pid: 0x5678)
        XCTAssertTrue(none.contains("没有 1234:5678"))
    }

    func testHexNormalization() {
        XCTAssertEqual(ModelCatalog.normalizeHex("0x187c"), "187C")
        XCTAssertEqual(ModelCatalog.normalizeHex("04f2:"), "04F2")
        XCTAssertEqual(ModelCatalog.normalizeHex(" 0527 "), "0527")
        XCTAssertEqual(ModelCatalog.normalizeHex(""), "")
    }

    func testProtocolOnlyWhenTableMatches() throws {
        let file = try loadFile()
        let a410 = try XCTUnwrap(file.models.first { $0.name == "Alienware AW410k" })
        XCTAssertNotNil(a410.protocolRule)
        XCTAssertEqual(a410.protocolRule?.category, "Keyboard")
        XCTAssertEqual(a410.protocolRule?.tron, "No")
        XCTAssertEqual(a410.protocolRule?.keyboard, "APIv8", "12 表里 AW410k 是键盘 APIv8")
        let r12 = try XCTUnwrap(file.models.first { $0.name == "Alienware Aurora R12" })
        XCTAssertEqual(r12.protocolRule?.tron, "APIv4")
        XCTAssertEqual(r12.protocolRule?.fan, "AMW1")
        let aw510k = try XCTUnwrap(file.models.first { $0.name == "Alienware AW510k" })
        XCTAssertNil(aw510k.protocolRule, "12 表里没有这款就不编协议")
    }

    func testMissingFieldsFallback() throws {
        let json = """
        {"schema":"alienmac.models/3","source":"","provenance":"","generatedAt":"2026-11-28",
         "models":[{"name":"Test Model","typeCode":3,"controllers":[],"zones":[],"keys":[]}]}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let file = try JSONDecoder().decode(ModelCatalogFile.self, from: data)
        let m = try XCTUnwrap(file.models.first)
        XCTAssertEqual(m.zoneCount, 0)
        XCTAssertEqual(m.perKeyCount, 0)
        XCTAssertNil(m.protocolRule)
        XCTAssertFalse(m.hasPerKey)
    }
}
