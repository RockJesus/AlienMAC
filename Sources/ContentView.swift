//
//  ContentView.swift
//  AlienMAC
//
//  主界面：真实比例 3D 笔记本 + 玻璃控制面板
//

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var viewModel: LightingViewModel

    @State private var lidOpen = true
    @State private var pose: ScenePose = .hero
    @State private var showPresets = false
    @State private var showSettings = false
    @State private var showDebug = false
    @State private var showSavePresetSheet = false
    @State private var newPresetName = ""

    var body: some View {
        ZStack {
            background

            GeometryReader { geo in
                LaptopSceneView(viewModel: viewModel, lidOpen: $lidOpen, pose: pose)
                    .frame(width: max(320, geo.size.width - 318),
                           height: max(240, geo.size.height - 150))
                    .position(x: (geo.size.width - 318) / 2,
                              y: 66 + (geo.size.height - 150) / 2)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                bottomBar
            }
            .padding(18)

            HStack {
                Spacer()
                controlPanel
                    .padding(.trailing, 18)
                    .padding(.top, 74)
                    .padding(.bottom, 118)
            }
        }
        .frame(minWidth: 1020, minHeight: 720)
        .sheet(isPresented: $showPresets) { presetsSheet }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .sheet(isPresented: $showDebug) { debugSheet }
        .sheet(isPresented: $showSavePresetSheet) { savePresetSheet }
    }

    // MARK: - 背景

    private var background: some View {
        ZStack {
            Color.black
            RadialGradient(
                colors: [
                    Color(red: 0.05, green: 0.12, blue: 0.22),
                    Color(red: 0.02, green: 0.03, blue: 0.06),
                    Color.black
                ],
                center: .init(x: 0.42, y: 0.38),
                startRadius: 60,
                endRadius: 900
            )
            LinearGradient(
                colors: [Color(red: 0.55, green: 0.1, blue: 0.7).opacity(0.12), .clear],
                startPoint: .bottomTrailing, endPoint: .center
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "alien")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 0.2, green: 0.9, blue: 1), Color(red: 0.8, green: 0.3, blue: 1)],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                VStack(alignment: .leading, spacing: 1) {
                    Text("AlienMAC")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Alienware 17 R4 · 灯光控制")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
            }

            statusBadge

            Spacer()

            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    ForEach(ScenePose.allCases) { item in
                        Button {
                            pose = item
                        } label: {
                            Text(item.label)
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(
                                    Capsule().fill(pose == item ? Color.white.opacity(0.18) : .clear)
                                )
                                .foregroundColor(pose == item ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))

                glassButton("开合盖", icon: lidOpen ? "laptopcomputer" : "laptopcomputer.and.iphone") {
                    lidOpen.toggle()
                }
                glassButton("预设", icon: "square.grid.2x2") { showPresets = true }
                glassButton("设置", icon: "gearshape") { showSettings = true }
                glassButton("调试", icon: "waveform.path.ecg") { showDebug = true }
            }
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.isConnected ? Color(red: 0.2, green: 0.95, blue: 0.6) : Color.red)
                .frame(width: 7, height: 7)
                .shadow(color: viewModel.isConnected ? .green : .red, radius: 4)
            Text(viewModel.isConnected ? "已连接" : "未连接")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func glassButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(title).font(.system(size: 11.5, weight: .medium))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 右侧控制面板

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            HStack {
                Text("灯效编辑")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(selectionText)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }

            // 颜色
            HStack(spacing: 10) {
                ColorPicker("", selection: $viewModel.currentColor, supportsOpacity: false)
                    .labelsHidden()
                    .scaleEffect(0.85)
                VStack(alignment: .leading, spacing: 2) {
                    Text("主颜色").font(.system(size: 11)).foregroundColor(.secondary)
                    Text(hexString(from: viewModel.currentColor))
                        .font(.system(size: 12, design: .monospaced))
                }
                Spacer()
            }

            // 效果
            VStack(alignment: .leading, spacing: 6) {
                Text("效果").font(.system(size: 11)).foregroundColor(.secondary)
                Picker("", selection: $viewModel.currentEffect) {
                    ForEach(LightEffect.allCases) { effect in
                        Text(effect.rawValue).tag(effect)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if viewModel.currentEffect.needsSecondaryColor {
                HStack(spacing: 10) {
                    ColorPicker("", selection: $viewModel.secondaryColor, supportsOpacity: false)
                        .labelsHidden()
                        .scaleEffect(0.85)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("次颜色").font(.system(size: 11)).foregroundColor(.secondary)
                        Text(hexString(from: viewModel.secondaryColor))
                            .font(.system(size: 12, design: .monospaced))
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("速度").font(.system(size: 11)).foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(viewModel.tempo)) ms").font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                    }
                    Slider(value: $viewModel.tempo, in: 500...8000, step: 250)
                }
            }

            // 亮度
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("亮度").font(.system(size: 11)).foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(viewModel.brightness))%").font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                }
                Slider(value: $viewModel.brightness, in: 0...100) { editing in
                    if !editing { viewModel.onBrightnessChanged() }
                }
            }

            Divider().opacity(0.4)

            // 操作
            VStack(spacing: 8) {
                Button {
                    viewModel.applyToSelected()
                } label: {
                    Label("应用到选中灯区", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedZones.isEmpty)

                HStack(spacing: 8) {
                    Button {
                        viewModel.applyToAll()
                    } label: {
                        Text("全部应用").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        viewModel.toggleLights()
                    } label: {
                        Text(viewModel.isLightsOff ? "开灯" : "关灯").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    newPresetName = suggestedPresetName
                    showSavePresetSheet = true
                } label: {
                    Label("存为预设", systemImage: "star")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .frame(width: 286)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
    }

    // MARK: - 底部灯区栏

    private var bottomBar: some View {
        HStack(spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(LightZone.allIndividual) { zone in
                        ZonePill(zone: zone,
                                 selected: viewModel.selectedZones.contains(zone),
                                 hovered: viewModel.hoveredZone == zone,
                                 color: viewModel.zoneColors[zone] ?? .black)
                        .onTapGesture { viewModel.toggleZone(zone) }
                    }
                }
                .padding(.vertical, 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.hoveredZone?.displayName ?? (viewModel.selectedZones.isEmpty ? "点击模型上的灯区进行多选" : "已选 \(viewModel.selectedZones.count) 个灯区"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Text("拖动旋转 · 滚轮缩放 · 点边框开合盖 · 点屏幕打开官网")
                    .font(.system(size: 9.5))
                    .foregroundColor(Color.secondary.opacity(0.6))
            }
            .frame(width: 200, alignment: .leading)

            HStack(spacing: 6) {
                Button("全选") { viewModel.selectedZones = Set(LightZone.allIndividual) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.white.opacity(0.06), in: Capsule())
                Button("清空") { viewModel.selectedZones.removeAll() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.white.opacity(0.06), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .frame(maxWidth: 830)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectionText: String {
        let count = viewModel.selectedZones.count
        if count == 0 { return "未选择" }
        if count == 1 { return viewModel.selectedZones.first?.displayName ?? "1 个" }
        return "\(count) 个灯区"
    }

    // MARK: - 预设弹窗

    private var presetsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("预设主题").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("关闭") { showPresets = false }
                    .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(LightingPreset.allCases) { preset in
                            PresetCard(preset: preset) { viewModel.applyPreset(preset) }
                        }
                    }

                    Divider()

                    HStack {
                        Text("我的预设").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Button {
                            newPresetName = suggestedPresetName
                            showSavePresetSheet = true
                        } label: {
                            Label("保存当前", systemImage: "plus.circle")
                        }
                        .buttonStyle(.bordered)
                    }

                    if viewModel.customPresets.isEmpty {
                        Text("还没有自定义预设。调好颜色和效果后点“保存当前”。")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                            .padding(.vertical, 12)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                            ForEach(viewModel.customPresets) { preset in
                                CustomPresetCard(preset: preset)
                                    .onTapGesture { viewModel.applyCustomPreset(preset) }
                                    .contextMenu {
                                        Button("应用") { viewModel.applyCustomPreset(preset) }
                                        Button("删除", role: .destructive) { viewModel.deleteCustomPreset(preset) }
                                    }
                            }
                        }
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 640, height: 560)
    }

    // MARK: - 设置弹窗

    private var settingsSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("设置").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("关闭") { showSettings = false }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    settingSection(title: "启动", icon: "power") {
                        Toggle("启动应用时恢复上次灯光配置", isOn: $viewModel.restoreOnLaunch)
                        Text("上次的灯区、颜色、效果和速度保存在本地，重连控制器后自动重新应用。")
                            .font(.caption).foregroundColor(.secondary)
                    }

                    settingSection(title: "登录项", icon: "person.badge.clock") {
                        Toggle("登录 macOS 时自动启动 AlienMAC", isOn: $viewModel.launchAtLogin)
                        HStack(spacing: 8) {
                            Text("当前状态：\(LaunchAtLogin.statusDescription)")
                                .font(.caption).foregroundColor(.secondary)
                            Button("打开登录项设置") {
                                LaunchAtLogin.openSystemSettings()
                            }
                            .font(.caption)
                            .buttonStyle(.link)
                        }
                        if let error = viewModel.loginError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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
                            .font(.caption).foregroundColor(.secondary)
                    }

                    settingSection(title: "关于", icon: "info.circle") {
                        InfoRow(label: "应用", value: "AlienMAC")
                        InfoRow(label: "版本", value: AppInfo.version)
                        InfoRow(label: "支持机型", value: "Alienware 17 R4 (424 × 332 × 30 mm)")
                        InfoRow(label: "数据目录", value: "~/Library/Application Support/AlienMAC")
                    }
                }
                .padding(22)
            }
        }
        .frame(width: 620, height: 640)
    }

    private func settingSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.system(size: 13, weight: .semibold))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.045)))
    }

    private func shortcutRow(_ keys: String, _ description: String) -> some View {
        HStack(spacing: 10) {
            Text(keys)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
            Text(description).font(.caption).foregroundColor(.secondary)
        }
    }

    // MARK: - 调试弹窗

    private var debugSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("HID 通信日志").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(viewModel.isTestingZones ? "停止测试" : "逐灯测试") {
                    viewModel.isTestingZones ? viewModel.stopZoneTest() : viewModel.startZoneTest()
                }
                .tint(viewModel.isTestingZones ? .red : .orange)
                Button("重新扫描") { viewModel.rescan() }
                Button("重置控制器") { viewModel.resetController() }
                Button("清空日志") { viewModel.controller.clearLog() }
                Button("关闭") { showDebug = false }.keyboardShortcut(.cancelAction)
            }
            .padding(18)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(viewModel.controller.logMessages.enumerated()), id: \.offset) { _, msg in
                        Text(msg)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(14)
            }

            Divider()

            HStack(spacing: 24) {
                InfoRow(label: "VID / PID", value: "0x187C / 0x0530")
                InfoRow(label: "协议", value: "APIv3")
                InfoRow(label: "连接", value: viewModel.isConnected ? "已连接" : "未连接")
            }
            .padding(14)
        }
        .frame(width: 760, height: 600)
    }

    // MARK: - 保存预设弹窗

    private var savePresetSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("保存为预设").font(.title3).fontWeight(.semibold)
            Text("范围：\(selectedZoneDescription)").font(.caption).foregroundColor(.secondary)
            TextField("预设名称", text: $newPresetName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitPreset() }
            HStack {
                Spacer()
                Button("取消") { showSavePresetSheet = false }.keyboardShortcut(.cancelAction)
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
        if viewModel.selectedZones.count == 1 { return viewModel.selectedZones.first?.displayName ?? "1 个灯区" }
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

    private func hexString(from color: Color) -> String {
        guard let nsColor = NSColor(color).usingColorSpace(.deviceRGB) else { return "#000000" }
        let r = Int((nsColor.redComponent * 255).rounded())
        let g = Int((nsColor.greenComponent * 255).rounded())
        let b = Int((nsColor.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - 底部灯区胶囊

struct ZonePill: View {
    let zone: LightZone
    let selected: Bool
    let hovered: Bool
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                .shadow(color: color.opacity(selected ? 0.8 : 0.3), radius: selected ? 4 : 1)
            Text(zone.displayName)
                .font(.system(size: 10.5, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? .primary : .secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(
                selected
                    ? Color(red: 0.15, green: 0.75, blue: 0.95).opacity(0.22)
                    : Color.white.opacity(hovered ? 0.1 : 0.05)
            )
        )
        .overlay(
            Capsule().stroke(
                selected ? Color(red: 0.25, green: 0.9, blue: 1).opacity(0.8) : Color.white.opacity(0.06),
                lineWidth: 1
            )
        )
        .contentShape(Capsule())
    }
}

// MARK: - 自定义预设卡片

struct CustomPresetCard: View {
    let preset: CustomPreset

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: preset.effect.needsSecondaryColor
                            ? [preset.color, preset.secondaryColor]
                            : [preset.color, preset.color.opacity(0.55)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 46)
                .shadow(color: preset.color.opacity(0.35), radius: 6)

            Text(preset.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
            HStack {
                Text(preset.effect.rawValue)
                Text("·")
                Text(preset.scopeDescription)
            }
            .font(.system(size: 10)).foregroundColor(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .contentShape(Rectangle())
    }
}

// MARK: - 内置预设卡片

struct PresetCard: View {
    let preset: LightingPreset
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: preset.effect.needsSecondaryColor
                                ? [preset.primaryColor, preset.secondaryColor]
                                : [preset.primaryColor, preset.primaryColor.opacity(0.55)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(height: 46)
                    .shadow(color: preset.primaryColor.opacity(0.35), radius: 6)
                Text(preset.rawValue).font(.system(size: 12, weight: .medium))
                Text(preset.effect.rawValue).font(.system(size: 10)).foregroundColor(.secondary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
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
                .frame(width: 104, alignment: .leading)
            Text(value)
                .font(.system(.body, design: .monospaced))
            Spacer()
        }
        .font(.system(size: 12))
    }
}

// MARK: - 版本信息

enum AppInfo {
    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }
}

#Preview {
    ContentView()
}
