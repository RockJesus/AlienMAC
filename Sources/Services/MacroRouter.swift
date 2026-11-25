//
//  MacroRouter.swift
//  AlienMAC
//
//  物理宏键 → 槽位动作：把 HID 按键事件路由到 MacroRunner
//

import Foundation

enum MacroRouter {
    /// 同一个按键 0.45 秒内只触发一次，避免长按连发
    private static var lastFire: [String: Date] = [:]
    private static let lock = NSLock()

    /// HID 按键落到哪个槽位就执行哪个槽位的动作
    static func handle(usagePage: Int, usage: Int) {
        guard usage != 0 else { return }
        let key = String(format: "%02X:%02X", usagePage, usage)

        lock.lock()
        if let last = lastFire[key], Date().timeIntervalSince(last) < 0.45 {
            lock.unlock()
            return
        }
        lastFire[key] = Date()
        lock.unlock()

        let bindings = LightingViewModel.shared.macroBindings.values
        guard let match = bindings.first(where: {
            $0.keyUsagePage == usagePage && $0.keyUsage == usage && $0.action != .none
        }) else { return }

        DispatchQueue.main.async {
            MacroRunner.run(match)
        }
    }

    /// 某个按键是否已被占用
    static func slotBound(toPage page: Int, usage: Int) -> String? {
        LightingViewModel.shared.macroBindings.values.first(where: {
            $0.keyUsagePage == page && $0.keyUsage == usage
        })?.slot
    }
}
