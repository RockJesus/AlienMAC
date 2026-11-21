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
