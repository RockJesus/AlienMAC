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

    var vidPid: String {
        String(format: "%04X:%04X", vendorID, productID)
    }

    var usageText: String {
        String(format: "0x%02X / 0x%02X", usagePage, usage)
    }
}
