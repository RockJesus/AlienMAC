//
//  ModulePanels.swift
//  AlienMAC
//
//  AlienFusion（电源）/ TactX（宏键）/ AlienAdrenaline（游戏档案）三个模块面板
//

import AppKit
import SwiftUI

// MARK: - AlienFusion

struct FusionPanel: View {
    @State private var info: PowerInfo = .read()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("AlienFusion")
                    .font(.system(size: 15.5 * AppTheme.fontScale, weight: .semibold))
                Spacer()
                Button {
                    info = .read()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12 * AppTheme.fontScale))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("重新读取电源方案")
            }

            Text("17 R4 上 AWCC 的 AlienFusion 退化为 Windows 电源方案，这里对应 macOS 的电源策略。")
                .font(.system(size: 12 * AppTheme.fontScale))
                .foregroundColor(Color.secondary.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                infoRow("供电", value: info.isAC ? "交流电源" : "电池", tint: info.isAC ? .green : .orange)
                if let percent = info.batteryPercent {
                    infoRow("电量", value: "\(percent)%" + (info.batteryCharging ? " · 充电中" : ""),
                            tint: percent < 20 ? .red : .secondary)
                }
                Divider().opacity(0.3)
                infoRow("系统休眠", value: PowerInfo.minutesText(info.systemSleepMinutes))
                infoRow("显示器休眠", value: PowerInfo.minutesText(info.displaySleepMinutes))
                infoRow("硬盘休眠", value: PowerInfo.minutesText(info.diskSleepMinutes))
                infoRow("低电量模式", value: info.lowPowerMode ? "已开启" : "关闭",
                        tint: info.lowPowerMode ? .yellow : .secondary)
            }
            .padding(12)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))

            Button {
                openBatterySettings()
            } label: {
                Label("在系统设置里修改电源方案", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Text("写入休眠时长需要管理员权限（pmset 属于 root 操作），这里只读展示并跳系统设置，不代你改系统配置。")
                .font(.system(size: 11.5 * AppTheme.fontScale))
                .foregroundColor(Color.secondary.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(18)
    }

    private func infoRow(_ title: String, value: String, tint: Color = .secondary) -> some View {
        HStack {
            Text(title).font(.system(size: 12.5 * AppTheme.fontScale)).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(size: 12.5 * AppTheme.fontScale, design: .monospaced)).foregroundColor(tint)
        }
    }

    private func openBatterySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - TactX

struct TactXPanel: View {
    @EnvironmentObject var viewModel: LightingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("TactX")
                    .font(.system(size: 15.5 * AppTheme.fontScale, weight: .semibold))
                Spacer()
                Text("\(boundCount) / \(viewModel.macroBindingList.count) 已绑定")
                    .font(.system(size: 12 * AppTheme.fontScale))
                    .foregroundColor(.secondary)
            }

            Text("17 R4 左侧 Δ1–Δ5 与顶部宏键。这里定义每个键做什么，改完即时保存。")
                .font(.system(size: 12 * AppTheme.fontScale))
                .foregroundColor(Color.secondary.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            ForEach(viewModel.macroBindingList) { binding in
                macroRow(binding)
            }

            Text("物理按键在工具栏「外设」里抓取后绑定，绑好即按即生效；这里只负责定义每个槽位做什么，也可以用「测试」单独验证动作。")
                .font(.system(size: 11.5 * AppTheme.fontScale))
                .foregroundColor(Color.secondary.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(18)
    }

    private var boundCount: Int {
        viewModel.macroBindingList.filter { $0.action != .none }.count
    }

    private func macroRow(_ binding: MacroBinding) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(MacroBinding.slotTitle(binding.slot))
                    .font(.system(size: 12.5 * AppTheme.fontScale, weight: .medium))
                if binding.hasPhysicalKey {
                    Text(binding.keyText)
                        .font(.system(size: 10.5 * AppTheme.fontScale, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.15), in: Capsule())
                        .foregroundColor(.cyan)
                }
                Spacer()
                Button("测试") { viewModel.testMacroBinding(binding) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5 * AppTheme.fontScale))
                    .foregroundColor(.cyan)
                    .disabled(binding.action == .none)
            }

            HStack(spacing: 8) {
                Picker("", selection: Binding(
                    get: { binding.action },
                    set: { newValue in
                        viewModel.updateMacroBinding(slot: binding.slot, action: newValue,
                                                     target: binding.target,
                                                     systemCode: binding.systemAction)
                    }
                )) {
                    ForEach(MacroAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 130)

                switch binding.action {
                case .launchApp:
                    TextField("应用名或 Bundle ID", text: targetBinding(binding))
                        .textFieldStyle(.roundedBorder)
                case .openURL:
                    TextField("https://… 或文件路径", text: targetBinding(binding))
                        .textFieldStyle(.roundedBorder)
                case .runScript:
                    TextField("脚本路径", text: targetBinding(binding))
                        .textFieldStyle(.roundedBorder)
                case .system:
                    Picker("", selection: Binding(
                        get: { binding.systemAction },
                        set: { viewModel.updateMacroBinding(slot: binding.slot, action: .system,
                                                           target: binding.target, systemCode: $0) }
                    )) {
                        ForEach(MacroSystemAction.allCases) { action in
                            Text(action.title).tag(action)
                        }
                    }
                    .labelsHidden()
                case .none:
                    Text("选择动作后填写目标")
                        .font(.system(size: 11.5 * AppTheme.fontScale))
                        .foregroundColor(Color.secondary.opacity(0.5))
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func targetBinding(_ binding: MacroBinding) -> Binding<String> {
        Binding(
            get: { viewModel.macroBindings[binding.slot]?.target ?? "" },
            set: { viewModel.updateMacroBinding(slot: binding.slot, action: binding.action, target: $0,
                                               systemCode: binding.systemAction) }
        )
    }
}

// MARK: - AlienAdrenaline

struct AdrenalinePanel: View {
    @EnvironmentObject var viewModel: LightingViewModel
    var onManageTriggers: () -> Void

    private var appRules: [TriggerRule] {
        TriggerEngine.shared.rules.filter { $0.source == .app }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("AlienAdrenaline")
                    .font(.system(size: 15.5 * AppTheme.fontScale, weight: .semibold))
                Spacer()
                Text("\(appRules.filter { $0.enabled }.count) 个启用")
                    .font(.system(size: 12 * AppTheme.fontScale))
                    .foregroundColor(.secondary)
            }

            Text("按游戏/应用各自套一份灯光档案：切到前台就换配色，离开保持。档案就是触发器里的「应用」规则。")
                .font(.system(size: 12 * AppTheme.fontScale))
                .foregroundColor(Color.secondary.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            if appRules.isEmpty {
                Text("还没有游戏档案。去触发器里加一条「某应用切到前台 → 套用预设」。")
                    .font(.system(size: 12 * AppTheme.fontScale))
                    .foregroundColor(Color.secondary.opacity(0.6))
                    .padding(.vertical, 8)
            } else {
                ForEach(appRules) { rule in
                    HStack(spacing: 8) {
                        Image(systemName: rule.enabled ? "gamecontroller.fill" : "gamecontroller")
                            .font(.system(size: 12 * AppTheme.fontScale))
                            .foregroundColor(rule.enabled ? .cyan : Color.secondary.opacity(0.5))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.appName.isEmpty ? rule.name : rule.appName)
                                .font(.system(size: 12.5 * AppTheme.fontScale, weight: .medium))
                            Text(rule.summary)
                                .font(.system(size: 11 * AppTheme.fontScale))
                                .foregroundColor(Color.secondary.opacity(0.7))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(9)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            Button {
                onManageTriggers()
            } label: {
                Label("管理游戏档案 / 触发器", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 0)
        }
        .padding(18)
    }
}
