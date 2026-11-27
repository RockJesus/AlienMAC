//
//  LightingViewModel+Web.swift
//  AlienMAC
//
//  手机网页 ↔ 主界面：同一套状态、同一套下发逻辑，只做一层数据映射
//

import Foundation
import SwiftUI
import AppKit

extension LightingViewModel {

    // MARK: - 状态快照（推给手机）

    func webSnapshot() -> [String: Any] {
        var zones: [[String: Any]] = []
        for zone in LightZone.allIndividual {
            zones.append([
                "id": Int(zone.rawValue),
                "name": zone.displayName,
                "selected": selectedZones.contains(zone),
                "color": Self.hexString(zoneDisplayColor(zone))
            ])
        }

        let effects = LightEffect.allCases.map { ["code": $0.code, "name": $0.rawValue] }
        let presets = LightingPreset.allCases.map {
            ["name": $0.rawValue, "color": Self.hexString($0.primaryColor)]
        }
        let customs = customPresets.map {
            ["id": $0.id.uuidString, "name": $0.name, "color": Self.hexString($0.color)]
        }

        let swatches = ["#0080FF", "#00E5FF", "#7A5CFF", "#FF33CC",
                        "#FF3B30", "#FF9500", "#35D94A", "#FFFFFF"].map { ["hex": $0] }

        let touchpadState: [String: Any] = [
            "padFollowsZone": touchpad.padFollowsZone,
            "padBrightness": Int(touchpad.padBrightness.rounded()),
            "edgeFollowsZone": touchpad.edgeFollowsZone,
            "edgeEnabled": touchpad.edgeEnabled,
            "edgeBrightness": Int(touchpad.edgeBrightness.rounded())
        ]

        let zoneActionPayload: [[String: Any]] = zoneActionList.map {
            ["zone": Int($0.zoneRaw),
             "name": $0.zone.displayName,
             "summary": $0.summary,
             "loop": $0.loop,
             "color": Self.hexString($0.primary.swiftUIColor)]
        }

        return [
            "modelName": controller.model.name,
            "swatches": swatches,
            "subtitle": "\(controller.model.shortName) · 手机遥控",
            "connected": isConnected,
            "hardware": controller.hardwareControllable,
            "brightness": Int(brightness.rounded()),
            "lightsOff": isLightsOff,
            "primary": Self.hexString(currentColor),
            "secondary": Self.hexString(secondaryColor),
            "effect": currentEffect.code,
            "effectName": currentEffect.rawValue,
            "needsSecondary": currentEffect.needsSecondaryColor,
            "tempo": Int(tempo.rounded()),
            "zones": zones,
            "effects": effects,
            "presets": presets,
            "customPresets": customs,
            "touchpad": touchpadState,
            "canUndo": canUndo,
            "canRedo": canRedo,
            "hasUnappliedEdits": hasUnappliedEdits,
            "zoneActions": zoneActionPayload
        ]
    }

    // MARK: - 手机端操作

    func handleWebAction(_ action: [String: Any]) {
        guard let type = action["type"] as? String else { return }

        switch type {
        case "toggleZone":
            // 网页已经把选中状态翻过来了，这里只做写入，避免二次取反
            if let raw = action["id"] as? Int {
                let zone = LightZone(rawValue: UInt32(raw))
                if selectedZones.contains(zone) {
                    selectedZones.remove(zone)
                } else {
                    selectedZones.insert(zone)
                    selectedKeys.removeAll()
                }
            }

        case "select":
            switch action["mode"] as? String {
            case "all":      selectedZones = Set(LightZone.allIndividual)
            case "keyboard": selectKeyboard()
            case "touchpad": selectTouchpadOnly()
            case "power":    selectPowerButtonOnly()
            case "clear":    selectedZones.removeAll()
            default: break
            }

        case "color":
            if let hex = action["hex"] as? String {
                currentColor = Self.color(fromHex: hex)
                liveApply()
            }

        case "brightness":
            if let value = action["value"] as? Double {
                brightness = min(100, max(0, value))
                onBrightnessChanged()
            } else if let value = action["value"] as? Int {
                brightness = Double(min(100, max(0, value)))
                onBrightnessChanged()
            }

        case "effect":
            if let code = action["code"] as? String {
                currentEffect = LightEffect(code: code)
                liveApply()
            }

        case "tempo":
            if let value = action["value"] as? Double {
                tempo = min(8000, max(500, value))
                liveApply()
            } else if let value = action["value"] as? Int {
                tempo = Double(min(8000, max(500, value)))
                liveApply()
            }

        case "preset":
            if let name = action["name"] as? String,
               let preset = LightingPreset(rawValue: name) {
                applyPreset(preset)
            }

        case "customPreset":
            if let id = action["id"] as? String,
               let uuid = UUID(uuidString: id),
               let preset = customPresets.first(where: { $0.id == uuid }) {
                applyCustomPreset(preset)
            }

        case "toggleLights":
            toggleLights()

        case "apply":
            applyToSelected()

        case "cancel":
            cancelEdits()

        case "touchpad":
            var next = touchpad
            if let v = action["padFollowsZone"] as? Bool { next.padFollowsZone = v }
            if let v = action["edgeFollowsZone"] as? Bool { next.edgeFollowsZone = v }
            if let v = action["edgeEnabled"] as? Bool { next.edgeEnabled = v }
            if let v = Self.doubleValue(action["padBrightness"]) { next.padBrightness = min(100, max(0, v)) }
            if let v = Self.doubleValue(action["edgeBrightness"]) { next.edgeBrightness = min(100, max(0, v)) }
            touchpad = next

        case "undo":
            undo()

        case "redo":
            redo()

        case "assignAction":
            assignActionToSelected()

        case "clearActions":
            clearAllActions()

        case "loopAction":
            if let raw = action["zone"] as? Int {
                toggleActionLoop(for: LightZone(rawValue: UInt32(raw)))
            }

        case "savePreset":
            if let name = action["name"] as? String {
                _ = saveCurrentAsPreset(name: name)
            }

        default:
            break
        }
    }

    /// JSON 里的数字可能是 Double / Int / NSNumber，统一取值
    static func doubleValue(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    // MARK: - 颜色转换

    static func hexString(_ color: Color) -> String {
        guard let ns = NSColor(color).usingColorSpace(.deviceRGB) else { return "#FFFFFF" }
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", min(255, max(0, r)), min(255, max(0, g)), min(255, max(0, b)))
    }

    static func color(fromHex hex: String) -> Color {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 {
            let expanded = text.map { "\($0)\($0)" }.joined()
            text = expanded
        }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return .white }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}
