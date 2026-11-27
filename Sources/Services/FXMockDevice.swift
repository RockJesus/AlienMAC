//
//  FXMockDevice.swift
//  AlienMAC
//
//  没有真机时用来“接住”v4 / v8 报文的模拟设备：把每一帧解回灯态，
//  同时检查包长、前导码、灯数、序号、常量位这些结构约束。
//  它只做两件事：**回读**（证明 App 想表达的灯态确实被帧带到了设备侧）
//  和**挑错**（错包不会被静默吞掉）。不解 USB、不发 HID。
//

import Foundation

// MARK: - 灯态

struct FXLightState: Equatable {
    var id: UInt8
    var effect: FXEffectKind
    var color: FXRGBA
    var color2: FXRGBA
    var dimming: UInt8 = 0
}

// MARK: - 模拟设备

/// Mock 只覆盖已经能组包的两代协议，不引用 App 的机型枚举，便于单测独立编译
enum FXMockFamily: String {
    case v4, v8

    var title: String { rawValue }
}

final class FXMockDevice {
    let family: FXMockFamily

    private(set) var lights: [UInt8: FXLightState] = [:]
    private(set) var brightness: Int = 100
    private(set) var chain: UInt8 = 0
    private(set) var selectedLights: [UInt8] = []
    private(set) var violations: [String] = []
    private(set) var acceptedFrames: Int = 0
    private(set) var lastSequence: UInt8 = 0

    init(family: FXMockFamily) {
        self.family = family
    }

    var hasViolation: Bool { !violations.isEmpty }

    func consume(_ packet: FXPacket) {
        switch family {
        case .v4: decodeV4(packet.payload)
        case .v8: decodeV8(packet.payload)
        default: violations.append("\(family.title) 没有接入 mock 解码")
        }
    }

    private func fail(_ reason: String, packet: [UInt8]) {
        violations.append(reason + "｜" + packet.map { String(format: "%02X", $0) }.joined(separator: " "))
    }

    // MARK: v4

    private func decodeV4(_ bytes: [UInt8]) {
        guard bytes.count == FXv4Codec.payloadLength else {
            return fail("v4 包长应为 \(FXv4Codec.payloadLength)，实际 \(bytes.count)", packet: bytes)
        }
        guard bytes[0] == 0x03 else {
            return fail("v4 前导码应为 03，实际 \(String(format: "%02X", bytes[0]))", packet: bytes)
        }

        switch bytes[1] {
        case 0x21:
            let kind = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
            let animID = UInt16(bytes[4]) << 8 | UInt16(bytes[5])
            if kind == 0x0001 { lights.removeAll(); selectedLights.removeAll() }
            acceptedFrames += 1
            _ = animID

        case 0x23:
            let count = Int(UInt16(bytes[3]) << 8 | UInt16(bytes[4]))
            let ids = Array(bytes[5..<(5 + count)])
            guard count > 0, 5 + count <= bytes.count else {
                return fail("v4 选灯数量 \(count) 与报文长度不符", packet: bytes)
            }
            selectedLights = ids
            for id in ids where lights[id] == nil {
                lights[id] = FXLightState(id: id, effect: .steady, color: .off, color2: .off)
            }
            acceptedFrames += 1

        case 0x24:
            let action = bytes[2]
            let tempo = UInt16(bytes[5]) << 8 | UInt16(bytes[6])
            let color = FXRGBA(r: bytes[7], g: bytes[8], b: bytes[9])
            let effect: FXEffectKind = action == 0x01 ? .pulse : (action == 0x02 ? .morph : .steady)
            guard !selectedLights.isEmpty else {
                return fail("v4 上色前没有选灯（缺 03 23）", packet: bytes)
            }
            for id in selectedLights {
                lights[id] = FXLightState(id: id, effect: effect, color: color,
                                          color2: .off, dimming: lights[id]?.dimming ?? 0)
            }
            acceptedFrames += 1
            _ = tempo

        case 0x26:
            let dimming = min(bytes[2], 0x64)
            let count = Int(UInt16(bytes[3]) << 8 | UInt16(bytes[4]))
            guard count > 0, 5 + count <= bytes.count else {
                return fail("v4 亮度灯数 \(count) 与报文长度不符", packet: bytes)
            }
            for id in bytes[5..<(5 + count)] {
                lights[id, default: FXLightState(id: id, effect: .steady, color: .off, color2: .off)].dimming = dimming
            }
            // dim 是压暗量：0 = 最亮，0x64 = 全灭
            brightness = 100 - Int(dimming)
            acceptedFrames += 1

        case 0x27:
            let color = FXRGBA(r: bytes[2], g: bytes[3], b: bytes[4])
            let count = Int(bytes[6])
            guard bytes[5] == 0x00 else {
                return fail("v4 单色快写第 6 字节应为 00", packet: bytes)
            }
            guard count > 0, 7 + count <= bytes.count else {
                return fail("v4 单色快写灯数 \(count) 与报文长度不符", packet: bytes)
            }
            for id in bytes[7..<(7 + count)] {
                lights[id, default: FXLightState(id: id, effect: .steady, color: .off, color2: .off)].color = color
            }
            acceptedFrames += 1

        default:
            fail("v4 未知命令 \(String(format: "%02X", bytes[1]))", packet: bytes)
        }
    }

    // MARK: v8

    private func decodeV8(_ bytes: [UInt8]) {
        guard bytes.count == FXv8Codec.payloadLength else {
            return fail("v8 包长应为 \(FXv8Codec.payloadLength)，实际 \(bytes.count)", packet: bytes)
        }
        guard bytes[0] == FXv8Codec.reportID else {
            return fail("v8 Report ID 应为 01，实际 \(String(format: "%02X", bytes[0]))", packet: bytes)
        }

        switch bytes[1] {
        case 0x05:
            guard bytes[2] == 0x01 else {
                return fail("v8 就绪帧第 3 字节应为 01", packet: bytes)
            }
            chain = bytes[3]
            acceptedFrames += 1

        case 0x0E:
            let count = Int(bytes[2])
            let seq = bytes[4]
            guard bytes[3] == 0x00 else {
                return fail("v8 上色头第 4 字节应为 00", packet: bytes)
            }
            guard count > 0, count <= FXv8Codec.blockOffsets.count else {
                return fail("v8 一包最多 \(FXv8Codec.blockOffsets.count) 块，实际 \(count)", packet: bytes)
            }
            if lastSequence != 0, seq != lastSequence + 1 {
                fail("v8 分包序号跳变：上一包 \(lastSequence)，本包 \(seq)", packet: bytes)
            }
            lastSequence = seq

            for index in 0..<count {
                let base = FXv8Codec.blockOffsets[index]
                guard bytes[base + 3] == 0xA5 else {
                    return fail("v8 块 \(index) 的常量位应为 A5，实际 \(String(format: "%02X", bytes[base + 3]))", packet: bytes)
                }
                let id = bytes[base]
                let opcode = bytes[base + 1]
                let color = FXRGBA(r: bytes[base + 6], g: bytes[base + 7], b: bytes[base + 8])
                let color2 = FXRGBA(r: bytes[base + 9], g: bytes[base + 10], b: bytes[base + 11])
                let effect = FXEffectKind.allCases.first { $0.v8Opcode == opcode }
                guard let effect = effect else {
                    return fail("v8 块 \(index) 效果码 \(String(format: "%02X", opcode)) 未知", packet: bytes)
                }
                lights[id] = FXLightState(id: id, effect: effect, color: color,
                                          color2: color2, dimming: lights[id]?.dimming ?? 0)
            }
            selectedLights = Array(lights.keys).sorted()
            acceptedFrames += 1

        case 0x17:
            let value = min(bytes[2], 0x0A)
            brightness = Int(value) * 10
            acceptedFrames += 1

        default:
            fail("v8 未知命令 \(String(format: "%02X", bytes[1]))", packet: bytes)
        }
    }
}

// MARK: - 试跑场景

struct FXMockRunResult {
    let family: FXMockFamily
    let packets: [FXPacket]
    let lights: [FXLightState]
    let brightness: Int
    let violations: [String]
    let notes: [String]

    var passed: Bool { violations.isEmpty }
}

extension FXMockRunResult: Identifiable {
    var id: String { family.rawValue }
}

enum FXMockScenario {
    /// v4：四段灯区（humanfx 的 LEFT / MIDDLE_LEFT / MIDDLE_RIGHT / RIGHT）各上一色
    static func runV4() -> FXMockRunResult {
        let device = FXMockDevice(family: .v4)
        var packets: [FXPacket] = []
        var notes: [String] = []

        func emit(_ bytes: [UInt8]?, _ note: String) {
            guard let raw = bytes, let padded = FXv4Codec.pad(raw) else { return }
            let packet = FXPacket(transport: .setReport, payload: padded, note: note)
            packets.append(packet)
            device.consume(packet)
        }

        let zones: [(UInt8, FXRGBA)] = [
            (0x00, FXRGBA(r: 0x00, g: 0xC8, b: 0x50)),
            (0x01, FXRGBA(r: 0x00, g: 0x82, b: 0xFF)),
            (0x02, FXRGBA(r: 0xC8, g: 0x32, b: 0xFF)),
            (0x03, FXRGBA(r: 0xFF, g: 0x64, b: 0x00)),
        ]

        // 一条 03 24 只作用于“当前选中的灯”，所以逐段先选一颗再上色
        emit(FXv4Codec.animation(.configStart, id: 0x0001), "动画 1 开始（清空旧动画）")
        for zone in zones {
            emit(FXv4Codec.selectLights(loop: false, ids: [zone.0]), "选中灯 \(zone.0)")
            emit(FXv4Codec.addColor(zone.1, action: 0x00, duration: 0, tempo: 0x00FA),
                 "灯 \(zone.0) 常亮 \(zone.1.hex)")
        }
        emit(FXv4Codec.selectLights(loop: false, ids: zones.map { $0.0 }), "选中全部 4 段（给亮度用）")
        emit(FXv4Codec.dim(0x00, ids: zones.map { $0.0 }), "亮度 100%（dim=0）")
        emit(FXv4Codec.animation(.configPlay, id: 0x0001), "动画 1 结束并播放")

        notes.append("33 字节无 Report ID，SET_REPORT wValue 0x0202")
        notes.append("选灯传的是 LightID 序号，不是 v3 的位掩码")
        notes.append("亮度是压暗量：dim=0 最亮、dim=0x64 全灭")

        return FXMockRunResult(family: .v4, packets: packets,
                               lights: device.lights.values.sorted { $0.id < $1.id },
                               brightness: device.brightness,
                               violations: device.violations, notes: notes)
    }

    /// v8：五颗键，一包四块 + 一包一块
    static func runV8() -> FXMockRunResult {
        let device = FXMockDevice(family: .v8)
        var packets: [FXPacket] = []
        var notes: [String] = []

        func emit(_ bytes: [UInt8], _ transport: FXPacket.Transport, _ note: String, pad: Bool = true) {
            var payload = bytes
            if pad, payload.count < FXv8Codec.payloadLength {
                payload += Array(repeating: UInt8(0), count: FXv8Codec.payloadLength - payload.count)
            }
            let packet = FXPacket(transport: transport, payload: payload, note: note)
            packets.append(packet)
            device.consume(packet)
        }

        let keys: [(UInt8, FXRGBA)] = [
            (0x01, FXRGBA(r: 0xFF, g: 0x00, b: 0xD9)),
            (0x02, FXRGBA(r: 0x00, g: 0x82, b: 0xFF)),
            (0x03, FXRGBA(r: 0x00, g: 0xC8, b: 0x50)),
            (0x04, FXRGBA(r: 0xFF, g: 0xC8, b: 0x00)),
            (0x05, FXRGBA(r: 0xC8, g: 0x32, b: 0xFF)),
        ]

        emit(FXv8Codec.ready(), .setFeature, "就绪 05 01 51")

        for (index, chunk) in stride(from: 0, to: keys.count, by: 4).map({ Array(keys[$0..<min($0 + 4, keys.count)]) }).enumerated() {
            let seq = UInt8(index + 1)
            let blocks = chunk.map {
                FXv8Codec.LightBlock(id: $0.0, effect: FXEffectKind.steady.v8Opcode, tempo: 0x00,
                                     duration: 0x00, color: $0.1, color2: .off)
            }
            if let bytes = FXv8Codec.colorPacket(seq: seq, blocks: blocks) {
                emit(bytes, .write, "上色包 \(seq)：\(chunk.count) 块")
            }
        }

        emit(FXv8Codec.brightness(0x0A), .setFeature, "亮度 0A（满）")

        notes.append("65 字节，Report ID 01 在第一字节")
        notes.append("块落在 5/20/35/50，步长 15，块内第 4 字节恒 A5")
        notes.append("一包最多四块，五颗键要拆两包，序号从 1 递增")

        return FXMockRunResult(family: .v8, packets: packets,
                               lights: device.lights.values.sorted { $0.id < $1.id },
                               brightness: device.brightness,
                               violations: device.violations, notes: notes)
    }

    static func run(family: FXMockFamily) -> FXMockRunResult? {
        switch family {
        case .v4: return runV4()
        case .v8: return runV8()
        default: return nil
        }
    }
}
