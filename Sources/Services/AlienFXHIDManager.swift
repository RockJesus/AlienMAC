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

    /// 已发现的 AlienFX 设备信息
    struct DeviceInfo {
        var productName: String
        var vendorID: UInt32
        var productID: UInt32
        var outputReportSize: Int
        var proto: AlienFXProtocol
        var model: AlienwareModel
    }

    private(set) var deviceInfo: DeviceInfo? {
        didSet { deviceInfoCallback?(deviceInfo) }
    }

    var deviceInfoCallback: ((DeviceInfo?) -> Void)?

    /// 手动指定的机型（nil = 自动识别）
    var manualModelID: String? {
        didSet { reidentify() }
    }

    // MARK: - 私有属性

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var chain: UInt8 = 1
    private let stateLock = NSLock()
    private var _inTransaction = false

    /// 事务状态：所有写入都在串行队列内完成，这里再加锁，避免外部线程读取时撕裂
    private var inTransaction: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _inTransaction }
        set { stateLock.lock(); _inTransaction = newValue; stateLock.unlock() }
    }
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

        // 只按厂商匹配，具体型号与协议在设备接入时按产品名 / 报文长度判定
        let matchingDict: [String: Any] = [
            kIOHIDVendorIDKey: AlienFXDeviceID.vendorID
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
            log("HID Manager started, scanning Alienware lighting devices (VID:0x\(String(AlienFXDeviceID.vendorID, radix: 16)), 任意 PID)")
        }
    }

    private func handleDeviceConnected(_ deviceRef: IOHIDDevice) {
        let name = IOHIDDeviceGetProperty(deviceRef, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        let vid = IOHIDDeviceGetProperty(deviceRef, kIOHIDVendorIDKey as CFString) as? UInt32 ?? 0
        let pid = IOHIDDeviceGetProperty(deviceRef, kIOHIDProductIDKey as CFString) as? UInt32 ?? 0
        let reportSize = IOHIDDeviceGetProperty(deviceRef, kIOHIDMaxOutputReportSizeKey as CFString) as? Int
            ?? IOHIDDeviceGetProperty(deviceRef, "MaxOutputReportSize" as CFString) as? Int
            ?? 0

        // 同一厂商下可能挂鼠标 / 键盘等外设，先按报文长度与产品名筛掉不是灯控的设备
        let looksLikeLighting = reportSize == 12 || reportSize == 34
            || name.lowercased().contains("alienfx")
            || name.lowercased().contains("aw-elc")
            || name.lowercased().contains("alienware")
        guard looksLikeLighting else {
            log("跳过非灯控设备: \(name) [PID:0x\(String(pid, radix: 16)) Report:\(reportSize)]")
            return
        }

        device = deviceRef
        isConnected = true
        inTransaction = false
        chain = 1

        let proto = Self.protocolForReport(size: reportSize)
        var model = AlienwareCatalog.match(productName: name, productID: pid)
            ?? AlienwareCatalog.placeholder(productName: name)
        if let manual = manualModelID,
           let picked = AlienwareCatalog.models.first(where: { $0.id == manual }) {
            model = picked
        }
        deviceInfo = DeviceInfo(productName: name, vendorID: vid, productID: pid,
                                outputReportSize: reportSize, proto: proto, model: model)
        log("Device connected: \(name) [VID:0x\(String(vid, radix: 16)) PID:0x\(String(pid, radix: 16)) Report:\(reportSize)] → \(model.name) / \(proto.rawValue)")

        // 设备跑完 AWCC 的初始化序列后才认实时颜色；没有该资源时按普通模式直连
        if !AWCCDeviceInit.shared.isEmpty {
            Thread.sleep(forTimeInterval: 0.2)
            replayDeviceInit(includingColor: false) { sent in
                self.log("设备就绪握手已下发 \(sent)/\(AWCCDeviceInit.shared.handshakeCount) 帧（跳过 \(AWCCDeviceInit.shared.count - AWCCDeviceInit.shared.handshakeCount) 个配色帧，设备当前灯光保持不变）")
            }
        } else {
            log("未附带设备就绪序列（awcc-device-init.json 缺失），按普通模式连接")
        }
    }

    private static func protocolForReport(size: Int) -> AlienFXProtocol {
        switch size {
        case 8:  return .apiV1
        case 9:  return .apiV2
        case 12: return .apiV3
        case 34: return .apiV4
        case 64: return .apiV5
        case 65: return .apiV8
        default: return .unknown
        }
    }

    /// 手动切换机型 / 重新识别
    func reidentify() {
        guard let info = deviceInfo else { return }
        var model = AlienwareCatalog.match(productName: info.productName, productID: info.productID)
            ?? AlienwareCatalog.placeholder(productName: info.productName)
        if let manual = manualModelID,
           let picked = AlienwareCatalog.models.first(where: { $0.id == manual }) {
            model = picked
        }
        deviceInfo = DeviceInfo(productName: info.productName, vendorID: info.vendorID,
                                productID: info.productID, outputReportSize: info.outputReportSize,
                                proto: info.proto, model: model)
        log("机型切换为: \(model.name)")
    }

    private func handleDeviceRemoved() {
        device = nil
        deviceInfo = nil
        isConnected = false
        inTransaction = false
        log("Device disconnected")
    }

    func rescan() {
        guard let manager = manager else { return }
        IOHIDManagerSetDeviceMatching(manager, nil)
        let matchingDict: [String: Any] = [
            kIOHIDVendorIDKey: AlienFXDeviceID.vendorID
        ]
        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)
        reidentify()
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
        guard deviceInfo?.proto.supportsControl ?? true else {
            log("当前机型协议 \((deviceInfo?.proto.rawValue ?? "未知")) 暂未接入，已跳过下发")
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

    // MARK: - 写会话（AWCC 真实协议）

    /// 收尾：`02 08 <DataID>` → `02 04 00` → `02 09 00` → `02 05 00`
    @discardableResult
    private func closeWireSession(_ dataID: UInt8 = AWCCWire.realtimeDataID) -> Bool {
        var ok = true
        if !sendRaw(data: AWCCWire.writeFinished(dataID)) { ok = false }
        Thread.sleep(forTimeInterval: 0.02)
        if !sendRaw(data: AWCCWire.latch) { ok = false }
        Thread.sleep(forTimeInterval: 0.02)
        if !sendRaw(data: AWCCWire.saveSlot) { ok = false }
        Thread.sleep(forTimeInterval: 0.03)
        if !sendRaw(data: AWCCWire.commit) { ok = false }
        inTransaction = false
        return ok
    }

    /// 打开写会话：复位 → 状态查询 → `02 08 <DataID>`
    @discardableResult
    private func openWireSession(_ dataID: UInt8 = AWCCWire.realtimeDataID) -> Bool {
        var ok = true
        if !sendRaw(data: AWCCWire.reset) { ok = false }
        Thread.sleep(forTimeInterval: 0.08)
        _ = sendRaw(data: AWCCWire.statusQuery)
        if !sendRaw(data: AWCCWire.writeStart(dataID)) { ok = false }
        Thread.sleep(forTimeInterval: 0.02)
        inTransaction = true
        return ok
    }

    /// 重放设备就绪序列（AWCC 启动那 134 帧）
    func replayDeviceInit(gap: TimeInterval = 0.02,
                          includingColor: Bool = true,
                          completion: ((Int) -> Void)? = nil) {
        let seq = AWCCDeviceInit.shared
        guard !seq.isEmpty else {
            log("设备就绪序列为空，跳过")
            completion?(0)
            return
        }
        sendQueue.async { [weak self] in
            guard let self = self else { return }
            let sent = seq.replay(send: { self.sendRaw(data: $0) }, gap: gap, includingColor: includingColor)
            DispatchQueue.main.async { completion?(sent) }
        }
    }

    // MARK: - 事务控制

    /// 开始事务：重置控制器，等待就绪
    func beginTransaction(completion: ((Bool) -> Void)? = nil) {
        sendQueue.async { [weak self] in
            guard let self = self else { return }
            self.chain = 1
            // 复位 + 查状态
            let ok = self.sendRaw(data: AWCCWire.reset)
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
            // 提交: 02 05 00
            let ok = self.sendRaw(data: AWCCWire.commit)
            self.inTransaction = false
            Thread.sleep(forTimeInterval: 0.03)
            DispatchQueue.main.async {
                completion?(ok)
            }
        }
    }

    // MARK: - 高层命令

    /// 设置灯区颜色和效果（AWCC 写会话：一次会话里下发全部颜色帧）
    ///
    /// 只要有一盏灯，就必须走完整会话，缺环设备不执行：
    ///   02 07 04 复位 → 02 06 00 查状态 → 02 08 01 写开始 → [02 0E 00 tempo] → 逐灯 02 03 帧
    ///   → 02 08 01 → 02 04 00 → 02 09 00 → 02 05 00 提交
    func setZones(_ zones: LightZone, effect: LightEffect, color1: RGBColor, color2: RGBColor? = nil, tempo: UInt16 = 2000, completion: ((Bool) -> Void)? = nil) {
        let targets = LightZone.orderedHardware.filter { zones.contains($0) }
        guard !targets.isEmpty else {
            completion?(false)
            return
        }

        sendQueue.async { [weak self] in
            guard let self = self else { return }
            var allOk = self.openWireSession()
            // 复位后设备要缓一小会儿才收颜色命令，且会话里第一条颜色指令会被吞/按残留亮度渲染
            // （键盘左永远排第一，所以总是它先出问题）。等 100ms，并在会话末尾把首条补发一次。
            Thread.sleep(forTimeInterval: 0.10)

            if effect.needsTempoCommand {
                if !self.sendRaw(data: [0x0E, 0x00, UInt8(tempo & 0xFF), UInt8((tempo >> 8) & 0xFF)]) { allOk = false }
                Thread.sleep(forTimeInterval: 0.02)
            }

            var firstCommand: [UInt8]?
            for zone in targets {
                guard let address = zone.hardwareAddress else { continue }
                let colorCmd = self.makeColorCommand(group: address.group, mask: address.mask,
                                                     effect: effect, color1: color1, color2: color2)
                if firstCommand == nil { firstCommand = colorCmd }
                if !self.sendRaw(data: colorCmd) { allOk = false }
                Thread.sleep(forTimeInterval: 0.03)
            }

            if let firstCommand {
                Thread.sleep(forTimeInterval: 0.03)
                if !self.sendRaw(data: firstCommand) { allOk = false }
            }

            if !self.closeWireSession() { allOk = false }
            Thread.sleep(forTimeInterval: 0.02)

            DispatchQueue.main.async {
                completion?(allOk)
            }
        }
    }

    /// 批量设置多个灯区不同颜色（同一个写会话内逐区下发）
    func setZoneColors(_ zoneColors: [(zone: LightZone, effect: LightEffect, color1: RGBColor, color2: RGBColor?)], tempo: UInt16 = 2000, completion: ((Bool) -> Void)? = nil) {
        guard !zoneColors.isEmpty else {
            completion?(false)
            return
        }

        sendQueue.async { [weak self] in
            guard let self = self else { return }
            var allOk = self.openWireSession()
            // 复位后设备要缓一小会儿才开始收颜色命令，太快发的第一条会被吞掉
            Thread.sleep(forTimeInterval: 0.10)

            let needsTempo = zoneColors.contains { $0.effect.needsTempoCommand }
            if needsTempo {
                if !self.sendRaw(data: [0x0E, 0x00, UInt8(tempo & 0xFF), UInt8((tempo >> 8) & 0xFF)]) { allOk = false }
                Thread.sleep(forTimeInterval: 0.02)
            }

            var firstCommand: [UInt8]?
            for item in zoneColors {
                guard let address = item.zone.hardwareAddress else { continue }
                let colorCmd = self.makeColorCommand(group: address.group, mask: address.mask,
                                                     effect: item.effect, color1: item.color1, color2: item.color2)
                if firstCommand == nil { firstCommand = colorCmd }
                if !self.sendRaw(data: colorCmd) { allOk = false }
                Thread.sleep(forTimeInterval: 0.03)
            }

            // 会话里第一条颜色指令会被吞或按残留亮度渲染，末尾补发一次，排第一的键盘左才不会偏暗
            if let firstCommand {
                Thread.sleep(forTimeInterval: 0.03)
                if !self.sendRaw(data: firstCommand) { allOk = false }
            }

            if !self.closeWireSession() { allOk = false }
            Thread.sleep(forTimeInterval: 0.02)

            DispatchQueue.main.async {
                completion?(allOk)
            }
        }
    }

    /// 设置亮度
    ///
    /// 帧形态：`02 1C <20..100> <mode>`，mode 实测结论：
    ///   01 = 全局亮度；00 = 仅电池档（AC 下不变，设备存两套值）；
    ///   02 = PerZone，在 02 1C 上无效；03 越界被忽略。
    /// 硬件下限 20（AWCC 模型 MinimumBrightness=20），0 保留为关灯。
    func setBrightness(_ brightness: UInt8, batteryOnly: Bool = false, completion: ((Bool) -> Void)? = nil) {
        let raw = Int(brightness)
        let br = raw <= 0 ? 0 : min(max(raw, 20), 100)
        sendAsync(data: [0x1C, UInt8(br), batteryOnly ? 0x00 : 0x01], delay: 0.03, completion: completion)
    }

    /// 重置控制器
    func reset(completion: ((Bool) -> Void)? = nil) {
        sendQueue.async { [weak self] in
            guard let self = self else { return }
            self.chain = 1
            self.inTransaction = false
            let ok = self.sendRaw(data: AWCCWire.reset)
            Thread.sleep(forTimeInterval: 0.08)
            _ = self.sendRaw(data: AWCCWire.statusQuery)
            Thread.sleep(forTimeInterval: 0.02)
            DispatchQueue.main.async {
                completion?(ok)
            }
        }
    }

    /// 保存当前设置到设备闪存（02 09 00 → 02 05 00）
    func save(completion: ((Bool) -> Void)? = nil) {
        sendQueue.async { [weak self] in
            guard let self = self else { return }
            var ok = self.sendRaw(data: AWCCWire.saveSlot)
            Thread.sleep(forTimeInterval: 0.03)
            if !self.sendRaw(data: AWCCWire.commit) { ok = false }
            DispatchQueue.main.async { completion?(ok) }
        }
    }

    // MARK: - 电源按钮特殊处理

    /// 设置电源按钮颜色（电源按钮有独立的电源状态块，需逐个设置否则蓝色底色叠加）
    /// 电源状态块: 0=开机, 1=充电, 2=低电量, 3=睡眠
    ///
    /// 说明：17 R4 官方 Leds 表里**没有**电源按钮的可寻址灯（它只有 Zones 条目、没有 Led 条目），
    /// 所以这里只写状态块，颜色帧用 group 8 / 掩码 0，不会误点亮其它灯区。
    func setPowerButtonColor(effect: LightEffect, color1: RGBColor, color2: RGBColor? = nil, tempo: UInt16 = 2000, completion: ((Bool) -> Void)? = nil) {
        sendQueue.async { [weak self] in
            guard let self = self else { return }

            var allOk = true
            self.log("电源按钮在 17 R4 上无独立颜色通道（官方 Leds 表无此灯），仅写电源状态块")

            // 遍历所有电源状态块，逐个设置颜色并保存
            for state in 0...3 {
                // 1. 切换到该状态保存块 [0x08, state]
                if !self.sendRaw(data: [0x08, UInt8(state)]) { allOk = false }
                Thread.sleep(forTimeInterval: 0.02)

                // 2. 重置控制器
                if !self.sendRaw(data: AWCCWire.reset) { allOk = false }
                Thread.sleep(forTimeInterval: 0.08)

                // 渐变/呼吸效果需要先设置速度
                if effect.needsTempoCommand {
                    _ = self.sendRaw(data: [0x0E, UInt8(tempo & 0xFF), UInt8((tempo >> 8) & 0xFF)])
                    Thread.sleep(forTimeInterval: 0.02)
                }

                // 3. 电源状态块颜色（掩码 0 = 不点亮任何可寻址灯），仍在写会话内
                _ = self.sendRaw(data: AWCCWire.writeStart(AWCCWire.realtimeDataID))
                Thread.sleep(forTimeInterval: 0.02)
                let colorCmd = self.makeColorCommand(group: 0x08, mask: 0x000000,
                                                     effect: effect, color1: color1, color2: color2)
                if !self.sendRaw(data: colorCmd) { allOk = false }
                Thread.sleep(forTimeInterval: 0.03)

                // 4. 写结束 + 锁存
                if !self.sendRaw(data: AWCCWire.writeFinished(AWCCWire.realtimeDataID)) { allOk = false }
                Thread.sleep(forTimeInterval: 0.02)
                if !self.sendRaw(data: AWCCWire.latch) { allOk = false }
                Thread.sleep(forTimeInterval: 0.03)

                // 5. 保存到该状态块
                if !self.sendRaw(data: AWCCWire.saveSlot) { allOk = false }
                Thread.sleep(forTimeInterval: 0.05)
            }

            // 恢复正常保存块
            if !self.sendRaw(data: [0x08, 0x00]) { allOk = false }
            Thread.sleep(forTimeInterval: 0.02)

            // 最后 UPDATE 使设置生效
            if !self.sendRaw(data: AWCCWire.commit) { allOk = false }
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
    /// 正确结构（真机 17 R4 复核通过）:
    ///   [0] opcode      效果操作码 (3=常亮, 2=脉冲, 1=渐变)
    ///   [1] chain       组号（官方 Groups ID，不是自增序号）
    ///   [2] mask_high   组内掩码高字节 (bits 16-23)
    ///   [3] mask_mid    组内掩码中字节 (bits 8-15)
    ///   [4] mask_low    组内掩码低字节 (bits 0-7)
    ///   [5] R1          主颜色 Red
    ///   [6] G1          主颜色 Green
    ///   [7] B1          主颜色 Blue
    ///   [8] R2          次颜色 Red
    ///   [9] G2          次颜色 Green
    ///   [10] B2         次颜色 Blue
    private func makeColorCommand(group: UInt8, mask: UInt32, effect: LightEffect, color1: RGBColor, color2: RGBColor?) -> [UInt8] {
        // 呼吸必须单色淡入淡出：副色强制黑，否则等价于两色渐变
        let c2: RGBColor = effect == .breathing ? .off : (color2 ?? .off)

        return [
            effect.opcode,                          // [0] 操作码（注意：不是 0x03！）
            group,                                  // [1] 组号
            UInt8((mask >> 16) & 0xFF),             // [2] 掩码高字节
            UInt8((mask >> 8) & 0xFF),              // [3] 掩码中字节
            UInt8(mask & 0xFF),                     // [4] 掩码低字节
            color1.r, color1.g, color1.b,           // [5-7] 主颜色 RGB
            c2.r, c2.g, c2.b                        // [8-10] 次颜色 RGB
        ]
    }

    // MARK: - 日志

    private func log(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.logCallback?(message)
        }
    }
}
