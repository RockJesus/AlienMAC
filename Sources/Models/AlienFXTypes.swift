//
//  AlienFXTypes.swift
//  AlienMAC
//
//  Alienware 17 R4 AlienFX APIv3 协议类型定义
//  VID: 0x187C  PID: 0x0530
//  HID Report ID: 0x02，数据长度 12 字节（不含 Report ID）
//

import Foundation
import SwiftUI
import AppKit

// MARK: - RGB 颜色

/// 8-bit RGB 颜色
struct RGBColor: Equatable, Codable {
    var r: UInt8
    var g: UInt8
    var b: UInt8

    /// 转为 SwiftUI Color
    var swiftUIColor: Color {
        Color(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0)
    }

    /// 从 SwiftUI Color 构建
    init(color: Color) {
        guard let nsColor = NSColor(color).usingColorSpace(.sRGB) else {
            self.r = 0; self.g = 0; self.b = 0
            return
        }
        self.r = UInt8(max(0, min(255, Int((nsColor.redComponent * 255).rounded()))))
        self.g = UInt8(max(0, min(255, Int((nsColor.greenComponent * 255).rounded()))))
        self.b = UInt8(max(0, min(255, Int((nsColor.blueComponent * 255).rounded()))))
    }

    init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    // 常用颜色
    static let red     = RGBColor(r: 255, g: 0,   b: 0)
    static let green   = RGBColor(r: 0,   g: 255, b: 0)
    static let blue    = RGBColor(r: 0,   g: 0,   b: 255)
    static let white   = RGBColor(r: 255, g: 255, b: 255)
    static let cyan    = RGBColor(r: 0,   g: 255, b: 255)
    static let magenta = RGBColor(r: 255, g: 0,   b: 255)
    static let yellow  = RGBColor(r: 255, g: 255, b: 0)
    static let orange  = RGBColor(r: 255, g: 165, b: 0)
    static let purple  = RGBColor(r: 128, g: 0,   b: 128)
    static let off     = RGBColor(r: 0,   g: 0,   b: 0)
}

// MARK: - 灯光效果

/// 硬件灯光效果类型
enum LightEffect: String, CaseIterable, Identifiable, Codable {
    case color     = "常亮"
    case pulse     = "脉冲"
    case morph     = "渐变"
    case breathing = "呼吸"
    case spectrum  = "光谱"
    case wave      = "光波"
    case scanner   = "扫描"

    var id: String { rawValue }

    /// 稳定的持久化标识（不随界面文案变化）
    var code: String {
        switch self {
        case .color:     return "color"
        case .pulse:     return "pulse"
        case .morph:     return "morph"
        case .breathing: return "breathing"
        case .spectrum:  return "spectrum"
        case .wave:      return "wave"
        case .scanner:   return "scanner"
        }
    }

    init(code: String) {
        switch code {
        case "pulse":     self = .pulse
        case "morph":     self = .morph
        case "breathing": self = .breathing
        case "spectrum":  self = .spectrum
        case "wave":      self = .wave
        case "scanner":   self = .scanner
        default:          self = .color
        }
    }

    /// APIv3 操作码 (v1OpCodes[])
    var opcode: UInt8 {
        switch self {
        case .color:     return 3
        case .pulse:     return 2
        case .morph:     return 1
        case .breathing: return 1
        // 光谱 / 光波 / 扫描这三类由 App 逐帧算色，硬件侧按常亮下发当前颜色
        case .spectrum, .wave, .scanner: return 3
        }
    }

    /// 是否需要第二个颜色
    var needsSecondaryColor: Bool {
        switch self {
        case .morph, .breathing:
            return true
        default:
            return false
        }
    }

    /// 是否需要下发节奏命令 (0x0E)：渐变/呼吸看 tempo，脉冲同样要看
    var needsTempoCommand: Bool {
        needsSecondaryColor || self == .pulse
    }
}

// MARK: - 灯区定义

/// 灯区（3 字节位掩码，24 位；Alienware 17 R4 实机只有 12 盏灯）
///
/// 权威来源：AWCC 模型资源 `AlienFX.ModelResources.Alienware17R4.dll` 内嵌 XML 的 Leds 表，
/// 其中 `LedID` 就是硬件掩码位、`LedIndex` 就是 LightFX 灯号。
/// 对应文档：reference/Alienware17R4-model.xml、zones.json
struct LightZone: OptionSet, Identifiable, Codable, Hashable {
    let rawValue: UInt32

    var id: UInt32 { rawValue }

    // MARK: 官方 12 盏灯（LedID 即掩码位）

    static let keyboardRight    = LightZone(rawValue: 1 << 0)   // 0x000001 Keyboard Right
    static let keyboardMidRight = LightZone(rawValue: 1 << 1)   // 0x000002 Keyboard Middle Right
    static let keyboardMidLeft  = LightZone(rawValue: 1 << 2)   // 0x000004 Keyboard Middle Left
    static let keyboardLeft     = LightZone(rawValue: 1 << 3)   // 0x000008 Keyboard Left
    static let alienHead        = LightZone(rawValue: 1 << 5)   // 0x000020 Alienhead
    static let screenLogo       = LightZone(rawValue: 1 << 6)   // 0x000040 Logo
    static let touchpad         = LightZone(rawValue: 1 << 7)   // 0x000080 Touchpad
    static let tronLeft         = LightZone(rawValue: 1 << 10)  // 0x000400 Left Tron
    static let tronRight        = LightZone(rawValue: 1 << 11)  // 0x000800 Right Tron
    static let lcdPanelLeft     = LightZone(rawValue: 1 << 12)  // 0x001000 LCD Panel Left
    static let lcdPanelRight    = LightZone(rawValue: 1 << 13)  // 0x002000 LCD Panel Right
    /// 1x5 宏键：官方标 OnlyForBrightnessSupport=true，只吃亮度，颜色会被硬件忽略
    static let macroKeys        = LightZone(rawValue: 1 << 14)  // 0x004000 1x5 Macro Keys

    // MARK: 非掩码灯区

    /// 电源按钮：不在颜色掩码里，走 0x08 电源状态块（bit8 是死位，仅作 UI 占位）
    static let powerButton      = LightZone(rawValue: 1 << 8)   // 0x000100 占位，非硬件灯

    /// 顶盖 A 面装饰（仅 3D 模型）
    static let lidRing          = LightZone(rawValue: 1 << 16)  // 0x010000 Logo 光环
    static let lidEyes          = LightZone(rawValue: 1 << 17)  // 0x020000 Logo 双眼

    /// UI 可选的灯区（12 盏灯 + 电源占位）
    static let all: LightZone = [
        .keyboardLeft, .keyboardMidLeft, .keyboardMidRight, .keyboardRight,
        .macroKeys, .alienHead, .screenLogo, .touchpad,
        .tronLeft, .tronRight, .lcdPanelLeft, .lcdPanelRight,
        .powerButton
    ]

    /// 真实可下发颜色的硬件灯区（不含电源占位与 3D 装饰）
    static let hardwareZones: LightZone = [
        .keyboardLeft, .keyboardMidLeft, .keyboardMidRight, .keyboardRight,
        .macroKeys, .alienHead, .screenLogo, .touchpad,
        .tronLeft, .tronRight, .lcdPanelLeft, .lcdPanelRight
    ]

    /// 仅存在于 3D 模型的装饰灯区（不参与 HID 下发）
    static let virtualZones: LightZone = [.lidRing, .lidEyes]

    /// 键盘四区（宏键单列）
    static let keyboard: LightZone = [.keyboardLeft, .keyboardMidLeft, .keyboardMidRight, .keyboardRight]

    /// 12 盏灯合并掩码（bit14 只吃亮度）
    static let maskAll: UInt32 = 0x007CEF

    /// 只能调亮度、不能改色
    var isBrightnessOnly: Bool { self == .macroKeys }

    /// 是否真实硬件灯（电源占位与 3D 装饰都不是）
    var isHardwareLamp: Bool {
        !LightZone.powerButton.contains(self) && !LightZone.virtualZones.contains(self)
    }

    /// 灯区显示名称（与 AWCC 官方组名对齐）
    var displayName: String {
        switch self {
        case .keyboardLeft:     return "键盘左"
        case .keyboardMidLeft:  return "键盘中左"
        case .keyboardMidRight: return "键盘中右"
        case .keyboardRight:    return "键盘右"
        case .macroKeys:        return "宏键（仅亮度）"
        case .alienHead:        return "顶盖头像"
        case .screenLogo:       return "屏幕 Logo"
        case .touchpad:         return "触摸板"
        case .powerButton:      return "电源按钮"
        case .tronLeft:         return "左侧灯带"
        case .tronRight:        return "右侧灯带"
        case .lcdPanelLeft:     return "屏下左灯条"
        case .lcdPanelRight:    return "屏下右灯条"
        case .lidRing:          return "Logo 光环"
        case .lidEyes:          return "Logo 双眼"
        default:
            if rawValue == 0 { return "无" }
            return "灯区 0x\(String(rawValue, radix: 16))"
        }
    }

    /// 独立灯区列表（按物理位置：顶盖 → 键盘 → 触摸板 → 机身灯带）
    static let allIndividual: [LightZone] = [
        .alienHead, .screenLogo,
        .powerButton, .macroKeys,
        .keyboardLeft, .keyboardMidLeft, .keyboardMidRight, .keyboardRight,
        .touchpad,
        .tronLeft, .tronRight, .lcdPanelLeft, .lcdPanelRight
    ]
}

// MARK: - 键盘按键（单键映射）

/// 一个物理按键：稳定 id + 所属硬件灯区
struct KeyboardKey: Identifiable, Hashable {
    enum Kind: String {
        case main, numpad, nav, macro
    }

    let id: String
    let zone: LightZone
    let kind: Kind
}

/// 键位目录：与 3D 模型的键位生成一一对应，用于单键配色与硬件回退
enum KeyboardCatalog {

    static let all: [KeyboardKey] = {
        var keys: [KeyboardKey] = []

        // 主键区 14 × 5（空格行中间三格让位给空格键）
        for row in 0..<5 {
            for col in 0..<14 {
                if row == 4 && col >= 4 && col <= 6 { continue }
                keys.append(KeyboardKey(id: "main-r\(row)c\(col)", zone: zone(forColumn: col), kind: .main))
            }
        }
        // 数字键盘 4 × 5
        for row in 0..<5 {
            for col in 0..<4 {
                keys.append(KeyboardKey(id: "num-r\(row)c\(col)", zone: .keyboardRight, kind: .numpad))
            }
        }
        // 导航键 3 个
        for i in 0..<3 {
            keys.append(KeyboardKey(id: "nav-\(i)", zone: .keyboardMidRight, kind: .nav))
        }
        // 左侧宏键 5 个
        for i in 0..<5 {
            keys.append(KeyboardKey(id: "macro-\(i)", zone: .macroKeys, kind: .macro))
        }
        return keys
    }()

    static let byID: [String: KeyboardKey] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// 主键区的分区：左 4 列 / 中左 3 列 / 中右 3 列 / 右 4 列（硬件只有 4 盏键盘灯）
    static func zone(forColumn col: Int) -> LightZone {
        if col <= 3 { return .keyboardLeft }
        if col <= 6 { return .keyboardMidLeft }
        if col <= 9 { return .keyboardMidRight }
        return .keyboardRight
    }

    static func zone(ofKey id: String) -> LightZone? { byID[id]?.zone }

    static func keys(in zone: LightZone) -> [KeyboardKey] {
        guard LightZone.keyboard.contains(zone) else { return [] }
        return all.filter { $0.zone == zone }
    }

    static func displayName(for id: String) -> String {
        guard let key = byID[id] else { return id }
        switch key.kind {
        case .macro:  return "宏键 M\(id.split(separator: "-").last ?? "?")"
        case .nav:    return "导航键 \(id.split(separator: "-").last ?? "?")"
        case .main, .numpad:
            let comps = id.split(separator: "-")
            guard comps.count == 2 else { return id }
            let body = comps[1] // r<row>c<col>
            let rest = body.dropFirst()
            guard let cIndex = rest.firstIndex(of: "c") else { return id }
            let row = rest[rest.startIndex..<cIndex]
            let col = rest[rest.index(after: cIndex)...]
            return "\(key.kind == .numpad ? "数字键" : "主键") R\(row)C\(col)"
        }
    }
}

// MARK: - APIv3 命令字节

/// AlienFX APIv3 命令码
enum AlienFXCommand: UInt8 {
    case color      = 0x03  // 设置颜色/效果
    case loop       = 0x04  // 循环设置
    case update     = 0x05  // 提交更新（使设置生效）
    case status     = 0x06  // 查询状态
    case reset      = 0x07  // 重置控制器
    case saveGroup  = 0x08  // 保存组
    case save       = 0x09  // 保存设置到闪存
    case setTempo   = 0x0E  // 设置速度
    case dim        = 0x1C  // 设置亮度
    case apply      = 0x1D  // 应用
}

/// 重置模式
enum ResetMode: UInt8 {
    case powerIndicator = 0x01  // 电源和指示灯
    case sleep          = 0x02  // 睡眠
    case off            = 0x03  // 关闭
    case on             = 0x04  // 开启
}

// MARK: - 设备信息

/// AlienFX 设备标识
struct AlienFXDeviceID {
    static let vendorID: UInt32  = 0x187C
    static let productID: UInt32 = 0x0530   // Alienware 17 R4
    static let reportID: UInt8   = 0x02
    static let reportLength: Int = 12       // Report ID(1) + 数据(11)，APIv3 OutputReportByteLength=12
}
