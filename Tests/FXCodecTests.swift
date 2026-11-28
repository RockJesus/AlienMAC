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

    // MARK: - v4 补全的块

    func testV4PowerBlockBytes() {
        XCTAssertEqual(FXv4Codec.powerBlock(0x00), [0x03, 0x22, 0x00])
        XCTAssertEqual(FXv4Codec.powerBlock(0xFF), [0x03, 0x22, 0x0F], "类型夹到 0–F")
        let padded = FXv4Codec.pad(FXv4Codec.powerBlock(0x01))
        XCTAssertEqual(padded?.count, FXv4Codec.payloadLength)
    }

    func testV4OneColorFrameLayout() {
        let frame = FXv4Codec.oneColor(FXRGBA(r: 0x12, g: 0x34, b: 0x56), ids: [1, 2, 3])
        XCTAssertEqual(frame?[0], 0x03)
        XCTAssertEqual(frame?[1], 0x27)
        XCTAssertEqual(Array(frame?[2..<5] ?? []), [0x12, 0x34, 0x56])
        XCTAssertEqual(frame?[5], 0x00, "固定占位字节")
        XCTAssertEqual(frame?[6], 0x03, "灯数")
        XCTAssertEqual(Array(frame?[7...] ?? []), [1, 2, 3])
        XCTAssertNil(FXv4Codec.oneColor(.white, ids: Array(0..<26)), "26 盏超过单帧上限")
    }

    // MARK: - 场景 Builder（Mock 与真机同一份组包）

    func testV4SceneBuilderFrameCountAndRoundTrip() {
        let lights = (0..<4).map { FXSceneLight(id: UInt8($0), color: FXRGBA(r: 0x00, g: 0x82, b: 0xFF)) }
        let packets = FXSceneBuilder.v4(lights: lights, dimming: 0x00)
        XCTAssertEqual(packets.count, 1 + lights.count * 2 + 2 + 1)

        let device = FXMockDevice(family: .v4)
        packets.forEach { device.consume($0) }
        XCTAssertEqual(device.violations.count, 0)
        XCTAssertEqual(device.lights.count, 4)
        XCTAssertTrue(device.lights.values.allSatisfy { $0.color.hex == "#0082FF" })
        XCTAssertEqual(device.brightness, 100)
    }

    func testV4SceneBuilderClampsDimmingAtFullBlack() {
        let lights = [FXSceneLight(id: 0, color: .white)]
        let packets = FXSceneBuilder.v4(lights: lights, dimming: 0x64)
        let device = FXMockDevice(family: .v4)
        packets.forEach { device.consume($0) }
        XCTAssertEqual(device.brightness, 0, "dim=0x64 应读作全灭")
    }

    func testV8SceneBuilderSplitsEveryFourBlocks() {
        // 13 颗灯 → 4 包（4/4/4/1），序号 1…4，块偏移不越界
        let lights = (1...13).map { FXSceneLight(id: UInt8($0), color: FXRGBA(r: 0x20, g: 0x40, b: 0x60)) }
        let packets = FXSceneBuilder.v8(lights: lights, brightness: 0x0A)
        XCTAssertEqual(packets.count, 1 + 4 + 1, "就绪 + 4 个上色包 + 亮度")

        let colorPackets = packets.filter { $0.transport == .write }
        XCTAssertEqual(colorPackets.count, 4)
        for (index, packet) in colorPackets.enumerated() {
            XCTAssertEqual(packet.payload.count, FXv8Codec.payloadLength)
            XCTAssertEqual(packet.payload[4], UInt8(index + 1), "分包序号从 1 递增")
        }
        XCTAssertEqual(colorPackets[0].payload[2], 4)
        XCTAssertEqual(colorPackets[3].payload[2], 1, "最后一包只有 1 块")
        // 第 4 包的 1 块应落在第一个块位
        XCTAssertEqual(colorPackets[3].payload[5], 13)
    }

    func testV8SceneBuilderRoundTripThirteenLights() {
        let lights = (1...13).map { FXSceneLight(id: UInt8($0), color: FXRGBA(r: 0xFF, g: 0x00, b: 0xD9)) }
        let packets = FXSceneBuilder.v8(lights: lights, brightness: 0x0A)
        let device = FXMockDevice(family: .v8)
        packets.forEach { device.consume($0) }
        XCTAssertEqual(device.violations.count, 0)
        XCTAssertEqual(device.lights.count, 13)
        XCTAssertTrue(device.lights.values.allSatisfy { $0.color.hex == "#FF00D9" })
    }

    func testV8BrightnessHardCeiling() {
        let packet = FXSceneBuilder.v8(lights: [FXSceneLight(id: 1, color: .white)], brightness: 0xFF).last
        XCTAssertEqual(packet?.payload[2], 0x0A)
    }

    // MARK: - 协议探测（包长 + VID）

    func testDetectionUsesVendorIDNotOnlyLength() {
        XCTAssertEqual(FXProtocol.detect(packetLengthWithReportID: 12, vendorID: 0x187C), .v3)
        XCTAssertEqual(FXProtocol.detect(packetLengthWithReportID: 34, vendorID: 0x187C), .v4)
        XCTAssertEqual(FXProtocol.detect(packetLengthWithReportID: 65, vendorID: 0x187C), .v6,
                       "65 字节 + Alienware 本体 VID 是 v6，不能当成 v8")
        XCTAssertEqual(FXProtocol.detect(packetLengthWithReportID: 65, vendorID: 0x04F2), .v8)
        XCTAssertEqual(FXProtocol.detect(packetLengthWithReportID: 65, vendorID: 0x0461), .v7)
        XCTAssertEqual(FXProtocol.detect(packetLengthWithReportID: 64, vendorID: 0x0D62), .v5)
    }

    // MARK: - 亮度映射（2.6.1）

    func testV4DimmingPercentMapping() {
        XCTAssertEqual(FXv4Codec.dimming(forPercent: 100), 0x00, "100% 不压暗")
        XCTAssertEqual(FXv4Codec.dimming(forPercent: 50), 0x32, "按上游 0x64 满量程线性压暗")
        XCTAssertEqual(FXv4Codec.dimming(forPercent: 1), 0x63)
        XCTAssertEqual(FXv4Codec.dimming(forPercent: 0), 0x64, "0% 全灭")
        XCTAssertEqual(FXv4Codec.dimming(forPercent: 120), 0x00, "越界钳到 100%")
    }

    // MARK: - 键盘四区按列划分（2.6.3）

    func testKeyboardZoneSplitFollowsColumnBoundary() {
        // 第 5 列边界右侧整格（"5" 键）归中左
        XCTAssertEqual(FXKeyboardZoneRule.segment(left: -7.13, right: -5.47), .middleLeft)
        // 边界左侧的整格（"4" 键）归左段
        XCTAssertEqual(FXKeyboardZoneRule.segment(left: -8.93, right: -7.27), .left)
        // 跨界的 "R"（中心正好压在列边界上）整体归入右侧，不切开
        XCTAssertEqual(FXKeyboardZoneRule.segment(left: -8.03, right: -6.37), .middleLeft)
        // 空间键、第 10 列之后
        XCTAssertEqual(FXKeyboardZoneRule.segment(left: -7.13, right: 0.83), .middleLeft)
        XCTAssertEqual(FXKeyboardZoneRule.segment(left: 1.87, right: 3.53), .middleRight)
    }

    // MARK: - Area-51m R2 双控制器（2.6.3，仅机身 v4 接入）

    func testArea51mr2Controllers() throws {
        let model = try XCTUnwrap(AlienwareCatalog.models.first { $0.id == "a51mr2" })
        XCTAssertEqual(model.controllers.count, 2, "键盘 v5 + 机身 v4 两套控制器")
        let chassis = try XCTUnwrap(model.controllers.first { $0.role == .chassis })
        XCTAssertEqual(chassis.vendorID, 0x187C)
        XCTAssertEqual(chassis.productID, 0x0550)
        XCTAssertEqual(chassis.protocol, .apiV4)
        XCTAssertEqual(chassis.byteLength, 34)
        XCTAssertTrue(chassis.supported, "机身 v4 已接入")
        XCTAssertEqual(model.protocol, .apiV4)
        XCTAssertEqual(model.zones, 5)

        let keyboard = try XCTUnwrap(model.controllers.first { $0.role == .keyboard })
        XCTAssertEqual(keyboard.vendorID, 0x0D62)
        XCTAssertEqual(keyboard.productID, 0x1A1C)
        XCTAssertEqual(keyboard.protocol, .apiV5)
        XCTAssertFalse(keyboard.supported, "v5 键盘只识别不下发")
        XCTAssertTrue(model.controllerSummary.contains("仅识别"))
    }

    func testArea51mr2ChassisLightIDs() {
        let ids = FXv4ChassisLights.area51mr2
        XCTAssertEqual(ids.map { $0.id }, [0, 1, 2, 3, 4])
        XCTAssertEqual(ids.last?.name, "下环")
    }

    func testV8BrightnessPercentMapping() {
        XCTAssertEqual(FXv8Codec.brightnessPercent(100), 0x0A)
        XCTAssertEqual(FXv8Codec.brightnessPercent(50), 0x05)
        XCTAssertEqual(FXv8Codec.brightnessPercent(10), 0x01)
        XCTAssertEqual(FXv8Codec.brightnessPercent(0), 0x00, "0% 关灯")
    }

    func testProtocolBridgeToAlienFXProtocol() {
        XCTAssertEqual(FXProtocol.v4.alienFXProtocol, .apiV4)
        XCTAssertEqual(FXProtocol.v8.alienFXProtocol, .apiV8)
        XCTAssertEqual(FXProtocol.v6.alienFXProtocol, .unknown, "v6/v7 还没有下发通道")
        XCTAssertEqual(FXProtocol.acpi.alienFXProtocol, .unknown)
    }
}
