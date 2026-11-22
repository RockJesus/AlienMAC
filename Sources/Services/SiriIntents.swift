//
//  SiriIntents.swift
//  AlienMAC
//
//  App Intents：让 Siri / 快捷指令 / 聚焦直接控制灯光。
//  「嘿 Siri，用 AlienMAC 关闭键盘灯」即可。
//

import AppIntents
import Foundation

/// 意图执行桥：等设备连上后调用主视图模型
enum LightActionBridge {
    @MainActor
    static func run(_ action: ScheduleAction) async -> Bool {
        let vm = LightingViewModel.shared
        // 冷启动时 HID 需要一点时间枚举设备，最多等 3 秒
        var waited = 0
        while !vm.isConnected && waited < 10 {
            try? await Task.sleep(nanoseconds: 300_000_000)
            waited += 1
        }
        guard vm.isConnected else { return false }
        vm.perform(action)
        return true
    }
}

// MARK: - 关闭键盘灯

struct TurnOffKeyboardLightIntent: AppIntent {
    static var title: LocalizedStringResource = "关闭键盘灯"
    static var description = IntentDescription("关闭 Alienware 键盘区域背光，其他灯区保持不变。")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ok = await LightActionBridge.run(.keyboardOff)
        return .result(dialog: ok ? IntentDialog("已关闭键盘灯") : IntentDialog("没连上 Alienware 灯控设备"))
    }
}

// MARK: - 打开键盘灯

struct TurnOnKeyboardLightIntent: AppIntent {
    static var title: LocalizedStringResource = "打开键盘灯"
    static var description = IntentDescription("重新点亮 Alienware 键盘区域背光。")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ok = await LightActionBridge.run(.keyboardOn)
        return .result(dialog: ok ? IntentDialog("已打开键盘灯") : IntentDialog("没连上 Alienware 灯控设备"))
    }
}

// MARK: - 全部关闭

struct TurnOffAllLightsIntent: AppIntent {
    static var title: LocalizedStringResource = "关闭全部灯光"
    static var description = IntentDescription("关闭机身所有灯区。")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ok = await LightActionBridge.run(.allOff)
        return .result(dialog: ok ? IntentDialog("全部灯光已关闭") : IntentDialog("没连上 Alienware 灯控设备"))
    }
}

// MARK: - 全部打开

struct TurnOnAllLightsIntent: AppIntent {
    static var title: LocalizedStringResource = "打开全部灯光"
    static var description = IntentDescription("恢复机身所有灯区的上次配置。")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ok = await LightActionBridge.run(.allOn)
        return .result(dialog: ok ? IntentDialog("全部灯光已打开") : IntentDialog("没连上 Alienware 灯控设备"))
    }
}

// MARK: - Siri 短语

struct AlienMACShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TurnOffKeyboardLightIntent(),
                    phrases: ["用 \(.applicationName) 关闭键盘灯",
                              "\(.applicationName) 关掉键盘灯"],
                    shortTitle: "关闭键盘灯",
                    systemImageName: "keyboard.badge.ellipsis")

        AppShortcut(intent: TurnOnKeyboardLightIntent(),
                    phrases: ["用 \(.applicationName) 打开键盘灯",
                              "\(.applicationName) 点亮键盘灯"],
                    shortTitle: "打开键盘灯",
                    systemImageName: "keyboard")

        AppShortcut(intent: TurnOffAllLightsIntent(),
                    phrases: ["用 \(.applicationName) 关闭全部灯光",
                              "\(.applicationName) 关掉所有灯"],
                    shortTitle: "全部关灯",
                    systemImageName: "lightbulb.slash")

        AppShortcut(intent: TurnOnAllLightsIntent(),
                    phrases: ["用 \(.applicationName) 打开全部灯光",
                              "\(.applicationName) 打开所有灯"],
                    shortTitle: "全部开灯",
                    systemImageName: "lightbulb.fill")
    }
}
