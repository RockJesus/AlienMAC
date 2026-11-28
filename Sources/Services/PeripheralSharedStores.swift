//
//  PeripheralSharedStores.swift
//  AlienMAC
//
//  两份可分享数据：别人导出的自检档案、AWCC 6.x 提取结果。
//  都落盘在 Application Support/AlienMAC，不进仓库、不带个人路径。
//

import Foundation
import Combine

private func alienmacSupportDirectory() -> URL {
    let fm = FileManager.default
    let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    let dir = support.appendingPathComponent("AlienMAC", isDirectory: true)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

final class ProbeArchiveStore: ObservableObject {
    static let shared = ProbeArchiveStore()

    @Published private(set) var items: [ProbeArchive] = []

    private var fileURL: URL { alienmacSupportDirectory().appendingPathComponent("probe-archive.json") }

    private init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(ProbeArchiveFile.self, from: data) else {
            items = []
            return
        }
        items = file.items
    }

    private func persist() {
        let file = ProbeArchiveFile(schema: ProbeArchive.schemaVersion, items: items)
        if let data = try? JSONEncoder.pretty.encode(file) {
            try? data.write(to: fileURL)
        }
    }

    /// 导入别人导出的档案，返回 (新增, 更新) 台数
    @discardableResult
    func importFile(_ url: URL) -> (added: Int, updated: Int) {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ProbeArchiveFile.self, from: data),
              file.schema == ProbeArchive.schemaVersion else { return (0, 0) }
        var added = 0
        var updated = 0
        for item in file.items {
            if let idx = items.firstIndex(where: { $0.vid == item.vid && $0.pid == item.pid }) {
                items[idx] = item
                updated += 1
            } else {
                items.append(item)
                added += 1
            }
        }
        persist()
        return (added, updated)
    }

    func compare(_ remote: ProbeArchive) -> String {
        ProbeArchiveCompare.summary(local: items, remote: remote)
    }

    /// 首次导入的对方档案（用于和本机自检记录比）
    func firstMatch(_ vid: Int, _ pid: Int) -> ProbeArchive? {
        items.first { $0.vid == vid && $0.pid == pid }
    }
}

final class AWCCExtensionStore: ObservableObject {
    static let shared = AWCCExtensionStore()

    @Published private(set) var profiles: [AWCCExtensionProfile] = []
    @Published private(set) var sourceVersion: String = ""

    private var fileURL: URL { alienmacSupportDirectory().appendingPathComponent("awcc6-profiles.json") }

    private init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let file = AWCCExtensionDecoder.decode(data) else {
            profiles = []
            sourceVersion = ""
            return
        }
        profiles = file.profiles
        sourceVersion = file.sourceVersion ?? ""
    }

    private func persist() {
        let file = AWCCExtensionFile(sourceVersion: sourceVersion.isEmpty ? nil : sourceVersion,
                                     profiles: profiles)
        if let data = try? JSONEncoder.pretty.encode(file) {
            try? data.write(to: fileURL)
        }
    }

    func profile(vid: Int, pid: Int) -> AWCCExtensionProfile? {
        profiles.first { $0.vid == vid && $0.pid == pid }
    }

    func modelProfiles(model: String) -> [AWCCExtensionProfile] {
        profiles.filter { $0.model == model }
    }

    @discardableResult
    func importFile(_ url: URL) -> Int {
        guard let data = try? Data(contentsOf: url),
              let file = AWCCExtensionDecoder.decode(data) else { return 0 }
        var added = 0
        for item in file.profiles {
            if let idx = profiles.firstIndex(where: { $0.vid == item.vid && $0.pid == item.pid }) {
                profiles[idx] = item
            } else {
                profiles.append(item)
                added += 1
            }
        }
        if let v = file.sourceVersion, !v.isEmpty { sourceVersion = v }
        persist()
        return added
    }

    func clear() {
        profiles = []
        sourceVersion = ""
        persist()
    }
}
