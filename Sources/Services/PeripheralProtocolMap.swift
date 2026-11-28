//
//  PeripheralProtocolMap.swift
//  AlienMAC
//
//  协议分派与亮度换算：同一句「亮度 50%」在不同族里是不同的数值
//

import Foundation

enum PeripheralProtocolMap {
    /// 九个协议代的 reportID（v0…v9）
    static let reportIDList: [Int] = [0, 2, 2, 2, 0, 0xCC, 0, 0, 1, 0]
    /// 九个协议代的亮度上限
    static let brightnessScale: [Int] = [0xF, 0x64, 0x64, 0x64, 0x64, 0xFF, 0x64, 0x64, 0x0A, 0x64]

    /// UI 的 0–100 换算成设备刻度：v8 只有 10 档，直接塞 100 会越界
    static func deviceBrightness(percent: Int, scale: Int) -> Int {
        let p = min(max(percent, 0), 100)
        guard scale > 0 else { return 0 }
        return Int((Double(p) / 100.0 * Double(scale)).rounded())
    }

    static func deviceBrightness(percent: Int, family: PeripheralFamily) -> Int {
        switch family {
        case .mouse5A:    return deviceBrightness(percent: percent, scale: 100)
        case .keyboardV8: return deviceBrightness(percent: percent, scale: 10)
        case .keyboardV5: return deviceBrightness(percent: percent, scale: 255)
        case .chassisV4:  return deviceBrightness(percent: percent, scale: 100)
        case .displayV6:  return deviceBrightness(percent: percent, scale: 100)
        case .none:       return 0
        }
    }

    /// 按 VID 推断族，用于目录里没有但插上了的设备
    static func family(vid: Int, category: String) -> PeripheralFamily {
        switch vid {
        case 0x04CA, 0x0461: return .mouse5A
        case 0x04F2:         return .keyboardV8
        case 0x0D62:         return .keyboardV5
        case 0x0424:         return .displayV6
        case 0x187C, 0x413C: return .chassisV4
        default:
            if category == "鼠标" { return .mouse5A }
            if category == "键盘" { return .keyboardV8 }
            return .none
        }
    }
}
