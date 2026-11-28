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
//  v2.8.0 修正（iMac + AW558 实测）：
//  - IOHIDManagerOpen 在未授权"输入监控"的 App 里返回 0xE00002E2（kIOReturnNotPermitted），
//    旧代码把它当致命错误直接放弃；实测"只写不发"根本不需要 open manager，改为不 open；
//  - 键盘/鼠标主接口（0001/xx）对普通 App 一律 0xE00002E2，所以打开失败要跳过、继续试下一个通道，
//    不能"第一个失败就整体失败"；
//  - 错误码按 UInt32 打印（旧代码把有符号负数当十六进制，出现 0x-1ffffd1e 这种畸形串），并附中文解释。
//

//  v2.8.2：把"逐通道试写"提取成通用路径——
//  - 通道记忆：上次成功的接口连签名一起存进偏好，下次先试它；插拔后接口签名变了自动作废；
//  - 报文类型可切换（Output / Feature）与 ReportID 可传，键盘族将来比对完帧就能直接复用同一套流程；
//  - 新增只读探测：只枚举接口并尝试打开、不写任何字节，接上新外设时先看清哪个接口放行。
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
        return ordered(channels, payload: payload).first
    }

    /// 按得分从高到低排好的通道下标；同分时保留原顺序，保证每次点同一设备落到同一通道
    static func ordered(_ channels: [Channel], payload: Int) -> [Int] {
        channels.indices.sorted { a, b in
            let sa = score(channels[a], payload: payload)
            let sb = score(channels[b], payload: payload)
            return sa == sb ? a < b : sa > sb
        }
    }

    /// 通道是否声明了足够长度的 **输出**（灯效是写命令；false 时仍可试写，但文案要说明是试写）
    static func declaresCapacity(_ c: Channel, payload: Int) -> Bool {
        c.maxOutput >= payload
    }
}

/// IOReturn 的人话解释：0xE00002E2 这种码必须能看懂，否则用户只知道"失败"
enum IOReturnText {
    /// 一律按无符号 32 位打印，杜绝 0x-1ffffd1e
    static func code(_ r: Int32) -> String {
        String(format: "0x%08X", UInt32(bitPattern: r))
    }

    static func describe(_ r: Int32) -> String {
        switch UInt32(bitPattern: r) {
        case 0xE00002E2: return "权限不足（系统设置 › 隐私与安全性 › 输入监控 勾选 AlienMAC）"
        case 0xE00002C5: return "设备被独占（先退出 AWCC 或其它灯控）"
        case 0xE00002C0: return "设备已不在（可能被拔掉或休眠）"
        case 0xE00002C7: return "接口不支持这次写入"
        case 0xE00002D9: return "接口已被占用"
        case 0: return "成功"
        default: return "未分类错误"
        }
    }

    static func line(_ r: Int32) -> String {
        "\(code(r))（\(describe(r))）"
    }
}

enum PeripheralLightSender {
    struct Outcome {
        /// 报文已写出（rc == success）；**不代表设备接收**
        var ok: Bool
        var message: String
        /// 实际使用的接口，如 "000C/01 · output 64B"
        var channel: String
        /// 试过的通道（按尝试顺序），便于对照日志
        var tried: [String] = []
        /// 这次是否用上了通道记忆（首次点色为 false，第二次起应为 true）
        var fromMemory: Bool = false
    }

    /// 枚举 vid/pid 下的接口并按得分逐个尝试，写一次 report
    /// - Parameters:
    ///   - reportID: 设备要求带 Report ID 时传（鼠标 0x5A 帧固定 0）
    ///   - reportType: 灯效是写命令，绝大多数走 Output；APIv8 键盘的握手走 Feature
    ///   - useMemory: 是否参考偏好里记下的通道（探测时为 false）
    static func send(payload: [UInt8],
                     vid: Int,
                     pid: Int,
                     reportID: Int = 0,
                     reportType: IOHIDReportType = kIOHIDReportTypeOutput,
                     useMemory: Bool = true) -> Outcome {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches: [[String: Any]] = [[
            kIOHIDVendorIDKey: vid,
            kIOHIDProductIDKey: pid
        ]]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        defer {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }

        // 注意：这里**不调用** IOHIDManagerOpen。只往下写报文时不需要它；
        // 未授权"输入监控"的 App 调它只会拿到 0xE00002E2，把整个下发挡在门口。
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !set.isEmpty else {
            return Outcome(ok: false,
                           message: "没有匹配到 \(String(format: "%04X:%04X", vid, pid))（可能被其它灯控软件占用）",
                           channel: "—")
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
        guard !channels.isEmpty else {
            return Outcome(ok: false, message: "未找到灯控通道", channel: "—")
        }

        let store = ChannelMemory.Store.shared
        let memoryEntry = useMemory ? store.entry(vid: vid, pid: pid) : nil
        let order = ChannelMemory.order(channels: channels, payload: payload.count, entry: memoryEntry)

        var tried: [String] = []
        var failures: [String] = []
        var memoryHit = false

        // 按得分（或记忆优先）逐个试，打不开就换下一个：
        // 键盘/鼠标主接口本来就会被系统拒绝，不该拖累真正能用的通道
        for idx in order {
            let device = candidates[idx]
            let channel = channels[idx]
            let channelText = ChannelMemory.channelKey(channel)
            let isMemory = memoryEntry?.channel == channelText
            if isMemory { memoryHit = true }
            tried.append(channelText)

            let devOpen = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard devOpen == kIOReturnSuccess else {
                failures.append("\(channelText) 打不开 \(IOReturnText.code(devOpen))")
                // 记忆里的通道打不开：设备可能换了口，趁早忘掉
                if isMemory { store.forget(vid: vid, pid: pid) }
                continue
            }

            let declares = LightChannelPlan.declaresCapacity(channel, payload: payload.count)
            let buffer = payload
            let result = buffer.withUnsafeBufferPointer { ptr -> IOReturn in
                guard let base = ptr.baseAddress else { return kIOReturnError }
                return IOHIDDeviceSetReport(device, reportType, CFIndex(reportID), base, payload.count)
            }
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))

            if result == kIOReturnSuccess {
                let full = "\(channelText) · output \(payload.count)B"
                let note = declares
                    ? "rc=0（该返回码不可信，请确认灯是否变化）"
                    : "rc=0，但接口只声明 \(channel.maxOutput)/\(channel.maxInput)B，属试写（请确认灯是否变化）"
                store.remember(channel: channelText, channels: channels, vid: vid, pid: pid)
                return Outcome(ok: true, message: "已写 \(full)，\(note)",
                               channel: full, tried: tried, fromMemory: isMemory)
            }
            failures.append("\(channelText) 写入 \(IOReturnText.code(result))")
            if isMemory { store.forget(vid: vid, pid: pid) }
        }

        let head = failures.isEmpty ? "未找到可用通道" : "全部候选都失败"
        return Outcome(ok: false,
                       message: "\(head)：\(failures.joined(separator: "；"))",
                       channel: "—",
                       tried: tried,
                       fromMemory: memoryHit)
    }

    /// 只读探测：枚举接口、逐个尝试打开、立刻关掉，**不写任何字节**。
    /// 接上新外设（尤其键盘/显示器）时先看清哪个接口放行，再去比对帧。
    static func probe(vid: Int, pid: Int) -> String {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches: [[String: Any]] = [[
            kIOHIDVendorIDKey: vid,
            kIOHIDProductIDKey: pid
        ]]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        defer {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }

        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !set.isEmpty else {
            return "没有匹配到 \(String(format: "%04X:%04X", vid, pid))"
        }

        let candidates = Array(set).sorted { lhs, rhs in
            let l = intProp(lhs, kIOHIDPrimaryUsagePageKey), r = intProp(rhs, kIOHIDPrimaryUsagePageKey)
            if l != r { return l < r }
            return intProp(lhs, kIOHIDPrimaryUsageKey) < intProp(rhs, kIOHIDPrimaryUsageKey)
        }

        var parts: [String] = []
        for device in candidates {
            let page = intProp(device, kIOHIDPrimaryUsagePageKey)
            let usage = intProp(device, kIOHIDPrimaryUsageKey)
            let channelText = String(format: "%04X/%02X", page, usage)
            let inputB = intProp(device, kIOHIDMaxInputReportSizeKey)
            let outputB = intProp(device, kIOHIDMaxOutputReportSizeKey)
            let featureB = intProp(device, kIOHIDMaxFeatureReportSizeKey)

            let open = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))

            let state = open == kIOReturnSuccess
                ? "可打开"
                : "打不开 \(IOReturnText.code(open))（\(IOReturnText.describe(open))）"
            parts.append("\(channelText) in \(inputB) / out \(outputB) / feature \(featureB)：\(state)")
        }
        return parts.joined(separator: "；")
    }

    /// 清掉某设备的通道记忆（用户手动重置时用）
    static func forgetChannel(vid: Int, pid: Int) {
        ChannelMemory.Store.shared.forget(vid: vid, pid: pid)
    }

    private static func intProp(_ dev: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(dev, key as CFString) as? Int) ?? 0
    }
}
