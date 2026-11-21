//
//  ContentView.swift
//  AlienMAC
//
//  主界面：颜色拾取、效果选择、亮度控制、预设主题、调试日志、设置
//

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var viewModel: LightingViewModel

    @State private var showSavePresetSheet = false
    @State private var newPresetName = ""

    var body: some View {
        TabView {
            controlPanel
                .tabItem { Label("灯光控制", systemImage: "lightbulb.fill") }

            presetsPanel
                .tabItem { Label("预设主题", systemImage: "paintpalette.fill") }

            settingsPanel
                .tabItem { Label("设置", systemImage: "gearshape.fill") }

            debugPanel
                .tabItem { Label("调试", systemImage: "wrench.and.screwdriver.fill") }
        }
        .frame(minWidth: 660, minHeight: 700)
        .sheet(isPresented: $showSavePresetSheet) {
            savePresetSheet
        }
    }

    // MARK: - 控制面板

    private var controlPanel: some View {
        ScrollView {
            VStack(spacing: 20) {
                connectionBanner

                ZoneGridView(viewModel: viewModel)
                    .padding(.horizontal)

                Divider()

                VStack(spacing: 16) {
                    HStack {
                        Text("主颜色")
                            .frame(width: 80, alignment: .leading)
                        ColorPicker("", selection: $viewModel.currentColor)
                            .labelsHidden()
                        Spacer()
                        Text(hexString(from: viewModel.currentColor))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("灯光效果")
                            .frame(width: 80, alignment: .leading)
                        Picker("", selection: $viewModel.currentEffect) {
                            ForEach(LightEffect.allCases) { effect in
                                Text(effect.rawValue).tag(effect)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    if viewModel.currentEffect.needsSecondaryColor {
                        HStack {
                            Text("次颜色")
                                .frame(width: 80, alignment: .leading)
                            ColorPicker("", selection: $viewModel.secondaryColor)
                                .labelsHidden()
                            Spacer()
                            Text(hexString(from: viewModel.secondaryColor))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .transition(.opacity)

                        HStack {
                            Text("速度")
                                .frame(width: 80, alignment: .leading)
                            Slider(value: $viewModel.tempo, in: 500...8000, step: 250)
                            Text("\(Int(viewModel.tempo)) ms")
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 70, alignment: .trailing)
                        }
                    }

                    HStack {
                        Text("亮度")
                            .frame(width: 80, alignment: .leading)
                        Slider(value: $viewModel.brightness, in: 0...100) {
                            Text("亮度")
                        } onEditingChanged: { editing in
                            if !editing { viewModel.onBrightnessChanged() }
                        }
                        Text("\(Int(viewModel.brightness))%")
                            .frame(width: 50, alignment: .trailing)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                .padding(.horizontal)

                Divider()

                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Button(action: { viewModel.applyToSelected() }) {
                            Label("应用到选中", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.selectedZones.isEmpty)

                        Button(action: { viewModel.applyToAll() }) {
                            Label("应用到全部", systemImage: "circle.hexagongrid.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    HStack(spacing: 12) {
                        Button(action: { viewModel.toggleLights() }) {
                            Label(viewModel.isLightsOff ? "开灯" : "全部关闭",
                                  systemImage: viewModel.isLightsOff ? "lightbulb.fill" : "poweroff")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button(action: { viewModel.saveAsDefault() }) {
                            Label("写入设备闪存", systemImage: "square.and.arrow.down.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        newPresetName = suggestedPresetName
                        showSavePresetSheet = true
                    } label: {
                        Label("把当前灯光存为预设", systemImage: "star.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .padding(.vertical)
        }
    }

    // MARK: - 预设主题面板

    private var presetsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("内置主题")
                    .font(.headline)
                    .padding(.horizontal, 4)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                    ForEach(LightingPreset.allCases) { preset in
                        PresetCard(preset: preset) {
                            viewModel.applyPreset(preset)
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 4)

                HStack {
                    Text("我的预设")
                        .font(.headline)
                    Spacer()
                    Button {
                        newPresetName = suggestedPresetName
                        showSavePresetSheet = true
                    } label: {
                        Label("保存当前", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if viewModel.customPresets.isEmpty {
                    Text("还没有自定义预设。调好颜色和效果后点“保存当前”，之后一键切换。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 20)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                        ForEach(viewModel.customPresets) { preset in
                            CustomPresetCard(preset: preset)
                                .onTapGesture { viewModel.applyCustomPreset(preset) }
                                .contextMenu {
                                    Button("应用") { viewModel.applyCustomPreset(preset) }
                                    Button("删除", role: .destructive) {
                                        viewModel.deleteCustomPreset(preset)
                                    }
                                }
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - 设置面板

    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                settingSection(title: "启动", icon: "power") {
                    Toggle("启动应用时恢复上次灯光配置", isOn: $viewModel.restoreOnLaunch)
                    Text("上次的灯区、颜色、效果和速度保存在本地，重连控制器后自动重新应用。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                settingSection(title: "登录项", icon: "person.badge.clock") {
                    Toggle("登录 macOS 时自动启动 AlienMAC", isOn: $viewModel.launchAtLogin)
                    Text("当前状态：\(LaunchAtLogin.statusDescription)。若系统要求批准，可在“系统设置 → 通用 → 登录项”中允许。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                settingSection(title: "全局快捷键", icon: "command") {
                    Toggle("启用全局快捷键", isOn: $viewModel.hotkeysEnabled)
                    VStack(alignment: .leading, spacing: 4) {
                        shortcutRow("⌥⌘L", "开灯 / 关灯切换")
                        shortcutRow("⌥⌘↑", "亮度 +10%")
                        shortcutRow("⌥⌘↓", "亮度 -10%")
                    }
                }

                settingSection(title: "灯区校准", icon: "slider.horizontal.3") {
                    HStack {
                        Text("屏幕 Logo 亮度补偿")
                        Slider(value: $viewModel.screenLogoBoost, in: 1.0...2.5, step: 0.1)
                        Text(String(format: "%.1fx", viewModel.screenLogoBoost))
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 46, alignment: .trailing)
                    }
                    Text("屏幕下方导光条偏暗时，可提高该系数让 Logo 亮度与其他灯区接近。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                settingSection(title: "关于", icon: "info.circle") {
                    InfoRow(label: "应用", value: "AlienMAC")
                    InfoRow(label: "版本", value: AppInfo.version)
                    InfoRow(label: "支持机型", value: "Alienware 17 R4 (APIv3)")
                    InfoRow(label: "数据目录", value: "~/Library/Application Support/AlienMAC")
                }
            }
            .padding()
        }
    }

    private func settingSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.08)))
    }

    private func shortcutRow(_ keys: String, _ description: String) -> some View {
        HStack(spacing: 10) {
            Text(keys)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.18)))
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 保存预设弹窗

    private var savePresetSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("保存为预设")
                .font(.title3)
                .fontWeight(.semibold)

            Text("范围：\(selectedZoneDescription)")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("预设名称", text: $newPresetName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitPreset() }

            HStack {
                Spacer()
                Button("取消") { showSavePresetSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { commitPreset() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private var selectedZoneDescription: String {
        if viewModel.selectedZones.isEmpty { return "全部灯区" }
        if viewModel.selectedZones.count == LightZone.allIndividual.count { return "全部灯区" }
        if viewModel.selectedZones.count == 1 {
            return viewModel.selectedZones.first?.displayName ?? "1 个灯区"
        }
        return "\(viewModel.selectedZones.count) 个选中灯区"
    }

    private var suggestedPresetName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return "预设 \(formatter.string(from: Date()))"
    }

    private func commitPreset() {
        if viewModel.saveCurrentAsPreset(name: newPresetName) {
            showSavePresetSheet = false
        }
    }

    // MARK: - 调试面板

    private var debugPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("HID 通信日志")
                    .font(.headline)
                Spacer()
                Button(viewModel.isTestingZones ? "停止测试" : "逐灯测试") {
                    if viewModel.isTestingZones {
                        viewModel.stopZoneTest()
                    } else {
                        viewModel.startZoneTest()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.isTestingZones ? .red : .orange)
                Button("重新扫描") { viewModel.rescan() }
                    .buttonStyle(.bordered)
                Button("重置控制器") { viewModel.resetController() }
                    .buttonStyle(.bordered)
                Button("清空日志") { viewModel.controller.clearLog() }
                    .buttonStyle(.bordered)
            }
            .padding()

            if viewModel.isTestingZones {
                HStack {
                    Image(systemName: "flashlight.on.fill")
                        .foregroundColor(.orange)
                    Text("正在测试 bit \(viewModel.currentTestBit) (0x\(String(format: "%04X", 1 << max(0, viewModel.currentTestBit))))")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                    Text("观察哪个物理灯亮了，记录对应的 bit 号")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
            }

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(viewModel.controller.logMessages.enumerated()), id: \.offset) { _, msg in
                            Text(msg)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("设备信息")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                InfoRow(label: "厂商 ID (VID)", value: "0x187C")
                InfoRow(label: "产品 ID (PID)", value: "0x0530 (Alienware 17 R4)")
                InfoRow(label: "协议版本", value: "APIv3 (12-byte HID Report)")
                InfoRow(label: "Report ID", value: "0x02")
                InfoRow(label: "连接状态", value: viewModel.isConnected ? "已连接" : "未连接")
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 连接状态横幅

    private var connectionBanner: some View {
        HStack {
            Circle()
                .fill(viewModel.isConnected ? Color.green : Color.red)
                .frame(width: 10, height: 10)
                .shadow(color: viewModel.isConnected ? .green : .red, radius: 4)
            Text(viewModel.isConnected ? "AlienFX 控制器已连接" : "未检测到 AlienFX 控制器")
                .font(.subheadline)
            Spacer()
            if !viewModel.isConnected {
                Button("重新扫描") { viewModel.rescan() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(viewModel.isConnected ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        )
        .padding(.horizontal)
    }

    // MARK: - 辅助

    private func hexString(from color: Color) -> String {
        guard let nsColor = NSColor(color).usingColorSpace(.deviceRGB) else {
            return "#000000"
        }
        let r = Int((nsColor.redComponent * 255).rounded())
        let g = Int((nsColor.greenComponent * 255).rounded())
        let b = Int((nsColor.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - 自定义预设卡片

struct CustomPresetCard: View {
    let preset: CustomPreset

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: preset.effect.needsSecondaryColor
                            ? [preset.color, preset.secondaryColor]
                            : [preset.color, preset.color.opacity(0.55)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 54)
                .shadow(color: preset.color.opacity(0.35), radius: 6)

            Text(preset.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)

            HStack {
                Text(preset.effect.rawValue)
                Text("·")
                Text(preset.scopeDescription)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        .contentShape(Rectangle())
    }
}

// MARK: - 预设卡片

struct PresetCard: View {
    let preset: LightingPreset
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: preset.effect.needsSecondaryColor
                                ? [preset.primaryColor, preset.secondaryColor]
                                : [preset.primaryColor, preset.primaryColor.opacity(0.55)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 60)
                    .shadow(color: preset.primaryColor.opacity(0.4), radius: 6)

                Text(preset.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(preset.effect.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 信息行

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(.system(.body, design: .monospaced))
            Spacer()
        }
    }
}

// MARK: - 版本信息

enum AppInfo {
    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }
}

#Preview {
    ContentView()
}
