//
//  PeripheralSharedDataTests.swift
//  AlienMACTests
//
//  档案自动落位、提针档案比对、AWCC 6.x 扩展格式：都是纯规则，逐条钉住
//

import XCTest

final class PeripheralSharedDataTests: XCTestCase {

    // MARK: - 档案自动落位

    private func override(verified: Bool, zones: [Int]?) -> PeripheralOverride {
        PeripheralOverride(vid: 0x04CA, pid: 0x00A5, name: "AW558",
                           family: .mouse5A, reportID: 0, payload: 64, brightnessScale: 100,
                           verified: verified, note: "写入成功且有回应", updatedAt: "2026-11-28",
                           zones: zones, effect: "breathing", colorHex: "#FF006E")
    }

    func testVerifiedOverrideWithZonesProducesPlan() {
        let plans = PeripheralAutoApply.plans(
            connected: [(vid: 0x04CA, pid: 0x00A5, key: "04CA:00A5")],
            overrides: [override(verified: true, zones: [1, 2])])
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans.first?.zones, [1, 2])
        XCTAssertEqual(plans.first?.effect, "breathing")
        XCTAssertEqual(plans.first?.rgb, PeripheralRGB(r: 255, g: 0, b: 110))
        XCTAssertTrue(PeripheralAutoApply.summary(plans).contains("自动选中 2 个灯区"))
    }

    func testUnverifiedOrEmptyZonesNeverAutoApplies() {
        let unverified = PeripheralAutoApply.plans(
            connected: [(vid: 0x04CA, pid: 0x00A5, key: "04CA:00A5")],
            overrides: [override(verified: false, zones: [1])])
        XCTAssertTrue(unverified.isEmpty)
        let noZones = PeripheralAutoApply.plans(
            connected: [(vid: 0x04CA, pid: 0x00A5, key: "04CA:00A5")],
            overrides: [override(verified: true, zones: [])])
        XCTAssertTrue(noZones.isEmpty)
        let offline = PeripheralAutoApply.plans(
            connected: [(vid: 0x187C, pid: 0x0530, key: "187C:0530")],
            overrides: [override(verified: true, zones: [1])])
        XCTAssertTrue(offline.isEmpty)
    }

    func testHexParsing() {
        XCTAssertEqual(PeripheralAutoApply.rgb(fromHex: "#00D2FF"), PeripheralRGB(r: 0, g: 210, b: 255))
        XCTAssertEqual(PeripheralAutoApply.rgb(fromHex: "00d2ff"), PeripheralRGB(r: 0, g: 210, b: 255))
        XCTAssertNil(PeripheralAutoApply.rgb(fromHex: "#FFF"))
        XCTAssertNil(PeripheralAutoApply.rgb(fromHex: nil))
    }

    // MARK: - 提针比对

    private func archive(_ verdict: ProbeVerdict?) -> ProbeArchive {
        let report = verdict.map {
            ProbeReport(vid: 0x04CA, pid: 0x00A5, product: "AW558", usagePage: 0x0C, usage: 0x01,
                        maxOutput: 64, maxFeature: 8, featureHex: "", responseHex: "",
                        verdict: $0, detail: "", familyGuess: .mouse5A, elapsedMS: 1)
        }
        return ProbeArchive(appVersion: "2.7.4", generatedAt: "2026-11-28 18:30",
                            deviceName: "AW558", vid: 0x04CA, pid: 0x00A5, family: .mouse5A,
                            capability: "usage 0C/01 · out 64B", report: report)
    }

    func testCompareWithoutLocalRecord() {
        let text = ProbeArchiveCompare.summary(local: [], remote: archive(.replied))
        XCTAssertTrue(text.contains("还没有这台设备的自检记录"))
    }

    func testCompareMismatch() {
        let text = ProbeArchiveCompare.summary(local: [archive(.readonly)], remote: archive(.replied))
        XCTAssertTrue(text.contains("结论不一致"))
        XCTAssertTrue(text.contains("本机 仅属性"))
        XCTAssertTrue(text.contains("对方 有回应"))
    }

    func testCompareMatch() {
        let text = ProbeArchiveCompare.summary(local: [archive(.replied)], remote: archive(.replied))
        XCTAssertTrue(text.contains("结论一致"))
    }

    // MARK: - AWCC 6.x 扩展格式

    func testExtensionDecodeAcceptsStringLEDs() throws {
        let json = """
        {"schema":"alienmac.awcc6/1","sourceVersion":"6.14.20.0",
         "profiles":[{"vid":16700,"pid":8486,"model":"AW920K","sourceVersion":"6.14.20.0",
                      "leds":["W","A","S","D"],"keys":["W","A","S","D"]}]}
        """
        let file = try XCTUnwrap(AWCCExtensionDecoder.decode(Data(json.utf8)))
        XCTAssertEqual(file.profiles.count, 1)
        let profile = try XCTUnwrap(file.profiles.first)
        XCTAssertEqual(profile.leds.count, 4)
        XCTAssertEqual(profile.leds.first?.name, "W")
        XCTAssertTrue(profile.displayDetail.contains("4 灯区"))
    }

    func testExtensionRejectsUnknownSchema() {
        let json = #"{"schema":"whatever/9","profiles":[]}"#
        XCTAssertNil(AWCCExtensionDecoder.decode(Data(json.utf8)))
    }
}
