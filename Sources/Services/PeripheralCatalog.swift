//
//  PeripheralCatalog.swift
//  AlienMAC
//
//  内置全量设备库：225 条授权设备 / 11 款带元数据外设 / 343 条官方灯区。
//  数据源为 AWCC 5.2.42 反解包，随 App 打包（Resources/PeripheralCatalog.json）。
//

import Foundation
import Combine

final class PeripheralCatalog: ObservableObject {
    static let shared = PeripheralCatalog()

    let devices: [CatalogDevice]
    let models: [String: CatalogModelProfile]

    private let byKey: [String: CatalogDevice]

    var modelCount: Int { models.count }
    var ledCount: Int { models.values.reduce(0) { $0 + $1.leds.count } }
    var vendorCount: Int { Set(devices.map { $0.vid }).count }

    private init() {
        var parsed: PeripheralCatalogFile?
        if let url = Bundle.main.url(forResource: "PeripheralCatalog", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            parsed = try? JSONDecoder().decode(PeripheralCatalogFile.self, from: data)
        } else {
            NSLog("AlienMAC 外设库未找到 PeripheralCatalog.json")
        }
        let file = parsed
        devices = file?.devices ?? []
        models = file?.models ?? [:]
        var map: [String: CatalogDevice] = [:]
        for d in (file?.devices ?? []) { map[d.id] = d }
        byKey = map
        NSLog("AlienMAC 外设库：\(devices.count) 台授权设备 / \(models.count) 款元数据 / \(ledCount) 条灯区")
    }

    // MARK: - 查询

    func device(vid: Int, pid: Int) -> CatalogDevice? {
        byKey[String(format: "%04X:%04X", vid, pid)]
    }

    func profile(vid: Int, pid: Int) -> CatalogModelProfile? {
        guard let d = device(vid: vid, pid: pid) else { return nil }
        return models[d.model]
    }

    /// 一个设备应使用的协议族：优先目录里登记的，其次按 VID 推断
    func family(for device: PeripheralDevice) -> PeripheralFamily {
        // 用户自建档案优先，其次设备库，最后按 VID 推断
        if let o = PeripheralOverridesStore.shared.override(vid: device.vendorID, pid: device.productID) {
            return o.family
        }
        if let hit = self.device(vid: device.vendorID, pid: device.productID) {
            return hit.family
        }
        return PeripheralProtocolMap.family(vid: device.vendorID, category: device.category)
    }

    /// 面板列表：按关键字过滤（型号 / 类别 / VID:PID）
    func search(_ keyword: String) -> [CatalogDevice] {
        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return devices }
        return devices.filter {
            $0.model.lowercased().contains(q)
                || $0.category.lowercased().contains(q)
                || $0.id.lowercased().contains(q)
                || $0.vendor.lowercased().contains(q)
        }
    }

    /// 带完整元数据、且本 App 能真正下发灯效的型号
    var sendableModels: [String] {
        models.keys.filter { name in
            guard let d = devices.first(where: { $0.model == name }) else { return false }
            return d.family.canSend
        }.sorted()
    }
}
