//
//  ContentView.swift
//  AlienMAC
//
//  主界面：真实比例 3D 笔记本 + 玻璃控制面板
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var viewModel: LightingViewModel
    /// 直接观察 HID 控制器，保证调试日志实时刷新（日志追加不会触发 viewModel 的 objectWillChange）
    @ObservedObject private var fx = AlienFXController.shared

    @State private var lidOpen = true
    @State private var pose: ScenePose = .hero
    @State private var showPresets = false
    @State private var showModels = false
    @State private var showSettings = false
    @State private var showTriggers = false
    @State private var showPeripherals = false
    @State private var module: AlienModule = {
        if let raw = ProcessInfo.processInfo.environment["ALIENMAC_MODULE"],
           let m = AlienModule(rawValue: raw) { return m }
        return .fx
    }()
    @State private var showDebug = false
    @State private var showSavePresetSheet = false
    /// 预设面板是二级 sheet，不能再往它上面弹 sheet，改成面板内联命名
    @State private var inlinePresetNaming = false
    @State private var importResult = ""
    @State private var showImportResult = false
    @State private var newPresetName = ""
    @State private var screenHoverPoint: CGPoint?
    @State private var showKeyMap = false
    @State private var showUpdate = false
    @StateObject private var updater = UpdateChecker()
    @StateObject private var gesture = HandGestureController.shared
    @StateObject private var voice = VoiceControlController.shared
    @StateObject private var schedule = ScheduleController.shared
    @StateObject private var ha = HomeAssistantBridge.shared

    @State private var showAddSchedule = false
    @State private var scheduleTime = Date()
    @State private var scheduleWeekdays: Set<Int> = []
    @State private var scheduleAction: ScheduleAction = .keyboardOff

    /// 3D 拆解（爆炸视图）
    @State private var exploded = false
    @State private var lidBeforeExplode = true

    var body: some View {
        ZStack {
            background

            GeometryReader { geo in
                LaptopSceneView(viewModel: viewModel, lidOpen: $lidOpen, pose: pose,
                                exploded: exploded,
                                onScreenHover: { screenHoverPoint = $0 })
                    .frame(width: max(320, geo.size.width - AppTheme.sceneInset),
                           height: max(240, geo.size.height - 150))
                    .overlay(alignment: .topLeading) { screenHoverCapsule(in: geo.size) }
                    .overlay(alignment: .bottom) {
                        // 场景区为了右侧面板整体左移了，这里右移半格让它落在窗口正中
                        cameraPill
                            .padding(.bottom, 8)
                            .offset(x: AppTheme.sceneInset / 2)
                    }
                    .overlay(alignment: .bottomLeading) {
                        if exploded {
                            explodeLegend
                                .padding(.bottom, 10)
                                .padding(.leading, 18)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                    .position(x: (geo.size.width - AppTheme.sceneInset) / 2,
                              y: 66 + (geo.size.height - 150) / 2)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                bottomBar
            }
            .padding(18)

            controlPanel
                .padding(.trailing, 18)
                .padding(.top, 74)
                .padding(.bottom, 88)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .frame(minWidth: 1140, minHeight: 780)
        .sheet(isPresented: $showPresets) { presetsSheet }
        .sheet(isPresented: $showModels) { AWCCModelLibraryView() }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .sheet(isPresented: $showTriggers) {
            TriggerSettingsView().environmentObject(viewModel)
        }
        .sheet(isPresented: $showPeripherals) { PeripheralPanel() }

        .onAppear {
            if ProcessInfo.processInfo.environment["ALIENMAC_SHEET"] == "peripherals" {
                showPeripherals = true
            }
        }
        .sheet(isPresented: $showDebug) { debugSheet }
        .sheet(isPresented: $showSavePresetSheet) { savePresetSheet }
        .sheet(isPresented: $showKeyMap) { keyMapSheet }
        .sheet(isPresented: $showUpdate) { updateSheet }
        .sheet(isPresented: $showAddSchedule) { addScheduleSheet }
        .onAppear {
            updater.checkOnLaunchIfNeeded()
            // 手机访问：开机即开服务，扫码就能用，不需要手动开关
            WebBridge.shared.bind(viewModel)
            WebBridge.shared.start()
        }
    }

    /// 鼠标悬停在模型屏幕上时跟随光标的胶囊提示
    private func screenHoverCapsule(in size: CGSize) -> some View {
        Group {
            if let point = screenHoverPoint {
                HStack(spacing: 7) {
                    Image(systemName: "cursorarrow.click.2")
                        .font(.system(size: 13 * AppTheme.fontScale, weight: .semibold))
                    Text("点击跳转作者博客")
                        .font(.system(size: 14 * AppTheme.fontScale, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .background(
                    Capsule().fill(Color(red: 0.10, green: 0.45, blue: 0.75).opacity(0.42))
                )
                .overlay(
                    Capsule().strokeBorder(Color.cyan.opacity(0.45), lineWidth: 0.8)
                )
                .shadow(color: Color.cyan.opacity(0.22), radius: 8, y: 3)
                .position(x: min(max(point.x, 88), max(size.width - 88, 88)),
                          y: max(point.y - 24, 18))
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.14), value: screenHoverPoint == nil)
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
                // 用 2 倍位图的高清版，不再把 18px 的小图硬放大；比例跟原图一致
                Image(nsImage: AppLogo.headerIcon)
                VStack(alignment: .leading, spacing: 1) {
                    Text("AlienMAC")
                        .font(.system(size: 18.5 * AppTheme.fontScale, weight: .semibold))
                    Text("Alienware \(viewModel.controller.model.shortName)")
                        .font(.system(size: 12.5 * AppTheme.fontScale))
                        .foregroundColor(.secondary)
                }
            }

            // 版本号在上、连接状态在下，竖着排成一列
            VStack(alignment: .leading, spacing: 4) {
                switch updater.state {
                case .available(let v, _, _, _):
                    updatePill(v)
                case .upToDate:
                    versionBadge(latest: true)
                case .checking:
                    versionBadge(latest: false)
                default:
                    versionBadge(latest: false)
                }
                statusBadge
            }

            Spacer()

            HStack(spacing: 8) {
                glassButton("触摸板", icon: "hand.point.up.left") { viewModel.selectTouchpadOnly() }
                glassButton("按键", icon: "keyboard") { showKeyMap = true }
                glassButton("预设", icon: "square.grid.2x2") { showPresets = true }
                glassButton("机型", icon: "laptopcomputer.and.arrow.down") { showModels = true }
                glassButton("手机", icon: "iphone") { MobileAccessWindow.shared.show() }
                glassButton("触发", icon: "bolt.badge.clock") { showTriggers = true }
                glassButton("外设", icon: "keyboard.badge.ellipsis") { showPeripherals = true }
                glassButton("设置", icon: "gearshape") { showSettings = true }
                glassButton("调试", icon: "waveform.path.ecg") { showDebug = true }
            }
        }
    }

    /// 顶部居中的视角胶囊（正面/俯视/后视 ｜ 合盖 拆解）
    private var cameraPill: some View {
            HStack(spacing: 2) {
                ForEach(ScenePose.allCases) { item in
                    Button {
                        pose = item
                    } label: {
                        Text(item.label)
                            .font(.system(size: 13 * AppTheme.fontScale, weight: .medium))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(
                                Capsule().fill(pose == item ? Color.white.opacity(0.18) : .clear)
                            )
                            .foregroundColor(pose == item ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }

                Rectangle().fill(Color.white.opacity(0.14))
                    .frame(width: 1, height: 16)
                    .padding(.horizontal, 4)

                Button {
                    lidOpen.toggle()
                } label: {
                    Text(lidOpen ? "合盖" : "开盖")
                        .font(.system(size: 13 * AppTheme.fontScale, weight: .medium))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Capsule().fill(lidOpen ? .clear : Color.white.opacity(0.18)))
                        .foregroundColor(lidOpen ? .secondary : .primary)
                }
                .buttonStyle(.plain)
                .help(lidOpen ? "合上顶盖" : "打开顶盖")

                Button {
                    // 拆解默认开盖：把顶盖状态一并同步，按钮文案才不会和实际顶盖状态打架
                    if !exploded {
                        lidBeforeExplode = lidOpen
                        lidOpen = true
                    } else {
                        lidOpen = lidBeforeExplode
                    }
                    exploded.toggle()
                } label: {
                    Text("拆解")
                        .font(.system(size: 13 * AppTheme.fontScale, weight: .medium))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Capsule().fill(exploded ? Color.cyan.opacity(0.26) : .clear))
                        .foregroundColor(exploded ? .cyan : .secondary)
                }
                .buttonStyle(.plain)
                .help("把灯区硬件炸开成可看的分层结构")
            }
            .padding(3)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    /// 顶栏版本号：没有新版时显示当前版本，已是最新时带个对勾。
    /// 点一下就是手动检查更新
    private func versionBadge(latest: Bool) -> some View {
        let checking = updater.state == .checking
        return Button {
            updater.check()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: checking ? "arrow.triangle.2.circlepath"
                      : (latest ? "checkmark.seal.fill" : "shippingbox.fill"))
                    .font(.system(size: 11.5 * AppTheme.fontScale, weight: .semibold))
                    .foregroundColor(checking ? .secondary
                                     : (latest ? Color(red: 0.3, green: 0.9, blue: 0.62) : .secondary))
                Text(checking ? "检查更新中…" : "v\(UpdateChecker.currentVersion)")
                    .font(.system(size: 13 * AppTheme.fontScale, weight: .medium,
                                  design: checking ? .default : .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(checking ? "正在检查更新" : "点击检查更新")
    }

    /// 顶栏「新版本」胶囊：跟在「已连接」后面，点开就是更新弹窗
    private func updatePill(_ version: String) -> some View {
        Button { showUpdate = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13 * AppTheme.fontScale, weight: .semibold))
                Text("新版本 v\(version)")
                    .font(.system(size: 13.5 * AppTheme.fontScale, weight: .semibold))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(LinearGradient(colors: [Color(red: 0.15, green: 0.85, blue: 1).opacity(0.30),
                                                      Color(red: 0.65, green: 0.35, blue: 1).opacity(0.30)],
                                              startPoint: .leading, endPoint: .trailing))
            )
            .overlay(Capsule().stroke(Color.cyan.opacity(0.55), lineWidth: 1))
            .shadow(color: Color.cyan.opacity(0.25), radius: 8)
        }
        .buttonStyle(.plain)
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.isConnected ? Color(red: 0.2, green: 0.95, blue: 0.6) : Color.red)
                .frame(width: 7, height: 7)
                .shadow(color: viewModel.isConnected ? .green : .red, radius: 4)
            Text(viewModel.isConnected ? "已连接" : "未连接")
                .font(.system(size: 13 * AppTheme.fontScale, weight: .medium))
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
                Image(systemName: icon).font(.system(size: 15.5 * AppTheme.fontScale, weight: .medium))
                Text(title).font(.system(size: 14 * AppTheme.fontScale, weight: .medium))
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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                moduleTabs
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 4)

                switch module {
                case .fx:
                    panelContent.padding(18)
                case .fusion:
                    FusionPanel()
                case .tactx:
                    TactXPanel().environmentObject(viewModel)
                case .adrenaline:
                    AdrenalinePanel(onManageTriggers: { showTriggers = true })
                        .environmentObject(viewModel)
                }
            }
        }
        .frame(width: AppTheme.panelWidth)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
        // 调色、次色、效果、速度、亮度：改动即写硬件，不用再点「应用」
        .onChange(of: viewModel.currentColor) { _ in viewModel.liveApply() }
        .onChange(of: viewModel.secondaryColor) { _ in viewModel.liveApply() }
        .onChange(of: viewModel.currentEffect) { _ in viewModel.liveApply() }
        .onChange(of: viewModel.tempo) { _ in viewModel.liveApply() }
        .onChange(of: viewModel.brightness) { _ in viewModel.onBrightnessChanged() }
    }

    /// 顶部四模块切换（AWCC 外壳）
    private var moduleTabs: some View {
        HStack(spacing: 5) {
            ForEach(AlienModule.allCases) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { module = item }
                } label: {
                    Text(item.shortTitle)
                        .font(.system(size: 10.5 * AppTheme.fontScale, weight: module == item ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                    .foregroundColor(module == item ? .primary : Color.secondary.opacity(0.75))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(module == item ? Color.white.opacity(0.14) : Color.white.opacity(0.045))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(module == item ? Color(red: 0, green: 0.82, blue: 1).opacity(0.6) : .clear,
                                    lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help(item.subtitle)
            }
        }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            HStack {
                Text("灯效编辑")
                    .font(.system(size: 15.5 * AppTheme.fontScale, weight: .semibold))
                Spacer()
                Text(selectionText)
                    .font(.system(size: 12.5 * AppTheme.fontScale))
                    .foregroundColor(.secondary)
            }

            if !viewModel.controller.hardwareControllable, let info = viewModel.controller.deviceInfo {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13 * AppTheme.fontScale))
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("已识别 \(info.model.name)")
                            .font(.system(size: 13 * AppTheme.fontScale, weight: .semibold))
                        Text("\(info.proto.rawValue) 协议与当前驱动不同，界面可预览，灯光暂不会下发。")
                            .font(.system(size: 12 * AppTheme.fontScale))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.10)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.orange.opacity(0.35), lineWidth: 1))
            }

            // 颜色
            HStack(spacing: 10) {
                ColorPicker("", selection: $viewModel.currentColor, supportsOpacity: false)
                    .labelsHidden()
                    .scaleEffect(0.85)
                VStack(alignment: .leading, spacing: 2) {
                    Text("主颜色").font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
                    Text(hexString(from: viewModel.currentColor))
                        .font(.system(size: 14 * AppTheme.fontScale, design: .monospaced))
                }
                Spacer()
            }

            // 效果
            VStack(alignment: .leading, spacing: 6) {
                Text("效果").font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(LightEffect.allCases) { effect in
                        Button {
                            viewModel.currentEffect = effect
                        } label: {
                            Text(effect.rawValue)
                                .font(.system(size: 13 * AppTheme.fontScale))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(viewModel.currentEffect == effect
                                              ? Color(red: 0.0, green: 0.82, blue: 1).opacity(0.22)
                                              : Color.white.opacity(0.05))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(viewModel.currentEffect == effect
                                                ? Color(red: 0.0, green: 0.82, blue: 1).opacity(0.75)
                                                : Color.white.opacity(0.08), lineWidth: 1)
                                )
                                .foregroundColor(viewModel.currentEffect == effect ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if viewModel.currentEffect.needsSecondaryColor {
                HStack(spacing: 10) {
                    ColorPicker("", selection: $viewModel.secondaryColor, supportsOpacity: false)
                        .labelsHidden()
                        .scaleEffect(0.85)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("次颜色").font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
                        Text(hexString(from: viewModel.secondaryColor))
                            .font(.system(size: 14 * AppTheme.fontScale, design: .monospaced))
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("速度").font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(viewModel.tempo)) ms").font(.system(size: 12 * AppTheme.fontScale, design: .monospaced)).foregroundColor(.secondary)
                    }
                    Slider(value: $viewModel.tempo, in: 500...8000, step: 250)
                }
            }

            if viewModel.isSoftwareEffect {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(viewModel.currentEffect == .spectrum ? "循环周期" : "扫过速度")
                            .font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(viewModel.tempo)) ms").font(.system(size: 12 * AppTheme.fontScale, design: .monospaced)).foregroundColor(.secondary)
                    }
                    Slider(value: $viewModel.tempo, in: 500...8000, step: 250)
                    Text(viewModel.currentEffect == .spectrum
                         ? "彩虹按灯区顺序绕一圈，14 个灯区同屏不同色。"
                         : (viewModel.currentEffect == .wave ? "亮带沿灯区顺序推过去，速度即一趟的时间。" : "一个灯区点亮后逐格移动，其余压暗。"))
                        .font(.system(size: 12 * AppTheme.fontScale)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // 亮度
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("亮度").font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(viewModel.brightness))%").font(.system(size: 12 * AppTheme.fontScale, design: .monospaced)).foregroundColor(.secondary)
                }
                Slider(value: $viewModel.brightness, in: 0...100)
            }

            if viewModel.selectedZones.contains(.touchpad) {
                touchpadDetail
            }

            Divider().opacity(0.4)

            // 操作
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10.5 * AppTheme.fontScale))
                        .foregroundColor(Color(red: 0, green: 0.82, blue: 1))
                    Text(viewModel.selectedKeys.isEmpty
                         ? (viewModel.selectedZones.isEmpty ? "调色即时生效 · 未选灯区时作用于全部" : "调色即时生效，无需再点应用")
                         : "单键上色 · 硬件按所在分区显示")
                        .font(.system(size: 12.5 * AppTheme.fontScale))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }

                if !viewModel.selectedKeys.isEmpty {
                    Button {
                        viewModel.clearKeyCustom()
                    } label: {
                        Label("清除单键配色", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 8) {
                    Button {
                        viewModel.applyToAll()
                    } label: {
                        Label("应用", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .help("把当前配色/效果应用到全部灯区并写入设置")

                    Button {
                        viewModel.cancelEdits()
                    } label: {
                        Text("取消").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.hasUnappliedEdits)
                    .help("放弃本轮未应用的改动，退回上次应用的状态")
                }

                HStack(spacing: 8) {
                    Button {
                        viewModel.undo()
                    } label: {
                        Label("撤销", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.canUndo)
                    .help("⌘Z 撤销上一步灯光改动")

                    Button {
                        viewModel.redo()
                    } label: {
                        Label("重做", systemImage: "arrow.uturn.forward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.canRedo)
                    .help("⇧⌘Z 重做下一步")

                    Button {
                        viewModel.toggleLights()
                    } label: {
                        Text(viewModel.isLightsOff ? "开灯" : "关灯").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                zoneActionSection

                Button {
                    newPresetName = suggestedPresetName
                    showSavePresetSheet = true
                } label: {
                    Label("存为预设", systemImage: "star")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                VStack(alignment: .leading, spacing: 8) {
                    Text("快捷主题")
                        .font(.system(size: 12.5 * AppTheme.fontScale, weight: .medium))
                        .foregroundColor(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                        GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        quickPresetChip(.alienBlue)
                        quickPresetChip(.cyberRed)
                        quickPresetChip(.matrixGreen)
                        quickPresetChip(.aurora)
                    }
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 7) {
                    Text("作者：RockJesus")
                        .font(.system(size: 12.5 * AppTheme.fontScale, weight: .medium))
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        linkButton("作者博客", icon: "globe", url: "https://rockjesus.cn")
                        linkButton("GitHub", icon: "chevron.left.forwardslash.chevron.right", url: "https://github.com/RockJesus")
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    /// 每区动作：AWCC 高级模式里“每区一行动作”的等价面板
    @ViewBuilder
    private var zoneActionSection: some View {
        if !viewModel.zoneActions.isEmpty || !viewModel.selectedZones.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("每区动作")
                        .font(.system(size: 12.5 * AppTheme.fontScale, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer(minLength: 0)
                    if !viewModel.zoneActions.isEmpty {
                        Button("清空") { viewModel.clearAllActions() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5 * AppTheme.fontScale))
                            .foregroundColor(Color.secondary.opacity(0.7))
                    }
                    Button {
                        viewModel.assignActionToSelected()
                    } label: {
                        Label("指派", systemImage: "plus.circle")
                            .font(.system(size: 11.5 * AppTheme.fontScale))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.cyan)
                    .disabled(viewModel.selectedZones.isEmpty)
                    .help("用当前配色/效果给选中灯区建立独立动作")
                }

                if viewModel.zoneActions.isEmpty {
                    Text(viewModel.selectedZones.isEmpty
                         ? "选中灯区后可单独指派效果，让它不再跟随全局"
                         : "点「指派」让 \(viewModel.selectedZones.count) 个选中灯区各跑自己的效果")
                        .font(.system(size: 11.5 * AppTheme.fontScale))
                        .foregroundColor(Color.secondary.opacity(0.55))
                        .lineLimit(2)
                } else {
                    ForEach(viewModel.zoneActionList) { action in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(action.primary.swiftUIColor)
                                .frame(width: 8, height: 8)
                            Text(action.zone.displayName)
                                .font(.system(size: 12 * AppTheme.fontScale))
                                .lineLimit(1)
                            Text(action.summary)
                                .font(.system(size: 11 * AppTheme.fontScale))
                                .foregroundColor(Color.secondary.opacity(0.7))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Button {
                                viewModel.toggleActionLoop(for: action.zone)
                            } label: {
                                Image(systemName: action.loop ? "repeat" : "repeat.1")
                                    .font(.system(size: 11 * AppTheme.fontScale))
                                    .foregroundColor(action.loop ? .cyan : Color.secondary.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .help(action.loop ? "循环执行" : "只执行一次后回到全局")
                            Button {
                                viewModel.removeAction(for: action.zone)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10 * AppTheme.fontScale))
                                    .foregroundColor(Color.secondary.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .help("删除该动作，回到跟随全局")
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// 右侧面板的快捷主题小胶囊
    private func quickPresetChip(_ preset: LightingPreset) -> some View {
        Button {
            viewModel.applyPreset(preset)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(LinearGradient(colors: [preset.primaryColor.opacity(0.95),
                                                  preset.primaryColor.opacity(0.45)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.6))
                Text(preset.rawValue)
                    .font(.system(size: 11.5 * AppTheme.fontScale, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(preset.primaryColor.opacity(0.28), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .help("应用「\(preset.rawValue)」主题")
    }

    /// 跳转外部网页的按钮：玻璃底 + 青紫渐变描边
    private func linkButton(_ title: String, icon: String, url: String) -> some View {
        Button {
            if let target = URL(string: url) { NSWorkspace.shared.open(target) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12.5 * AppTheme.fontScale, weight: .medium))
                Text(title).font(.system(size: 13 * AppTheme.fontScale, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().stroke(
                    LinearGradient(colors: [Color(red: 0.15, green: 0.85, blue: 1).opacity(0.45),
                                            Color(red: 0.65, green: 0.35, blue: 1).opacity(0.45)],
                                   startPoint: .leading, endPoint: .trailing),
                    lineWidth: 1)
            )
            .shadow(color: Color(red: 0.15, green: 0.85, blue: 1).opacity(0.15), radius: 6)
        }
        .buttonStyle(.plain)
        .help(url)
    }

    // MARK: - 触摸板细调

    private var touchpadDetail: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "hand.point.up.left")
                    .font(.system(size: 10.5 * AppTheme.fontScale))
                    .foregroundColor(Color(red: 0, green: 0.82, blue: 1))
                Text("触摸板细调")
                    .font(.system(size: 13 * AppTheme.fontScale, weight: .semibold))
                Spacer()
                Button("恢复默认") { viewModel.resetTouchpad() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12 * AppTheme.fontScale))
                    .foregroundColor(.secondary)
            }

            touchpadRow(title: "整面背光",
                        color: $viewModel.touchpad.padColor,
                        follows: $viewModel.touchpad.padFollowsZone,
                        value: $viewModel.touchpad.padBrightness,
                        valueLabel: "整面亮度")

            Divider().opacity(0.25)

            touchpadRow(title: "边光",
                        color: $viewModel.touchpad.edgeColor,
                        follows: $viewModel.touchpad.edgeFollowsZone,
                        value: $viewModel.touchpad.edgeBrightness,
                        valueLabel: "边光强度",
                        showEdgeToggle: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(red: 0, green: 0.82, blue: 1).opacity(0.22), lineWidth: 1)
        )
    }

    private func touchpadRow(title: String,
                             color: Binding<Color>,
                             follows: Binding<Bool>,
                             value: Binding<Double>,
                             valueLabel: String,
                             showEdgeToggle: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ColorPicker("", selection: color, supportsOpacity: false)
                .labelsHidden()
                .scaleEffect(0.8)
                .disabled(follows.wrappedValue)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Toggle("\(title)跟随灯区色", isOn: follows)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12.5 * AppTheme.fontScale))
                    if showEdgeToggle {
                        Toggle("显示", isOn: $viewModel.touchpad.edgeEnabled)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 12.5 * AppTheme.fontScale))
                    }
                }
                HStack {
                    Text(valueLabel).font(.system(size: 12 * AppTheme.fontScale)).foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(value.wrappedValue))%")
                        .font(.system(size: 12 * AppTheme.fontScale, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Slider(value: value, in: 0...100, step: 1)
            }
        }
    }

    // MARK: - 底部灯区栏

    private var bottomBar: some View {
        HStack(spacing: 12) {
            // 13 个灯区胶囊压成一行：宽度不够时横向滚动，不再折行
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(LightZone.allIndividual) { zone in
                        ZonePill(zone: zone,
                                 selected: viewModel.selectedZones.contains(zone),
                                 hovered: viewModel.hoveredZone == zone,
                                 color: viewModel.zoneColors[zone] ?? .black)
                        .onTapGesture { viewModel.toggleZone(zone) }
                        // 无障碍：把胶囊暴露成可操作的按钮，VoiceOver / 全键盘控制才能点选灯区
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(zone.displayName)
                        .accessibilityValue(viewModel.selectedZones.contains(zone) ? "已选择" : "未选择")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAddTraits(viewModel.selectedZones.contains(zone) ? .isSelected : [])
                        .accessibilityAction { viewModel.toggleZone(zone) }
                    }
                }
                .padding(.vertical, 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .help(statusLine + " · 拖动旋转 · 滚轮缩放 · 点按键上色 · 点屏幕开官网")

            if gesture.status.isRunning {
                HStack(spacing: 5) {
                    Image(systemName: "hand.raised.fill").font(.system(size: 12 * AppTheme.fontScale))
                    Text(gesture.handPresent ? "手势 · 已识别" : "手势开启")
                        .font(.system(size: 12 * AppTheme.fontScale))
                }
                .foregroundColor(gesture.handPresent ? .cyan : .secondary)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.white.opacity(0.06), in: Capsule())
                .fixedSize()
            }

            if ha.connected {
                HStack(spacing: 5) {
                    Image(systemName: "house.fill").font(.system(size: 12 * AppTheme.fontScale))
                    Text("HA · 已接入")
                        .font(.system(size: 12 * AppTheme.fontScale))
                }
                .foregroundColor(Color(red: 0.45, green: 0.85, blue: 1))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.white.opacity(0.06), in: Capsule())
                .fixedSize()
            }

            if voice.status.isRunning {
                HStack(spacing: 5) {
                    Image(systemName: "mic.fill").font(.system(size: 12 * AppTheme.fontScale))
                    Text(voice.lastText.isEmpty ? "语音 · 正在听" : "语音 · 已听到")
                        .font(.system(size: 12 * AppTheme.fontScale))
                }
                .foregroundColor(.cyan)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.white.opacity(0.06), in: Capsule())
                .fixedSize()
            }

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1, height: 18)

            HStack(spacing: 6) {
                Button("全选") { viewModel.selectedZones = Set(LightZone.allIndividual) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5 * AppTheme.fontScale))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.white.opacity(0.06), in: Capsule())
                Button("清空") {
                    viewModel.selectedZones.removeAll()
                    viewModel.selectedKeys.removeAll()
                }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5 * AppTheme.fontScale))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.white.opacity(0.06), in: Capsule())
            }
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .frame(maxWidth: .infinity)
    }

    // MARK: 拆解图例

    private var explodeLegendItems: [(String, Color)] {
        [("屏幕盖总成 · 外星头 / 屏幕 Logo", Color(red: 1.0, green: 0.30, blue: 0.55)),
         ("键盘背光 · 左 / 中 / 右 / 数字键", Color(red: 0.30, green: 1.0, blue: 0.45)),
         ("宏键区", Color(red: 1.0, green: 0.75, blue: 0.25)),
         ("触摸板整面 + 边光", Color(red: 0.30, green: 0.65, blue: 1.0)),
         ("电源键", Color(red: 1.0, green: 0.35, blue: 0.30)),
         ("前部灯带 L / R", Color(red: 0.30, green: 0.95, blue: 1.0)),
         ("后部灯带 L / R", Color(red: 0.65, green: 0.45, blue: 1.0))]
    }

    private var explodeLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("3D 拆解 · 灯光硬件")
                .font(.system(size: 12.5 * AppTheme.fontScale, weight: .semibold))
                .foregroundColor(.cyan)
            ForEach(Array(explodeLegendItems.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Circle().fill(item.1).frame(width: 6, height: 6)
                    Text(item.0)
                        .font(.system(size: 12 * AppTheme.fontScale))
                        .foregroundColor(.white.opacity(0.82))
                }
            }
            Text("拖动旋转 · 滚轮缩放，退出点顶栏视角组的「拆解」")
                .font(.system(size: 10.5 * AppTheme.fontScale))
                .foregroundColor(.white.opacity(0.45))
                .padding(.top, 2)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var statusLine: String {
        if let key = viewModel.hoveredKey { return KeyboardCatalog.displayName(for: key) }
        if let zone = viewModel.hoveredZone { return zone.displayName }
        if !viewModel.selectedKeys.isEmpty { return "已选 \(viewModel.selectedKeys.count) 个按键" }
        if viewModel.selectedZones.isEmpty { return "点灯区或单个按键进行多选" }
        return "已选 \(viewModel.selectedZones.count) 个灯区"
    }

    private var selectionText: String {
        if !viewModel.selectedKeys.isEmpty {
            return viewModel.selectedKeys.count == 1
                ? KeyboardCatalog.displayName(for: viewModel.selectedKeys.first ?? "")
                : "\(viewModel.selectedKeys.count) 个按键"
        }
        let count = viewModel.selectedZones.count
        if count == 0 { return "未选择" }
        if count == 1 { return viewModel.selectedZones.first?.numberedName ?? "1 个" }
        return "\(count) 个灯区"
    }

    // MARK: - 键盘按键映射

    private var keyMapSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("键盘按键映射")
                    .font(.system(size: 17.5 * AppTheme.fontScale, weight: .semibold))
                Spacer()
                Text(viewModel.selectedKeys.isEmpty ? "未选按键" : "已选 \(viewModel.selectedKeys.count) 个按键")
                    .font(.system(size: 13 * AppTheme.fontScale))
                    .foregroundColor(.secondary)
                Button("关闭") { showKeyMap = false }
                    .keyboardShortcut(.cancelAction)
            }

            Text("点按键选中，再用左侧主颜色上色（选中即写为当前色）。17 R4 硬件只有 4 区背光，下发时取该区出现最多的颜色。")
                .font(.system(size: 13 * AppTheme.fontScale))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    keyRowGroup(title: "主键区")
                    HStack(alignment: .top, spacing: 26) {
                        VStack(alignment: .leading, spacing: 8) {
                            groupTitle("数字键盘")
                            VStack(spacing: 4) {
                                ForEach(0..<5, id: \.self) { row in
                                    HStack(spacing: 4) {
                                        ForEach(0..<4, id: \.self) { col in
                                            keyChip("num-r\(row)c\(col)")
                                        }
                                    }
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            groupTitle("导航键")
                            VStack(spacing: 4) {
                                ForEach(0..<3, id: \.self) { index in
                                    keyChip("nav-\(index)")
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            groupTitle("宏键")
                            VStack(spacing: 4) {
                                ForEach(0..<5, id: \.self) { index in
                                    keyChip("macro-\(index)", width: 26, height: 20)
                                }
                            }
                        }
                        Spacer()
                    }

                    keymapZoneLegend
                }
                .padding(.vertical, 4)
            }

            Divider().opacity(0.4)

            HStack(spacing: 10) {
                Button {
                    viewModel.liveApply()
                } label: {
                    Label("用主颜色填充", systemImage: "paintbrush.fill")
                }
                .disabled(viewModel.selectedKeys.isEmpty)

                Button {
                    viewModel.clearKeyCustom()
                } label: {
                    Label("清除单键配色", systemImage: "arrow.uturn.backward")
                }
                .disabled(viewModel.selectedKeys.isEmpty)

                Spacer()

                Button("全不选") { viewModel.selectedKeys.removeAll() }
                    .disabled(viewModel.selectedKeys.isEmpty)
                Button("关闭") { viewModel.selectedKeys.removeAll(); showKeyMap = false }
            }
        }
        .padding(20)
        .frame(width: 740, height: 620)
    }

    private func groupTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13 * AppTheme.fontScale, weight: .semibold))
            .foregroundColor(.secondary)
    }

    private func keyRowGroup(title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            groupTitle(title)
            VStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(0..<14, id: \.self) { col in
                            if row == 4 && col >= 4 && col <= 6 {
                                Spacer().frame(width: 32, height: 24)
                            } else {
                                keyChip("main-r\(row)c\(col)")
                            }
                        }
                    }
                }
            }
        }
    }

    /// 按键弹窗底部的硬件分区说明（4 区背光的实际落点）
    private var keymapZoneLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("硬件背光分区")
                .font(.system(size: 13 * AppTheme.fontScale, weight: .semibold))
            HStack(spacing: 10) {
                ForEach([LightZone.keyboardLeft, .keyboardMidLeft, .keyboardMidRight, .keyboardRight]) { zone in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.zoneColors[zone] ?? .black)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.6))
                        Text(zone.displayName)
                            .font(.system(size: 11.5 * AppTheme.fontScale))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.05), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.09), lineWidth: 0.8))
                }
            }
        }
        .padding(.top, 4)
    }

    /// AWCC 风格预设色板
    static let awccPalette: [(name: String, color: Color)] = [
        ("白", Color(white: 1.0)),
        ("冰蓝", Color(red: 0.42, green: 0.86, blue: 1.0)),
        ("青", Color(red: 0.0, green: 0.82, blue: 1.0)),
        ("蓝", Color(red: 0.0, green: 0.45, blue: 1.0)),
        ("靛蓝", Color(red: 0.28, green: 0.2, blue: 0.95)),
        ("紫", Color(red: 0.55, green: 0.0, blue: 1.0)),
        ("品红", Color(red: 1.0, green: 0.0, blue: 0.72)),
        ("粉", Color(red: 1.0, green: 0.36, blue: 0.62)),
        ("红", Color(red: 1.0, green: 0.11, blue: 0.13)),
        ("橙", Color(red: 1.0, green: 0.42, blue: 0.0)),
        ("琥珀", Color(red: 1.0, green: 0.66, blue: 0.0)),
        ("黄", Color(red: 1.0, green: 0.9, blue: 0.0)),
        ("青柠", Color(red: 0.55, green: 1.0, blue: 0.0)),
        ("绿", Color(red: 0.1, green: 1.0, blue: 0.25)),
        ("青绿", Color(red: 0.0, green: 1.0, blue: 0.6)),
        ("暖白", Color(red: 1.0, green: 0.88, blue: 0.72))
    ]

    private func keyChip(_ id: String, width: CGFloat = 32, height: CGFloat = 24) -> some View {
        let selected = viewModel.selectedKeys.contains(id)
        let color = viewModel.keyDisplayColor(id)
        return Button {
            viewModel.toggleKey(id)
        } label: {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.62)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: width, height: height)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(selected ? Color.cyan : Color.white.opacity(0.10),
                                lineWidth: selected ? 1.8 : 0.8)
                )
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.22))
                        .frame(height: 1.5)
                        .padding(.horizontal, 4)
                        .padding(.top, 1)
                }
                .shadow(color: selected ? color.opacity(0.75) : .black.opacity(0.28),
                        radius: selected ? 6 : 2, y: selected ? 0 : 1)
        }
        .buttonStyle(.plain)
        .help(KeyboardCatalog.displayName(for: id))
        .accessibilityLabel(KeyboardCatalog.displayName(for: id))
    }

    // MARK: - 预设弹窗

    private var presetsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("预设主题").font(.system(size: 17.5 * AppTheme.fontScale, weight: .semibold))
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
                        Text("AWCC 自带主题").font(.system(size: 15.5 * AppTheme.fontScale, weight: .semibold))
                        Spacer()
                        Text("\(viewModel.awccThemes.count) 套官方预置 · 来自机型资源")
                            .font(.system(size: 12 * AppTheme.fontScale))
                            .foregroundStyle(.secondary)
                    }

                    if viewModel.awccThemes.isEmpty {
                        Text("没读到 awcc-catalog.json，机型资源没有打进包里。")
                            .font(.system(size: 14 * AppTheme.fontScale)).foregroundColor(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                            ForEach(viewModel.awccThemes) { theme in
                                Button {
                                    _ = viewModel.applyAWCCBuiltInTheme(theme)
                                } label: {
                                    AWCCThemeTile(theme: theme)
                                }
                                .buttonStyle(.plain)
                                .help("把「\(theme.name)」压成每区动作后下发")
                            }
                        }
                    }

                    Divider()

                    HStack {
                        Text("我的预设").font(.system(size: 15.5 * AppTheme.fontScale, weight: .semibold))
                        Spacer()
                        Button {
                            importATHThemeFile()
                        } label: {
                            Label("导入 .ath", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                        .help("读取 AWCC 保存的主题文件，把每区配色搬过来")
                        Button {
                            newPresetName = suggestedPresetName
                            inlinePresetNaming = true
                        } label: {
                            Label("保存当前", systemImage: "plus.circle")
                        }
                        .buttonStyle(.bordered)
                    }

                    if inlinePresetNaming {
                        HStack(spacing: 8) {
                            Text("范围：\(selectedZoneDescription)")
                                .font(.system(size: 13 * AppTheme.fontScale))
                                .foregroundColor(.secondary)
                            TextField("预设名称", text: $newPresetName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { commitInlinePreset() }
                            Button("取消") { inlinePresetNaming = false }
                            Button("保存") { commitInlinePreset() }
                                .buttonStyle(.borderedProminent)
                                .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(.vertical, 4)
                    }

                    if viewModel.customPresets.isEmpty {
                        Text("还没有自定义预设。调好颜色和效果后点“保存当前”。")
                            .font(.system(size: 14 * AppTheme.fontScale)).foregroundColor(.secondary)
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
        .frame(width: 720, height: 620)
        .alert(importResult, isPresented: $showImportResult) {
            Button("好", role: .cancel) {}
        }
    }

    /// 选一个 .ath 文件并导入
    private func importATHThemeFile() {
        let panel = NSOpenPanel()
        panel.title = "选择 AWCC 主题"
        panel.prompt = "导入"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let type = UTType(filenameExtension: "ath") {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importResult = viewModel.importATHTheme(url: url)
        showImportResult = true
    }

    // MARK: - 更新

    private var updateButtonTitle: String {
        if updater.state == .checking { return "检查中…" }
        return "检查更新"
    }

    @ViewBuilder
    private var updateStatusLine: some View {
        switch updater.state {
        case .idle:
            Text("尚未检查").font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("正在向 GitHub 查询最新版本…").font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
            }
        case .upToDate(let latest):
            Label("已是最新版本（GitHub 最新 v\(latest)）", systemImage: "checkmark.circle.fill")
                .font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(Color(red: 0.3, green: 0.9, blue: 0.55))
        case .available(let v, _, _, _):
            Label("发现新版本 v\(v)", systemImage: "arrow.down.circle.fill")
                .font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.cyan)
        case .failed(let msg):
            Label("检查失败：\(msg)", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.orange)
        }
    }

    @ViewBuilder
    private func noteLine(_ raw: String) -> some View {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty {
            EmptyView()
        } else if line.hasPrefix("### ") {
            Text(line.dropFirst(4)).font(.system(size: 14 * AppTheme.fontScale, weight: .semibold)).padding(.top, 2)
        } else if line.hasPrefix("## ") {
            Text(line.dropFirst(3)).font(.system(size: 15.5 * AppTheme.fontScale, weight: .bold)).padding(.top, 2)
        } else if line.hasPrefix("# ") {
            Text(line.dropFirst(2)).font(.system(size: 15.5 * AppTheme.fontScale, weight: .bold))
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 6) {
                Text("•").font(.system(size: 14 * AppTheme.fontScale)).foregroundColor(.cyan)
                Text(line.dropFirst(2)).font(.system(size: 14 * AppTheme.fontScale))
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(line).font(.system(size: 14 * AppTheme.fontScale))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var updateSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("发现新版本").font(.system(size: 17.5 * AppTheme.fontScale, weight: .semibold))
                    if case .available(let v, _, _, _) = updater.state {
                        Text("v\(v) · 当前 \(UpdateChecker.currentVersion)")
                            .font(.system(size: 13 * AppTheme.fontScale, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button("关闭") { showUpdate = false }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if case .available(_, let notes, _, _) = updater.state {
                        if notes.isEmpty {
                            Text("这个版本没有附带更新说明。")
                                .font(.system(size: 14 * AppTheme.fontScale)).foregroundColor(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 7) {
                                ForEach(Array(notes.components(separatedBy: "\n").enumerated()), id: \.offset) { _, raw in
                                    noteLine(raw)
                                }
                            }
                        }
                    } else {
                        Text("暂时没有可用的更新信息，可以到 Release 页面看看。")
                            .font(.system(size: 14 * AppTheme.fontScale)).foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.045)))
                .padding(.horizontal, 22)
            }

            if updater.isInstalling || updater.installError != nil {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text(updater.installStage)
                            .font(.system(size: 12.5 * AppTheme.fontScale, weight: .medium))
                            .foregroundColor(updater.installError == nil ? .secondary : Color(red: 1, green: 0.45, blue: 0.42))
                        Spacer()
                        Text("\(Int(updater.installProgress * 100))%")
                            .font(.system(size: 12 * AppTheme.fontScale, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    ProgressView(value: updater.installProgress)
                        .progressViewStyle(.linear)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 10)
            }

            HStack(spacing: 10) {
                Button("打开发布页") { updater.openReleasePage() }
                Button("下载 dmg 到浏览器") { updater.openDownloadPage() }
                Spacer()
                Button("稍后") { showUpdate = false }
                    .disabled(updater.isInstalling)
                Button {
                    updater.installUpdate()
                } label: {
                    Label(updater.isInstalling ? "正在更新…" : "立即更新",
                          systemImage: updater.isInstalling ? "arrow.triangle.2.circlepath" : "arrow.down.circle.fill")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(updater.isInstalling)
            }
            .padding(22)
        }
        .frame(width: 630, height: 520)
    }

    // MARK: - 设置弹窗

    private var addScheduleSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("添加定时任务").font(.system(size: 17.5 * AppTheme.fontScale, weight: .semibold))
                Spacer()
                Button("取消") { showAddSchedule = false }
                    .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 12) {
                Text("时间").frame(width: 48, alignment: .leading)
                DatePicker("", selection: $scheduleTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.stepperField)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("重复").font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { bit in
                        let names = ["日", "一", "二", "三", "四", "五", "六"]
                        Button {
                            if scheduleWeekdays.contains(bit) { scheduleWeekdays.remove(bit) }
                            else { scheduleWeekdays.insert(bit) }
                        } label: {
                            Text(names[bit])
                                .font(.system(size: 13 * AppTheme.fontScale, weight: .medium))
                                .frame(width: 30, height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(scheduleWeekdays.contains(bit)
                                              ? Color(red: 0.0, green: 0.82, blue: 1).opacity(0.22)
                                              : Color.white.opacity(0.05))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(scheduleWeekdays.contains(bit)
                                                ? Color(red: 0.0, green: 0.82, blue: 1).opacity(0.7)
                                                : Color.white.opacity(0.08), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(scheduleWeekdays.isEmpty ? "不选＝每天" : "只在选中的星期执行")
                    .font(.system(size: 12 * AppTheme.fontScale)).foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Text("动作").frame(width: 48, alignment: .leading)
                Picker("", selection: $scheduleAction) {
                    ForEach(ScheduleAction.allCases) { action in
                        Text(action.rawValue).tag(action)
                    }
                }
                .labelsHidden()
                Spacer()
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("添加") {
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: scheduleTime)
                    let mask = scheduleWeekdays.reduce(0) { $0 | (1 << $1) }
                    schedule.add(ScheduleRule(hour: comps.hour ?? 23,
                                              minute: comps.minute ?? 0,
                                              weekdayMask: mask,
                                              action: scheduleAction))
                    showAddSchedule = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 505, height: 370)
    }

    private var settingsSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("设置").font(.system(size: 17.5 * AppTheme.fontScale, weight: .semibold))
                Spacer()
                Button("关闭") { showSettings = false }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    settingSection(title: "机型与协议", icon: "laptopcomputer") {
                        if let info = viewModel.controller.deviceInfo {
                            InfoRow(label: "机型", value: viewModel.controller.model.name
                                    + (viewModel.controller.manualModelID == nil ? "（自动识别）" : "（手动指定）"))
                            InfoRow(label: "设备", value: info.productName)
                            InfoRow(label: "VID / PID", value: "0x\(String(format: "%04X", info.vendorID)) / 0x\(String(format: "%04X", info.productID))")
                            InfoRow(label: "协议", value: "\(info.proto.rawValue) · \(info.outputReportSize) 字节报文")
                            InfoRow(label: "灯区", value: viewModel.controller.model.zoneDescription)
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(info.proto.supportsControl ? Color(red: 0.2, green: 0.95, blue: 0.6) : Color.orange)
                                    .frame(width: 7, height: 7)
                                Text(info.proto.supportsControl ? "可直接控制灯光" : "已识别，协议暂未接入控制")
                                    .font(.system(size: 13 * AppTheme.fontScale))
                                    .foregroundColor(info.proto.supportsControl ? Color(red: 0.3, green: 0.9, blue: 0.55) : .orange)
                            }
                        } else {
                            Text("未检测到灯控设备，接上 Alienware 后会自动识别。")
                                .font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
                        }

                        HStack(spacing: 10) {
                            Text("机型").frame(width: 54, alignment: .leading)
                            Picker("", selection: Binding(
                                get: { viewModel.controller.manualModelID ?? "auto" },
                                set: { viewModel.controller.selectModel($0 == "auto" ? nil : $0) }
                            )) {
                                Text("自动识别").tag("auto")
                                ForEach(AlienwareCatalog.models) { item in
                                    Text("\(item.name) · \(item.protocol.rawValue)").tag(item.id)
                                }
                            }
                            .labelsHidden()
                            Spacer()
                            Button("重新检测") { viewModel.controller.redetect() }
                        }
                        Text("按设备产品名与 USB 报文长度自动判断机型与协议；识别不准时可手动指定。当前驱动覆盖 APIv3（12 字节报文，17 R4 实测 13 个灯区），APIv2 / APIv4 / APIv5 机型会被正确识别但暂不下发灯光，避免发错协议。")
                            .font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    settingSection(title: "手势旋转", icon: "hand.raised") {
                        Toggle("用摄像头手势旋转 3D 机型", isOn: $gesture.enabled)
                        HStack(spacing: 8) {
                            Circle()
                                .fill(gesture.status.isRunning ? Color(red: 0.2, green: 0.95, blue: 0.6) : Color.white.opacity(0.25))
                                .frame(width: 7, height: 7)
                            Text(gesture.status.label)
                                .font(.system(size: 13 * AppTheme.fontScale))
                                .foregroundColor(gesture.status.isRunning ? Color(red: 0.3, green: 0.9, blue: 0.55) : .secondary)
                            if gesture.status.isRunning {
                                Text(gesture.handPresent ? "已识别到手掌" : "等待手掌入镜")
                                    .font(.system(size: 13 * AppTheme.fontScale))
                                    .foregroundColor(gesture.handPresent ? .cyan : .secondary)
                            }
                        }
                        if gesture.status == .denied {
                            Button("打开摄像头权限设置") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .font(.system(size: 13 * AppTheme.fontScale))
                            .buttonStyle(.link)
                        }
                        HStack {
                            Text("灵敏度").frame(width: 64, alignment: .leading)
                            Slider(value: $gesture.sensitivity, in: 0.5...2.0, step: 0.1)
                            Text(String(format: "%.1fx", gesture.sensitivity))
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 44, alignment: .trailing)
                        }
                        Text("手掌对着摄像头左右移动＝绕机身转，上下移动＝调俯仰，方向和鼠标拖动一致；灵敏度越高，手移动同样距离转得越多。画面只在本机做识别，不保存、不上传。")
                            .font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    settingSection(title: "语音控制", icon: "mic") {
                        Toggle("用语音控制灯光", isOn: $voice.enabled)
                        HStack(spacing: 8) {
                            Circle()
                                .fill(voice.status.isRunning ? Color(red: 0.2, green: 0.95, blue: 0.6) : Color.white.opacity(0.25))
                                .frame(width: 7, height: 7)
                            Text(voice.status.label)
                                .font(.system(size: 13 * AppTheme.fontScale))
                                .foregroundColor(voice.status.isRunning ? Color(red: 0.3, green: 0.9, blue: 0.55) : .secondary)
                            Spacer()
                        }
                        if voice.status.isRunning {
                            Text(voice.lastText.isEmpty ? "等你说话，试试「关闭键盘灯」" : "听到：\(voice.lastText)")
                                .font(.system(size: 13 * AppTheme.fontScale))
                                .foregroundColor(voice.lastText.isEmpty ? .secondary : .cyan)
                                .lineLimit(2)
                        }
                        if voice.status == .denied {
                            HStack(spacing: 10) {
                                Button("打开麦克风权限") {
                                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .buttonStyle(.link).font(.system(size: 13 * AppTheme.fontScale))
                                Button("打开语音识别权限") {
                                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .buttonStyle(.link).font(.system(size: 13 * AppTheme.fontScale))
                            }
                        }
                        Text("口令：关闭键盘灯 / 打开键盘灯 / 关灯 / 开灯 / 亮一点 / 暗一点 / 光谱·光波·扫描·呼吸·脉冲·渐变·常亮。音频只在本机识别，不保存不上传；Siri 与快捷指令里也有「关闭键盘灯」等动作。")
                            .font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    settingSection(title: "定时任务", icon: "clock") {
                        Toggle("按设定时间自动执行", isOn: $schedule.masterEnabled)
                        if schedule.rules.isEmpty {
                            Text("还没有定时任务。添加一条，例如「每天 23:00 关闭键盘灯」。")
                                .font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
                        } else {
                            ForEach(schedule.rules) { rule in
                                HStack(spacing: 10) {
                                    Text(rule.timeText)
                                        .font(.system(size: 15.5 * AppTheme.fontScale, weight: .medium, design: .monospaced))
                                        .frame(width: 50, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(rule.action.rawValue).font(.system(size: 14 * AppTheme.fontScale))
                                        Text(rule.repeatText).font(.system(size: 12 * AppTheme.fontScale)).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { rule.enabled },
                                        set: { schedule.setEnabled($0, for: rule) }
                                    ))
                                    .labelsHidden()
                                    .scaleEffect(0.8)
                                    Button {
                                        schedule.remove(rule)
                                    } label: {
                                        Image(systemName: "trash").font(.system(size: 13 * AppTheme.fontScale))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(.secondary)
                                }
                            }
                        }
                        HStack(spacing: 10) {
                            Button {
                                scheduleTime = Date()
                                scheduleWeekdays = []
                                scheduleAction = .keyboardOff
                                showAddSchedule = true
                            } label: {
                                Label("添加定时", systemImage: "plus")
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                            if !schedule.lastFiredText.isEmpty {
                                Text("最近触发 \(schedule.lastFiredText)")
                                    .font(.system(size: 12 * AppTheme.fontScale)).foregroundColor(.secondary)
                            }
                        }
                        Text("到点由应用直接下发；同一分钟只触发一次。应用需保持运行，可在「启动」里设为开机自启。")
                            .font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    settingSection(title: "接入 Home Assistant", icon: "house") {
                        Toggle("通过 MQTT 接入 HAOS（自动发现两盏灯）", isOn: $ha.enabled)
                        HStack(spacing: 8) {
                            Text("主机").frame(width: 52, alignment: .leading)
                            TextField("MQTT 主机，如 homeassistant.local", text: $ha.host)
                                .textFieldStyle(.roundedBorder)
                            Text("端口").font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
                            TextField("1883", text: $ha.port)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 64)
                        }
                        HStack(spacing: 8) {
                            Text("用户名").frame(width: 52, alignment: .leading)
                            TextField("MQTT 账号", text: $ha.username)
                                .textFieldStyle(.roundedBorder)
                            Text("密码").font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
                            SecureField("", text: $ha.password)
                                .textFieldStyle(.roundedBorder)
                        }
                        HStack(spacing: 8) {
                            Text("前缀").frame(width: 52, alignment: .leading)
                            TextField("alienmac", text: $ha.topicPrefix)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                            Spacer()
                            Button("重连") { ha.reconnect() }
                                .buttonStyle(.bordered)
                        }
                        HStack(spacing: 8) {
                            Circle()
                                .fill(ha.connected ? Color(red: 0.2, green: 0.95, blue: 0.6) : Color.white.opacity(0.25))
                                .frame(width: 7, height: 7)
                            Text(ha.status)
                                .font(.system(size: 13 * AppTheme.fontScale))
                                .foregroundColor(ha.connected ? Color(red: 0.3, green: 0.9, blue: 0.55) : .secondary)
                            Spacer()
                            if !ha.lastCommandText.isEmpty {
                                Text("HA 命令 \(ha.lastCommandText)")
                                    .font(.system(size: 12 * AppTheme.fontScale)).foregroundColor(.secondary).lineLimit(1)
                            }
                        }
                        Text("先在 HA 的 Mosquitto broker 加载项里建账号（或直接用现有 MQTT 账号），把主机、端口、用户名密码填这里。连上后 HA 会自动发现「AlienMAC 键盘灯」和「AlienMAC 整机灯」两盏带 RGB 调色、亮度与灯效的灯；在 HA 里开关/调色会实时下发到机器，机器状态也会回报 HA。")
                            .font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    settingSection(title: "启动", icon: "power") {
                        Toggle("启动应用时下发上次灯光配置", isOn: $viewModel.restoreOnLaunch)
                        Text("默认开启：连上控制器就按上次的灯区、颜色、效果和速度重刷一遍。就绪序列里抓包带来的紫色配色帧已跳过，所以不会先闪一下再变色；关掉后 app 完全不动灯光，设备会停在自身保存的状态（一般是灭灯）。")
                            .font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
                    }

                    settingSection(title: "登录项", icon: "person.badge.clock") {
                        Toggle("登录 macOS 时自动启动 AlienMAC", isOn: $viewModel.launchAtLogin)
                        HStack(spacing: 8) {
                            Text("当前状态：\(LaunchAtLogin.statusDescription)")
                                .font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
                            Button("打开登录项设置") {
                                LaunchAtLogin.openSystemSettings()
                            }
                            .font(.system(size: 13 * AppTheme.fontScale))
                            .buttonStyle(.link)
                        }
                        if let error = viewModel.loginError {
                            Text(error)
                                .font(.system(size: 13 * AppTheme.fontScale))
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

                    settingSection(title: "预设颜色", icon: "paintpalette") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                            ForEach(Array(Self.awccPalette.enumerated()), id: \.offset) { _, entry in
                                Button {
                                    viewModel.applyPresetColor(entry.color)
                                } label: {
                                    Circle()
                                        .fill(entry.color)
                                        .frame(height: 22)
                                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .help(entry.name)
                            }
                        }
                        Text("AWCC 那套预设颜色：点一下直接刷到当前灯区（选了单键时刷到这些键）。")
                            .font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
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
                            .font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
                    }

                    settingSection(title: "开机键", icon: "power.circle") {
                        HStack(spacing: 10) {
                            Text("单击（点 3D 电源键）").frame(width: 150, alignment: .leading)
                            Picker("", selection: $viewModel.powerButton.clickAction) {
                                ForEach(SettingsStore.PowerAction.allCases) { action in
                                    Text(action.title).tag(action)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 220)
                        }
                        HStack(spacing: 10) {
                            Text("双击").frame(width: 150, alignment: .leading)
                            Picker("", selection: $viewModel.powerButton.doubleClickAction) {
                                ForEach(SettingsStore.PowerAction.allCases) { action in
                                    Text(action.title).tag(action)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 220)
                        }
                        HStack(spacing: 10) {
                            Text("长按 1.2 秒").frame(width: 150, alignment: .leading)
                            Picker("", selection: $viewModel.powerButton.holdAction) {
                                ForEach(SettingsStore.PowerAction.allCases) { action in
                                    Text(action.title).tag(action)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 220)
                        }
                        Toggle("重启 / 关机前弹窗二次确认", isOn: $viewModel.powerButton.confirmDangerous)
                        Text("单击默认只选中灯区上色；给双击或长按挑一个系统动作就能把电源键当快捷开关用。单击与双击互斥，设了其中一个，另一个会自动回到无动作。")
                            .font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Divider().padding(.vertical, 2)
                        Toggle("电源键灯效跟随灯区颜色", isOn: $viewModel.powerButton.lightFollowsZone)
                        HStack(spacing: 10) {
                            ColorPicker("颜色", selection: $viewModel.powerButton.lightColor, supportsOpacity: false)
                                .frame(width: 108, alignment: .leading)
                                .disabled(viewModel.powerButton.lightFollowsZone)
                            Slider(value: $viewModel.powerButton.lightBrightness, in: 0...100, step: 5)
                            Text("\(Int(viewModel.powerButton.lightBrightness.rounded()))%")
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 40, alignment: .trailing)
                        }
                        Text("外圈光与外星人头图标以该亮度点亮，0% 即熄灭。")
                            .font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
                    }

                    settingSection(title: "版本更新", icon: "arrow.triangle.2.circlepath") {
                        Toggle("启动时自动检查更新（12 小时一次）", isOn: $updater.autoCheckEnabled)
                        HStack(spacing: 10) {
                            Text("当前版本").font(.system(size: 14 * AppTheme.fontScale))
                            Text(AppInfo.version)
                                .font(.system(size: 14 * AppTheme.fontScale, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button {
                                updater.check()
                            } label: {
                                Text(updateButtonTitle)
                            }
                            .disabled(updater.state == .checking)
                        }
                        updateStatusLine
                        Text("检查 GitHub 上 RockJesus/AlienMAC 的最新 Release，有新版时顶栏会出现提示，可直接下载 dmg。")
                            .font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
                    }

                    settingSection(title: "关于", icon: "info.circle") {
                        InfoRow(label: "应用", value: "AlienMAC")
                        InfoRow(label: "版本", value: AppInfo.version)
                        InfoRow(label: "支持机型", value: "Alienware 17 R4 (424 × 332 × 30 mm)")
                        InfoRow(label: "数据目录", value: "~/Library/Application Support/AlienMAC")
                        HStack(spacing: 8) {
                            linkButton("作者博客", icon: "globe", url: "https://rockjesus.cn")
                            linkButton("GitHub", icon: "chevron.left.forwardslash.chevron.right", url: "https://github.com/RockJesus")
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(22)
            }
        }
        .frame(width: 620, height: 640)

    }

    private func settingSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.system(size: 15.5 * AppTheme.fontScale, weight: .semibold))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.045)))
    }

    private func shortcutRow(_ keys: String, _ description: String) -> some View {
        HStack(spacing: 10) {
            Text(keys)
                .font(.system(size: 13 * AppTheme.fontScale, weight: .medium))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
            Text(description).font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
        }
    }

    // MARK: - 调试弹窗

    /// 日志始终跟到最新一行
    private func scrollLogToBottom(_ proxy: ScrollViewProxy) {
        guard let last = fx.logMessages.indices.last else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(last, anchor: .bottom)
        }
    }

    private var debugSheet: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("HID 通信日志").font(.system(size: 17.5 * AppTheme.fontScale, weight: .semibold))
                if viewModel.manualTestIndex >= 0,
                   LightZone.orderedHardware.indices.contains(viewModel.manualTestIndex) {
                    Text("手动 \(viewModel.manualTestIndex + 1)/\(LightZone.orderedHardware.count) \(LightZone.orderedHardware[viewModel.manualTestIndex].displayName)")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.green)
                }
                Spacer(minLength: 8)
                Button(viewModel.isTestingZones ? "停止测试" : "逐灯测试") {
                    viewModel.isTestingZones ? viewModel.stopZoneTest() : viewModel.startZoneTest()
                }
                .tint(viewModel.isTestingZones ? .red : .orange)
                Button("下一个灯区") { viewModel.manualNextZone() }
                .tint(.orange)
                .help("点一次亮下一个灯区，跑完一圈从头开始")
                if viewModel.manualTestIndex >= 0 {
                    Button("恢复配色") { viewModel.endManualZoneTest() }
                        .tint(.blue)
                }
                Button("重新扫描") { viewModel.rescan() }
                Button("重置控制器") { viewModel.resetController() }
                Button("清空日志") { viewModel.controller.clearLog() }
                Button("关闭") { showDebug = false }.keyboardShortcut(.cancelAction)
            }
            .padding(18)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(fx.logMessages.enumerated()), id: \.offset) { index, msg in
                            Text(msg)
                                .font(.system(size: 12 * AppTheme.fontScale, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(14)
                }
                .onAppear { scrollLogToBottom(proxy) }
                .onChange(of: fx.logMessages.count) { _ in scrollLogToBottom(proxy) }
            }

            Divider()

            HStack(spacing: 24) {
                InfoRow(label: "VID / PID", value: viewModel.controller.deviceInfo.map { "0x\(String(format: "%04X", $0.vendorID)) / 0x\(String(format: "%04X", $0.productID))" } ?? "—")
                InfoRow(label: "协议", value: viewModel.controller.deviceInfo?.proto.rawValue ?? "—")
                InfoRow(label: "连接", value: viewModel.isConnected ? "已连接" : "未连接")
            }
            .padding(14)
        }
        .frame(width: 900, height: 620)
    }

    // MARK: - 保存预设弹窗

    private var savePresetSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("保存为预设").font(.title3).fontWeight(.semibold)
            Text("范围：\(selectedZoneDescription)").font(.system(size: 13 * AppTheme.fontScale)).foregroundColor(.secondary)
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

    private func commitInlinePreset() {
        if viewModel.saveCurrentAsPreset(name: newPresetName) {
            inlinePresetNaming = false
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

struct ZoneCheckbox: View {
    let color: Color
    let selected: Bool
    let hovered: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .fill(selected ? color : Color.white.opacity(hovered ? 0.10 : 0.04))
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .strokeBorder(
                    selected ? Color.white.opacity(0.55) : Color.white.opacity(hovered ? 0.38 : 0.22),
                    lineWidth: 1
                )
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 8.5, weight: .heavy))
                    .foregroundColor(.white)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .frame(width: 15, height: 15)
        .shadow(color: selected ? color.opacity(0.55) : .clear, radius: 4)
        .animation(.easeOut(duration: 0.16), value: selected)
    }
}

struct ZonePill: View {
    let zone: LightZone
    let selected: Bool
    let hovered: Bool
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            ZoneCheckbox(color: color, selected: selected, hovered: hovered)
            Text(zone.displayName)
                .font(.system(size: 12.5 * AppTheme.fontScale, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? .primary : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(
                selected
                    ? color.opacity(0.18)
                    : Color.white.opacity(hovered ? 0.10 : 0.05)
            )
        )
        .overlay(
            Capsule().stroke(
                selected ? color.opacity(0.85) : Color.white.opacity(hovered ? 0.16 : 0.06),
                lineWidth: 1
            )
        )
        .contentShape(Capsule())
        .help(zone.awccZone.map { "AWCC 区域 \($0) · \(zone.displayName)" } ?? zone.displayName)
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

            Text(preset.name).font(.system(size: 14 * AppTheme.fontScale, weight: .medium)).lineLimit(1)
            HStack {
                Text(preset.effect.rawValue)
                Text("·")
                Text(preset.scopeDescription)
            }
            .font(.system(size: 12 * AppTheme.fontScale)).foregroundColor(.secondary)
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
                Text(preset.rawValue).font(.system(size: 14 * AppTheme.fontScale, weight: .medium))
                Text(preset.effect.rawValue).font(.system(size: 12 * AppTheme.fontScale)).foregroundColor(.secondary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 信息行

struct InfoRow: View {    let label: String
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
        .font(.system(size: 14 * AppTheme.fontScale))
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

// MARK: - AWCC 自带主题卡片

struct AWCCThemeTile: View {
    let theme: AWCCThemeInfo

    private var swatches: [RGBColor] { AWCCThemeBridge.swatches(from: theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(theme.name.replacingOccurrences(of: "Advanced - ", with: "")
                     .replacingOccurrences(of: "Basic - ", with: ""))
                    .font(.system(size: 13.5 * AppTheme.fontScale, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            HStack(spacing: 3) {
                ForEach(Array(swatches.enumerated()), id: \.offset) { _, color in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.swiftUIColor)
                        .frame(height: 14)
                }
                if swatches.isEmpty {
                    Text("—").font(.system(size: 11 * AppTheme.fontScale)).foregroundStyle(.secondary)
                }
            }

            Text(theme.family ?? "")
                .font(.system(size: 10.5 * AppTheme.fontScale))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

/// 自动换行布局：灯区胶囊按自然宽度从左排到右，超出宽度自动折行
struct FlowLayout: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : max(x, 0), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
