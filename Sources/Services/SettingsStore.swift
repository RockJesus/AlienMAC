//
//  SettingsStore.swift
//  AlienMAC
//
//  本地持久化：亮度、上次灯光状态、自定义预设、启动行为等
//  存放于 ~/Library/Application Support/AlienMAC/settings.json
//

import Foundation
import Combine

final class SettingsStore: ObservableObject {

    static let shared = SettingsStore()

    // MARK: - 数据结构

    struct Snapshot: Codable, Equatable {
        /// 全局亮度 0-100
        var brightness: Int = 100
        /// 上次使用的主颜色
        var color: RGBColor = RGBColor(r: 0, g: 128, b: 255)
        /// 上次使用的次颜色
        var secondary: RGBColor = RGBColor(r: 0, g: 0, b: 0)
        /// 上次使用的效果（稳定标识）
        var effectCode: String = "color"
        /// 效果速度（毫秒）
        var tempo: UInt16 = 2000
        /// 上次应用的范围（0 = 全部）
        var zones: UInt32 = 0
        /// 启动时恢复上次灯光
        var restoreOnLaunch: Bool = true
        /// 启用全局快捷键
        var hotkeysEnabled: Bool = true
        /// 屏幕 Logo 导光条亮度补偿系数
        var screenLogoBoost: Double = 1.6
        /// 自定义预设
        var customPresets: [CustomPreset] = []
        /// 单键自定义颜色（键 id → 颜色），缺省表示跟随所属灯区
        var keyColors: [String: RGBColor] = [:]
        /// 触摸板细调（整面背光与四薄条边光分开控制）
        var touchpad: TouchpadConfig = TouchpadConfig()
        /// 电源键功能与灯效
        var powerButton: PowerButtonConfig = PowerButtonConfig()
        /// 每区独立动作（键为灯区 rawValue 的十进制字符串）
        var zoneActions: [String: ZoneAction] = [:]
    }

    /// 电源键可执行的动作
    enum PowerAction: String, Codable, CaseIterable, Identifiable {
        case none, lock, sleep, lightsOff, restart, shutdown
        var id: String { rawValue }
        var title: String {
            switch self {
            case .none:      return "无动作（只选灯区）"
            case .lock:      return "锁定屏幕"
            case .sleep:     return "进入睡眠"
            case .lightsOff: return "关闭全部灯光"
            case .restart:   return "重新启动"
            case .shutdown:  return "关机"
            }
        }
        var isDangerous: Bool { self == .restart || self == .shutdown }
    }

    /// 电源键功能与灯效参数
    struct PowerButtonConfig: Codable, Equatable {
        var clickAction: PowerAction = .none
        var doubleClickAction: PowerAction = .none
        var holdAction: PowerAction = .none
        /// 重启 / 关机前二次确认
        var confirmDangerous: Bool = true
        /// 电源键灯效是否跟随灯区颜色
        var lightFollowsZone: Bool = true
        var lightColor: RGBColor = RGBColor(r: 0, g: 209, b: 255)
        var lightBrightness: Int = 100
    }

    /// 触摸板细调参数
    struct TouchpadConfig: Codable, Equatable {
        /// 整面背光是否跟随灯区颜色
        var padFollowsZone: Bool = true
        /// 整面背光自定义颜色
        var padColor: RGBColor = RGBColor(r: 0, g: 209, b: 255)
        /// 整面亮度（相对全局亮度的百分比）
        var padBrightness: Int = 100
        /// 边光是否跟随灯区颜色
        var edgeFollowsZone: Bool = true
        /// 边光自定义颜色
        var edgeColor: RGBColor = RGBColor(r: 0, g: 209, b: 255)
        /// 边光强度（百分比）
        var edgeBrightness: Int = 100
        /// 是否显示边光
        var edgeEnabled: Bool = true
    }

    // MARK: - 状态

    @Published var snapshot: Snapshot {
        didSet { scheduleSave() }
    }

    /// 便于外部快速访问最近一次错误
    private(set) var lastError: String?

    // MARK: - 路径

    private let queue = DispatchQueue(label: "com.alienmac.settings", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?

    private var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("AlienMAC", isDirectory: true)
    }

    private var fileURL: URL {
        directoryURL.appendingPathComponent("settings.json")
    }

    // MARK: - 初始化

    private init() {
        snapshot = Self.load(from: SettingsStore.makeFileURLStatic())
    }

    private static func makeFileURLStatic() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("AlienMAC", isDirectory: true).appendingPathComponent("settings.json")
    }

    private static func load(from url: URL) -> Snapshot {
        guard let data = try? Data(contentsOf: url) else { return Snapshot() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Snapshot.self, from: data)) ?? Snapshot()
    }

    // MARK: - 保存

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        saveWorkItem = work
        queue.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// 立即落盘（退出应用前调用）
    func saveNow() {
        let value = snapshot
        let url = fileURL
        let dir = directoryURL
        queue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let data = try encoder.encode(value)
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("AlienMAC settings save failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 预设操作

    func addPreset(_ preset: CustomPreset) {
        var s = snapshot
        s.customPresets.append(preset)
        snapshot = s
    }

    func updatePreset(_ preset: CustomPreset) {
        var s = snapshot
        if let index = s.customPresets.firstIndex(where: { $0.id == preset.id }) {
            s.customPresets[index] = preset
            snapshot = s
        }
    }

    func removePreset(id: UUID) {
        var s = snapshot
        s.customPresets.removeAll { $0.id == id }
        snapshot = s
    }

    func renamePreset(id: UUID, to name: String) {
        var s = snapshot
        if let index = s.customPresets.firstIndex(where: { $0.id == id }) {
            s.customPresets[index].name = name
            snapshot = s
        }
    }
}

// MARK: - 编解码（缺字段回落到默认值，避免升级后设置被重置）

extension SettingsStore.Snapshot {
    enum CodingKeys: String, CodingKey {
        case brightness, color, secondary, effectCode, tempo, zones
        case restoreOnLaunch, hotkeysEnabled, screenLogoBoost
        case customPresets, keyColors, touchpad, powerButton, zoneActions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brightness = (try? c.decodeIfPresent(Int.self, forKey: .brightness)) ?? 100
        color = (try? c.decodeIfPresent(RGBColor.self, forKey: .color)) ?? RGBColor(r: 0, g: 128, b: 255)
        secondary = (try? c.decodeIfPresent(RGBColor.self, forKey: .secondary)) ?? RGBColor(r: 0, g: 0, b: 0)
        effectCode = (try? c.decodeIfPresent(String.self, forKey: .effectCode)) ?? "color"
        tempo = (try? c.decodeIfPresent(UInt16.self, forKey: .tempo)) ?? 2000
        zones = (try? c.decodeIfPresent(UInt32.self, forKey: .zones)) ?? 0
        restoreOnLaunch = (try? c.decodeIfPresent(Bool.self, forKey: .restoreOnLaunch)) ?? true
        hotkeysEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .hotkeysEnabled)) ?? true
        screenLogoBoost = (try? c.decodeIfPresent(Double.self, forKey: .screenLogoBoost)) ?? 1.6
        customPresets = (try? c.decodeIfPresent([CustomPreset].self, forKey: .customPresets)) ?? []
        keyColors = (try? c.decodeIfPresent([String: RGBColor].self, forKey: .keyColors)) ?? [:]
        touchpad = (try? c.decodeIfPresent(SettingsStore.TouchpadConfig.self, forKey: .touchpad)) ?? SettingsStore.TouchpadConfig()
        powerButton = (try? c.decodeIfPresent(SettingsStore.PowerButtonConfig.self, forKey: .powerButton)) ?? SettingsStore.PowerButtonConfig()
        zoneActions = (try? c.decodeIfPresent([String: ZoneAction].self, forKey: .zoneActions)) ?? [:]
    }
}
