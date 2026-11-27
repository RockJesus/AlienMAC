//
//  AlienMACApp.swift
//  AlienMAC
//
//  macOS App 入口
//

import SwiftUI
import AppKit

/// App 标志（透明底，无背景框）
enum AppLogo {
    /// 优先用网页用的 4 倍分辨视图（204×244），退回到 47×57 的原图
    private static func sourceImage() -> NSImage? {
        for name in ["app_logo_web", "app_logo"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }

    /// 按目标高度生成带 2 倍位图的图标。
    /// 之前是先把图缩放成 18px 存进 NSImage，顶栏显示 40pt 时就是拿 18px 硬放大，所以糊
    private static func makeIcon(height: CGFloat) -> NSImage {
        guard let src = sourceImage() else {
            return NSImage(systemSymbolName: "lightbulb.fill", accessibilityDescription: nil) ?? NSImage()
        }
        let ratio = src.size.width / max(src.size.height, 1)
        let pointSize = NSSize(width: (height * ratio).rounded(), height: height)
        let pixelSize = NSSize(width: (pointSize.width * 2).rounded(), height: (pointSize.height * 2).rounded())
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(pixelSize.width), pixelsHigh: Int(pixelSize.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            return src
        }
        rep.size = pointSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        src.draw(in: NSRect(origin: .zero, size: pointSize))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: pointSize)
        image.addRepresentation(rep)
        image.isTemplate = false
        return image
    }

    /// 菜单栏用的透明标志（菜单栏里也放大一档）
    static let menuBarIcon: NSImage = makeIcon(height: 22)
    /// 主界面左上角用的高清标志
    static let headerIcon: NSImage = makeIcon(height: 40)
}

@main
struct AlienMACApp: App {
    @StateObject private var viewModel: LightingViewModel
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // 全局单例：Siri 意图、定时任务、语音控制都作用在同一个视图模型上
        let vm = LightingViewModel.shared
        _viewModel = StateObject(wrappedValue: vm)

        ScheduleController.shared.executor = { action in
            vm.perform(action)
        }
        VoiceControlController.shared.onCommand = { command in
            vm.perform(voice: command)
        }
        HomeAssistantBridge.shared.bootstrap()
        TriggerEngine.shared.start()
        PeripheralMonitor.shared.start()
        PeripheralMonitor.shared.onKeyEvent = { page, usage in
            MacroRouter.handle(usagePage: page, usage: usage)
        }
        if let key = ProcessInfo.processInfo.environment["ALIENMAC_SELFTEST_KEY"], let usage = Int(key) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                MacroRouter.handle(usagePage: 0x07, usage: usage)
            }
        }
    }


    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: AppTheme.defaultWindowWidth, height: AppTheme.defaultWindowHeight)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .undoRedo) {
                Button("撤销灯光改动") {
                    LightingViewModel.shared.undo()
                }
                .keyboardShortcut("z", modifiers: .command)

                Button("重做灯光改动") {
                    LightingViewModel.shared.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }

        // 菜单栏
        MenuBarExtra {
            MenuBarContent(viewModel: viewModel)
        } label: {
            Image(nsImage: AppLogo.menuBarIcon)
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
                // 弹出的面板里这只头和菜单栏那只一起放大，保持原图比例
                Image(nsImage: AppLogo.headerIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 28)
                Text("AlienMAC")
                    .font(.system(size: 15 * AppTheme.fontScale, weight: .semibold))
                Spacer()
                Circle()
                    .fill(viewModel.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
            }

            Divider()

            Text("快捷颜色")
                .font(.system(size: 13 * AppTheme.fontScale))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                ForEach(Array(quickColors.enumerated()), id: \.offset) { _, color in
                    Button {
                        viewModel.currentColor = color
                        viewModel.currentEffect = .color
                        viewModel.liveApply()
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
                    .font(.system(size: 13 * AppTheme.fontScale))
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
                                .font(.system(size: 12 * AppTheme.fontScale))
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
                    .font(.system(size: 12 * AppTheme.fontScale))
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
                    .font(.system(size: 12 * AppTheme.fontScale))
                    .foregroundColor(.secondary)
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
                    .buttonStyle(.link)
                    .font(.system(size: 12 * AppTheme.fontScale))
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
