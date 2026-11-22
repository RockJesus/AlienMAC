//
//  HomeAssistantBridge.swift
//  AlienMAC
//
//  接入 Home Assistant（MQTT Discovery）：把键盘灯与整机灯作为两盏带 RGB 与灯效的灯发布到 HA，
//  并订阅 HA 下发的开关 / 亮度 / 颜色 / 灯效命令。配合 HA 的 Mosquitto broker 加载项使用。
//

import Foundation
import Combine
import SwiftUI
import AppKit

final class HomeAssistantBridge: ObservableObject {
    static let shared = HomeAssistantBridge()

    // MARK: - 配置（持久化）

    /// 初始化期间不要触发 didSet 里的落盘/连接，否则会先按空值覆盖已有配置
    private var isLoading = true

    @Published var enabled: Bool = false {
        didSet { guard !isLoading else { return }; persist(); enabled ? start() : stop() }
    }
    @Published var host: String = "" { didSet { guard !isLoading else { return }; persist() } }
    @Published var port: String = "1883" { didSet { guard !isLoading else { return }; persist() } }
    @Published var username: String = "" { didSet { guard !isLoading else { return }; persist() } }
    @Published var password: String = "" { didSet { guard !isLoading else { return }; persist() } }
    @Published var topicPrefix: String = "alienmac" { didSet { guard !isLoading else { return }; persist() } }

    // MARK: - 状态

    @Published private(set) var status: String = "未启用"
    @Published private(set) var lastCommandText: String = ""
    @Published private(set) var connected: Bool = false

    // MARK: - 内部

    private let client = MQTTClient()
    private var stateTimer: Timer?
    private var lastSignature = ""

    private init() {
        let defaults = UserDefaults.standard
        enabled = defaults.bool(forKey: "AlienMAC.haEnabled")
        host = defaults.string(forKey: "AlienMAC.haHost") ?? ""
        port = defaults.string(forKey: "AlienMAC.haPort") ?? "1883"
        username = defaults.string(forKey: "AlienMAC.haUser") ?? ""
        password = defaults.string(forKey: "AlienMAC.haPass") ?? ""
        topicPrefix = defaults.string(forKey: "AlienMAC.haPrefix") ?? "alienmac"
        isLoading = false
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(enabled, forKey: "AlienMAC.haEnabled")
        defaults.set(host, forKey: "AlienMAC.haHost")
        defaults.set(port, forKey: "AlienMAC.haPort")
        defaults.set(username, forKey: "AlienMAC.haUser")
        defaults.set(password, forKey: "AlienMAC.haPass")
        defaults.set(topicPrefix, forKey: "AlienMAC.haPrefix")
    }

    // MARK: - 话题

    private var prefix: String {
        let raw = topicPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "alienmac" : raw
    }
    private var availabilityTopic: String { "\(prefix)/availability" }
    private var keyboardStateTopic: String { "\(prefix)/keyboard/state" }
    private var keyboardCommandTopic: String { "\(prefix)/keyboard/set" }
    private var chassisStateTopic: String { "\(prefix)/chassis/state" }
    private var chassisCommandTopic: String { "\(prefix)/chassis/set" }
    private var keyboardConfigTopic: String { "homeassistant/light/\(prefix)_keyboard/config" }
    private var chassisConfigTopic: String { "homeassistant/light/\(prefix)_chassis/config" }

    /// App 启动时调用：已启用就直接连
    private static var didBootstrap = false

    func bootstrap() {
        guard !Self.didBootstrap else { return }
        Self.didBootstrap = true
        if enabled { start() }
    }

    /// 设置页「重连」按钮
    func reconnect() {
        guard enabled else { return }
        client.disconnect()
        start()
    }

    // MARK: - 启停

    private func start() {
        guard enabled else { return }
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty else {
            status = "请填写 Home Assistant 的 MQTT 主机地址"
            return
        }
        let p = UInt16(port.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1883
        status = "正在连接 \(h):\(p)…"

        client.onConnected = { [weak self] in self?.handleConnected() }
        client.onDisconnected = { [weak self] in self?.handleDisconnected() }
        client.onMessage = { [weak self] topic, payload in
            self?.handleMessage(topic: topic, payload: payload)
        }

        let cfg = MQTTClient.Config(
            host: h,
            port: p,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            clientID: "alienmac-\(UUID().uuidString.prefix(8))",
            willTopic: availabilityTopic,
            willPayload: "offline"
        )
        client.connect(cfg)
    }

    private func stop() {
        stateTimer?.invalidate(); stateTimer = nil
        lastSignature = ""
        connected = false
        if client.isConnected {
            client.publish(topic: availabilityTopic, payload: "offline", retain: true)
        }
        client.disconnect()
        status = "未启用"
    }

    private func handleConnected() {
        connected = true
        NSLog("HA_MQTT_CONNECTED")
        status = "已连接 · 已发布 2 个灯实体"
        client.publish(topic: availabilityTopic, payload: "online", retain: true)
        publishDiscovery()
        client.subscribe(keyboardCommandTopic)
        client.subscribe(chassisCommandTopic)
        startStateTimer()
    }

    private func handleDisconnected() {
        connected = false
        NSLog("HA_MQTT_DISCONNECTED")
        status = "连接断开，正在自动重连…"
        stateTimer?.invalidate(); stateTimer = nil
    }

    // MARK: - Discovery

    private func publishDiscovery() {
        let device: [String: Any] = [
            "identifiers": ["alienmac"],
            "name": "AlienMAC",
            "manufacturer": "RockJesus",
            "model": "Alienware 17 R4"
        ]

        let keyboard: [String: Any] = [
            "name": "AlienMAC 键盘灯",
            "unique_id": "\(prefix)_keyboard",
            "schema": "json",
            "command_topic": keyboardCommandTopic,
            "state_topic": keyboardStateTopic,
            "availability_topic": availabilityTopic,
            "payload_available": "online",
            "payload_not_available": "offline",
            "supported_color_modes": ["rgb"],
            "brightness": true,
            "effect": true,
            "effect_list": LightEffect.allCases.map { $0.rawValue },
            "device": device
        ]

        let chassis: [String: Any] = [
            "name": "AlienMAC 整机灯",
            "unique_id": "\(prefix)_chassis",
            "schema": "json",
            "command_topic": chassisCommandTopic,
            "state_topic": chassisStateTopic,
            "availability_topic": availabilityTopic,
            "payload_available": "online",
            "payload_not_available": "offline",
            "supported_color_modes": ["rgb"],
            "brightness": true,
            "effect": true,
            "effect_list": LightEffect.allCases.map { $0.rawValue },
            "device": device
        ]

        if let payload = encode(keyboard) {
            client.publish(topic: keyboardConfigTopic, payload: payload, retain: true)
        }
        if let payload = encode(chassis) {
            client.publish(topic: chassisConfigTopic, payload: payload, retain: true)
        }
    }

    // MARK: - 状态上报

    private func startStateTimer() {
        stateTimer?.invalidate()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.publishStateIfChanged()
        }
        RunLoop.main.add(timer, forMode: .common)
        stateTimer = timer
        publishStateIfChanged(force: true)
    }

    private func publishStateIfChanged(force: Bool = false) {
        let vm = LightingViewModel.shared
        let allOn = !vm.isLightsOff
        let keyboardOn = allOn && zoneLit(.keyboardMid)
        let (r, g, b) = rgbComponents(of: vm.currentColor)
        let brightness = Int((vm.brightness / 100.0 * 255).rounded())
        let effect = vm.currentEffect.rawValue

        let signature = "\(keyboardOn)-\(allOn)-\(brightness)-\(r),\(g),\(b)-\(effect)"
        guard force || signature != lastSignature else { return }
        lastSignature = signature

        var keyboardPayload: [String: Any] = [
            "state": keyboardOn ? "ON" : "OFF",
            "brightness": brightness,
            "color_mode": "rgb",
            "color": ["r": r, "g": g, "b": b],
            "effect": effect
        ]
        var chassisPayload = keyboardPayload
        chassisPayload["state"] = allOn ? "ON" : "OFF"
        keyboardPayload["state"] = keyboardOn ? "ON" : "OFF"

        if let p = encode(keyboardPayload) { client.publish(topic: keyboardStateTopic, payload: p, retain: true) }
        if let p = encode(chassisPayload) { client.publish(topic: chassisStateTopic, payload: p, retain: true) }
    }

    // MARK: - 命令处理

    private func handleMessage(topic: String, payload: String) {
        if payload.trimmingCharacters(in: .whitespacesAndNewlines) == "OFFLINE" { return }
        NSLog("HA_COMMAND %@ %@", topic, payload)

        let vm = LightingViewModel.shared
        let isKeyboard = topic.hasSuffix("keyboard/set")
        var desiredOn: Bool? = nil
        var desiredBrightness: Double? = nil
        var desiredColor: Color? = nil
        var desiredEffect: LightEffect? = nil

        if let data = payload.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let state = object["state"] as? String {
                desiredOn = state.uppercased() == "ON"
            }
            if let number = object["brightness"] as? NSNumber {
                desiredBrightness = Double(max(0, min(255, number.intValue))) / 2.55
            }
            if let color = object["color"] as? [String: Any] {
                let r = (color["r"] as? NSNumber).map { Double($0.intValue) / 255 } ?? 0
                let g = (color["g"] as? NSNumber).map { Double($0.intValue) / 255 } ?? 0
                let b = (color["b"] as? NSNumber).map { Double($0.intValue) / 255 } ?? 0
                desiredColor = Color(red: r, green: g, blue: b)
            }
            if let effect = object["effect"] as? String, let parsed = LightEffect(rawValue: effect) {
                desiredEffect = parsed
            }
        }

        if let color = desiredColor { vm.currentColor = color }
        if let effect = desiredEffect { vm.currentEffect = effect }
        if let brightness = desiredBrightness {
            vm.brightness = brightness
            vm.onBrightnessChanged()
        }

        if let on = desiredOn {
            if isKeyboard {
                if on { vm.applyCurrentToKeyboard() } else { vm.setKeyboardLights(on: false) }
            } else {
                if on { vm.applyToAll() } else { vm.perform(.allOff) }
            }
        } else if desiredColor != nil || desiredEffect != nil {
            // 只调色不开关：按当前状态把新颜色推下去
            if isKeyboard { vm.applyCurrentToKeyboard() } else { vm.applyToAll() }
        }

        lastCommandText = "\(topic.hasSuffix("keyboard/set") ? "键盘" : "整机") · \(payload)"
        publishStateIfChanged(force: true)
    }

    // MARK: - 工具

    private func encode(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    private func zoneLit(_ zone: LightZone) -> Bool {
        let vm = LightingViewModel.shared
        guard let color = vm.zoneColors[zone],
              let ns = NSColor(color).usingColorSpace(.sRGB) else { return false }
        return ns.redComponent + ns.greenComponent + ns.blueComponent > 0.08
    }

    private func rgbComponents(of color: Color) -> (Int, Int, Int) {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return (0, 0, 0) }
        return (Int((ns.redComponent * 255).rounded()),
                Int((ns.greenComponent * 255).rounded()),
                Int((ns.blueComponent * 255).rounded()))
    }
}
