//
//  TriggerSettingsView.swift
//  AlienMAC
//
//  触发器管理面板（AWCC 高级模式事件树的 macOS 版）
//

import AppKit
import SwiftUI

struct TriggerSettingsView: View {
    @EnvironmentObject var viewModel: LightingViewModel
    @State private var rules: [TriggerRule] = TriggerEngine.shared.rules

    // 新增表单
    @State private var newSource: TriggerSource = .app
    @State private var newBundleID: String = ""
    @State private var newAction: TriggerAction = .preset
    @State private var newPresetID: UUID?
    @State private var newHour: Int = 9
    @State private var newMinute: Int = 0

    private var runningApps: [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && ($0.bundleIdentifier ?? "").isEmpty == false }
            .compactMap { app in
                guard let id = app.bundleIdentifier else { return nil }
                return (id, app.localizedName ?? id)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("触发器")
                    .font(.system(size: 17.5 * AppTheme.fontScale, weight: .semibold))
                Spacer()
                Text("\(rules.filter { $0.enabled }.count) / \(rules.count) 启用")
                    .font(.system(size: 12 * AppTheme.fontScale))
                    .foregroundColor(.secondary)
                Button("关闭") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider().opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if rules.isEmpty {
                        Text("还没有触发器。选一个触发源和动作，加一条试试——比如「切到 DaVinci Resolve 就套用剪辑蓝」或「拔掉电源自动省电暖白」。")
                            .font(.system(size: 12.5 * AppTheme.fontScale))
                            .foregroundColor(Color.secondary.opacity(0.65))
                            .padding(.vertical, 10)
                    }
                    ForEach(rules) { rule in
                        ruleRow(rule)
                    }

                    Divider().opacity(0.3).padding(.vertical, 6)

                    newRuleForm
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        }
        .frame(width: 560, height: 520)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.98))
        .onAppear { rules = TriggerEngine.shared.rules }
    }

    // MARK: - 现有规则

    private func ruleRow(_ rule: TriggerRule) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { value in update(rule) { $0.enabled = value } }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name.isEmpty ? rule.summary : rule.name)
                    .font(.system(size: 12.5 * AppTheme.fontScale, weight: .medium))
                Text(rule.summary)
                    .font(.system(size: 11 * AppTheme.fontScale))
                    .foregroundColor(Color.secondary.opacity(0.7))
            }
            Spacer(minLength: 0)
            Button {
                remove(rule)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11.5 * AppTheme.fontScale))
                    .foregroundColor(Color.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 新增

    private var newRuleForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("新增触发器")
                .font(.system(size: 12.5 * AppTheme.fontScale, weight: .medium))
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                Picker("触发源", selection: $newSource) {
                    ForEach(TriggerSource.allCases) { s in
                        Text(s.title).tag(s)
                    }
                }
                .frame(maxWidth: 220)

                if newSource == .app {
                    Picker("应用", selection: $newBundleID) {
                        Text("选择应用").tag("")
                        ForEach(runningApps, id: \.bundleID) { app in
                            Text(app.name).tag(app.bundleID)
                        }
                    }
                    .frame(maxWidth: 260)
                } else if newSource == .daily {
                    HStack(spacing: 4) {
                        Stepper(value: $newHour, in: 0...23) { Text(String(format: "%02d", newHour)) }
                            .fixedSize()
                        Text("时")
                        Stepper(value: $newMinute, in: 0...59) { Text(String(format: "%02d", newMinute)) }
                            .fixedSize()
                        Text("分")
                    }
                }
            }

            HStack(spacing: 10) {
                Picker("动作", selection: $newAction) {
                    ForEach(TriggerAction.allCases) { a in
                        Text(a.title).tag(a)
                    }
                }
                .frame(maxWidth: 220)

                if newAction == .preset {
                    Picker("预设", selection: $newPresetID) {
                        Text("选择预设").tag(UUID?.none)
                        ForEach(viewModel.customPresets) { preset in
                            Text(preset.name).tag(Optional(preset.id))
                        }
                    }
                    .frame(maxWidth: 260)
                }
            }

            HStack {
                Spacer()
                Button("添加") { addRule() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newAction == .preset && newPresetID == nil)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 数据操作

    private func addRule() {
        var rule = TriggerRule()
        rule.sourceCode = newSource.rawValue
        rule.actionCode = newAction.rawValue
        rule.enabled = true

        if newSource == .app {
            rule.appBundleID = newBundleID
            rule.appName = runningApps.first { $0.bundleID == newBundleID }?.name ?? newBundleID
            rule.name = "\(rule.appName) 上机"
        } else if newSource == .daily {
            rule.minuteOfDay = newHour * 60 + newMinute
            rule.name = String(format: "每天 %02d:%02d", newHour, newMinute)
        } else {
            rule.name = newSource.title
        }

        if newAction == .preset, let id = newPresetID,
           let preset = viewModel.customPresets.first(where: { $0.id == id }) {
            rule.presetID = id
            rule.presetName = preset.name
        }

        rules.append(rule)
        persist()
    }

    private func update(_ rule: TriggerRule, _ change: (inout TriggerRule) -> Void) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        change(&rules[index])
        persist()
    }

    private func remove(_ rule: TriggerRule) {
        rules.removeAll { $0.id == rule.id }
        persist()
    }

    private func persist() {
        TriggerEngine.shared.rules = rules
    }
}
