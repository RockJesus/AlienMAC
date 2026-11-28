//
//  PeripheralProbe.swift
//  AlienMAC
//
//  macOS 侧外设自检：不依赖 Windows 抓包，直接在本机读接口能力、试写 query 帧、收回应。
//  只发只读 query 帧（按键状态 04 5A 17 00 A5），不改灯效、不改配置。
//

import Foundation
import IOKit.hid
import Combine

final class PeripheralProbe: ObservableObject {
    static let shared = PeripheralProbe()

    /// 全量扫描结果（不按 VID 过滤）
    @Published private(set) var interfaces: [PeripheralDevice] = []
    /// 自检报告（按设备累积）
    @Published private(set) var reports: [ProbeReport] = []
    /// 现场日志（十六进制收发）
    @Published private(set) var log: [String] = []
    /// 每行接口的能力值（扫描时缓存，避免面板再开一次 HID）
    @Published private(set) var capabilities: [String: Capability] = [:]

    /// 一个 HID 接口的静态能力
    struct Capability: Hashable {
        var maxOut: Int
        var maxFeature: Int
        var maxInput: Int
        var usagePage: Int
        var usage: Int
        var transport: String
    }

    func capability(for device: PeripheralDevice) -> Capability? {
        capabilities[key(vid: device.vendorID, pid: device.productID, usagePage: device.usagePage, usage: device.usage)]
    }

    private func key(vid: Int, pid: Int, usagePage: Int, usage: Int) -> String {
        String(format: "%04X:%04X:%02X:%02X", vid, pid, usagePage, usage)
    }
    @Published private(set) var isScanning = false

    private init() {}

    // MARK: - 扫描

    func scan() {
        isScanning = true
        defer { isScanning = false }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // 不设匹配字典 = 匹配全部 HID 设备；不设的话 CopyDevices 永远是空
        IOHIDManagerSetDeviceMatching(manager, nil)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        defer {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }

        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? Set<IOHIDDevice>()
        push("枚举到 \(devices.count) 个 HID 设备")

        var seen = Set<String>()
        var list: [PeripheralDevice] = []
        if true {
            for dev in devices {
                let info = describe(dev)
                guard info.maxOutput > 0 || info.maxFeature > 0 || info.usagePage == 0x0C else { continue }
                let key = "\(info.vid):\(info.pid):\(info.usagePage):\(info.usage)"
                guard seen.insert(key).inserted else { continue }
                list.append(PeripheralDevice(
                    id: UInt64(CFHash(dev)),
                    product: info.product,
                    manufacturer: info.manufacturer,
                    vendorID: info.vid,
                    productID: info.pid,
                    usagePage: info.usagePage,
                    usage: info.usage,
                    maxInputReportSize: info.maxInput,
                    transport: info.transport
                ))
            }
        }
        capabilities = [:]
        for dev in devices {
            let info = describe(dev)
            capabilities[key(vid: info.vid, pid: info.pid, usagePage: info.usagePage, usage: info.usage)] = Capability(
                maxOut: info.maxOutput, maxFeature: info.maxFeature, maxInput: info.maxInput,
                usagePage: info.usagePage, usage: info.usage, transport: info.transport)
        }
        interfaces = list.sorted {
            if $0.vendorID != $1.vendorID { return $0.vendorID < $1.vendorID }
            return $0.usagePage < $1.usagePage
        }
        push("扫描完成：\(interfaces.count) 个可读接口")
    }


    // MARK: - 插拔自动重扫

    @Published private(set) var isAutoMonitor = false
    private var autoManager: IOHIDManager?
    private var pendingRescan: DispatchWorkItem?

    /// 开一个常驻 IOHIDManager 只监听插拔，插上/拔掉后 0.6 秒自动重扫一次
    func startAutoMonitor() {
        guard autoManager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, probeHotplugCallback, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, probeHotplugCallback, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        autoManager = manager
        isAutoMonitor = true
        push("插拔监听：已开启，接入/拔掉设备会自动重扫")
    }

    func stopAutoMonitor() {
        guard let manager = autoManager else { return }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        autoManager = nil
        pendingRescan?.cancel()
        pendingRescan = nil
        isAutoMonitor = false
        push("插拔监听：已关闭")
    }

    func toggleAutoMonitor() {
        isAutoMonitor ? stopAutoMonitor() : startAutoMonitor()
    }

    /// 回调进来：防抖 0.6 秒再扫，避免一次插入的多个接口连着扫好几次
    func handleHotplug(_ reason: String, device: IOHIDDevice) {
        let info = describe(device)
        pendingRescan?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.push("\(reason) \(String(format: "%04X:%04X", info.vid, info.pid)) \(info.product)，自动重扫")
            self.scan()
        }
        pendingRescan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    // MARK: - 自检

    /// 对一台设备做一次无害自检，返回结论；不改灯效
    func probe(_ device: PeripheralDevice) -> ProbeReport {
        let started = Date()
        var report = ProbeReport(
            vid: device.vendorID, pid: device.productID, product: device.product,
            usagePage: device.usagePage, usage: device.usage,
            maxOutput: 0, maxFeature: 0, featureHex: "", responseHex: "",
            verdict: .noInterface, detail: "", familyGuess: .none, elapsedMS: 0
        )

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(manager, [[
            kIOHIDVendorIDKey: device.vendorID,
            kIOHIDProductIDKey: device.productID
        ]] as CFArray)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        defer {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }

        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            report.detail = "枚举失败"
            report.elapsedMS = ms(since: started)
            record(report)
            return report
        }
        // 优先挑与扫描行一致的那个接口（同 VID/PID 常有多条 MI）
        let chosen = set.first { dev in
            let info = describe(dev)
            return info.usagePage == device.usagePage && info.usage == device.usage
        } ?? set.first
        guard let dev = chosen else {
            report.detail = "没有匹配的接口（可能已拔出）"
            report.elapsedMS = ms(since: started)
            record(report)
            return report
        }

        let info = describe(dev)
        report.maxOutput = info.maxOutput
        report.maxFeature = info.maxFeature
        report.familyGuess = PeripheralProbeRules.family(
            usagePage: info.usagePage, usage: info.usage,
            maxOutput: info.maxOutput, maxFeature: info.maxFeature, vid: info.vid)

        let opened = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        guard opened == kIOReturnSuccess else {
            report.verdict = .blocked
            report.detail = "打开失败 0x\(String(opened, radix: 16))：先退出 AWCC / 其它灯控"
            report.elapsedMS = ms(since: started)
            record(report)
            return report
        }
        defer { IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone)) }

        // 1) 读 Feature（reportID 0）——多数外设会回固件信息
        if info.maxFeature > 0 {
            var buf = [UInt8](repeating: 0, count: info.maxFeature)
            var length = CFIndex(info.maxFeature)
            let r = buf.withUnsafeMutableBufferPointer { p -> IOReturn in
                guard let base = p.baseAddress else { return kIOReturnError }
                return IOHIDDeviceGetReport(dev, kIOHIDReportTypeFeature, 0, base, &length)
            }
            if r == kIOReturnSuccess, buf.contains(where: { $0 != 0 }) {
                report.featureHex = PeripheralProbeRules.hex(buf)
                push("FEATURE ← \(report.featureHex)")
            }
        }

        // 2) 鼠标族：只发 query 帧（04 5A 17 00 A5），等 0x35s 看有没有回应
        guard report.familyGuess == .mouse5A, info.maxOutput >= 64 else {
            report.verdict = report.featureHex.isEmpty ? .readonly : .replied
            report.detail = report.featureHex.isEmpty
                ? "只有属性信息，没有可写的灯控通道"
                : "读到了 Feature 数据；该族暂不试写"
            report.elapsedMS = ms(since: started)
            record(report)
            return report
        }

        let box = ReplyBox()
        IOHIDDeviceRegisterInputReportCallback(dev, box.buffer, 64, { context, _, _, _, reportID, report, length in
            guard let context else { return }
            let box = Unmanaged<ReplyBox>.fromOpaque(context).takeUnretainedValue()
            guard box.bytes.isEmpty else { return }
            let n = min(Int(length), 64)
            guard n > 0 else { return }
            box.bytes = Array(UnsafeBufferPointer(start: report, count: n))
            box.reportID = Int(reportID)
        }, Unmanaged.passUnretained(box).toOpaque())

        let query = FXMouseCodec.buttonState()
        var payload = query
        let wrote = payload.withUnsafeBufferPointer { p -> Bool in
            guard let base = p.baseAddress else { return false }
            return IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 0, base, payload.count) == kIOReturnSuccess
        }
        push("TX \(PeripheralProbeRules.hex(query, limit: 8))")

        if wrote {
            let deadline = Date().addingTimeInterval(0.35)
            while box.bytes.isEmpty && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
        }

        if !box.bytes.isEmpty {
            report.responseHex = PeripheralProbeRules.hex(box.bytes)
            push("RX \(report.responseHex) reportID \(box.reportID)")
        }

        report.verdict = PeripheralProbeRules.verdict(
            writeOK: wrote, responseEmpty: box.bytes.isEmpty,
            maxOutput: info.maxOutput, payload: query.count)
        switch report.verdict {
        case .replied:
            report.detail = "写入成功且有回应，判定为鼠标 0x5A 族"
        case .written:
            report.detail = "写入成功但没等到回应（部分固件只收不回），可先用单色试发验证"
        case .tooSmall:
            report.detail = "输出报表 \(info.maxOutput) 字节 < \(query.count)，写不进去"
        default:
            report.detail = "写入被拒，设备可能被其它灯控占用"
        }
        report.elapsedMS = ms(since: started)
        record(report)
        return report
    }

    // MARK: - 辅助

    private func record(_ report: ProbeReport) {
        if let idx = reports.firstIndex(where: { $0.id == report.id }) {
            reports[idx] = report
        } else {
            reports.append(report)
        }
        push("自检 \(String(format: "%04X:%04X", report.vid, report.pid)) → \(report.verdict.rawValue)（\(report.elapsedMS)ms）")
    }

    private func ms(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }

    private func push(_ line: String) {
        let stamp = DateFormatter()
        stamp.dateFormat = "HH:mm:ss"
        log.append("\(stamp.string(from: Date())) \(line)")
        if log.count > 60 { log.removeFirst(log.count - 60) }
    }

    func clearLog() { log.removeAll() }

    private struct DeviceInfo {
        var product: String
        var manufacturer: String
        var vid: Int
        var pid: Int
        var usagePage: Int
        var usage: Int
        var maxInput: Int
        var maxOutput: Int
        var maxFeature: Int
        var transport: String
    }

    private func describe(_ dev: IOHIDDevice) -> DeviceInfo {
        func int(_ key: String) -> Int {
            (IOHIDDeviceGetProperty(dev, key as CFString) as? Int) ?? 0
        }
        func str(_ key: String) -> String {
            (IOHIDDeviceGetProperty(dev, key as CFString) as? String) ?? ""
        }
        return DeviceInfo(
            product: str(kIOHIDProductKey),
            manufacturer: str(kIOHIDManufacturerKey),
            vid: int(kIOHIDVendorIDKey),
            pid: int(kIOHIDProductIDKey),
            usagePage: int(kIOHIDPrimaryUsagePageKey),
            usage: int(kIOHIDPrimaryUsageKey),
            maxInput: int(kIOHIDMaxInputReportSizeKey),
            maxOutput: int(kIOHIDMaxOutputReportSizeKey),
            maxFeature: int(kIOHIDMaxFeatureReportSizeKey),
            transport: str(kIOHIDTransportKey)
        )
    }
}

/// 承接 input report 的稳定盒子（回调 context 用）
private final class ReplyBox {
    var buffer: UnsafeMutablePointer<UInt8>
    var bytes: [UInt8] = []
    var reportID: Int = 0
    init() {
        buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        buffer.initialize(repeating: 0, count: 64)
    }
    deinit {
        buffer.deinitialize(count: 64)
        buffer.deallocate()
    }
}

/// 插拔回调（C 函数签名，不能捕获上下文，用 Unmanaged 拿回实例）
private let probeHotplugCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    let probe = Unmanaged<PeripheralProbe>.fromOpaque(context).takeUnretainedValue()
    probe.handleHotplug("插入/拔出", device: device)
}
