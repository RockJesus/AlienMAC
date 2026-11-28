//
//  AlienFXController.swift
//  AlienMAC
//
//  高层灯光控制器，封装 HID 通信，提供友好的 API
//

import Foundation
import Combine

/// 灯光控制器，提供高层 API 控制 AlienFX 灯光
final class AlienFXController: ObservableObject {

    static let shared = AlienFXController()

    // MARK: - 发布属性

    @Published private(set) var isConnected: Bool = false
    @Published var logMessages: [String] = []

    /// 全局亮度 0-100
    @Published var brightness: Int = 100

    /// 当前设备信息（产品名 / VID / PID / 协议 / 机型）
    @Published private(set) var deviceInfo: AlienFXHIDManager.DeviceInfo?

    /// 当前选中的机型（自动识别或手动指定）
    @Published private(set) var model: AlienwareModel = AlienwareCatalog.placeholder(productName: "Alienware")

    /// 手动指定的机型 id，nil 表示自动识别
    @Published var manualModelID: String? {
        didSet {
            UserDefaults.standard.set(manualModelID, forKey: Self.manualKey)
            hid.manualModelID = manualModelID
            refreshModel()
        }
    }

    /// 当前机型是否可被本 App 控制
    var hardwareControllable: Bool {
        (deviceInfo?.proto ?? .unknown).supportsControl
    }

    private static let manualKey = "AlienMAC.manualModelID"

    // MARK: - 私有属性

    private let hid = AlienFXHIDManager.shared

    // MARK: - 初始化

    private init() {
        hid.connectionCallback = { [weak self] connected in
            DispatchQueue.main.async {
                self?.isConnected = connected
                if connected {
                    self?.log("AlienFX 控制器已连接")
                }
            }
        }

        hid.logCallback = { [weak self] message in
            DispatchQueue.main.async {
                self?.log(message)
            }
        }

        hid.deviceInfoCallback = { [weak self] info in
            DispatchQueue.main.async {
                self?.deviceInfo = info
                self?.refreshModel()
            }
        }

        manualModelID = UserDefaults.standard.string(forKey: Self.manualKey)
        hid.manualModelID = manualModelID
        isConnected = hid.isConnected
    }

    // MARK: - 机型识别

    /// 当前设备在 AWCC 机型灯表里的能力（亮度上下限 / keypad / tempo / 灯数）
    var modelCapability: AWCCModelInfo? {
        AWCCCatalogStore.shared.model(matchingDeviceName: deviceInfo?.productName)
    }

    /// 本机亮度下限（0 仍然表示关灯）
    var brightnessFloor: Int {
        let floor = modelCapability?.capabilities.brightness.min ?? 20
        return min(100, max(1, floor))
    }

    /// 根据设备信息刷新当前机型（手动指定优先）
    private func refreshModel() {
        if let manual = manualModelID,
           let picked = AlienwareCatalog.models.first(where: { $0.id == manual }) {
            model = picked
            return
        }
        if let info = deviceInfo {
            model = info.model
            syncCapabilities(info)
        }
    }

    /// 把机型灯表里的能力接到驱动层：亮度下限跟着机型走，亮度值不许落在下限以下
    private func syncCapabilities(_ info: AlienFXHIDManager.DeviceInfo) {
        guard let capability = AWCCCatalogStore.shared.model(matchingDeviceName: info.productName) else {
            hid.minBrightness = 20
            return
        }
        let floor = min(100, max(1, capability.capabilities.brightness.min ?? 20))
        hid.minBrightness = floor
        if brightness > 0, brightness < floor {
            brightness = floor
            hid.setBrightness(UInt8(floor))
        }
        let colorZones = capability.leds.filter { !($0.brightnessOnly ?? false) }.count
        log("机型 \(capability.name)：亮度 \(capability.capabilities.brightness.min ?? 20)–\(capability.capabilities.brightness.max ?? 100)%，可设色 \(colorZones) 区，keypad \(capability.capabilities.keypad == true ? "支持" : "无")")
    }

    /// 手动指定机型；传 nil 回到自动识别
    func selectModel(_ id: String?) {
        manualModelID = id
        log("机型手动指定为 \(model.name)")
    }

    /// 重新扫描设备并按新的机型设置识别
    func redetect() {
        hid.rescan()
    }

    // MARK: - 基础控制

    /// 重置控制器
    func reset() {
        guard hardwareControllable else {
            log("当前机型协议 \(deviceInfo?.proto.rawValue ?? "未知") 暂未接入，跳过重置")
            return
        }
        hid.reset { [weak self] success in
            if success {
                self?.log("控制器已重置")
            }
        }
    }

    /// 关闭所有灯光
    func turnOffAll() {
        setAllZones(color: .off, effect: .color)
    }

    /// 设置全局亮度
    func setBrightness(_ value: Int) {
        guard hardwareControllable else {
            log("当前机型协议 \(deviceInfo?.proto.rawValue ?? "未知") 暂未接入，跳过亮度下发")
            return
        }
        let floor = brightnessFloor
        let clamped = value <= 0 ? 0 : max(floor, min(100, value))
        brightness = clamped
        hid.setBrightness(UInt8(clamped)) { [weak self] success in
            if success {
                self?.log("亮度已设置为 \(clamped)%")
            }
        }
    }

    // MARK: - 颜色设置

    /// 设置单个灯区颜色
    func setZone(_ zone: LightZone, color: RGBColor, effect: LightEffect = .color, color2: RGBColor? = nil, tempo: UInt16 = 2000) {
        setZones(zone, color: color, effect: effect, color2: color2, tempo: tempo)
    }

    /// 设置多个灯区为同一颜色（自动管理完整事务）
    func setZones(_ zones: LightZone, color: RGBColor, effect: LightEffect = .color, color2: RGBColor? = nil, tempo: UInt16 = 2000) {
        guard zones.rawValue != 0 else { return }

        // v4 / v8 没有 v3 的位掩码语义，统一走“每盏灯一条”的场景组包
        if let proto = hid.deviceInfo?.proto, proto == .apiV4 || proto == .apiV8 {
            let targets = LightZone.orderedHardware.filter { zones.contains($0) }
            setZoneColors(targets.map { (zone: $0, color: color, effect: effect, color2: color2) },
                          tempo: tempo, persistSlot: false)
            return
        }

        hid.setZones(zones, effect: effect, color1: color, color2: color2, tempo: tempo) { [weak self] success in
            if success {
                self?.log("已设置灯区 [0x\(String(zones.rawValue, radix: 16))] 颜色 #\(String(format: "%02X%02X%02X", color.r, color.g, color.b)) 效果:\(effect.rawValue)")
            } else {
                self?.log("设置失败，请检查设备连接")
            }
        }
    }

    /// 设置所有灯区为同一颜色
    func setAllZones(color: RGBColor, effect: LightEffect = .color, color2: RGBColor? = nil, tempo: UInt16 = 2000) {
        setZones(.all, color: color, effect: effect, color2: color2, tempo: tempo)
    }

    /// 批量设置不同灯区不同颜色（一次事务，效率更高）
    func setZoneColors(_ zoneColors: [(zone: LightZone, color: RGBColor, effect: LightEffect, color2: RGBColor?)], tempo: UInt16 = 2000, persistSlot: Bool = true) {
        guard !zoneColors.isEmpty else { return }

        if let proto = hid.deviceInfo?.proto, proto == .apiV4 || proto == .apiV8 {
            applyForeignScene(zoneColors, proto: proto, tempo: tempo)
            return
        }

        let converted = zoneColors.map { (zone: $0.zone, effect: $0.effect, color1: $0.color, color2: $0.color2) }
        hid.setZoneColors(converted, tempo: tempo, persistSlot: persistSlot) { [weak self] success in
            if success {
                self?.log(persistSlot ? "已批量应用 \(zoneColors.count) 个灯区设置" : "已下发预览帧 \(zoneColors.count) 个灯区（不写入存储）")
            } else {
                self?.log("批量设置失败")
            }
        }
    }

    // MARK: - v4 / v8 场景下发

    /// 把每盏灯的颜色编成 v4/v8 帧后下发；组包与 Mock 设备用的是同一份 FXSceneBuilder
    private func applyForeignScene(_ zoneColors: [(zone: LightZone, color: RGBColor, effect: LightEffect, color2: RGBColor?)],
                                   proto: AlienFXProtocol,
                                   tempo: UInt16) {
        let lights = zoneColors.compactMap { item -> FXSceneLight? in
            guard let index = LightZone.orderedHardware.firstIndex(of: item.zone) else { return nil }
            return FXSceneLight(id: UInt8(index),
                                color: FXRGBA(r: item.color.r, g: item.color.g, b: item.color.b),
                                effect: Self.fxKind(item.effect),
                                tempo: tempo)
        }
        guard !lights.isEmpty else {
            log("\(proto.rawValue) 场景里没有可映射的硬件灯区")
            return
        }

        var packets = proto == .apiV4
            ? FXSceneBuilder.v4(lights: lights)
            : FXSceneBuilder.v8(lights: lights)

        // v4 的电源按钮走独立块 03 22，不参与颜色
        if proto == .apiV4,
           zoneColors.contains(where: { $0.zone == .powerButton }),
           let padded = FXv4Codec.pad(FXv4Codec.powerBlock(0x00)) {
            packets.insert(FXPacket(transport: .setReport, payload: padded, note: "电源块 03 22 00"), at: 0)
        }

        let family = proto.rawValue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.hid.sendScene(packets)
            DispatchQueue.main.async {
                var text = "\(family) 场景已下发 \(result.sent)/\(packets.count) 帧"
                if result.failed > 0 { text += "（失败 \(result.failed) 帧）" }
                self.log(text)
            }
        }
    }

    /// LightEffect → FXEffectKind；光波/扫描在硬件侧按常亮下发，由 App 逐帧算色
    static func fxKind(_ effect: LightEffect) -> FXEffectKind {
        switch effect {
        case .color:     return .steady
        case .pulse:     return .pulse
        case .morph:     return .morph
        case .breathing: return .breathing
        case .spectrum:  return .spectrum
        case .wave, .scanner: return .steady
        }
    }

    /// 设置电源按钮颜色（特殊处理：遍历所有电源状态块，避免蓝色底色叠加）
    func setPowerButton(color: RGBColor, effect: LightEffect = .color, color2: RGBColor? = nil, tempo: UInt16 = 2000) {
        hid.setPowerButtonColor(effect: effect, color1: color, color2: color2, tempo: tempo) { [weak self] success in
            if success {
                self?.log("电源按钮颜色已设置（含所有电源状态块）")
            } else {
                self?.log("电源按钮设置失败")
            }
        }
    }

    // MARK: - 预设效果

    /// 呼吸效果（所有灯区）
    func breathingAll(color: RGBColor) {
        setAllZones(color: color, effect: .breathing, color2: .off)
    }

    /// 脉冲效果（所有灯区）
    func pulseAll(color: RGBColor) {
        setAllZones(color: color, effect: .pulse, color2: .off)
    }

    /// 渐变效果（所有灯区在两色之间渐变）
    func morphAll(color1: RGBColor, color2: RGBColor) {
        setAllZones(color: color1, effect: .morph, color2: color2)
    }

    // MARK: - 保存

    /// 保存当前设置为开机默认
    func saveAsDefault() {
        hid.save { [weak self] success in
            if success {
                self?.log("设置已保存到设备闪存")
            }
        }
    }

    /// 重新扫描设备
    func rescan() {
        hid.rescan()
        log("正在重新扫描设备...")
    }

    // MARK: - 日志

    /// 写入日志（内部和外部共用）
    func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logMessages.append("[\(timestamp)] \(message)")
        if logMessages.count > 200 {
            logMessages.removeFirst(logMessages.count - 200)
        }
    }

    func clearLog() {
        logMessages.removeAll()
    }
}
