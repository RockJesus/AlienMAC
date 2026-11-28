//
//  PeripheralCatalogTests.swift
//  AlienMACTests
//
//  外设库与鼠标 0x5A 帧的纯逻辑测试（无需真机）
//

import XCTest

final class PeripheralCatalogTests: XCTestCase {

    // MARK: - 帧格式

    func testSingleColorFrame() {
        let f = FXMouseCodec.singleColor(r: 255, g: 0, b: 0)
        XCTAssertEqual(f.count, 64)
        XCTAssertEqual(Array(f.prefix(8)), [0x07, 0x5A, 0x03, 0x01, 0xFF, 0x00, 0x00, 0xA5])
        XCTAssertEqual(f[8], 0x00)
    }

    func testTriColorFrame() {
        let f = FXMouseCodec.triColor([(255, 0, 0), (0, 255, 0), (0, 0, 255)])
        XCTAssertEqual(Array(f.prefix(14)), [0x0D, 0x5A, 0x03, 0x00,
                                             0xFF, 0x00, 0x00,
                                             0x00, 0xFF, 0x00,
                                             0x00, 0x00, 0xFF, 0xA5])
        XCTAssertEqual(f.count, 64)
    }

    func testResetAndBootFrames() {
        XCTAssertEqual(Array(FXMouseCodec.bootLight().prefix(6)), [0x05, 0x5A, 0x01, 0x00, 0x00, 0xA5])
        let reset = FXMouseCodec.resetDefault()
        XCTAssertEqual(Array(reset.prefix(10)), [0x09, 0x5A, 0x10, 0x00, 0x52, 0x65, 0x73, 0x65, 0x74, 0xA5])
        XCTAssertEqual(reset.count, 64)
    }

    func testDPIFrame() {
        let f = FXMouseCodec.dpi(index: 1, x: 100, y: 100)
        XCTAssertEqual(Array(f.prefix(8)), [0x07, 0x5A, 0x12, 0x00, 0x01, 0x64, 0x64, 0xA5])
        XCTAssertEqual(f.count, 64)
    }

    func testLengthByteAndTerminatorAlwaysConsistent() {
        let frames = [FXMouseCodec.singleColor(r: 1, g: 2, b: 3),
                      FXMouseCodec.bootLight(),
                      FXMouseCodec.sleepLight(),
                      FXMouseCodec.reportRate(),
                      FXMouseCodec.sensorRead(),
                      FXMouseCodec.buttonState()]
        for f in frames {
            XCTAssertEqual(f.count, 64)
            XCTAssertEqual(f[Int(f[0])], 0xA5, "长度字节应正好指向 0xA5")
        }
    }

    func testBrightnessScalesColor() {
        let f = FXMouseCodec.singleColor(r: 200, g: 100, b: 0, brightness: 50)
        XCTAssertEqual(Array(f.prefix(7)), [0x07, 0x5A, 0x03, 0x01, 100, 50, 0])
    }

    // MARK: - 亮度刻度

    func testBrightnessConversionPerProtocol() {
        XCTAssertEqual(PeripheralProtocolMap.deviceBrightness(percent: 100, family: .keyboardV8), 10)
        XCTAssertEqual(PeripheralProtocolMap.deviceBrightness(percent: 50, family: .keyboardV8), 5)
        XCTAssertEqual(PeripheralProtocolMap.deviceBrightness(percent: 100, family: .keyboardV5), 255)
        XCTAssertEqual(PeripheralProtocolMap.deviceBrightness(percent: 50, family: .mouse5A), 50)
        XCTAssertEqual(PeripheralProtocolMap.deviceBrightness(percent: 130, family: .mouse5A), 100)
        XCTAssertEqual(PeripheralProtocolMap.deviceBrightness(percent: -5, family: .mouse5A), 0)
        XCTAssertEqual(PeripheralProtocolMap.deviceBrightness(percent: 50, family: .none), 0)
    }

    func testReportIDTable() {
        XCTAssertEqual(PeripheralProtocolMap.reportIDList.count, 10)
        XCTAssertEqual(PeripheralProtocolMap.reportIDList[5], 0xCC)
        XCTAssertEqual(PeripheralProtocolMap.reportIDList[8], 1)
        XCTAssertEqual(PeripheralProtocolMap.brightnessScale[5], 0xFF)
        XCTAssertEqual(PeripheralProtocolMap.brightnessScale[8], 0x0A)
    }

    // MARK: - 协议分派

    func testFamilyByVID() {
        XCTAssertEqual(PeripheralProtocolMap.family(vid: 0x04CA, category: "鼠标"), .mouse5A)
        XCTAssertEqual(PeripheralProtocolMap.family(vid: 0x0461, category: "鼠标"), .mouse5A)
        XCTAssertEqual(PeripheralProtocolMap.family(vid: 0x04F2, category: "键盘"), .keyboardV8)
        XCTAssertEqual(PeripheralProtocolMap.family(vid: 0x0424, category: "显示器灯控"), .displayV6)
        XCTAssertEqual(PeripheralProtocolMap.family(vid: 0x0D62, category: "内置逐键 RGB 键盘控制器"), .keyboardV5)
        XCTAssertEqual(PeripheralProtocolMap.family(vid: 0x187C, category: "整机 FX 控制器"), .chassisV4)
        XCTAssertEqual(PeripheralProtocolMap.family(vid: 0x0B0E, category: "耳机"), .none)
    }

    func testOnlyVerifiedFamiliesCanSend() {
        XCTAssertTrue(PeripheralFamily.mouse5A.canSend)
        for f in [PeripheralFamily.keyboardV8, .keyboardV5, .chassisV4, .displayV6, .none] {
            XCTAssertFalse(f.canSend, "\(f) 不应在真机比对前开放下发")
        }
    }

    // MARK: - 设备库资源

    func testBundledCatalogDecodes() throws {
        let bundle = Bundle(for: type(of: self))
        let url = try XCTUnwrap(bundle.url(forResource: "PeripheralCatalog", withExtension: "json"),
                                "测试包内缺少 PeripheralCatalog.json")
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(PeripheralCatalogFile.self, from: data)
        XCTAssertEqual(file.devices.count, 225)
        XCTAssertEqual(file.models.count, 11)
        XCTAssertEqual(file.models.values.reduce(0) { $0 + $1.leds.count }, 343)

        let guldan = try XCTUnwrap(file.devices.first { $0.pid == 0x00A5 })
        XCTAssertEqual(guldan.model, "Alienware Advanced Gaming Mouse AW558")
        XCTAssertEqual(guldan.family, .mouse5A)
        XCTAssertEqual(guldan.vid, 0x04CA)

        let keyboard = try XCTUnwrap(file.models["Alienware 510K Low-Profile RGB Mechanical Gaming Keyboard"])
        XCTAssertEqual(keyboard.leds.count, 106)
        XCTAssertGreaterThan(keyboard.keys.count, 100)
    }
}
