//
//  FXFrameCodec.swift
//  AlienMAC
//
//  v4 / v8 协议族的帧构造与解码。刻意不碰 IOKit、不碰 SwiftUI，
//  这样一套逻辑可以同时在 App 里跑、在单元测试里跑、在 Mock 设备里被逐帧解回来。
//
//  证据：
//  - v4（33 字节，无 Report ID，SET_REPORT 0x21/0x09 wValue 0x0202）字节布局取自
//    humanfx（G15 5511，PID 0x0550，实机跑通的组包）；部分命令（单色快写 03 27）
//    只有 alien-tools 的字段注释，没有实机实证，标 tableOnly。
//  - v8（65 字节，Report ID 0x01，先 SET_FEATURE 再 WRITE）字段偏移取自
//    alien-tools 的 AlienFX_SDK：block 落在 5/20/35/50，步长 15，四块一包。
//
//  两种公开实现在 v4 的“灯数”字段上有分歧：alien-tools 是 `0x00 + 1 字节数量`，
//  humanfx 是 `2 字节数量`（高字节恒 0）。这里按 humanfx 落，因为它是实机跑通的版本。
//

import Foundation

// MARK: - 颜色

struct FXRGBA: Equatable {
    var r: UInt8
    var g: UInt8
    var b: UInt8

    static let off = FXRGBA(r: 0, g: 0, b: 0)
    static let white = FXRGBA(r: 255, g: 255, b: 255)

    var hex: String { String(format: "#%02X%02X%02X", r, g, b) }
}

// MARK: - 效果

/// 与两代协议的公共子集对齐的效果类型
enum FXEffectKind: String, CaseIterable {
    case off, steady, pulse, morph, breathing, spectrum

    var title: String {
        switch self {
        case .off:       return "关"
        case .steady:    return "常亮"
        case .pulse:     return "脉冲"
        case .morph:     return "渐变"
        case .breathing: return "呼吸"
        case .spectrum:  return "光谱"
        }
    }

    /// v4 的动作码：0 常亮 / 1 脉冲 / 2 渐变
    var v4Action: UInt8? {
        switch self {
        case .steady:             return 0x00
        case .pulse, .breathing:  return 0x01
        case .morph:              return 0x02
        case .spectrum:           return 0x00
        case .off:                return 0x00
        }
    }

    /// v8 的效果码：80 关 / 81 常亮 / 82 脉冲 / 83 渐变 / 87 呼吸 / 88 光谱
    var v8Opcode: UInt8 {
        switch self {
        case .off:       return 0x80
        case .steady:    return 0x81
        case .pulse:     return 0x82
        case .morph:     return 0x83
        case .breathing: return 0x87
        case .spectrum:  return 0x88
        }
    }
}

// MARK: - 报文

/// 一帧待下发的报文
struct FXPacket: Identifiable {
    enum Transport: String {
        case setReport = "SET_REPORT"
        case setFeature = "SET_FEATURE"
        case write = "WRITE"
    }

    let id = UUID()
    let transport: Transport
    let payload: [UInt8]
    let note: String

    var hex: String { payload.map { String(format: "%02X", $0) }.joined(separator: " ") }
}

// MARK: - v4

enum FXv4Codec {
    /// humanfx 实机口径：33 字节，首字节 0x03 是前导码，不带 Report ID
    static let payloadLength = 33

    enum Animation: UInt16 {
        case configStart = 0x0001
        case configSave  = 0x0002
        case configPlay  = 0x0003
        case remove      = 0x0004
        case play        = 0x0005
        case setDefault  = 0x0006
        case setStartup  = 0x0007
    }

    static func animation(_ kind: Animation, id: UInt16 = 0x0001) -> [UInt8] {
        [0x03, 0x21,
         UInt8((kind.rawValue >> 8) & 0xFF), UInt8(kind.rawValue & 0xFF),
         UInt8((id >> 8) & 0xFF), UInt8(id & 0xFF)]
    }

    /// `03 23 <loop> <count hi> <count lo> <LightID…>`，LightID 是序号不是位掩码
    static func selectLights(loop: Bool, ids: [UInt8]) -> [UInt8]? {
        guard ids.count <= 28 else { return nil }
        var bytes: [UInt8] = [0x03, 0x23, loop ? 0x01 : 0x00,
                              UInt8((ids.count >> 8) & 0xFF), UInt8(ids.count & 0xFF)]
        bytes.append(contentsOf: ids)
        return bytes
    }

    /// `03 24 <action> <duration hi/lo> <tempo hi/lo> <R G B>`
    /// humanfx 只组单色，副色交给下一条 addColor 或走 v5/v8
    static func addColor(_ color: FXRGBA,
                         action: UInt8,
                         duration: UInt16 = 0,
                         tempo: UInt16 = 0x00FA) -> [UInt8] {
        [0x03, 0x24, action,
         UInt8((duration >> 8) & 0xFF), UInt8(duration & 0xFF),
         UInt8((tempo >> 8) & 0xFF), UInt8(tempo & 0xFF),
         color.r, color.g, color.b]
    }

    /// `03 26 <dim> <count hi/lo> <LightID…>`；dim 是“压暗量”，0 = 最亮、0x64 = 全灭
    static func dim(_ dimming: UInt8, ids: [UInt8]) -> [UInt8]? {
        guard ids.count <= 27 else { return nil }
        var bytes: [UInt8] = [0x03, 0x26, min(dimming, 0x64),
                              UInt8((ids.count >> 8) & 0xFF), UInt8(ids.count & 0xFF)]
        bytes.append(contentsOf: ids)
        return bytes
    }

    /// `03 27 <R G B> <00> <count> <LightID…>` —— 仅见 alien-tools 字段注释，未实机
    static func oneColor(_ color: FXRGBA, ids: [UInt8]) -> [UInt8]? {
        guard ids.count <= 25 else { return nil }
        var bytes: [UInt8] = [0x03, 0x27, color.r, color.g, color.b, 0x00, UInt8(ids.count)]
        bytes.append(contentsOf: ids)
        return bytes
    }

    /// 补零到 33 字节；超长直接判失败，绝不静默截断
    static func pad(_ bytes: [UInt8]) -> [UInt8]? {
        guard bytes.count <= payloadLength else { return nil }
        return bytes + Array(repeating: 0x00, count: payloadLength - bytes.count)
    }
}

// MARK: - v8

enum FXv8Codec {
    /// 65 字节，首字节是 Report ID 0x01
    static let payloadLength = 65
    static let reportID: UInt8 = 0x01
    static let blockStride = 15
    static let blockOffsets = [5, 20, 35, 50]

    /// `05 01 51`：chain 51 = 主键盘；FF 表示复位
    static func ready(chain: UInt8 = 0x51) -> [UInt8] {
        [reportID, 0x05, 0x01, chain]
    }

    /// `0E 01 <count> 00 <seq>`：声明本包要写几颗灯、第几包
    static func colorHeader(count: UInt8, seq: UInt8) -> [UInt8] {
        [reportID, 0x0E, count, 0x00, seq]
    }

    struct LightBlock {
        var id: UInt8
        var effect: UInt8
        var tempo: UInt8
        var duration: UInt8
        var color: FXRGBA
        var color2: FXRGBA
        var colorCount: UInt8 = 0x02
    }

    /// 一包四块，块内 13 字节，块间留 2 字节空位
    static func colorPacket(seq: UInt8, blocks: [LightBlock]) -> [UInt8]? {
        guard blocks.count <= blockOffsets.count else { return nil }
        var bytes = Array(repeating: UInt8(0x00), count: payloadLength)
        let header = colorHeader(count: UInt8(blocks.count), seq: seq)
        for (i, value) in header.enumerated() { bytes[i] = value }

        for (index, block) in blocks.enumerated() {
            let base = blockOffsets[index]
            bytes[base + 0] = block.id
            bytes[base + 1] = block.effect
            bytes[base + 2] = block.tempo
            bytes[base + 3] = 0xA5
            bytes[base + 4] = block.duration
            bytes[base + 5] = 0x0A
            bytes[base + 6] = block.color.r
            bytes[base + 7] = block.color.g
            bytes[base + 8] = block.color.b
            bytes[base + 9] = block.color2.r
            bytes[base + 10] = block.color2.g
            bytes[base + 11] = block.color2.b
            bytes[base + 12] = block.colorCount
        }
        return bytes
    }

    /// `17 <0–A>`：外置键盘亮度是 0–10，不是 0–100
    static func brightness(_ value: UInt8) -> [UInt8] {
        [reportID, 0x17, min(value, 0x0A)]
    }
}

// MARK: - 组包失败的显式错误

enum FXCodecError: Error, CustomStringConvertible {
    case tooManyLights(Int, limit: Int)
    case packetOverflow(Int, limit: Int)
    case sequenceExhausted

    var description: String {
        switch self {
        case .tooManyLights(let n, let limit): return "灯数 \(n) 超过单包上限 \(limit)"
        case .packetOverflow(let n, let limit): return "报文 \(n) 字节超过 \(limit) 字节"
        case .sequenceExhausted:               return "分包序号越界"
        }
    }
}
