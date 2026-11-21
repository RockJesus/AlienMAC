//
//  AlienMACApp.swift
//  AlienMAC
//
//  macOS App 入口
//

import SwiftUI
import AppKit

@main
struct AlienMACApp: App {
    @StateObject private var viewModel = LightingViewModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 720, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        // 菜单栏
        MenuBarExtra {
            MenuBarContent(viewModel: viewModel)
        } label: {
            Image(systemName: viewModel.isLightsOff ? "lightbulb.slash.fill" : "lightbulb.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        SettingsStore.shared.saveNow()
    }
}

// MARK: - 菜单栏快捷控制

struct MenuBarContent: View {
    @ObservedObject var viewModel: LightingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                Text("AlienMAC")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(viewModel.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
            }

            Divider()

            Text("快捷颜色")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                ForEach(Array(quickColors.enumerated()), id: \.offset) { _, color in
                    Button {
                        viewModel.currentColor = color
                        viewModel.currentEffect = .color
                        viewModel.applyToAll()
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 24, height: 24)
                            .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            if !viewModel.customPresets.isEmpty {
                Divider()
                Text("我的预设")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(viewModel.customPresets) { preset in
                    Button {
                        viewModel.applyCustomPreset(preset)
                    } label: {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(LinearGradient(colors: [preset.color, preset.secondaryColor],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: 24, height: 14)
                            Text(preset.name)
                            Spacer()
                            Text(preset.scopeDescription)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            HStack {
                Image(systemName: "sun.max.fill")
                Slider(value: $viewModel.brightness, in: 0...100) {
                    Text("亮度")
                } onEditingChanged: { editing in
                    if !editing { viewModel.onBrightnessChanged() }
                }
                Text("\(Int(viewModel.brightness))%")
                    .font(.caption2)
                    .frame(width: 38, alignment: .trailing)
            }

            HStack {
                Button {
                    viewModel.toggleLights()
                } label: {
                    Label(viewModel.isLightsOff ? "开灯" : "关灯",
                          systemImage: viewModel.isLightsOff ? "lightbulb.fill" : "lightbulb.slash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("主界面", systemImage: "macwindow")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Divider()

            HStack {
                Text("⌥⌘L 开关 · ⌥⌘↑↓ 亮度")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
                    .buttonStyle(.link)
                    .font(.caption2)
            }
        }
        .padding()
        .frame(width: 300)
    }

    private var quickColors: [Color] {
        [
            Color(red: 0, green: 0.5, blue: 1),
            .red, .green, .cyan,
            Color(red: 1.0, green: 0.0, blue: 1.0),
            .yellow, .white, .orange
        ]
    }
}
