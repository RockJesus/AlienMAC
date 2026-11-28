//
//  PeripheralDevice.swift
//  AlienMAC
//
//  外设 V8：Alienware / Dell 外设识别结果
//

import Foundation

/// 一个 HID 外设（键盘、鼠标、耳机底座等）
struct PeripheralDevice: Identifiable, Hashable {
    var id: UInt64
    var product: String
    var manufacturer: String
    var vendorID: Int
    var productID: Int
    var usagePage: Int
    var usage: Int
    var maxInputReportSize: Int
    var transport: String

    /// 笔记本内置灯控（17 R4 的 VID 187C / PID 0530）
    var isBuiltIn: Bool { vendorID == 0x187C && productID == 0x0530 }

    /// AWCC 里的外设大类（按产品名粗分，识别不到就是通用 HID）
    var category: String {
        let name = product.lowercased()
        if name.contains("mouse") { return "鼠标" }
        if name.contains("keyboard") { return "键盘" }
        if name.contains("headset") || name.contains("headphone") { return "耳机" }
        if isBuiltIn { return "内置" }
        return "HID"
    }

    /// 设备库里命中的授权条目（VID/PID 精确匹配）
    var catalogDevice: CatalogDevice? {
        PeripheralCatalog.shared.device(vid: vendorID, pid: productID)
    }

    /// 带官方元数据的型号（灯区、宏键、按键名）
    var catalogProfile: CatalogModelProfile? {
        guard let hit = catalogDevice else { return nil }
        return PeripheralCatalog.shared.models[hit.model]
    }

    /// 官方型号名；设备库没收录时退回系统产品名
    var catalogModel: String {
        catalogDevice?.model ?? product
    }

    /// 官方灯区数量
    var ledCount: Int {
        catalogProfile?.leds.count ?? 0
    }

    var vidPid: String {
        String(format: "%04X:%04X", vendorID, productID)
    }

    var usageText: String {
        String(format: "0x%02X / 0x%02X", usagePage, usage)
    }
}
