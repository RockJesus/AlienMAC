//
//  FXCodecTests.swift
//  AlienMACTests
//
//  没有真机，就用 Mock 设备把 v4 / v8 的帧走一遍：
//  先断言报文形状（长度、前导码、报告号、字段偏移），
//  再让 Mock 把帧解回灯态，和“App 想表达的灯态”比对。
//

import XCTest

final class FXCodecTests: XCTestCase {

    // MARK: - v4 形状

    func testV4PayloadIs33BytesWithoutReportID() {
        let frame = FXv4Codec.animation(.configStart)
        XCTAssertEqual(frame[0], 0x03, "v4 首字节是前导码 03，不是 Report ID")
        XCTAssertNotNil(FXv4Codec.pad(frame))
        XCTAssertEqual(FXv4Codec.pad(frame)?.count, FXv4Codec.payloadLength)
        XCTAssertEqual(FXv4Codec.payloadLength, 33)
    }

    func testV4OverflowIsRejectedNotTruncated() {
        let tooMany = (0..<29).map { UInt8($0) }
        XCTAssertNil(FXv4Codec.selectLights(loop: true, ids: tooMany))
        var over = FXv4Codec.animation(.configStart)
        over += Array(repeating: UInt8(0xAA), count: 30)
        XCTAssertNil(FXv4Codec.pad(over), "超长必须报错，不能静默截断成 33 字节")
    }

    func testV4SelectFrameFieldOrder() {
        let ids: [UInt8] = [0x00, 0x01, 0x02, 0x03]
        let bytes = FXv4Codec.selectLights(loop: true, ids: ids)!
        XCTAssertEqual(Array(bytes[0..<5]), [0x03, 0x23, 0x01, 0x00, 0x04])
        XCTAssertEqual(Array(bytes[5..<9]), ids)
    }

    func testV4ColorFrameCarriesRGBAtExpectedOffsets() {
        let color = FXRGBA(r: 0x00, g: 0x82, b: 0xFF)
        let bytes = FXv4Codec.addColor(color, action: 0x00, duration: 0, tempo: 0x00FA)
        XCTAssertEqual(Array(bytes[0..<3]), [0x03, 0x24, 0x00], "动作码 0 = 常亮")
        XCTAssertEqual(Array(bytes[3..<5]), [0x00, 0x00], "时长 0 = 常驻")
        XCTAssertEqual(Array(bytes[5..<7]), [0x00, 0xFA], "节奏 0xFA = 稳定")
        XCTAssertEqual(Array(bytes[7..<10]), [0x00, 0x82, 0xFF])
    }

    // MARK: - v4 回读

    func testV4ScenarioRoundTrip() {
        let result = FXMockScenario.runV4()
        XCTAssertTrue(result.passed, "不该有结构违规：\(result.violations)")
        XCTAssertEqual(result.packets.count, 12, "开始 + 4×(选灯+上色) + 全选 + 亮度 + 播放")
        XCTAssertEqual(result.packets.first?.payload.count, 33)
        XCTAssertEqual(result.lights.count, 4)
        XCTAssertEqual(result.brightness, 100)

        let expected: [UInt8: FXRGBA] = [
            0x00: FXRGBA(r: 0x00, g: 0xC8, b: 0x50),
            0x01: FXRGBA(r: 0x00, g: 0x82, b: 0xFF),
            0x02: FXRGBA(r: 0xC8, g: 0x32, b: 0xFF),
            0x03: FXRGBA(r: 0xFF, g: 0x64, b: 0x00),
        ]
        for light in result.lights {
            XCTAssertEqual(light.color, expected[light.id], "灯 \(light.id) 颜色回读不一致")
            XCTAssertEqual(light.effect, .steady)
        }
    }

    func testV4BrightnessIsInvertedDimming() {
        let device = FXMockDevice(family: .v4)
        let select = FXv4Codec.pad(FXv4Codec.selectLights(loop: true, ids: [0x00])!)!
        device.consume(FXPacket(transport: .setReport, payload: select, note: "选灯"))
        let dim = FXv4Codec.pad(FXv4Codec.dim(0x64, ids: [0x00])!)!
        device.consume(FXPacket(transport: .setReport, payload: dim, note: "压到 0x64"))
        XCTAssertEqual(device.brightness, 0, "dim=0x64 对应完全熄灭")
    }

    func testV4ColorWithoutSelectIsAViolation() {
        let device = FXMockDevice(family: .v4)
        let bytes = FXv4Codec.pad(FXv4Codec.addColor(.white, action: 0x00))!
        device.consume(FXPacket(transport: .setReport, payload: bytes, note: "直接上色"))
        XCTAssertTrue(device.hasViolation)
        XCTAssertTrue(device.violations.contains { $0.contains("没有选灯") })
    }

    // MARK: - v8 形状

    func testV8ReadyAndHeader() {
        let ready = FXv8Codec.ready()
        XCTAssertEqual(ready, [0x01, 0x05, 0x01, 0x51])
        let header = FXv8Codec.colorHeader(count: 4, seq: 1)
        XCTAssertEqual(header, [0x01, 0x0E, 0x04, 0x00, 0x01])
    }

    func testV8BlockOffsetsAndConstants() {
        let blocks = (0..<4).map {
            FXv8Codec.LightBlock(id: UInt8($0 + 1), effect: 0x81, tempo: 0x10,
                                 duration: 0x20, color: FXRGBA(r: 0x10, g: 0x20, b: 0x30),
                                 color2: .off)
        }
        let packet = FXv8Codec.colorPacket(seq: 1, blocks: blocks)!
        XCTAssertEqual(packet.count, 65)
        for (index, base) in FXv8Codec.blockOffsets.enumerated() {
            XCTAssertEqual(packet[base], UInt8(index + 1), "块 \(index) 灯号")
            XCTAssertEqual(packet[base + 1], 0x81, "块 \(index) 效果码")
            XCTAssertEqual(packet[base + 3], 0xA5, "块 \(index) 常量位")
            XCTAssertEqual(packet[base + 6], 0x10)
            XCTAssertEqual(packet[base + 7], 0x20)
            XCTAssertEqual(packet[base + 8], 0x30)
        }
    }

    func testV8FifthBlockIsRejected() {
        let blocks = (0..<5).map {
            FXv8Codec.LightBlock(id: UInt8($0), effect: 0x81, tempo: 0, duration: 0,
                                 color: .off, color2: .off)
        }
        XCTAssertNil(FXv8Codec.colorPacket(seq: 1, blocks: blocks), "一包最多四块")
    }

    func testV8BrightnessClampsTo0A() {
        XCTAssertEqual(FXv8Codec.brightness(0x14), [0x01, 0x17, 0x0A])
    }

    // MARK: - v8 回读

    func testV8ScenarioRoundTrip() {
        let result = FXMockScenario.runV8()
        XCTAssertTrue(result.passed, "不该有结构违规：\(result.violations)")
        XCTAssertEqual(result.packets.count, 4, "就绪 + 两包上色 + 亮度")
        XCTAssertEqual(result.lights.count, 5)
        XCTAssertEqual(result.brightness, 100)

        let expected: [UInt8: FXRGBA] = [
            0x01: FXRGBA(r: 0xFF, g: 0x00, b: 0xD9),
            0x02: FXRGBA(r: 0x00, g: 0x82, b: 0xFF),
            0x03: FXRGBA(r: 0x00, g: 0xC8, b: 0x50),
            0x04: FXRGBA(r: 0xFF, g: 0xC8, b: 0x00),
            0x05: FXRGBA(r: 0xC8, g: 0x32, b: 0xFF),
        ]
        for light in result.lights {
            XCTAssertEqual(light.color, expected[light.id], "键 \(light.id) 颜色回读不一致")
            XCTAssertEqual(light.effect, .steady)
        }
    }

    func testV8SequenceGapIsDetected() {
        let device = FXMockDevice(family: .v8)
        func send(seq: UInt8) {
            let block = FXv8Codec.LightBlock(id: 1, effect: 0x81, tempo: 0, duration: 0,
                                             color: .white, color2: .off)
            let packet = FXPacket(transport: .write,
                                  payload: FXv8Codec.colorPacket(seq: seq, blocks: [block])!,
                                  note: "包 \(seq)")
            device.consume(packet)
        }
        send(seq: 1)
        send(seq: 3)
        XCTAssertTrue(device.hasViolation)
        XCTAssertTrue(device.violations.contains { $0.contains("序号跳变") })
    }

    func testV8ReportIDMismatchIsAViolation() {
        var payload = FXv8Codec.ready()
        payload[0] = 0x02
        payload += Array(repeating: UInt8(0), count: 65 - payload.count)
        let device = FXMockDevice(family: .v8)
        device.consume(FXPacket(transport: .setFeature, payload: payload, note: "错报告号"))
        XCTAssertTrue(device.violations.contains { $0.contains("Report ID") })
    }
}
