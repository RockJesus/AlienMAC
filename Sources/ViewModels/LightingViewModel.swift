//
//  LightingViewModel.swift
//  AlienMAC
//
//  主视图模型，管理 UI 状态、持久化、预设与全局快捷键
//

import Foundation
import SwiftUI
import Combine
import AppKit
import QuartzCore

/// 主视图模型
final class LightingViewModel: ObservableObject {

    // MARK: - 发布属性

    /// 是否已连接
    @Published var isConnected: Bool = false

    /// 全局亮度 0-100
    @Published var brightness: Double = 100

    /// 当前选中的灯区
    @Published var selectedZones: Set<LightZone> = []

    /// 单键自定义颜色（键 id → 颜色）；没有记录的键跟随所属灯区颜色
    @Published var keyColors: [String: Color] = [:]

    /// 当前选中的单个按键（键盘按键映射）
    @Published var selectedKeys: Set<String> = []

    /// 3D 模型上当前悬停的按键
    @Published var hoveredKey: String?

    /// 触摸板细调（整面背光与四薄条边光分开控制）
    struct TouchpadOverride {
        /// 整面背光是否跟随灯区颜色
        var padFollowsZone: Bool = true
        var padColor: Color = Color(red: 0.0, green: 0.82, blue: 1.0)
        /// 整面亮度（百分比）
        var padBrightness: Double = 100
        /// 边光是否跟随灯区颜色
        var edgeFollowsZone: Bool = true
        var edgeColor: Color = Color(red: 0.0, green: 0.82, blue: 1.0)
        /// 边光强度（百分比）
        var edgeBrightness: Double = 100
        var edgeEnabled: Bool = true

        static let standard = TouchpadOverride()
    }

    @Published var touchpad = TouchpadOverride.standard {
        didSet {
            guard !isLoadingSettings else { return }
            persistState()
            dispatchColors()
        }
    }

    /// 电源键功能与灯效
    struct PowerOverride {
        var clickAction: SettingsStore.PowerAction = .none
        var doubleClickAction: SettingsStore.PowerAction = .none
        var holdAction: SettingsStore.PowerAction = .none
        var confirmDangerous: Bool = true
        var lightFollowsZone: Bool = true
        var lightColor: Color = Color(red: 0.0, green: 0.82, blue: 1.0)
        var lightBrightness: Double = 100

        static let standard = PowerOverride()
    }

    @Published var powerButton = PowerOverride.standard {
        didSet {
            guard !isLoadingSettings else { return }
            // 单击与双击互斥：都设动作会让第一次点击先触发单击
            if powerButton.clickAction != oldValue.clickAction, powerButton.clickAction != .none,
               powerButton.doubleClickAction != .none {
                powerButton.doubleClickAction = .none
            }
            if powerButton.doubleClickAction != oldValue.doubleClickAction, powerButton.doubleClickAction != .none,
               powerButton.clickAction != .none {
                powerButton.clickAction = .none
            }
            persistState()
            dispatchColors()
        }
    }

    /// 初始化期间不触发下发
    private var isLoadingSettings = true

    /// 当前编辑颜色
    @Published var currentColor: Color = .blue

    /// 当前效果
    @Published var currentEffect: LightEffect = .color

    /// 次颜色（渐变效果用）
    @Published var secondaryColor: Color = Color(red: 0.0, green: 0.82, blue: 1.0)

    /// 效果速度（毫秒）
    @Published var tempo: Double = 2000

    /// 是否显示调试日志
    @Published var showDebugLog: Bool = false

    /// 各灯区当前颜色（用于 UI 预览）
    @Published var zoneColors: [LightZone: Color] = [:]

    /// 三维模型上当前悬停的灯区
    @Published var hoveredZone: LightZone?

    /// 自定义预设
    @Published var customPresets: [CustomPreset] = []

    /// 启动时恢复上次灯光
    @Published var restoreOnLaunch: Bool = true {
        didSet { store.snapshot.restoreOnLaunch = restoreOnLaunch }
    }

    /// 启用全局快捷键
    @Published var hotkeysEnabled: Bool = true {
        didSet {
            store.snapshot.hotkeysEnabled = hotkeysEnabled
            if hotkeysEnabled { HotKeyCenter.shared.install() } else { HotKeyCenter.shared.uninstall() }
        }
    }

    /// 登录时自动启动
    @Published var launchAtLogin: Bool = false {
        didSet {
            guard !isSyncingLoginState else { return }
            guard launchAtLogin != LaunchAtLogin.isEnabled else { return }
            if let error = LaunchAtLogin.set(launchAtLogin) {
                controller.log("登录启动设置失败: \(error)")
                loginError = error
                isSyncingLoginState = true
                launchAtLogin = LaunchAtLogin.isEnabled
                isSyncingLoginState = false
            } else {
                loginError = nil
                controller.log(launchAtLogin ? "已启用登录时自动启动" : "已关闭登录时自动启动")
            }
        }
    }

    /// 登录项设置失败时的提示文案
    @Published var loginError: String?

    /// 内部同步开关状态时避免 didSet 递归
    private var isSyncingLoginState = false

    /// 屏幕 Logo 亮度补偿系数
    @Published var screenLogoBoost: Double = 1.6 {
        didSet { store.snapshot.screenLogoBoost = screenLogoBoost }
    }

    /// 灯光当前是否处于关闭状态（供快捷键切换使用）
    @Published var isLightsOff: Bool = false

    /// 逐灯测试状态
    @Published var isTestingZones = false
    @Published var currentTestBit: Int = -1
    private var testTimer: Timer?

    /// 跑马灯动画状态
    @Published var isMarqueeActive = false
    private var marqueeTimer: Timer?
    private var marqueeOffset = 0
    private let marqueeColors: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, Color(red: 0.5, green: 0, blue: 1)]
    private let marqueeZoneOrder: [LightZone] = [
        .macroKeys, .keyboardLeft, .keyboardMid, .keyboardRight, .numpad,
        .touchpad, .frontLeft, .frontRight, .rearLeft, .rearRight,
        .alienHead, .screenLogo
    ]

    // MARK: - 引用

    let controller = AlienFXController.shared
    private let store = SettingsStore.shared
    private var cancellables = Set<AnyCancellable>()
    private var didRestore = false
    /// 关闭前保存的灯光状态，用于快捷键重新点亮
    private var lastOnSnapshot: ZoneSnapshot?

    // MARK: - 初始化

    init() {
        // 监听控制器状态
        controller.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                guard let self = self else { return }
                self.isConnected = connected
                if connected {
                    self.restoreIfNeeded()
                }
            }
            .store(in: &cancellables)

        // 初始化所有灯区为蓝色预览
        for zone in LightZone.allIndividual {
            zoneColors[zone] = .blue
        }

        // 读取本地设置
        let snapshot = store.snapshot
        brightness = Double(snapshot.brightness)
        currentColor = snapshot.color.swiftUIColor
        // 旧版本默认次色为纯黑，渐变时会出现“阶段性全暗”，这里做一次迁移
        let storedSecondary = snapshot.secondary.swiftUIColor
        let sec = NSColor(storedSecondary).usingColorSpace(.deviceRGB)
        let isBlack = (sec?.redComponent ?? 0) < 0.06 && (sec?.greenComponent ?? 0) < 0.06 && (sec?.blueComponent ?? 0) < 0.06
        if isBlack {
            secondaryColor = Color(red: 0.0, green: 0.82, blue: 1.0)
        } else {
            secondaryColor = storedSecondary
        }
        currentEffect = LightEffect(code: snapshot.effectCode)
        tempo = Double(snapshot.tempo)
        screenLogoBoost = snapshot.screenLogoBoost
        restoreOnLaunch = snapshot.restoreOnLaunch
        hotkeysEnabled = snapshot.hotkeysEnabled
        launchAtLogin = LaunchAtLogin.isEnabled
        customPresets = snapshot.customPresets

        // 恢复上一次的灯区预览
        let storedZones = snapshot.zones == 0 ? LightZone.all : LightZone(rawValue: snapshot.zones)
        if snapshot.zones != 0 {
            selectedZones = Set(LightZone.allIndividual.filter { snapshot.zones & $0.rawValue != 0 })
        }
        for zone in LightZone.allIndividual where storedZones.contains(zone) {
            zoneColors[zone] = snapshot.color.swiftUIColor
        }
        for (id, rgb) in snapshot.keyColors {
            keyColors[id] = rgb.swiftUIColor
        }

        let tp = snapshot.touchpad
        touchpad = TouchpadOverride(
            padFollowsZone: tp.padFollowsZone,
            padColor: tp.padColor.swiftUIColor,
            padBrightness: Double(tp.padBrightness),
            edgeFollowsZone: tp.edgeFollowsZone,
            edgeColor: tp.edgeColor.swiftUIColor,
            edgeBrightness: Double(tp.edgeBrightness),
            edgeEnabled: tp.edgeEnabled
        )
        let pb = snapshot.powerButton
        powerButton = PowerOverride(
            clickAction: pb.clickAction,
            doubleClickAction: pb.doubleClickAction,
            holdAction: pb.holdAction,
            confirmDangerous: pb.confirmDangerous,
            lightFollowsZone: pb.lightFollowsZone,
            lightColor: pb.lightColor.swiftUIColor,
            lightBrightness: Double(pb.lightBrightness)
        )
        isLoadingSettings = false

        setupHotKeys()
    }

    // MARK: - 快捷键

    private func setupHotKeys() {
        let center = HotKeyCenter.shared
        if hotkeysEnabled && !center.isInstalled {
            center.install()
        }
        center.onAction = { [weak self] action in
            DispatchQueue.main.async {
                guard let self = self, self.hotkeysEnabled else { return }
                switch action {
                case .toggle:   self.toggleLights()
                case .brighter: self.stepBrightness(+10)
                case .dimmer:   self.stepBrightness(-10)
                }
            }
        }
    }

    /// 快捷键 / 菜单栏：开灯关灯切换
    func toggleLights() {
        if isLightsOff {
            let snapshot = lastOnSnapshot ?? currentSnapshot()
            apply(zones: .all, snapshot: snapshot, persist: false)
            isLightsOff = false
            controller.log("快捷键：恢复灯光")
        } else {
            lastOnSnapshot = currentSnapshot()
            turnOffAll()
            controller.log("快捷键：关闭灯光")
        }
    }

    /// 快捷键：增减亮度
    func stepBrightness(_ delta: Double) {
        let value = max(0, min(100, brightness + delta))
        brightness = value
        onBrightnessChanged()
    }

    /// 某个灯区当前生效的预览效果（目前所有灯区跟随全局设置）
    func effect(for zone: LightZone) -> LightEffect {
        currentEffect
    }

    // MARK: - 灯区选择

    /// 切换灯区选中状态
    func toggleZone(_ zone: LightZone) {
        if selectedZones.contains(zone) {
            selectedZones.remove(zone)
        } else {
            selectedZones.insert(zone)
            selectedKeys.removeAll()
        }
    }

    // MARK: - 单键映射

    /// 点选/取消单个按键
    func toggleKey(_ id: String) {
        if selectedKeys.contains(id) {
            selectedKeys.remove(id)
        } else {
            selectedKeys.insert(id)
            selectedZones.removeAll()
            // 选中的按键立刻用当前颜色标记，方便逐个上色
            keyColors[id] = currentColor
            dispatchColors()
            persistState()
        }
    }

    /// 某个按键当前显示的颜色
    func keyDisplayColor(_ id: String) -> Color {
        if let color = keyColors[id] { return color }
        if let zone = KeyboardCatalog.zone(ofKey: id), let color = zoneColors[zone] { return color }
        return currentColor
    }

    /// 触摸板整面背光当前显示的颜色
    func touchpadPadDisplayColor() -> Color {
        touchpad.padFollowsZone ? (zoneColors[.touchpad] ?? currentColor) : touchpad.padColor
    }

    /// 触摸板边光当前显示的颜色
    func touchpadEdgeDisplayColor() -> Color {
        touchpad.edgeFollowsZone ? (zoneColors[.touchpad] ?? currentColor) : touchpad.edgeColor
    }

    /// 电源键灯效当前显示的颜色
    func powerButtonDisplayColor() -> Color {
        powerButton.lightFollowsZone ? (zoneColors[.powerButton] ?? currentColor) : powerButton.lightColor
    }

    /// 某个灯区最终呈现的颜色：区内有单键自定义时取出现最多的颜色，否则用分区颜色
    func zoneDisplayColor(_ zone: LightZone) -> Color {
        if zone == .touchpad { return touchpadPadDisplayColor() }
        if zone == .powerButton { return powerButtonDisplayColor() }
        let keys = KeyboardCatalog.keys(in: zone)
        guard !keys.isEmpty else { return zoneColors[zone] ?? currentColor }
        var hasCustom = false
        var counts: [String: (color: Color, count: Int)] = [:]
        for key in keys {
            let custom = keyColors[key.id]
            if custom != nil { hasCustom = true }
            let resolved = custom ?? zoneColors[zone] ?? currentColor
            let ns = NSColor(resolved).usingColorSpace(.deviceRGB)
            let sig = String(format: "%d-%d-%d",
                             Int(((ns?.redComponent ?? 0) * 255).rounded()),
                             Int(((ns?.greenComponent ?? 0) * 255).rounded()),
                             Int(((ns?.blueComponent ?? 0) * 255).rounded()))
            var entry = counts[sig] ?? (color: resolved, count: 0)
            entry.count += 1
            counts[sig] = entry
        }
        guard hasCustom else { return zoneColors[zone] ?? currentColor }
        return counts.values.max { $0.count < $1.count }?.color ?? (zoneColors[zone] ?? currentColor)
    }

    /// 区内是否有单键自定义颜色
    func hasCustomKeys(in zone: LightZone) -> Bool {
        KeyboardCatalog.keys(in: zone).contains { keyColors[$0.id] != nil }
    }

    /// 只选中触摸板灯区（顶栏「触摸板」按钮用）
    func selectTouchpadOnly() {
        selectedKeys.removeAll()
        selectedZones = [.touchpad]
    }

    /// 选择电源键灯区（顶栏「开机键」按钮用）
    func selectPowerButtonOnly() {
        selectedKeys.removeAll()
        selectedZones = [.powerButton]
    }

    /// 电源键细调恢复默认
    func resetPowerButton() {
        powerButton = .standard
        controller.log("电源键设置已恢复默认")
    }

    /// 执行电源键动作（dangerous 动作按配置二次确认）
    func runPowerAction(_ action: SettingsStore.PowerAction) {
        guard action != .none else { return }
        if action.isDangerous && powerButton.confirmDangerous {
            let alert = NSAlert()
            alert.messageText = action == .restart ? "确定要重新启动这台 Mac 吗？" : "确定要关机吗？"
            alert.informativeText = "这是点按 3D 电源键触发的系统动作，未保存的工作可能丢失。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: action == .restart ? "重新启动" : "关机")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else {
                controller.log("电源键动作已取消：\(action.title)")
                return
            }
        }
        controller.log("电源键动作：\(action.title)")
        switch action {
        case .none:
            break
        case .lightsOff:
            turnOffAll()
        case .lock:
            Self.lockScreen()
        case .sleep:
            Self.runShell("/usr/bin/pmset", ["sleepnow"])
        case .restart:
            Self.runAppleScript("tell application \"System Events\" to restart")
        case .shutdown:
            Self.runAppleScript("tell application \"System Events\" to shut down")
        }
    }

    /// 锁屏（login.framework 的 SACLockScreenImmediate，无需辅助功能授权）
    private static func lockScreen() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
              let symbol = dlsym(handle, "SACLockScreenImmediate") else {
            runShell("/usr/bin/osascript", ["-e", "tell application \"System Events\" to keystroke \"q\" using {control down, command down}"])
            return
        }
        typealias LockFn = @convention(c) () -> Void
        unsafeBitCast(symbol, to: LockFn.self)()
    }

    private static func runShell(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try? process.run()
        process.waitUntilExit()
    }

    private static func runAppleScript(_ source: String) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }

    // MARK: - 逐帧灯效（光谱 / 光波 / 扫描）

    private var softwareTimer: Timer?

    /// 当前效果是否由 App 逐帧算色
    var isSoftwareEffect: Bool {
        switch currentEffect {
        case .spectrum, .wave, .scanner: return true
        default: return false
        }
    }

    /// 某一灯区在动画中的颜色
    func animatedColor(for zone: LightZone, at time: TimeInterval) -> Color? {
        guard isSoftwareEffect, let idx = LightZone.allIndividual.firstIndex(of: zone) else { return nil }
        let count = Double(LightZone.allIndividual.count)
        let i = Double(idx)
        let period = max(0.6, Double(tempo) / 1000.0)
        let phase = (time / period).truncatingRemainder(dividingBy: 1)

        func dim(_ color: Color, _ k: Double) -> Color {
            let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
            return Color(red: Double(ns.redComponent) * k,
                         green: Double(ns.greenComponent) * k,
                         blue: Double(ns.blueComponent) * k)
        }

        switch currentEffect {
        case .spectrum:
            let hue = (i / count + phase).truncatingRemainder(dividingBy: 1)
            return Color(hue: hue, saturation: 1, brightness: 1)
        case .wave:
            let p = (phase + i / count).truncatingRemainder(dividingBy: 1)
            let k = 0.18 + 0.82 * pow(sin(p * Double.pi), 2)
            return dim(currentColor, k)
        case .scanner:
            let head = Int((phase * count).rounded(.down)) % LightZone.allIndividual.count
            let dist = Double(min(abs(idx - head), LightZone.allIndividual.count - abs(idx - head)))
            let k: Double
            switch dist {
            case 0:  k = 1.0
            case 1:  k = 0.42
            default: k = 0.10
            }
            return dim(currentColor, k)
        default:
            return nil
        }
    }

    /// 逐帧灯效的硬件同步：光谱 / 光波 / 扫描靠 App 每 0.12 秒下发一帧
    func syncSoftwareAnimation() {
        if isSoftwareEffect {
            guard softwareTimer == nil else { return }
            softwareTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
                self?.pushSoftwareFrame()
            }
            pushSoftwareFrame()
        } else {
            softwareTimer?.invalidate()
            softwareTimer = nil
        }
    }

    private func pushSoftwareFrame() {
        guard isConnected, isSoftwareEffect, !isLightsOff else { return }
        let zones = selectedZones.isEmpty
            ? LightZone.all
            : selectedZones.reduce(LightZone()) { $0.union($1) }
        let now = CACurrentMediaTime()
        var payload: [(zone: LightZone, color: RGBColor, effect: LightEffect, color2: RGBColor?)] = []
        for zone in LightZone.allIndividual where zones.contains(zone) {
            guard let color = animatedColor(for: zone, at: now) else { continue }
            payload.append((zone: zone, color: RGBColor(color: color), effect: .color, color2: nil))
        }
        controller.setZoneColors(payload)
    }

    /// 触摸板细调恢复默认
    func resetTouchpad() {
        touchpad = .standard
        controller.log("触摸板细调已恢复默认")
    }

    /// 清除选中按键的自定义颜色，回到所属灯区颜色
    func clearKeyCustom() {
        guard !selectedKeys.isEmpty else { return }
        for id in selectedKeys { keyColors.removeValue(forKey: id) }
        dispatchColors()
        persistState()
        controller.log("已清除 \(selectedKeys.count) 个按键的单键配色")
    }

    /// 套用一个预设颜色（AWCC 预设色板）
    func applyPresetColor(_ color: Color) {
        currentColor = color
        if !selectedKeys.isEmpty {
            for id in selectedKeys { keyColors[id] = color }
        }
        liveApply()
        controller.log("预设颜色已应用")
    }

    /// 全选/全不选
    func toggleSelectAll() {
        if selectedZones.count == LightZone.allIndividual.count {
            selectedZones.removeAll()
        } else {
            selectedZones = Set(LightZone.allIndividual)
        }
    }

    /// 选择键盘区域
    func selectKeyboard() {
        selectedZones = [.macroKeys, .keyboardLeft, .keyboardMid, .keyboardRight, .numpad]
    }

    // MARK: - 应用设置

    /// 将当前颜色/效果应用到选中灯区
    func applyToSelected() {
        guard !selectedZones.isEmpty else { return }

        let zones = selectedZones.reduce(LightZone()) { $0.union($1) }
        apply(zones: zones, snapshot: currentSnapshot(), persist: true)
        isLightsOff = false
    }

    // MARK: - 实时应用（调色/调亮度即改即生效）

    private var liveWorkItem: DispatchWorkItem?
    private var lastLiveApply = Date.distantPast

    /// 颜色 / 效果 / 速度 改动后立即下发：首帧立刻生效，后续约 100ms 合并一次
    func liveApply() {
        if isMarqueeActive { stopMarquee() }
        let elapsed = Date().timeIntervalSince(lastLiveApply)
        if elapsed >= 0.1 {
            lastLiveApply = Date()
            performLiveApply()
            return
        }
        liveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, self.isConnected else { return }
            self.lastLiveApply = Date()
            self.performLiveApply()
        }
        liveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (0.1 - elapsed), execute: item)
    }

    /// 真正下发一次当前配置：选中按键时给按键上色，否则按灯区生效
    private func performLiveApply() {
        guard isConnected else { return }
        if !selectedKeys.isEmpty {
            for id in selectedKeys { keyColors[id] = currentColor }
        }
        dispatchColors()
        persistState()
        syncSoftwareAnimation()
    }

    /// 按“每个灯区最终呈现的颜色”分组下发：单键自定义会改变所在分区的实际颜色
    private func dispatchColors() {
        guard isConnected else { return }
        var zones = selectedZones.reduce(LightZone()) { $0.union($1) }
        for id in keyColors.keys {
            if let zone = KeyboardCatalog.zone(ofKey: id) { zones.insert(zone) }
        }
        if zones.rawValue == 0 { zones = .all }

        var groups: [String: (color: RGBColor, zones: LightZone)] = [:]
        for zone in LightZone.allIndividual where zones.contains(zone) {
            let color = RGBColor(color: zoneDisplayColor(zone))
            let sig = "\(color.r)-\(color.g)-\(color.b)"
            if var group = groups[sig] {
                group.zones.insert(zone)
                groups[sig] = group
            } else {
                groups[sig] = (color, zone)
            }
        }
        let previousColors = zoneColors
        for group in groups.values {
            var snapshot = currentSnapshot()
            snapshot.primary = group.color
            apply(zones: group.zones, snapshot: snapshot, persist: false)
        }
        if selectedZones.isEmpty && selectedKeys.isEmpty {
            // 什么都不选：调色作用于全部灯区，基准色沿用 apply() 的结果
        } else {
            // 只选了灯区 / 只选了按键时，apply() 写入的是推导色，必须还原基准色：
            // 单键自定义只覆盖那个键，不能把同区其他键或其它灯区一起染色
            zoneColors = previousColors
            for zone in LightZone.allIndividual where selectedZones.contains(zone) {
                zoneColors[zone] = currentColor
            }
        }
        isLightsOff = false
    }

    /// 把颜色、效果、单键映射一起落盘（SettingsStore 自带防抖）
    private func persistState() {
        var s = store.snapshot
        s.color = RGBColor(color: currentColor)
        s.secondary = RGBColor(color: secondaryColor)
        s.effectCode = currentEffect.code
        s.tempo = UInt16(tempo)
        s.zones = selectedZones.isEmpty ? 0 : selectedZones.reduce(LightZone()) { $0.union($1) }.rawValue
        s.keyColors = keyColors.mapValues { RGBColor(color: $0) }
        s.touchpad = SettingsStore.TouchpadConfig(
            padFollowsZone: touchpad.padFollowsZone,
            padColor: RGBColor(color: touchpad.padColor),
            padBrightness: Int(touchpad.padBrightness.rounded()),
            edgeFollowsZone: touchpad.edgeFollowsZone,
            edgeColor: RGBColor(color: touchpad.edgeColor),
            edgeBrightness: Int(touchpad.edgeBrightness.rounded()),
            edgeEnabled: touchpad.edgeEnabled
        )
        s.powerButton = SettingsStore.PowerButtonConfig(
            clickAction: powerButton.clickAction,
            doubleClickAction: powerButton.doubleClickAction,
            holdAction: powerButton.holdAction,
            confirmDangerous: powerButton.confirmDangerous,
            lightFollowsZone: powerButton.lightFollowsZone,
            lightColor: RGBColor(color: powerButton.lightColor),
            lightBrightness: Int(powerButton.lightBrightness.rounded())
        )
        store.snapshot = s
    }

    /// 应用到所有灯区
    func applyToAll(tempo: UInt16? = nil) {
        var snapshot = currentSnapshot()
        if let tempo = tempo { snapshot.tempo = tempo }
        keyColors.removeAll()
        selectedKeys.removeAll()
        apply(zones: .all, snapshot: snapshot, persist: true)
        persistState()
        isLightsOff = false
        syncSoftwareAnimation()
    }

    /// 关闭所有灯光
    func turnOffAll() {
        lastOnSnapshot = currentSnapshot()
        let off = ZoneSnapshot(primary: .off, secondary: .off, effectCode: LightEffect.color.code, tempo: UInt16(tempo))
        apply(zones: .all, snapshot: off, persist: false)
        isLightsOff = true
    }

    /// 当前 UI 状态转快照
    private func currentSnapshot() -> ZoneSnapshot {
        ZoneSnapshot(
            primary: RGBColor(color: currentColor),
            secondary: RGBColor(color: secondaryColor),
            effectCode: currentEffect.code,
            tempo: UInt16(tempo)
        )
    }

    /// 统一应用入口：普通灯区、屏幕 Logo（亮度补偿）、电源按钮（独立状态块）
    private func apply(zones: LightZone, snapshot: ZoneSnapshot, persist: Bool) {
        guard zones.rawValue != 0 else { return }

        let secondary = snapshot.effect.needsSecondaryColor ? snapshot.secondary : nil
        // 装饰灯区（Logo 光环 / 双眼）只影响 3D 预览，不下发到硬件
        let hardware = zones.intersection(LightZone.hardwareZones)
        guard hardware.rawValue != 0 else { return }

        // 关闭时不必做亮度补偿
        let isOff = snapshot.primary == .off
        var normalZones = hardware.subtracting(.powerButton).subtracting(.screenLogo)
        if isOff { normalZones = hardware }

        // 1. 普通灯区
        if normalZones.rawValue != 0 {
            controller.setZones(normalZones, color: snapshot.primary, effect: snapshot.effect,
                                color2: secondary, tempo: snapshot.tempo)
        }

        if !isOff {
            // 2. 屏幕 Logo（导光条偏暗，按系数补偿）
            if hardware.contains(.screenLogo) {
                let boosted = boostColor(snapshot.primary, factor: screenLogoBoost)
                let boosted2 = secondary != nil ? boostColor(secondary!, factor: screenLogoBoost) : nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.controller.setZone(.screenLogo, color: boosted, effect: snapshot.effect,
                                             color2: boosted2, tempo: snapshot.tempo)
                }
            }

            // 3. 电源按钮（遍历所有电源状态块）
            if hardware.contains(.powerButton) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.controller.setPowerButton(color: snapshot.primary, effect: snapshot.effect,
                                                    color2: secondary, tempo: snapshot.tempo)
                }
            }
        }

        // 更新 UI 预览
        for zone in LightZone.allIndividual where zones.contains(zone) {
            zoneColors[zone] = snapshot.primary.swiftUIColor
        }

        if persist {
            var s = store.snapshot
            s.zones = (zones == .all) ? 0 : zones.rawValue
            s.color = snapshot.primary
            s.secondary = snapshot.secondary
            s.effectCode = snapshot.effect.code
            s.tempo = snapshot.tempo
            store.snapshot = s
        }
    }

    // MARK: - 启动恢复

    private func restoreIfNeeded() {
        guard !didRestore else { return }
        didRestore = true

        if restoreOnLaunch {
            let snapshot = store.snapshot
            let zones = snapshot.zones == 0 ? LightZone.all : LightZone(rawValue: snapshot.zones)
            let restored = ZoneSnapshot(
                primary: snapshot.color,
                secondary: snapshot.secondary,
                effectCode: snapshot.effectCode,
                tempo: snapshot.tempo
            )
            apply(zones: zones, snapshot: restored, persist: false)
            controller.log("启动恢复：已应用上次灯光配置")
        }

        let value = Int(brightness)
        if value > 0 { controller.setBrightness(value) }
    }

    // MARK: - 颜色工具

    /// 亮度补偿：将颜色RGB值乘以系数，上限255
    private func boostColor(_ color: RGBColor, factor: Double) -> RGBColor {
        RGBColor(
            r: UInt8(min(255, Int(Double(color.r) * factor))),
            g: UInt8(min(255, Int(Double(color.g) * factor))),
            b: UInt8(min(255, Int(Double(color.b) * factor)))
        )
    }

    // MARK: - 亮度

    /// 亮度变化时实时应用并保存
    func onBrightnessChanged() {
        controller.setBrightness(Int(brightness))
        store.snapshot.brightness = Int(brightness)
        if brightness > 0 { isLightsOff = false }
    }

    // MARK: - 内置预设

    /// 应用预设主题
    func applyPreset(_ preset: LightingPreset) {
        stopMarquee()
        stopZoneTest()
        if preset == .marquee {
            startMarquee()
            return
        }
        currentColor = preset.primaryColor
        currentEffect = preset.effect
        secondaryColor = preset.secondaryColor
        applyToAll(tempo: preset.tempo)
    }

    // MARK: - 自定义预设

    /// 将当前配置存为预设
    @discardableResult
    func saveCurrentAsPreset(name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let zones = selectedZones.isEmpty ? LightZone.all : selectedZones.reduce(LightZone()) { $0.union($1) }
        let preset = CustomPreset.make(
            name: trimmed,
            zones: zones,
            primary: RGBColor(color: currentColor),
            secondary: RGBColor(color: secondaryColor),
            effect: currentEffect,
            tempo: UInt16(tempo)
        )

        store.addPreset(preset)
        customPresets = store.snapshot.customPresets
        controller.log("已保存预设「\(trimmed)」")
        return true
    }

    /// 应用自定义预设
    func applyCustomPreset(_ preset: CustomPreset) {
        stopMarquee()
        stopZoneTest()

        currentColor = preset.snapshot.primary.swiftUIColor
        secondaryColor = preset.snapshot.secondary.swiftUIColor
        currentEffect = preset.snapshot.effect
        tempo = Double(preset.snapshot.tempo)

        keyColors.removeAll()
        selectedKeys.removeAll()
        let zones = preset.zonesRaw == 0 ? LightZone.all : LightZone(rawValue: preset.zonesRaw)
        apply(zones: zones, snapshot: preset.snapshot, persist: true)
        persistState()
        isLightsOff = false
        controller.log("已应用预设「\(preset.name)」")
    }

    /// 删除自定义预设
    func deleteCustomPreset(_ preset: CustomPreset) {
        store.removePreset(id: preset.id)
        customPresets = store.snapshot.customPresets
        controller.log("已删除预设「\(preset.name)」")
    }

    /// 重命名自定义预设
    func renameCustomPreset(_ preset: CustomPreset, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.renamePreset(id: preset.id, to: trimmed)
        customPresets = store.snapshot.customPresets
    }

    // MARK: - 保存与重置

    /// 保存为开机默认（写入设备闪存）
    func saveAsDefault() {
        controller.log("把当前设置写入设备闪存")
        controller.saveAsDefault()
    }

    /// 重置控制器
    func resetController() {
        controller.reset()
        isLightsOff = false
    }

    /// 重新扫描设备
    func rescan() {
        controller.rescan()
    }

    /// 应用退出前落盘
    func persistBeforeExit() {
        store.saveNow()
    }

    // MARK: - 逐灯测试

    /// 开始逐灯测试：依次点亮 bit 0-15，每个 2 秒，帮助确认灯区映射
    func startZoneTest() {
        guard !isTestingZones else { return }
        isTestingZones = true
        currentTestBit = -1

        var bit = 0
        testTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if bit >= 16 {
                self.stopZoneTest()
                return
            }
            self.currentTestBit = bit
            let zone = LightZone(rawValue: UInt32(1) << bit)
            let name = zone.displayName
            self.controller.log("测试 bit \(bit) (0x\(String(format: "%02X", 1 << bit))): \(name)")
            // 先全灭，再点亮当前测试位
            self.controller.setAllZones(color: .off, effect: .color)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.controller.setZones(zone, color: .red, effect: .color)
            }
            bit += 1
        }
        testTimer?.fire()
    }

    /// 停止逐灯测试
    func stopZoneTest() {
        testTimer?.invalidate()
        testTimer = nil
        isTestingZones = false
        currentTestBit = -1
        controller.setAllZones(color: .off, effect: .color)
    }

    // MARK: - 跑马灯动画

    /// 启动跑马灯：彩虹色在各灯区间循环流动
    func startMarquee() {
        guard !isMarqueeActive else { return }
        isMarqueeActive = true
        marqueeOffset = 0
        controller.log("跑马灯已启动")
        marqueeTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.updateMarquee()
        }
        marqueeTimer?.fire()
    }

    /// 停止跑马灯
    func stopMarquee() {
        marqueeTimer?.invalidate()
        marqueeTimer = nil
        if isMarqueeActive {
            isMarqueeActive = false
            controller.log("跑马灯已停止")
        }
    }

    /// 更新跑马灯一帧
    private func updateMarquee() {
        var zoneColors: [(zone: LightZone, color: RGBColor, effect: LightEffect, color2: RGBColor?)] = []
        for (index, zone) in marqueeZoneOrder.enumerated() {
            let color = marqueeColors[(index + marqueeOffset) % marqueeColors.count]
            zoneColors.append((zone: zone, color: RGBColor(color: color), effect: .color, color2: nil))
        }
        controller.setZoneColors(zoneColors)
        // 更新 UI 预览
        for (index, zone) in marqueeZoneOrder.enumerated() {
            self.zoneColors[zone] = marqueeColors[(index + marqueeOffset) % marqueeColors.count]
        }
        marqueeOffset += 1
    }
}

// MARK: - 预设主题

enum LightingPreset: String, CaseIterable, Identifiable {
    case alienBlue   = "外星人蓝"
    case cyberRed    = "赛博红"
    case matrixGreen = "矩阵绿"
    case aurora      = "极光渐变"
    case warmOrange  = "暖橙"
    case purpleHaze  = "紫雾"
    case white       = "纯白"
    case rainbow     = "彩虹脉冲"
    case marquee     = "跑马灯"
    case colorFlow   = "色彩渐变"
    // AWCC 对齐主题
    case awccBlue     = "AWCC 蓝"
    case awccRed      = "AWCC 红"
    case awccSpectrum = "AWCC 光谱"
    case awccWave     = "AWCC 单色波"
    case awccScanner  = "AWCC 扫描"
    case awccPulse    = "AWCC 紫脉冲"
    case awccBreath   = "AWCC 熔岩呼吸"
    case awccMorph    = "AWCC 青洋渐变"

    var id: String { rawValue }

    var primaryColor: Color {
        switch self {
        case .alienBlue:   return Color(red: 0, green: 0.5, blue: 1)
        case .cyberRed:    return .red
        case .matrixGreen: return Color(red: 0, green: 1, blue: 0.2)
        case .aurora:      return Color(red: 0, green: 1, blue: 0.8)
        case .warmOrange:  return .orange
        case .purpleHaze:  return Color(red: 0.5, green: 0, blue: 1)
        case .white:       return .white
        case .rainbow:     return .red
        case .marquee:     return .red
        case .colorFlow:   return .red
        case .awccBlue:     return Color(red: 0.0, green: 0.68, blue: 0.94)
        case .awccRed:      return Color(red: 0.89, green: 0.12, blue: 0.14)
        case .awccSpectrum: return .red
        case .awccWave:     return Color(red: 0.0, green: 0.82, blue: 1)
        case .awccScanner:  return Color(red: 0.1, green: 1, blue: 0.25)
        case .awccPulse:    return Color(red: 0.55, green: 0.0, blue: 1)
        case .awccBreath:   return Color(red: 1, green: 0.42, blue: 0)
        case .awccMorph:    return Color(red: 0.0, green: 0.85, blue: 1)
        }
    }

    var secondaryColor: Color {
        switch self {
        case .aurora:     return Color(red: 0.5, green: 0, blue: 1)
        case .colorFlow:  return Color(red: 0, green: 1, blue: 0.8)
        case .awccBreath: return Color(red: 0.85, green: 0.05, blue: 0.05)
        case .awccMorph:  return Color(red: 1, green: 0.15, blue: 0.7)
        default:          return .black
        }
    }

    var effect: LightEffect {
        switch self {
        case .aurora, .colorFlow, .awccMorph: return .morph
        case .rainbow, .awccPulse:            return .pulse
        case .awccBreath:                     return .breathing
        case .awccSpectrum:                   return .spectrum
        case .awccWave:                       return .wave
        case .awccScanner:                    return .scanner
        default:                              return .color
        }
    }

    /// 渐变速度（毫秒），值越大越慢越丝滑
    var tempo: UInt16 {
        switch self {
        case .aurora:     return 2500
        case .colorFlow:  return 5000
        case .awccBreath: return 3000
        case .awccMorph:  return 4000
        case .awccPulse:  return 1200
        case .awccSpectrum: return 3000
        case .awccWave:     return 2500
        case .awccScanner:  return 2000
        default:            return 2000
        }
    }
}
