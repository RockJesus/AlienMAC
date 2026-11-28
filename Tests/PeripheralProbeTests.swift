//
//  PeripheralProbeTests.swift
//  AlienMACTests
//
//  自检判定与「用户自建档案」的纯逻辑测试（不需要真机）
//

import XCTest

final class PeripheralProbeTests: XCTestCase {

    // MARK: - 协议族推断

    func testFamilyGuessByInterfaceCapability() {
        // 鼠标灯控接口：UsagePage 0x0C / Usage 0x01 且 64 字节输出
        XCTAssertEqual(PeripheralProbeRules.family(usagePage: 0x0C, usage: 0x01, maxOutput: 64, maxFeature: 0, vid: 0x1D57), .mouse5A)
        // 键盘：VID 0x04F2
        XCTAssertEqual(PeripheralProbeRules.family(usagePage: 0x06, usage: 0x02, maxOutput: 8, maxFeature: 65, vid: 0x04F2), .keyboardV8)
        // 显示器
        XCTAssertEqual(PeripheralProbeRules.family(usagePage: 0xFF00, usage: 0x01, maxOutput: 8, maxFeature: 0, vid: 0x0424), .displayV6)
        // 内置逐键键盘
        XCTAssertEqual(PeripheralProbeRules.family(usagePage: 0x0C, usage: 0x01, maxOutput: 64, maxFeature: 0, vid: 0x0D62), .keyboardV5)
        // 未知小报表设备：不猜
        XCTAssertEqual(PeripheralProbeRules.family(usagePage: 0x06, usage: 0x02, maxOutput: 4, maxFeature: 4, vid: 0x1234), .none)
    }

    func testMouseInterfaceWinsOverVID() {
        // 即便 VID 是未知的第三方鼠标，只要接口形状对，也能判成 0x5A 族
        XCTAssertEqual(PeripheralProbeRules.family(usagePage: 0x0C, usage: 0x01, maxOutput: 64, maxFeature: 8, vid: 0x2EA8), .mouse5A)
    }

    // MARK: - 结论判定

    func testVerdicts() {
        XCTAssertEqual(PeripheralProbeRules.verdict(writeOK: true, responseEmpty: false, maxOutput: 64, payload: 64), .replied)
        XCTAssertEqual(PeripheralProbeRules.verdict(writeOK: true, responseEmpty: true, maxOutput: 64, payload: 64), .written)
        XCTAssertEqual(PeripheralProbeRules.verdict(writeOK: false, responseEmpty: true, maxOutput: 64, payload: 64), .blocked)
        // 输出报表只有 8 字节：先判报表不足，而不是被占用
        XCTAssertEqual(PeripheralProbeRules.verdict(writeOK: false, responseEmpty: true, maxOutput: 8, payload: 64), .tooSmall)
    }

    func testReplyRecognition() {
        XCTAssertTrue(PeripheralProbeRules.looksLikeMouseReply([0x04, 0x5A, 0x17, 0x00, 0xA5]))
        XCTAssertTrue(PeripheralProbeRules.looksLikeMouseReply([0xA5]))
        XCTAssertFalse(PeripheralProbeRules.looksLikeMouseReply([0x01, 0x02, 0x03]))
    }

    // MARK: - 档案

    func testOverrideRoundTrip() throws {
        let item = PeripheralOverride(
            vid: 0x04CA, pid: 0x00A5,
            name: "Alienware Advanced Gaming Mouse AW558",
            family: .mouse5A, reportID: 0, payload: 64, brightnessScale: 100,
            verified: true, note: "写入成功且有回应", updatedAt: "2026-11-28")
        let file = PeripheralOverrideFile(schema: "alienmac.peripheral-overrides/1", items: [item])
        let data = try JSONEncoder.pretty.encode(file)
        let decoded = try JSONDecoder().decode(PeripheralOverrideFile.self, from: data)
        XCTAssertEqual(decoded.items.count, 1)
        XCTAssertEqual(decoded.items[0].id, "04CA:00A5")
        XCTAssertEqual(decoded.items[0].family, .mouse5A)
        XCTAssertTrue(decoded.items[0].verified)
    }

    func testProbeReportIdentity() {
        let r = ProbeReport(vid: 0x04CA, pid: 0x00A5, product: "AW558",
                            usagePage: 0x0C, usage: 0x01, maxOutput: 64, maxFeature: 8,
                            featureHex: "01 02", responseHex: "04 5A 17 00 A5",
                            verdict: .replied, detail: "ok", familyGuess: .mouse5A, elapsedMS: 120)
        XCTAssertEqual(r.id, "04CA:00A5-0C01")
    }
}
