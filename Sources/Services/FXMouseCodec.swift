//
//  FXMouseCodec.swift
//  AlienMAC
//
//  鼠标族 0x5A 帧构造：帧首是长度字节，帧尾 0xA5，其余补 0 到 64 字节。
//  参考 AW558（04CA:00A5）协议说明书，全部帧已在 Windows 侧硬件验证。
//

import Foundation

enum FXMouseCodec {
    static let defaultPayloadLength = 64
    static let terminator: UInt8 = 0xA5

    /// 组装：[len][0x5A]…[0xA5]，补 0 到 payloadLength
    static func frame(_ body: [UInt8], payloadLength: Int = defaultPayloadLength) -> [UInt8] {
        // body 形状：0x5A, cmd, subcmd, 数据…（不含 len 与 A5）
        let lengthByte = UInt8(body.count + 1)   // +1 是结尾的 A5
        var out = [lengthByte] + body + [terminator]
        if out.count < payloadLength {
            out.append(contentsOf: Array(repeating: 0, count: payloadLength - out.count))
        }
        return Array(out.prefix(payloadLength))
    }

    /// 单色：07 5A 03 01 R G B A5
    static func singleColor(r: Int, g: Int, b: Int, brightness: Int = 100) -> [UInt8] {
        frame([0x5A, 0x03, 0x01] + rgb(r, g, b, brightness: brightness))
    }

    /// 三色：0D 5A 03 00 R1G1B1 R2G2B2 R3G3B3 A5
    static func triColor(_ colors: [(Int, Int, Int)], brightness: Int = 100) -> [UInt8] {
        var data: [UInt8] = []
        for i in 0..<3 {
            let c = i < colors.count ? colors[i] : colors.last ?? (0, 0, 0)
            data += rgb(c.0, c.1, c.2, brightness: brightness)
        }
        return frame([0x5A, 0x03, 0x00] + data)
    }

    /// 双色：0A 5A 03 02 R1G1B1 R2G2B2 A5
    static func dualColor(_ a: (Int, Int, Int), _ b: (Int, Int, Int), brightness: Int = 100) -> [UInt8] {
        frame([0x5A, 0x03, 0x02] + rgb(a.0, a.1, a.2, brightness: brightness)
                              + rgb(b.0, b.1, b.2, brightness: brightness))
    }

    /// 七彩：19 5A 03 03 (7×RGB) A5
    static func sevenColor(_ colors: [(Int, Int, Int)], brightness: Int = 100) -> [UInt8] {
        var data: [UInt8] = []
        for i in 0..<7 {
            let c = i < colors.count ? colors[i] : colors.last ?? (0, 0, 0)
            data += rgb(c.0, c.1, c.2, brightness: brightness)
        }
        return frame([0x5A, 0x03, 0x03] + data)
    }

    /// 静态/动态：0A 5A 03 04 mode type color tempo duration option A5
    static func mode(mode: Int, type: Int, color: Int, tempo: Int, duration: Int, option: Int) -> [UInt8] {
        frame([0x5A, 0x03, 0x04,
               UInt8(clamping: mode), UInt8(clamping: type), UInt8(clamping: color),
               UInt8(clamping: tempo), UInt8(clamping: duration), UInt8(clamping: option)])
    }

    /// 开机灯效：05 5A 01 00 00 A5
    static func bootLight() -> [UInt8] { frame([0x5A, 0x01, 0x00, 0x00]) }

    /// 休眠灯效：06 5A 02 00 00 00 A5
    static func sleepLight() -> [UInt8] { frame([0x5A, 0x02, 0x00, 0x00, 0x00]) }

    /// 恢复默认：09 5A 10 00 "Reset" A5
    static func resetDefault() -> [UInt8] {
        frame([0x5A, 0x10, 0x00] + Array("Reset".utf8))
    }

    /// 回报率：05 5A 11 00 00 A5
    static func reportRate() -> [UInt8] { frame([0x5A, 0x11, 0x00, 0x00]) }

    /// DPI：07 5A 12 00 DpiNo DpiX DpiY A5
    static func dpi(index: Int, x: Int, y: Int) -> [UInt8] {
        frame([0x5A, 0x12, 0x00, UInt8(clamping: index), UInt8(clamping: x), UInt8(clamping: y)])
    }

    /// 读传感器：04 5A 14 02 A5
    static func sensorRead() -> [UInt8] { frame([0x5A, 0x14, 0x02]) }

    /// 读按键状态：04 5A 17 00 A5
    static func buttonState() -> [UInt8] { frame([0x5A, 0x17, 0x00]) }

    // MARK: - 辅助

    private static func rgb(_ r: Int, _ g: Int, _ b: Int, brightness: Int) -> [UInt8] {
        let k = Double(min(max(brightness, 0), 100)) / 100.0
        func c(_ v: Int) -> UInt8 {
            UInt8(min(max(Int((Double(min(max(v, 0), 255)) * k).rounded()), 0), 255))
        }
        return [c(r), c(g), c(b)]
    }
}
