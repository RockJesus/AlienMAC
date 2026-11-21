//
//  AlienFXHIDManager.swift
//  AlienMAC
//
//  基于 IOKit HID Manager 的用户态 USB HID 通信层
//  协议参考: T-Troll/alienfx-tools APIv3 实现
//  无需 kext、无需关闭 SIP，纯用户态访问
//

import Foundation
import IOKit
import IOKit.hid

/// HID 通信管理器，负责设备发现、连接和原始字节收发
final class AlienFXHIDManager {

    static let shared = AlienFXHIDManager()

    // MARK: - 状态

    /// 是否已连接到 AlienFX 设备
    private(set) var isConnected: Bool = false {
        didSet { connectionCallback?(isConnected) }
    }

    /// 连接状态变化回调
    var connectionCallback: ((Bool) -> Void)?

    /// 调试日志回调
    var logCallback: ((String) -> Void)?

    // MARK: - 私有属性

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var chain: UInt8 = 1
    private var inTransaction = false
    private let sendQueue = DispatchQueue(label: "com.alienfx.hid.send", qos: .userInitiated)

    // MARK: - 初始化

    private init() {
        setupManager()
    }

    deinit {
        if let manager = manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    // MARK: - 设备管理

    private func setupManager() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        guard let manager = manager else {
            log("Failed to create HID Manager")
            return
        }

        let matchingDict: [String: Any] = [
            kIOHIDVendorIDKey:  AlienFXDeviceID.vendorID,
            kIOHIDProductIDKey: AlienFXDeviceID.productID
        ]
        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context = context else { return }
            let `self` = Unmanaged<AlienFXHIDManager>.fromOpaque(context).takeUnretainedValue()
            self.handleDeviceConnected(device)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
            guard let context = context else { return }
            let `self` = Unmanaged<AlienFXHIDManager>.fromOpaque(context).takeUnretainedValue()
            self.handleDeviceRemoved()
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            log("IOHIDManagerOpen failed: \(result)")
        } else {
            log("HID Manager started, waiting for AlienFX device (VID:0x\(String(AlienFXDeviceID.vendorID, radix: 16)) PID:0x\(String(AlienFXDeviceID.productID, radix: 16)))")
        }
    }

    private func handleDeviceConnected(_ deviceRef: IOHIDDevice) {
        device = deviceRef
        isConnected = true
        inTransaction = false
        chain = 1

        let name = IOHIDDeviceGetProperty(deviceRef, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        let vid = IOHIDDeviceGetProperty(deviceRef, kIOHIDVendorIDKey as CFString) as? UInt32 ?? 0
        let pid = IOHIDDeviceGetProperty(deviceRef, kIOHIDProductIDKey as CFString) as? UInt32 ?? 0
        log("Device connected: \(name) [VID:0x\(String(vid, radix: 16)) PID:0x\(String(pid, radix: 16))]")
    }

    private func handleDeviceRemoved() {
        device = nil
        isConnected = false
        inTransaction = false
        log("Device disconnected")
    }

    func rescan() {
        guard let manager = manager else { return }
        IOHIDManagerSetDeviceMatching(manager, nil)
        let matchingDict: [String: Any] = [
            kIOHIDVendorIDKey:  AlienFXDeviceID.vendorID,
            kIOHIDProductIDKey: AlienFXDeviceID.productID
        ]
        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)
    }

    // MARK: - 底层发送

    /// 发送 HID Output Report（同步，在调用线程执行）
    /// APIv3 报告总长 12 字节：[ReportID] + [11 字节数据]
    @discardableResult
    private func sendRaw(data: [UInt8]) -> Bool {
        guard isConnected, let device = device else {
            log("Send failed: no device connected")
            return false
        }

        // 构造完整报告：Report ID + 数据，补齐到 12 字节
        var report = [AlienFXDeviceID.reportID] + data
        while report.count < AlienFXDeviceID.reportLength {
            report.append(0x00)
        }
        if report.count > AlienFXDeviceID.reportLength {
            report = Array(report.prefix(AlienFXDeviceID.reportLength))
        }

        let result = IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeOutput,
            CFIndex(AlienFXDeviceID.reportID),
            report,
            report.count
        )

        if result != kIOReturnSuccess {
            log("IOHIDDeviceSetReport failed: 0x\(String(result, radix: 16))")
            return false
        }

        log("TX: \(report.map { String(format: "%02X", $0) }.joined(separator: " "))")
        return true
    }

    /// 在串行队列中发送命令（带防崩溃延时）
    private func sendAsync(data: [UInt8], delay: TimeInterval = 0.03, completion: ((Bool) -> Void)? = nil) {
        sendQueue.async { [weak self] in
            guard let self = self else { return }
            let success = self.sendRaw(data: data)
            if delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }
            DispatchQueue.main.async {
                completion?(success)
            }
        }
    }

    // MARK: - 事务控制

    /// 开始事务：重置控制器，等待就绪
    func beginTransaction(completion: ((Bool) -> Void)? = nil) {
        sendQueue.async { [weak self] in
            guard let self = self else { return }
            self.chain = 1
            // 重置命令: [0x07, 0x04] (reset + on)
            let ok = self.sendRaw(data: [0x07, 0x04])
            if ok {
                self.inTransaction = true
                // 等待设备就绪（alienfx-tools 中 WaitForReady 最多等 100ms）
                Thread.sleep(forTimeInterval: 0.08)
            }
            DispatchQueue.main.async {
                completion?(ok)
            }
        }
    }

    /// 结束事务：发送 UPDATE 命令使所有设置生效
    func endTransaction(completion: ((Bool) -> Void)? = nil) {
        sendQueue.async { [weak self] in
            guard let self = self else { return }
            // UPDATE 命令: [0x05]
            let ok = self.sendRaw(data: [0x05])
            self.inTransaction = false
            Thread.sleep(forTimeInterval: 0.03)
            DispatchQueue.main.async {
                completion?(ok)
            }
        }
    }

    // MARK: - 高层命令

    /// 设置灯区颜色和效果（自动管理事务）
    /// 这是最常用的入口，自动完成: begin → tempo(如需) → color+loop → end
    func setZones(_ zones: LightZone, effect: LightEffect, color1: RGBColor, color2: RGBColor? = nil, tempo: UInt16 = 2000, completion: ((Bool) -> Void)? = nil) {
        guard zones.rawValue != 0 else {
            completion?(false)
            return
        }

        sendQueue.async { [weak self] in
            guard let self = self else { return }

            // 如果不在事务中，先开始事务
            if !self.inTransaction {
                self.chain = 1
                _ = self.sendRaw(data: [0x07, 0x04])
                Thread.sleep(forTimeInterval: 0.08)
                self.inTransaction = true
            }

            // 渐变/呼吸效果需要先设置速度
            if effect.needsSecondaryColor {
                _ = self.sendRaw(data: [0x0E, UInt8(tempo & 0xFF), UInt8((tempo >> 8) & 0xFF)])
                Thread.sleep(forTimeInterval: 0.02)
            }

            // 发送颜色命令
            let colorCmd = self.makeColorCommand(zones: zones, effect: effect, color1: color1, color2: color2)
            let colorOk = self.sendRaw(data: colorCmd)
            Thread.sleep(forTimeInterval: 0.03)

            // 发送 LOOP 命令使当前颜色生效
            let loopOk = self.sendRaw(data: [0x04])
            self.chain = self.chain &+ 1
            if self.chain == 0 { self.chain = 1 }
            Thread.sleep(forTimeInterval: 0.03)

            // 发送 UPDATE 命令提交事务
            let updateOk = self.sendRaw(data: [0x05])
            self.inTransaction = false
            Thread.sleep(forTimeInterval: 0.02)

            let success = colorOk && loopOk && updateOk
            DispatchQueue.main.async {
                completion?(success)
            }
        }
    }

    /// 批量设置多个灯区不同颜色（一次事务）
    func setZoneColors(_ zoneColors: [(zone: LightZone, effect: LightEffect, color1: RGBColor, color2: RGBColor?)], tempo: UInt16 = 2000, completion: ((Bool) -> Void)? = nil) {
        guard !zoneColors.isEmpty else {
            completion?(false)
            return
        }

        sendQueue.async { [weak self] in
            guard let self = self else { return }

            // 开始事务
            self.chain = 1
            _ = self.sendRaw(data: [0x07, 0x04])
            Thread.sleep(forTimeInterval: 0.08)
            self.inTransaction = true

            var allOk = true

            // 逐个发送颜色 + LOOP
            for item in zoneColors {
                guard item.zone.rawValue != 0 else { continue }
                // 渐变/呼吸效果需要先设置速度
                if item.effect.needsSecondaryColor {
                    _ = self.sendRaw(data: [0x0E, UInt8(tempo & 0xFF), UInt8((tempo >> 8) & 0xFF)])
                    Thread.sleep(forTimeInterval: 0.02)
                }
                let colorCmd = self.makeColorCommand(zones: item.zone, effect: item.effect, color1: item.color1, color2: item.color2)
                if !self.sendRaw(data: colorCmd) { allOk = false }
                Thread.sleep(forTimeInterval: 0.03)
                if !self.sendRaw(data: [0x04]) { allOk = false }
                self.chain = self.chain &+ 1
                if self.chain == 0 { self.chain = 1 }
                Thread.sleep(forTimeInterval: 0.03)
            }

            // 提交事务
            if !self.sendRaw(data: [0x05]) { allOk = false }
            self.inTransaction = false
            Thread.sleep(forTimeInterval: 0.02)

            DispatchQueue.main.async {
                completion?(allOk)
            }
        }
    }

    /// 设置全局亮度
    func setBrightness(_ brightness: UInt8, completion: ((Bool) -> Void)? = nil) {
        let br = min(brightness, 100)
        sendAsync(data: [0x1C, br, 0x01], delay: 0.03, completion: completion)
    }

    /// 重置控制器
    func reset(completion: ((Bool) -> Void)? = nil) {
        sendQueue.async { [weak self] in
            guard let self = self else { return }
            self.chain = 1
            self.inTransaction = false
            let ok = self.sendRaw(data: [0x07, 0x04])
            Thread.sleep(forTimeInterval: 0.1)
            DispatchQueue.main.async {
                completion?(ok)
            }
        }
    }

    /// 保存当前设置到设备闪存
    func save(completion: ((Bool) -> Void)? = nil) {
        sendAsync(data: [0x09], delay: 0.05, completion: completion)
    }

    // MARK: - 电源按钮特殊处理

    /// 设置电源按钮颜色（电源按钮有独立的电源状态块，需逐个设置否则蓝色底色叠加）
    /// 电源状态块: 0=开机, 1=充电, 2=低电量, 3=睡眠
    func setPowerButtonColor(effect: LightEffect, color1: RGBColor, color2: RGBColor? = nil, tempo: UInt16 = 2000, completion: ((Bool) -> Void)? = nil) {
        sendQueue.async { [weak self] in
            guard let self = self else { return }

            var allOk = true
            let powerZone = LightZone(rawValue: 1 << 8)  // 电源按钮 bit 8

            // 遍历所有电源状态块，逐个设置颜色并保存
            for state in 0...3 {
                // 1. 切换到该状态保存块 [0x08, state]
                if !self.sendRaw(data: [0x08, UInt8(state)]) { allOk = false }
                Thread.sleep(forTimeInterval: 0.02)

                // 2. 重置控制器
                self.chain = 1
                if !self.sendRaw(data: [0x07, 0x04]) { allOk = false }
                Thread.sleep(forTimeInterval: 0.08)

                // 渐变/呼吸效果需要先设置速度
                if effect.needsSecondaryColor {
                    _ = self.sendRaw(data: [0x0E, UInt8(tempo & 0xFF), UInt8((tempo >> 8) & 0xFF)])
                    Thread.sleep(forTimeInterval: 0.02)
                }

                // 3. 设置电源按钮颜色
                let colorCmd = self.makeColorCommand(zones: powerZone, effect: effect, color1: color1, color2: color2)
                if !self.sendRaw(data: colorCmd) { allOk = false }
                Thread.sleep(forTimeInterval: 0.03)

                // 4. LOOP
                if !self.sendRaw(data: [0x04]) { allOk = false }
                self.chain = self.chain &+ 1
                if self.chain == 0 { self.chain = 1 }
                Thread.sleep(forTimeInterval: 0.03)

                // 5. 保存到该状态块 [0x09]
                if !self.sendRaw(data: [0x09]) { allOk = false }
                Thread.sleep(forTimeInterval: 0.05)
            }

            // 恢复正常保存块
            if !self.sendRaw(data: [0x08, 0x00]) { allOk = false }
            Thread.sleep(forTimeInterval: 0.02)

            // 最后 UPDATE 使设置生效
            if !self.sendRaw(data: [0x05]) { allOk = false }
            self.inTransaction = false
            Thread.sleep(forTimeInterval: 0.02)

            DispatchQueue.main.async {
                completion?(allOk)
            }
        }
    }

    // MARK: - 协议命令构造

    /// 构造 APIv3 颜色命令数据部分（11 字节，不含 Report ID）
    ///
    /// 正确结构（对照 alienfx-tools SetMaskAndColor）:
    ///   [0] opcode      效果操作码 (3=常亮, 2=脉冲, 1=渐变)
    ///   [1] chain       序列号 (1-255)
    ///   [2] mask_high   灯掩码高字节 (bits 16-23)
    ///   [3] mask_mid    灯掩码中字节 (bits 8-15)
    ///   [4] mask_low    灯掩码低字节 (bits 0-7)
    ///   [5] R1          主颜色 Red
    ///   [6] G1          主颜色 Green
    ///   [7] B1          主颜色 Blue
    ///   [8] R2          次颜色 Red
    ///   [9] G2          次颜色 Green
    ///   [10] B2         次颜色 Blue
    private func makeColorCommand(zones: LightZone, effect: LightEffect, color1: RGBColor, color2: RGBColor?) -> [UInt8] {
        let mask = zones.rawValue
        let c2 = color2 ?? RGBColor(r: 0, g: 0, b: 0)

        return [
            effect.opcode,                     // [0] 操作码（注意：不是 0x03！）
            chain,                             // [1] 序列号
            UInt8((mask >> 16) & 0xFF),        // [2] 掩码高字节
            UInt8((mask >> 8) & 0xFF),         // [3] 掩码中字节
            UInt8(mask & 0xFF),                // [4] 掩码低字节
            color1.r, color1.g, color1.b,      // [5-7] 主颜色 RGB
            c2.r, c2.g, c2.b                   // [8-10] 次颜色 RGB
        ]
    }

    // MARK: - 日志

    private func log(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.logCallback?(message)
        }
    }
}
