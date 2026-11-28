//
//  PeripheralLightSender.swift
//  AlienMAC
//
//  外设灯效下发：只在硬件验证过的协议族上开放（当前为鼠标 0x5A）。
//  macOS 侧必须用 Output Report（IOHIDDeviceSetReport），不能用 Feature。
//
//  v2.7.9 实测修正（AW558 04CA:00A5）：
//  - 灯控通道不是鼠标主接口（0001/02），而是消费控制接口 000C/01 的 64 字节 output；
//  - 该接口只声明 64B 输入、不声明输出长度（maxOutputReportSize 读到 0），
//    按"声明长度"当门槛会把唯一能用的通道挡掉，所以改为"按声明排序 + 允许试写"；
//  - IOHIDDeviceSetReport 的 rc 在这个设备上不可信（伪造 rid 0xFF 也回 0），
//    因此文案必须写明"rc 成功 ≠ 设备已接收，请肉眼确认"。
//

import Foundation
import IOKit.hid

/// 通道打分：纯函数，便于单测（不碰真机）
enum LightChannelPlan {
    struct Channel: Hashable {
        var usagePage: Int
        var usage: Int
        var maxInput: Int
        var maxOutput: Int
    }

    /// 越靠前越可能是灯控接口
    /// - 消费控制接口 0x0C/0x01：Alienware 鼠标灯控实测落点（AW558）
    /// - 声明了 ≥64B 报文的接口：有真实 64 字节管道
    /// - 鼠标主接口 0x01/0x02：旧逻辑的默认，实测 AW558 打不通
    static func score(_ c: Channel, payload: Int) -> Int {
        var s = 0
        if c.usagePage == 0x0C && c.usage == 0x01 { s += 60 }
        if c.maxOutput >= payload { s += 100 } else if c.maxOutput >= 8 { s += 20 }
        if c.maxInput >= payload { s += 25 } else if c.maxInput >= 64 { s += 15 }
        if c.usagePage == 0x01 && c.usage == 0x02 { s += 10 }
        if c.maxOutput >= payload && c.maxInput >= payload { s += 5 }
        return s
    }

    static func bestIndex(_ channels: [Channel], payload: Int) -> Int? {
        guard !channels.isEmpty else { return nil }
        let scored = channels.enumerated().map { (offset: $0.offset, score: score($0.element, payload: payload)) }
        return scored.max { $0.score < $1.score }?.offset
    }

    /// 通道是否声明了足够长度的 **输出**（灯效是写命令；false 时仍可试写，但文案要说明是试写）
    static func declaresCapacity(_ c: Channel, payload: Int) -> Bool {
        c.maxOutput >= payload
    }
}

enum PeripheralLightSender {
    struct Outcome {
        /// 报文已写出（rc == success）；**不代表设备接收**
        var ok: Bool
        var message: String
        /// 实际使用的接口，如 "000C/01 · output 64B"
        var channel: String
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
            return Outcome(ok: false,
                           message: "打开 \(String(format: "%04X:%04X", vid, pid)) 失败：0x\(String(opened, radix: 16))",
                           channel: "—")
        }
        defer {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }

        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !set.isEmpty else {
            return Outcome(ok: false, message: "没有匹配到设备（可能被其它灯控软件占用）", channel: "—")
        }

        let candidates = Array(set).sorted { lhs, rhs in
            // 稳定顺序，避免每次点同一设备选到不同接口
            let l = intProp(lhs, kIOHIDPrimaryUsagePageKey), r = intProp(rhs, kIOHIDPrimaryUsagePageKey)
            if l != r { return l < r }
            return intProp(lhs, kIOHIDPrimaryUsageKey) < intProp(rhs, kIOHIDPrimaryUsageKey)
        }
        let channels = candidates.map { dev in
            LightChannelPlan.Channel(usagePage: intProp(dev, kIOHIDPrimaryUsagePageKey),
                                     usage: intProp(dev, kIOHIDPrimaryUsageKey),
                                     maxInput: intProp(dev, kIOHIDMaxInputReportSizeKey),
                                     maxOutput: intProp(dev, kIOHIDMaxOutputReportSizeKey))
        }
        guard let idx = LightChannelPlan.bestIndex(channels, payload: payload.count) else {
            return Outcome(ok: false, message: "未找到灯控通道", channel: "—")
        }
        let device = candidates[idx]
        let channel = channels[idx]
        let channelText = String(format: "%04X/%02X · output %dB", channel.usagePage, channel.usage, payload.count)
        let declares = LightChannelPlan.declaresCapacity(channel, payload: payload.count)

        let devOpen = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard devOpen == kIOReturnSuccess else {
            return Outcome(ok: false,
                           message: "设备占用中，先退出 AWCC / 其它灯控：0x\(String(devOpen, radix: 16))",
                           channel: channelText)
        }
        defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

        var buffer = payload
        let result = buffer.withUnsafeBufferPointer { ptr -> IOReturn in
            guard let base = ptr.baseAddress else { return kIOReturnError }
            return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, base, payload.count)
        }
        if result == kIOReturnSuccess {
            let note = declares
                ? "rc=0（该返回码不可信，请确认灯是否变化）"
                : "rc=0，但接口只声明 \(channel.maxOutput)/\(channel.maxInput)B，属试写（请确认灯是否变化）"
            return Outcome(ok: true, message: "已写 \(channelText)，\(note)", channel: channelText)
        }
        return Outcome(ok: false,
                       message: "写入 \(channelText) 失败：0x\(String(result, radix: 16))",
                       channel: channelText)
    }

    private static func intProp(_ dev: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(dev, key as CFString) as? Int) ?? 0
    }
}
