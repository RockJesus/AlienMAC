//
//  TriggerEngine.swift
//  AlienMAC
//
//  触发器管线：监听应用切换 / 电源状态 / 锁屏解锁 / 每日定时，命中即执行灯光动作
//

import AppKit
import Foundation

final class TriggerEngine {
    static let shared = TriggerEngine()

    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var lastPowerIsAC: Bool?
    private var firedDailyToday: Set<String> = []
    private var lastFiredDate: Date = .distantPast
    private var started = false

    private init() {}

    /// 规则直接读写设置，界面改动即时生效
    var rules: [TriggerRule] {
        get { SettingsStore.shared.snapshot.triggers }
        set {
            var s = SettingsStore.shared.snapshot
            s.triggers = newValue
            SettingsStore.shared.snapshot = s
        }
    }

    func start() {
        guard !started else { return }
        started = true

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                           object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.handleAppActivation(bundleID: app.bundleIdentifier ?? "", name: app.localizedName ?? "")
        })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification,
                                           object: nil, queue: .main) { [weak self] _ in
            self?.fire(source: .lock)
        })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification,
                                           object: nil, queue: .main) { [weak self] _ in
            self?.fire(source: .unlock)
        })
        observers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                           object: nil, queue: .main) { [weak self] _ in
            self?.fire(source: .lock)
        })

        // 电源状态与定时：20 秒一轮，够用且开销可忽略
        lastPowerIsAC = TriggerEngine.isOnACPower()
        let t = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.pollPower()
            self?.pollClock()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        NSLog("AlienMAC 触发器已启动，共 \(rules.filter { $0.enabled }.count) 条启用")
    }

    // MARK: - 触发源

    private func handleAppActivation(bundleID: String, name: String) {
        fire(source: .app, bundleID: bundleID)
    }

    private func pollPower() {
        guard let isAC = TriggerEngine.isOnACPower() else { return }
        defer { lastPowerIsAC = isAC }
        guard let previous = lastPowerIsAC, previous != isAC else { return }
        fire(source: isAC ? .powerAC : .powerBattery)
    }

    private func pollClock() {
        let now = Date()
        guard now.timeIntervalSince(lastFiredDate) >= 10 else { return }
        lastFiredDate = now

        let comps = Calendar.current.dateComponents([.hour, .minute, .day], from: now)
        let minute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let dayKey = "\(comps.day ?? 0)-\(minute)"

        for rule in rules where rule.enabled && rule.source == .daily && rule.minuteOfDay == minute {
            guard !firedDailyToday.contains(dayKey + (rule.id.uuidString)) else { continue }
            firedDailyToday.insert(dayKey + (rule.id.uuidString))
            perform(rule)
            NSLog("触发器命中：\(rule.summary)")
        }
        if firedDailyToday.count > 200 { firedDailyToday.removeAll() }
    }

    /// 通用命中入口：应用类需要匹配 Bundle ID，其余按触发源匹配
    private func fire(source: TriggerSource, bundleID: String? = nil) {
        for rule in rules where rule.enabled && rule.source == source {
            if source == .app {
                guard let bundleID, rule.appBundleID == bundleID else { continue }
            }
            perform(rule)
            NSLog("触发器命中：\(rule.summary)")
        }
    }

    private func perform(_ rule: TriggerRule) {
        let vm = LightingViewModel.shared
        switch rule.action {
        case .lightsOff:
            vm.turnOffAll()
        case .lightsOn:
            if vm.isLightsOff { vm.toggleLights() }
        case .preset:
            guard let id = rule.presetID,
                  let preset = vm.customPresets.first(where: { $0.id == id }) else {
                NSLog("触发器「\(rule.name)」指向的预设已不存在")
                return
            }
            vm.applyCustomPreset(preset)
        }
    }

    // MARK: - 电源状态

    private static func isOnACPower() -> Bool? {
        let task = Process()
        task.launchPath = "/usr/bin/pmset"
        task.arguments = ["-g", "batt"]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
        } catch {
            return nil
        }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        if text.contains("AC Power") { return true }
        if text.contains("Battery Power") { return false }
        return nil
    }
}
