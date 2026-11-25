//
//  MacroRunner.swift
//  AlienMAC
//
//  宏键动作执行器（TactX）
//

import AppKit
import Foundation

enum MacroRunner {
    static func run(_ binding: MacroBinding) {
        switch binding.action {
        case .none:
            return
        case .launchApp:
            launchApp(named: binding.target)
        case .openURL:
            open(binding.target)
        case .runScript:
            runScript(binding.target)
        case .system:
            perform(binding.systemAction)
        }
        NSLog("AlienMAC 宏键 \(MacroBinding.slotTitle(binding.slot)) 执行：\(binding.summary)")
    }

    private static func launchApp(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if trimmed.contains("/") {
            NSWorkspace.shared.open(URL(fileURLWithPath: trimmed))
            return
        }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed)
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple." + trimmed)
        if let url {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            // 兜底：按应用名走 open -a
            runProcess("/usr/bin/open", ["-a", trimmed])
        }
    }

    private static func open(_ target: String) {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let url = URL(string: trimmed), url.scheme != nil {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath))
        }
    }

    private static func runScript(_ path: String) {
        let expanded = (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard FileManager.default.isExecutableFile(atPath: expanded) else {
            NSLog("AlienMAC 宏键脚本不可执行：\(expanded)")
            return
        }
        runProcess(expanded, [])
    }

    private static func perform(_ action: MacroSystemAction) {
        switch action {
        case .lock:
            runProcess("/usr/bin/pmset", ["displaysleepnow"])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let task = Process()
                task.launchPath = "/usr/bin/osascript"
                task.arguments = ["-e", "tell application \"System Events\" to keystroke \"q\" using {command down, control down}"]
                try? task.run()
            }
        case .sleep:
            runProcess("/usr/bin/pmset", ["sleepnow"])
        case .lightsOff:
            LightingViewModel.shared.turnOffAll()
        case .lightsOn:
            if LightingViewModel.shared.isLightsOff { LightingViewModel.shared.toggleLights() }
        case .muteToggle:
            runProcess("/usr/bin/osascript", ["-e", "set volume output muted not (output muted of (get volume settings))"])
        }
    }

    private static func runProcess(_ path: String, _ args: [String]) {
        let task = Process()
        task.launchPath = path
        task.arguments = args
        do { try task.run() } catch { NSLog("AlienMAC 宏键执行失败：\(error.localizedDescription)") }
    }
}
