//
//  HotKeyCenter.swift
//  AlienMAC
//
//  全局快捷键（Carbon RegisterEventHotKey，不需要辅助功能权限）
//  ⌥⌘L 开关灯光 / ⌥⌘↑ 亮度+ / ⌥⌘↓ 亮度-
//

import Foundation
import Carbon.HIToolbox
import AppKit

final class HotKeyCenter {

    static let shared = HotKeyCenter()

    enum Action: UInt32 {
        case toggle   = 1
        case brighter = 2
        case dimmer   = 3
    }

    /// 快捷键触发回调
    var onAction: ((Action) -> Void)?

    private(set) var isInstalled = false
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?

    private static let signature: OSType = 0x414D4143   // 'AMAC'

    private init() {}

    // MARK: - 安装 / 卸载

    func install() {
        guard !isInstalled else { return }
        installHandler()

        register(.toggle,   key: UInt32(kVK_ANSI_L),     modifiers: UInt32(optionKey | cmdKey))
        register(.brighter, key: UInt32(kVK_UpArrow),    modifiers: UInt32(optionKey | cmdKey))
        register(.dimmer,   key: UInt32(kVK_DownArrow),  modifiers: UInt32(optionKey | cmdKey))

        isInstalled = true
    }

    func uninstall() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()

        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
        isInstalled = false
    }

    // MARK: - 私有实现

    private func register(_ action: Action, key: UInt32, modifiers: UInt32) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: HotKeyCenter.signature, id: action.rawValue)
        let status = RegisterEventHotKey(key, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)

        if status == noErr, let ref = ref {
            hotKeyRefs.append(ref)
        } else {
            NSLog("AlienMAC hotkey \(action.rawValue) register failed: \(status)")
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event = event, let userData = userData else { return noErr }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            if status == noErr {
                let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                center.fire(id: hotKeyID.id)
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(),
                            callback,
                            1,
                            &eventType,
                            Unmanaged.passUnretained(self).toOpaque(),
                            &eventHandler)
    }

    fileprivate func fire(id: UInt32) {
        guard let action = Action(rawValue: id) else { return }
        onAction?(action)
    }
}
