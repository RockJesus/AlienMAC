//
//  PeripheralPanel.swift
//  AlienMAC
//
//  外设 V8 面板：识别 Alienware / Dell HID 设备，抓取宏键按键
//

import SwiftUI

struct PeripheralPanel: View {
    @ObservedObject private var monitor = PeripheralMonitor.shared

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
                Button("关闭") { NSApp.keyWindow?.performClose(nil) }
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

                    Divider().opacity(0.3).padding(.vertical, 2)

                    captureSection
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
        }
    }

    private func deviceRow(_ device: PeripheralDevice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: device.isBuiltIn ? "laptopcomputer" : "keyboard")
                .font(.system(size: 13 * AppTheme.fontScale))
                .foregroundColor(device.isBuiltIn ? .cyan : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.product)
                        .font(.system(size: 12.5 * AppTheme.fontScale, weight: .medium))
                    Text(device.category)
                        .font(.system(size: 10.5 * AppTheme.fontScale))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.white.opacity(0.1), in: Capsule())
                        .foregroundColor(.secondary)
                }
                Text("\(device.vidPid) · \(device.usageText) · 输入报文 \(device.maxInputReportSize) B · \(device.transport)")
                    .font(.system(size: 11 * AppTheme.fontScale, design: .monospaced))
                    .foregroundColor(Color.secondary.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $monitor.isCapturing) {
                Text("宏键捕获")
                    .font(.system(size: 12.5 * AppTheme.fontScale, weight: .medium))
            }
            .toggleStyle(.switch)

            Text("开启后监听 Dell/Alienware 外设的按键报文（不独占设备，键鼠照常可用），按一下宏键就能看到它的 usage page / usage —— 拿到编号即可在 TactX 里对号绑定。")
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

            Text("macOS 10.15 起读取按键需要「系统设置 → 隐私与安全性 → 输入监控」授权，没授权时列表可能为空；关闭开关即停止监听。")
                .font(.system(size: 11 * AppTheme.fontScale))
                .foregroundColor(Color.secondary.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
}
