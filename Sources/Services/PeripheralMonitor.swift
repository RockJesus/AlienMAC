//
//  PeripheralMonitor.swift
//  AlienMAC
//
//  外设 V8：枚举 Alienware / Dell 的 HID 外设，并抓取按键 usage 供宏键绑定
//

import Foundation
import IOKit.hid
import Combine

final class PeripheralMonitor: ObservableObject {
    static let shared = PeripheralMonitor()

    /// 识别到的外设（含内置灯控）
    @Published private(set) var devices: [PeripheralDevice] = []
    /// 是否正在抓取按键（宏键捕获）
    @Published var isCapturing: Bool = false {
        didSet { applyCapture() }
    }
    /// 最近一次捕获到的按键
    @Published private(set) var lastEvent: String = ""
    /// 最近一次捕获的 usage page / usage，便于直接绑定
    @Published private(set) var lastUsagePage: Int = 0
    @Published private(set) var lastUsage: Int = 0
    /// 最近一次捕获的时间
    @Published private(set) var lastEventDate: Date?
    /// 诊断用：把本机所有 HID 设备都列出来
    @Published var showAllDevices: Bool = false {
        didSet { refresh() }
    }

    /// 收到物理按键（usage page / usage），由 MacroRouter 消费
    var onKeyEvent: ((Int, Int) -> Void)?

    /// 设备别名（键为 VID:PID，写在 UserDefaults）
    @Published private(set) var aliases: [String: String] = [:]
    /// 最近一次导出的诊断文件
    @Published private(set) var lastExportPath: String = ""

    private var manager: IOHIDManager?
    private var started = false
    private var captureDevices: [IOHIDDevice] = []

    private init() {}

    // MARK: - 生命周期

    func start() {
        guard !started else { return }
        started = true

        if let saved = UserDefaults.standard.dictionary(forKey: "AlienMAC.peripheralAliases") as? [String: String] {
            aliases = saved
        }

        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr

        // 筛 Alienware / Dell 及授权外设的全部 VID；不限定 usage page，避免漏掉厂商私有页
        // 外接鼠标 0x04CA / 0x0461、键盘 0x04F2、显示器 0x0424、耳机 0x0B0E 之前全被漏掉
        var vids: [Int] = [0x187C, 0x0D62, 0x413C]
        for vid in PeripheralCatalog.shared.devices.map({ $0.vid }) where !vids.contains(vid) {
            vids.append(vid)
        }
        let matches: [[String: Any]] = vids.map { [kIOHIDVendorIDKey: $0] }
        IOHIDManagerSetDeviceMatchingMultiple(mgr, matches as CFArray)
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { context, _, _, device in
            guard let context else { return }
            let monitor = Unmanaged<PeripheralMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.add(device)
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { context, _, _, device in
            guard let context else { return }
            let monitor = Unmanaged<PeripheralMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.remove(device)
        }, Unmanaged.passUnretained(self).toOpaque())

        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            NSLog("AlienMAC 外设枚举打开失败：\(result)")
        }
        refresh()
        NSLog("AlienMAC 外设监控启动，已识别 \(devices.count) 个设备")
        // 默认就打开按键监听，物理宏键开箱即用；面板开关只用于临时让出
        isCapturing = true
    }

    /// 重新读取设备列表（拔插回调之外的兜底）
    func refresh() {
        guard let manager else { return }
        var all: [IOHIDDevice] = []
        if let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            all = Array(set)
        }
        if showAllDevices {
            let probe = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerScheduleWithRunLoop(probe, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerOpen(probe, IOOptionBits(kIOHIDOptionsTypeNone))
            if let set = IOHIDManagerCopyDevices(probe) as? Set<IOHIDDevice> {
                all.append(contentsOf: Array(set))
            }
            IOHIDManagerClose(probe, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        var seen = Set<UInt64>()
        let list = all.compactMap { makeDevice($0) }.filter { seen.insert($0.id).inserted }
        devices = list.sorted { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn }
            return lhs.product.localizedStandardCompare(rhs.product) == .orderedAscending
        }
        if isCapturing { applyCapture() }
    }

    // MARK: - 设备回调

    private func add(_ device: IOHIDDevice) {
        guard let info = makeDevice(device) else { return }
        if !devices.contains(where: { $0.id == info.id }) {
            devices.append(info)
        }
        devices.sort { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn }
            return lhs.product.localizedStandardCompare(rhs.product) == .orderedAscending
        }
        if isCapturing { applyCapture() }
        NSLog("AlienMAC 外设接入：\(info.product) \(info.vidPid)")
    }

    private func remove(_ device: IOHIDDevice) {
        guard let info = makeDevice(device) else { return }
        devices.removeAll { $0.id == info.id }
        NSLog("AlienMAC 外设移除：\(info.product) \(info.vidPid)")
    }

    private func makeDevice(_ device: IOHIDDevice) -> PeripheralDevice? {
        let product = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "未命名设备"
        let manufacturer = (IOHIDDeviceGetProperty(device, kIOHIDManufacturerKey as CFString) as? String) ?? "未知厂商"
        let vid = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int) ?? 0
        let pid = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int) ?? 0
        let usagePage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int) ?? 0
        let usage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int) ?? 0
        let reportSize = (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int) ?? 0
        let transport = (IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String) ?? "-"
        return PeripheralDevice(
            id: UInt64(CFHash(device)),
            product: product,
            manufacturer: manufacturer,
            vendorID: vid,
            productID: pid,
            usagePage: usagePage,
            usage: usage,
            maxInputReportSize: reportSize,
            transport: transport
        )
    }

    // MARK: - 宏键捕获

    /// isCapturing 只控制监听开关；绑定到的物理键由 MacroRouter 随时响应
    private func applyCapture() {
        guard let manager, let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return }
        for device in set {
            if isCapturing {
                IOHIDDeviceRegisterInputValueCallback(device, { context, _, _, value in
                    guard let context else { return }
                    let monitor = Unmanaged<PeripheralMonitor>.fromOpaque(context).takeUnretainedValue()
                    monitor.handle(value)
                }, Unmanaged.passUnretained(self).toOpaque())
                let opened = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
                if opened != kIOReturnSuccess {
                    NSLog("AlienMAC 捕获打开失败：\(opened)")
                }
            } else {
                IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
                IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            }
        }
        if isCapturing {
            NSLog("AlienMAC 宏键捕获已开始")
        }
    }

    private func handle(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)
        guard intValue != 0 else { return }
        guard usagePage == 0x07 || usagePage == 0x0C || usagePage == 0xFF00 || usagePage == 0xFF89 else { return }

        lastUsagePage = Int(usagePage)
        lastUsage = Int(usage)
        lastEventDate = Date()
        lastEvent = String(format: "usage page 0x%02X · usage 0x%02X · 值 %d", usagePage, usage, intValue)
        onKeyEvent?(Int(usagePage), Int(usage))
    }

    // MARK: - 别名

    func alias(for device: PeripheralDevice) -> String {
        aliases[device.vidPid] ?? ""
    }

    func setAlias(_ text: String, for device: PeripheralDevice) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            aliases.removeValue(forKey: device.vidPid)
        } else {
            aliases[device.vidPid] = trimmed
        }
        UserDefaults.standard.set(aliases, forKey: "AlienMAC.peripheralAliases")
    }

    // MARK: - 诊断导出

    /// 把当前识别结果 + 最近按键写成 JSON，供 Windows 侧抓 AWCC 报文时对照
    @discardableResult
    func exportDiagnostics() -> String? {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmm"
        let fileName = "peripherals-\(stamp.string(from: Date())).json"

        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = support.appendingPathComponent("AlienMAC/diagnostics", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(fileName)

        var payload: [String: Any] = [
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "deviceCount": devices.count,
            "devices": devices.map { device -> [String: Any] in
                var info = PeripheralLightingMap.describe(device)
                let alias = alias(for: device)
                if !alias.isEmpty { info["alias"] = alias }
                return info
            }
        ]
        if lastUsage != 0 {
            payload["lastKey"] = [
                "usagePage": String(format: "0x%02X", lastUsagePage),
                "usage": String(format: "0x%02X", lastUsage)
            ]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        do {
            try data.write(to: file)
            lastExportPath = file.path
            NSLog("AlienMAC 外设诊断已导出：\(file.path)")
            return file.path
        } catch {
            NSLog("AlienMAC 外设诊断导出失败：\(error.localizedDescription)")
            return nil
        }
    }

    /// 清空最近一次捕获
    func clearLastEvent() {
        lastEvent = ""
        lastUsagePage = 0
        lastUsage = 0
        lastEventDate = nil
    }
}
