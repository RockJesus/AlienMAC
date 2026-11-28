//
//  PeripheralDiagnosticReportTests.swift
//  AlienMACTests
//
//  诊断文本：必须带结论与回读，且不能把「没自检」写成「有回应」
//

import XCTest

final class PeripheralDiagnosticReportTests: XCTestCase {

    private func report(_ verdict: ProbeVerdict, writeOK: Bool) -> ProbeReport {
        ProbeReport(vid: 0x04CA, pid: 0x00A5, product: "AW558",
                    usagePage: 0x0C, usage: 0x01, maxOutput: 64, maxFeature: 8,
                    featureHex: "01 02 03",
                    responseHex: verdict == .replied ? "04 5A 17 00 A5" : "",
                    verdict: verdict,
                    detail: verdict == .replied ? "写入成功且有回应" : "写入成功但没等到回应",
                    familyGuess: .mouse5A, elapsedMS: 42)
    }

    func testReportWithReply() {
        let text = PeripheralDiagnosticReport.text(
            deviceName: "AW558", vid: 0x04CA, pid: 0x00A5, family: .mouse5A,
            capability: "usage 0C/01 · out 64B · feature 8B · in 8B · USB",
            report: report(.replied, writeOK: true),
            frames: PeripheralFrameExport.frames(family: .mouse5A),
            appVersion: "2.7.3", date: "2026-11-28 18:00")
        XCTAssertTrue(text.contains("App 版本：2.7.3"))
        XCTAssertTrue(text.contains("结论：有回应"))
        XCTAssertTrue(text.contains("RX ← 04 5A 17 00 A5"))
        XCTAssertTrue(text.contains("FEATURE ← 01 02 03"))
        XCTAssertTrue(text.contains("未在你的设备上验证"))
        XCTAssertTrue(text.contains("不含用户名、路径、序列号"))
    }

    func testReportWithoutProbeSaysSo() {
        let text = PeripheralDiagnosticReport.text(
            deviceName: "AW768", vid: 0x04F2, pid: 0x1666, family: .keyboardV8,
            capability: "usage 01/06 · out 8B · feature 65B · in 14B · USB",
            report: nil, frames: [], appVersion: "2.7.3", date: "2026-11-28 18:00")
        XCTAssertTrue(text.contains("还没有做过自检"))
        XCTAssertFalse(text.contains("结论：有回应"))
        XCTAssertFalse(text.contains("结论：有回应\n"))
    }

    func testEmptyFramesAreExplained() {
        let text = PeripheralDiagnosticReport.text(
            deviceName: "AW3418DW", vid: 0x0424, pid: 0x1234, family: .displayV6,
            capability: "usage FF00/01 · out 8B", report: nil, frames: [],
            appVersion: "2.7.3", date: "2026-11-28 18:00")
        XCTAssertTrue(text.contains("该协议族暂没有内置编码器"))
    }
}
