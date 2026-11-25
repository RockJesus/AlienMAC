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

    private var manager: IOHIDManager?
    private var started = false
    private var captureDevices: [IOHIDDevice] = []

    private init() {}

    // MARK: - 生命周期

    func start() {
        guard !started else { return }
        started = true

        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr

        // 只筛 Alienware / Dell 的 VID；不限定 usage page，避免漏掉厂商私有页
        let matches: [[String: Any]] = [
            [kIOHIDVendorIDKey: 0x187C],
            [kIOHIDVendorIDKey: 0x0D62],   // Dell 部分外设
            [kIOHIDVendorIDKey: 0x413C]    // Dell 传统 VID
        ]
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
        guard usagePage == 0x07 || usagePage == 0xFF00 || usagePage == 0xFF89 else { return }

        lastUsagePage = Int(usagePage)
        lastUsage = Int(usage)
        lastEventDate = Date()
        lastEvent = String(format: "usage page 0x%02X · usage 0x%02X · 值 %d", usagePage, usage, intValue)
    }

    /// 清空最近一次捕获
    func clearLastEvent() {
        lastEvent = ""
        lastUsagePage = 0
        lastUsage = 0
        lastEventDate = nil
    }
}
