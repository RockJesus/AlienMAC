//
//  PeripheralPanel.swift
//  AlienMAC
//
//  外设 V8 面板：识别 Alienware / Dell HID 设备，抓取宏键按键
//

import SwiftUI

/// 试发用的预设色块
private struct MousePreset: Identifiable {
    let name: String
    let r: Int
    let g: Int
    let b: Int
    var id: String { name }
    var color: Color {
        Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }
    static let all: [MousePreset] = [
        MousePreset(name: "青", r: 0, g: 210, b: 255),
        MousePreset(name: "琥珀", r: 255, g: 96, b: 0),
        MousePreset(name: "红", r: 255, g: 40, b: 60),
        MousePreset(name: "绿", r: 60, g: 220, b: 120)
    ]
}

struct PeripheralPanel: View {
    @ObservedObject private var monitor = PeripheralMonitor.shared
    @ObservedObject private var viewModel = LightingViewModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var bindSlot: String = "m1"
    @State private var showCatalog = false
    @State private var showDebug = false
    @State private var sendResult: String = ""
    @State private var lastSent: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("外设")
                    .font(.system(size: 17.5 * AppTheme.fontScale, weight: .semibold))
                Spacer()
                Toggle("全部 HID", isOn: $monitor.showAllDevices)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11 * AppTheme.fontScale))
                Button {
                    showCatalog = true
                } label: {
                    Text("设备库 \(PeripheralCatalog.shared.devices.count)")
                        .font(.system(size: 11 * AppTheme.fontScale))
                }
                .buttonStyle(.plain)
                .foregroundColor(.cyan)
                .help("225 条授权设备 / 11 款元数据 / 343 条官方灯区")
                Button {
                    showDebug = true
                } label: {
                    Text("调试台")
                        .font(.system(size: 11 * AppTheme.fontScale))
                }
                .buttonStyle(.plain)
                .foregroundColor(.cyan)
                .help("全量 HID 扫描与本机自检，不需要 Windows 抓包")
                Text("\(monitor.devices.count) 个设备")
                    .font(.system(size: 12 * AppTheme.fontScale))
                    .foregroundColor(.secondary)
                Button {
                    monitor.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12 * AppTheme.fontScale))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                Button {
                    if let path = monitor.exportDiagnostics() {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12 * AppTheme.fontScale))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("导出外设诊断 JSON")
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Divider().opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if monitor.devices.isEmpty {
                        Text(monitor.showAllDevices ? "本机没有可读的 HID 设备。" : "没有识别到 Alienware / Dell 的 HID 外设。插上键盘、鼠标或耳机底座后会自动出现在这里；只想先看看本机 HID 结构，可以打开「全部 HID」。")
                            .font(.system(size: 12.5 * AppTheme.fontScale))
                            .foregroundColor(Color.secondary.opacity(0.65))
                            .padding(.vertical, 8)
                    } else {
                        ForEach(monitor.devices) { device in
                            deviceRow(device)
                        }
                    }

                    Text("灯效下发：内置通道（APIv3 · 12B）与鼠标族（0x5A · 64B Output Report）已可用；键盘 v8 / 显示器 v6 报文没在真机比对前只做识别与诊断导出。")
                        .font(.system(size: 11 * AppTheme.fontScale))
                        .foregroundColor(Color.secondary.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)

                    Divider().opacity(0.3).padding(.vertical, 2)

                    captureSection
                    bindSection
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        }
        .frame(width: 560, height: 520)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.98))
        .sheet(isPresented: $showCatalog) { PeripheralCatalogPanel() }
        .sheet(isPresented: $showDebug) { PeripheralDebugPanel() }
        .onAppear {
            monitor.refresh()
            if ProcessInfo.processInfo.environment["ALIENMAC_CAPTURE"] == "1" {
                monitor.isCapturing = true
            }
            if ProcessInfo.processInfo.environment["ALIENMAC_EXPORT"] == "1" {
                monitor.exportDiagnostics()
            }
            if ProcessInfo.processInfo.environment["ALIENMAC_CATALOG"] == "1" {
                showCatalog = true
            }
            if ProcessInfo.processInfo.environment["ALIENMAC_DEBUG"] == "1" {
                showDebug = true
            }
        }
    }

    private func deviceRow(_ device: PeripheralDevice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: device.isBuiltIn ? "laptopcomputer" : "keyboard")
                .font(.system(size: 13 * AppTheme.fontScale))
                .foregroundColor(device.isBuiltIn ? .cyan : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(device.product)
                        .font(.system(size: 12.5 * AppTheme.fontScale, weight: .medium))
                    Text(device.category)
                        .font(.system(size: 10.5 * AppTheme.fontScale))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.white.opacity(0.1), in: Capsule())
                        .foregroundColor(.secondary)
                    let proto = PeripheralLightingMap.protocol(for: device)
                    Text(proto.title)
                        .font(.system(size: 10 * AppTheme.fontScale))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background((proto.canSendFromApp ? Color.cyan : Color.orange).opacity(0.16), in: Capsule())
                        .foregroundColor(proto.canSendFromApp ? .cyan : .orange)
                }
                Text("\(device.vidPid) · \(device.usageText) · 输入报文 \(device.maxInputReportSize) B · \(device.transport)")
                    .font(.system(size: 11 * AppTheme.fontScale, design: .monospaced))
                    .foregroundColor(Color.secondary.opacity(0.7))
                if let hit = device.catalogDevice {
                    Text("设备库 \(hit.model) · \(hit.category) · 灯区 \(device.ledCount) · 亮度刻度 \(hit.brightnessScale)")
                        .font(.system(size: 10.5 * AppTheme.fontScale, design: .monospaced))
                        .foregroundColor(Color.cyan.opacity(0.75))
                }
                if PeripheralLightingMap.protocol(for: device) == .mouse5A {
                    HStack(spacing: 6) {
                        ForEach(MousePreset.all) { item in
                            Button(item.name) { sendMouseColor(device, preset: item) }
                                .buttonStyle(.plain)
                                .font(.system(size: 10.5 * AppTheme.fontScale))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.white.opacity(0.08), in: Capsule())
                                .foregroundColor(item.color)
                        }
                        Button("恢复默认") { resetMouse(device) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5 * AppTheme.fontScale))
                            .foregroundColor(.secondary)
                        if !sendResult.isEmpty {
                            Text(sendResult)
                                .font(.system(size: 10 * AppTheme.fontScale))
                                .foregroundColor(lastSent == device.vidPid ? .green : .orange)
                                .lineLimit(1)
                        }
                    }
                }
                TextField("别名（可留空）", text: Binding(
                    get: { monitor.alias(for: device) },
                    set: { monitor.setAlias($0, for: device) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 11 * AppTheme.fontScale))
                .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }


    /// 鼠标族单色试发（0x5A · 64 字节 Output Report）
    private func sendMouseColor(_ device: PeripheralDevice, preset: MousePreset) {
        let frame = FXMouseCodec.singleColor(r: preset.r, g: preset.g, b: preset.b)
        let outcome = PeripheralLightSender.send(payload: frame, vid: device.vendorID, pid: device.productID)
        lastSent = device.vidPid
        sendResult = outcome.ok ? "已写入 64B" : outcome.message
    }

    private func resetMouse(_ device: PeripheralDevice) {
        let frame = FXMouseCodec.resetDefault()
        let outcome = PeripheralLightSender.send(payload: frame, vid: device.vendorID, pid: device.productID)
        lastSent = device.vidPid
        sendResult = outcome.ok ? "已恢复默认" : outcome.message
    }

    private var bindSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("物理宏键")
                .font(.system(size: 12.5 * AppTheme.fontScale, weight: .medium))

            if monitor.lastUsage == 0 {
                Text("先在上面按一下宏键拿到 usage，再选槽位绑定。")
                    .font(.system(size: 11.5 * AppTheme.fontScale))
                    .foregroundColor(Color.secondary.opacity(0.6))
            } else {
                HStack(spacing: 8) {
                    Text(String(format: "当前按键 0x%02X / 0x%02X", monitor.lastUsagePage, monitor.lastUsage))
                        .font(.system(size: 11.5 * AppTheme.fontScale, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer(minLength: 0)
                    Picker("", selection: $bindSlot) {
                        ForEach(MacroBinding.allSlots, id: \.self) { slot in
                            Text(MacroBinding.slotTitle(slot)).tag(slot)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 120)
                    Button("绑定") {
                        viewModel.assignPhysicalKey(page: monitor.lastUsagePage,
                                                    usage: monitor.lastUsage, to: bindSlot)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(viewModel.macroBindings[bindSlot]?.action == MacroAction.none)
                }
                if viewModel.macroBindings[bindSlot]?.action == MacroAction.none {
                    Text("这个槽位还没配动作，先去 TactX 给它选动作，再回来绑定。")
                        .font(.system(size: 11 * AppTheme.fontScale))
                        .foregroundColor(Color.orange.opacity(0.8))
                }
                if let occupied = MacroRouter.slotBound(toPage: monitor.lastUsagePage, usage: monitor.lastUsage),
                   occupied != bindSlot {
                    Text("该按键已绑在 \(MacroBinding.slotTitle(occupied))，重新绑定会把它挪到新槽位。")
                        .font(.system(size: 11 * AppTheme.fontScale))
                        .foregroundColor(Color.secondary.opacity(0.6))
                }
            }

            if viewModel.physicalKeyBindings.isEmpty {
                Text("还没有物理键绑定。")
                    .font(.system(size: 11.5 * AppTheme.fontScale))
                    .foregroundColor(Color.secondary.opacity(0.5))
            } else {
                ForEach(viewModel.physicalKeyBindings) { binding in
                    HStack(spacing: 8) {
                        Text(MacroBinding.slotTitle(binding.slot))
                            .font(.system(size: 12 * AppTheme.fontScale, weight: .medium))
                            .frame(width: 72, alignment: .leading)
                        Text(binding.keyText)
                            .font(.system(size: 11 * AppTheme.fontScale, design: .monospaced))
                            .foregroundColor(.cyan)
                        Text(binding.summary)
                            .font(.system(size: 11.5 * AppTheme.fontScale))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Button("解绑") { viewModel.clearPhysicalKey(slot: binding.slot) }
                            .buttonStyle(.plain)
                            .font(.system(size: 11 * AppTheme.fontScale))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $monitor.isCapturing) {
                Text("宏键捕获")
                    .font(.system(size: 12.5 * AppTheme.fontScale, weight: .medium))
            }
            .toggleStyle(.switch)

            Text("默认开启，监听 Dell/Alienware 外设的按键报文（不独占设备，键鼠照常可用）。按一下宏键就能看到它的 usage page / usage，下面直接选槽位绑定，绑定后按该键即执行 TactX 里配好的动作。")
                .font(.system(size: 11.5 * AppTheme.fontScale))
                .foregroundColor(Color.secondary.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Circle()
                    .fill(monitor.isCapturing ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
                Text(monitor.lastEvent.isEmpty ? (monitor.isCapturing ? "等待按键…" : "未开始捕获") : monitor.lastEvent)
                    .font(.system(size: 12 * AppTheme.fontScale, design: .monospaced))
                    .foregroundColor(monitor.lastEvent.isEmpty ? Color.secondary.opacity(0.7) : .primary)
                Spacer(minLength: 0)
                if !monitor.lastEvent.isEmpty {
                    Button("复制") {
                        let text = "page \(monitor.lastUsagePage) usage \(monitor.lastUsage)"
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5 * AppTheme.fontScale))
                    .foregroundColor(.cyan)
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

            Text("macOS 10.15 起读取按键需要「系统设置 → 隐私与安全性 → 输入监控」授权，没授权时列表可能为空；关掉开关会暂停监听，已绑定的物理键也随之失效。")
                .font(.system(size: 11 * AppTheme.fontScale))
                .foregroundColor(Color.secondary.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
}
