//
//  PeripheralPanel.swift
//  AlienMAC
//
//  外设 V8 面板：识别 Alienware / Dell HID 设备，抓取宏键按键
//

import SwiftUI

struct PeripheralPanel: View {
    @ObservedObject private var monitor = PeripheralMonitor.shared
    @ObservedObject private var viewModel = LightingViewModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var bindSlot: String = "m1"

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

                    Text("灯效下发：内置通道（APIv3 · 12B）已可用；外设 APIv7 / APIv8 目前只做识别与诊断导出，报文没在真机比对前不下发。")
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
        .onAppear {
            monitor.refresh()
            if ProcessInfo.processInfo.environment["ALIENMAC_CAPTURE"] == "1" {
                monitor.isCapturing = true
            }
            if ProcessInfo.processInfo.environment["ALIENMAC_EXPORT"] == "1" {
                monitor.exportDiagnostics()
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
