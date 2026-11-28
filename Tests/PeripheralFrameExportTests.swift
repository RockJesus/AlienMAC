//
//  PeripheralFrameExportTests.swift
//  AlienMACTests
//
//  参考帧导出：只对已有内置编码器的族出帧，帧形状必须自洽
//

import XCTest

final class PeripheralFrameExportTests: XCTestCase {

    func testMouseFramesAreWellFormed() {
        let frames = PeripheralFrameExport.frames(family: .mouse5A, color: (r: 0, g: 200, b: 255), brightnessPercent: 100)
        XCTAssertEqual(frames.count, 3)
        let single = frames[0]
        XCTAssertEqual(single.bytes.count, 64)
        // 帧尾 A5 后面是补 0 到 64 字节，所以 A5 在第 8 位（索引 7）
        XCTAssertEqual(single.bytes[7], 0xA5)
        XCTAssertEqual(Int(single.bytes[0]), 7)  // 长度字节 = 有效字节数（含末尾 A5）
        XCTAssertEqual(Array(single.bytes.prefix(4)), [0x07, 0x5A, 0x03, 0x01])
        XCTAssertFalse(frames[2].bytes.isEmpty)
    }

    func testKeyboardV8Frames() {
        let frames = PeripheralFrameExport.frames(family: .keyboardV8, color: (r: 255, g: 0, b: 0), brightnessPercent: 80)
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[0].reportType, "Feature")
        XCTAssertEqual(frames[0].bytes.first, 0x01)      // reportID 在载荷首位
        XCTAssertEqual(frames[0].bytes.count, 4)
        XCTAssertEqual(frames[0].bytes, [0x01, 0x05, 0x01, 0x51])
        XCTAssertEqual(frames[2].bytes.count, 65)
        // 亮度 80% → 0x08（0–10 刻度）
        XCTAssertEqual(frames[1].bytes, [0x01, 0x17, 0x08])
    }

    func testChassisV4Frames() {
        let frames = PeripheralFrameExport.frames(family: .chassisV4, color: (r: 255, g: 0, b: 128), brightnessPercent: 50)
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[0].bytes.count, 33)          // v4 固定 33 字节，无 Report ID
        XCTAssertEqual(frames[0].bytes.prefix(3), [0x03, 0x23, 0x00])
        XCTAssertEqual(Array(frames[1].bytes.prefix(3)), [0x03, 0x27, 0xFF])
        XCTAssertEqual(frames[2].bytes[2], FXv4Codec.dimming(forPercent: 50))
    }

    func testUnknownFamilyExportsNothing() {
        XCTAssertTrue(PeripheralFrameExport.frames(family: .displayV6).isEmpty)
        XCTAssertTrue(PeripheralFrameExport.frames(family: .none).isEmpty)
    }

    func testExportTextForV8() {
        let text = PeripheralFrameExport.text(deviceName: "AW768", vid: 0x04F2, pid: 0x1666, family: .keyboardV8)
        XCTAssertTrue(text.contains("04F2:1666"))
        XCTAssertTrue(text.contains("键盘 v8"))
        XCTAssertTrue(text.contains("未在你的这台设备上验证"))
        XCTAssertTrue(text.contains("[1] 握手 READY"))
    }

    func testExportTextExplainsMissingEncoder() {
        let text = PeripheralFrameExport.text(deviceName: "AW3418DW", vid: 0x0424, pid: 0x1234, family: .displayV6)
        XCTAssertTrue(text.contains("暂没有内置编码器"))
        XCTAssertTrue(text.contains("只读自检"))
    }
}
