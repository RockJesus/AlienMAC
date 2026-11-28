//
//  PeripheralOverridesStore.swift
//  AlienMAC
//
//  用户自建的外设档案：按 VID/PID 记住协议族与报表参数，可导出分享给同型号用户。
//

import Foundation
import Combine

final class PeripheralOverridesStore: ObservableObject {
    static let shared = PeripheralOverridesStore()

    @Published private(set) var items: [PeripheralOverride] = []

    private var fileURL: URL {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = support.appendingPathComponent("AlienMAC", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("peripheral-overrides.json")
    }

    private init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(PeripheralOverrideFile.self, from: data) else {
            items = []
            return
        }
        items = file.items
        NSLog("AlienMAC 外设档案：已载入 \(items.count) 台自定义设备")
    }

    private func persist() {
        let file = PeripheralOverrideFile(schema: "alienmac.peripheral-overrides/1", items: items)
        if let data = try? JSONEncoder.pretty.encode(file) {
            try? data.write(to: fileURL)
        }
    }

    func override(vid: Int, pid: Int) -> PeripheralOverride? {
        items.first { $0.vid == vid && $0.pid == pid }
    }

    func upsert(_ item: PeripheralOverride) {
        if let idx = items.firstIndex(where: { $0.vid == item.vid && $0.pid == item.pid }) {
            items[idx] = item
        } else {
            items.append(item)
        }
        persist()
    }

    func remove(vid: Int, pid: Int) {
        items.removeAll { $0.vid == vid && $0.pid == pid }
        persist()
    }

    /// 协议族：自定义档案优先，其次设备库，最后按 VID 推断
    func family(vid: Int, pid: Int, fallback: () -> PeripheralFamily) -> PeripheralFamily {
        if let o = override(vid: vid, pid: pid) { return o.family }
        return fallback()
    }

    @discardableResult
    func export(to url: URL? = nil) -> URL? {
        let file = PeripheralOverrideFile(schema: "alienmac.peripheral-overrides/1", items: items)
        guard let data = try? JSONEncoder.pretty.encode(file) else { return nil }
        let target = url ?? fileURL.deletingLastPathComponent()
            .appendingPathComponent("peripheral-overrides-export.json")
        do {
            try data.write(to: target)
            return target
        } catch {
            NSLog("AlienMAC 档案导出失败：\(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    func importFile(_ url: URL) -> Int {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(PeripheralOverrideFile.self, from: data) else {
            return 0
        }
        var added = 0
        for item in file.items {
            if override(vid: item.vid, pid: item.pid) == nil { added += 1 }
            upsert(item)
        }
        return added
    }
}
