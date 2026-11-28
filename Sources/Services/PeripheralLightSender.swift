//
//  PeripheralLightSender.swift
//  AlienMAC
//
//  外设灯效下发：只在硬件验证过的协议族上开放（当前为鼠标 0x5A）。
//  macOS 侧必须用 Output Report（IOHIDDeviceSetReport），不能用 Feature。
//

import Foundation
import IOKit.hid

enum PeripheralLightSender {
    struct Outcome {
        var ok: Bool
        var message: String
    }

    /// 打开目标设备并写一次 output report
    static func send(payload: [UInt8], vid: Int, pid: Int) -> Outcome {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches: [[String: Any]] = [[
            kIOHIDVendorIDKey: vid,
            kIOHIDProductIDKey: pid
        ]]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let opened = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard opened == kIOReturnSuccess else {
            return Outcome(ok: false, message: "打开 \(String(format: "%04X:%04X", vid, pid)) 失败：0x\(String(opened, radix: 16))")
        }
        defer {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }

        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !set.isEmpty else {
            return Outcome(ok: false, message: "没有匹配到设备（可能被其它灯控软件占用）")
        }
        // 鼠标灯控走 MI_01：UsagePage 0x0C / Usage 0x01 才是可写的灯效接口
        let candidates = Array(set)
        let light = candidates.first { dev in
            let page = (IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsagePageKey as CFString) as? Int) ?? 0
            let usage = (IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsageKey as CFString) as? Int) ?? 0
            return page == 0x0C && usage == 0x01
        } ?? candidates.first

        guard let device = light else {
            return Outcome(ok: false, message: "未找到灯控通道")
        }
        let maxOut = (IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? Int) ?? 0
        guard maxOut >= payload.count else {
            return Outcome(ok: false, message: "输出报表长度不足：设备 \(maxOut) 字节，需要 \(payload.count)")
        }

        let devOpen = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard devOpen == kIOReturnSuccess else {
            return Outcome(ok: false, message: "设备占用中，先退出 AWCC / 其它灯控：0x\(String(devOpen, radix: 16))")
        }
        defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

        var buffer = payload
        let result = buffer.withUnsafeBufferPointer { ptr -> IOReturn in
            guard let base = ptr.baseAddress else { return kIOReturnError }
            return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, base, payload.count)
        }
        if result == kIOReturnSuccess {
            return Outcome(ok: true, message: "已下发 \(payload.count) 字节 · reportID 0")
        }
        return Outcome(ok: false, message: "写入失败：0x\(String(result, radix: 16))")
    }
}
