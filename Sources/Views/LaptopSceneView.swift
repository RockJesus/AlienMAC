//
//  LaptopSceneView.swift
//  AlienMAC
//
//  Alienware 17 R4 真实比例三维模型（424 × 332 × 30 mm，17.3" 屏）
//  灯区直接可点，支持自由旋转、缩放、开合盖与视角切换
//

import SwiftUI
import AVFoundation
import SceneKit
import SpriteKit
import AppKit
import QuartzCore

// MARK: - 视角

enum ScenePose: String, CaseIterable, Identifiable {
    case hero, top, back

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hero: return "正面"
        case .top:  return "俯视"
        case .back: return "顶盖"
        }
    }

    var icon: String {
        switch self {
        case .hero: return "laptopcomputer"
        case .top:  return "square.on.square.dashed"
        case .back: return "arrow.triangle.2.circlepath"
        }
    }

    /// 相机轨道参数：theta 绕 Y 的方位角，phi 俯仰角，targetY 观察点高度
    var orbit: (theta: CGFloat, phi: CGFloat, targetY: CGFloat) {
        switch self {
        case .hero: return (0.56, 0.22, 15.2)
        case .top:  return (0.08, 1.00, 8.0)
        case .back: return (.pi - 0.10, 1.30, 12.6)
        }
    }
}

// MARK: - SwiftUI 封装

struct LaptopSceneView: NSViewRepresentable {

    @ObservedObject var viewModel: LightingViewModel
    @Binding var lidOpen: Bool
    var pose: ScenePose = .hero
    /// 3D 拆解（爆炸视图）
    var exploded: Bool = false
    /// 鼠标悬停在屏幕区域时回调（坐标为 SwiftUI 坐标系，原点左上）
    var onScreenHover: ((CGPoint?) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, lidOpen: $lidOpen)
    }

    func makeNSView(context: Context) -> LaptopSceneNSView {
        let view = LaptopSceneNSView()
        view.viewModel = viewModel
        view.onZoneTap = { zone in
            // 点击空白区域保持当前选中与视角，不清空选择
            guard let zone = zone else { return }
            viewModel.toggleZone(zone)
        }
        view.onZoneHover = { zone in
            viewModel.hoveredZone = zone
        }
        view.onKeyTap = { id in
            if let id = id { viewModel.toggleKey(id) }
        }
        view.onKeyHover = { id in
            viewModel.hoveredKey = id
        }
        view.onScreenHover = { [weak view] point in
            guard let view = view else { return }
            guard let point = point else { onScreenHover?(nil); return }
            onScreenHover?(CGPoint(x: point.x, y: view.bounds.height - point.y))
        }
        context.coordinator.view = view
        LaptopSceneNSView.shared = view
        HandGestureController.shared.onOrbit = { [weak view] dTheta, dPhi in
            view?.applyGestureOrbit(dTheta: dTheta, dPhi: dPhi)
        }
        view.setLid(open: lidOpen, animated: false)
        if let camera = LaptopSceneNSView.lastCamera {
            view.restoreCamera(camera)
        } else {
            view.setPose(pose, animated: false)
        }
        context.coordinator.appliedPose = pose
        view.setExploded(exploded, animated: false)
        context.coordinator.startTimer()
        return view
    }

    func updateNSView(_ view: LaptopSceneNSView, context: Context) {
        view.setLid(open: lidOpen, animated: true)
        // 仅在视角项真的切换时才重新摆位，避免刷新时把用户拖出来的角度弹回去
        if context.coordinator.appliedPose != pose {
            context.coordinator.appliedPose = pose
            if !exploded { view.setPose(pose, animated: true) }
        }
        view.setExploded(exploded, animated: true)
    }

    static func dismantleNSView(_ nsView: LaptopSceneNSView, coordinator: Coordinator) {
        coordinator.stopTimer()
    }

    final class Coordinator {
        /// 已应用的视角项，用于区分「用户切换视角」与「普通刷新」
        var appliedPose: ScenePose?
        let viewModel: LightingViewModel
        let lidOpen: Binding<Bool>
        weak var view: LaptopSceneNSView?
        private var timer: Timer?
        private var frameTick = 0

        init(viewModel: LightingViewModel, lidOpen: Binding<Bool>) {
            self.viewModel = viewModel
            self.lidOpen = lidOpen
        }

        func startTimer() {
            timer?.invalidate()
            let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                guard let self, let view = self.view else { return }
                self.frameTick += 1
                // 动效运行时 30fps 跟随；静态灯效降到 5fps，事件驱动时立即补一帧
                if view.needsFastTick {
                    if view.preferredFramesPerSecond < 30 { view.preferredFramesPerSecond = 30 }
                    view.tick()
                } else if self.frameTick % 6 == 0 {
                    view.tick()
                }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }

        func stopTimer() {
            timer?.invalidate()
            timer = nil
        }
    }
}

// MARK: - 调试输出


// MARK: - 交互视图

final class LaptopSceneNSView: SCNView {

    /// 全局弱引用，供手机网页截取「app 同一套建模」的画面
    static weak var shared: LaptopSceneNSView?

    var onZoneTap: ((LightZone?) -> Void)?
    var onZoneHover: ((LightZone?) -> Void)?
    /// 单个按键点击（nil 表示点在空白处）
    var onKeyTap: ((String?) -> Void)?
    /// 单个按键悬停
    var onKeyHover: ((String?) -> Void)?
    /// 屏幕区域悬停回调，参数为视图坐标（原点左下），离开时为 nil
    var onScreenHover: ((NSPoint?) -> Void)?
    private var hoveringScreen = false
    weak var viewModel: LightingViewModel?

    // 相机
    private var cameraNode = SCNNode()
    private var theta: CGFloat = 0.58
    private var phi: CGFloat = 0.24
    private var targetY: CGFloat = 15.2
    private var zoomScale: CGFloat = 1.0
    private var baseRadius: CGFloat = 70
    private var cameraReady = false

    // 动画
    private var animFrom: (theta: CGFloat, phi: CGFloat, targetY: CGFloat)?
    private var animTo: (theta: CGFloat, phi: CGFloat, targetY: CGFloat)?
    private var animStart: CFTimeInterval = 0
    private var animDuration: CFTimeInterval = 0.85

    // 模型
    private var lidPivot: SCNNode!
    /// A 面银色面板的背面 z（用于贴装饰与头标）
    private var lidAFaceZ: CGFloat = -0.70
    private var lidIsOpen = false
    /// 顶盖外星人头标节点（用于点击命中修正：盖合状态下点 logo 应选中灯区，而不是开合盖）
    private weak var lidLogoNode: SCNNode?
    private var wallpaperPlayer: AVQueuePlayer?
    private var wallpaperLooper: AVPlayerLooper?
    private var zoneEntries: [LightZone: ZoneVisual] = [:]

    // 拆解（爆炸视图）
    private struct ExplodePart {
        let node: SCNNode
        let base: SCNVector3
        let zoneRaw: Int
    }
    private var explodeParts: [ExplodePart] = []
    private var isExploded = false
    private var lidBasePosition = SCNVector3Zero
    private var lidBeforeExplode = false
    private var zoomBeforeExplode: CGFloat = 1.0
    private var thetaBeforeExplode: CGFloat = 0
    private var phiBeforeExplode: CGFloat = 0
    private var targetYBeforeExplode: CGFloat = 0

    // 交互
    private var dragOrigin: NSPoint = .zero
    private var lastDrag: NSPoint = .zero
    private var didDrag = false
    private var trackingArea: NSTrackingArea?
    private var hovered: LightZone?
    private var hoveredKey: String?

    private struct ZoneVisual {
        let node: SCNNode
        let materials: [SCNMaterial]
        let outline: SCNNode
        var glowIntensity: CGFloat
    }

    // MARK: - 渲染调度（后台不空转）

    private var renderObservers: [NSObjectProtocol] = []
    private var isSuspendedForHidden = false
    private var lastInteraction: CFTimeInterval = 0
    private var idleWorkItem: DispatchWorkItem?
    private var videoIdleTask: DispatchWorkItem?
    private var videoFrozenForIdle = false

    var needsFastTick: Bool {
        guard let vm = viewModel else { return false }
        if vm.isSoftwareEffect { return true }
        for zone in LightZone.allIndividual {
            switch vm.effect(for: zone) {
            case .pulse, .breathing, .morph, .spectrum, .wave, .scanner:
                return true
            case .color:
                continue
            }
        }
        return false
    }

    private var isWindowHidden: Bool {
        guard let win = window else { return true }
        return win.isMiniaturized
            || !win.occlusionState.contains(.visible)
            || NSApp.isHidden
    }

    /// 窗口不在前台也停机：切走冻结，回来恢复，避免后台按 30fps 空转
    private var shouldSuspendRendering: Bool {
        isWindowHidden || !(window?.isKeyWindow ?? false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        renderObservers.forEach { NotificationCenter.default.removeObserver($0) }
        renderObservers.removeAll()

        guard let win = window else { return }
        let targets: [(Notification.Name, Any?)] = [
            (NSWindow.didChangeOcclusionStateNotification, win),
            (NSWindow.didMiniaturizeNotification, win),
            (NSWindow.didDeminiaturizeNotification, win),
            (NSWindow.didBecomeKeyNotification, win),
            (NSWindow.didResignKeyNotification, win),
            (NSApplication.didHideNotification, nil),
            (NSApplication.didUnhideNotification, nil)
        ]
        for (name, object) in targets {
            let token = NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                self?.applyRenderPolicy()
            }
            renderObservers.append(token)
        }
        applyRenderPolicy()
    }

    deinit {
        renderObservers.forEach { NotificationCenter.default.removeObserver($0) }
        idleWorkItem?.cancel()
        videoIdleTask?.cancel()
    }

    /// 静置 6 秒后暂停屏内视频（保留最后一帧），有交互再恢复
    private func scheduleVideoIdleFreeze() {
        // 壁纸改为「有焦点就无限循环」：不再因为静置暂停，只随窗口焦点起停（见 applyRenderPolicy）
        videoIdleTask?.cancel()
    }

    private func resumeVideoIfFrozen() {
        guard videoFrozenForIdle else { return }
        videoFrozenForIdle = false
        if lidIsOpen, !shouldSuspendRendering { wallpaperPlayer?.play() }
        updateFrameRate()
    }

    private func applyRenderPolicy() {
        guard window != nil else { return }

        if shouldSuspendRendering {
            if isPlaying {
                isPlaying = false
                isSuspendedForHidden = true
            }
            // rendersContinuously 仍会驱动 CVDisplayLink 出帧，后台必须一起关掉
            rendersContinuously = false
            preferredFramesPerSecond = 1
            wallpaperPlayer?.pause()
            return
        }

        if isSuspendedForHidden || !isPlaying {
            isSuspendedForHidden = false
            rendersContinuously = true
            isPlaying = true
            if lidIsOpen { wallpaperPlayer?.play() }
            videoFrozenForIdle = false
            scheduleVideoIdleFreeze()
        }
        updateFrameRate()
    }

    private func updateFrameRate() {
        guard let win = window, !isWindowHidden else { return }
        let recentlyActive = CACurrentMediaTime() - lastInteraction < 1.5
        preferredFramesPerSecond = (win.isKeyWindow && recentlyActive) ? 60 : 30
    }

    /// 任何鼠标操作/动画入口调用：短暂升到 60fps，静置后自动回落 30fps
    private func noteInteraction() {
        lastInteraction = CACurrentMediaTime()
        resumeVideoIfFrozen()
        scheduleVideoIdleFreeze()
        tick()
        if !isWindowHidden {
            if !isPlaying && !shouldSuspendRendering {
                isPlaying = true
                isSuspendedForHidden = false
            }
            if !shouldSuspendRendering { preferredFramesPerSecond = 60 }
        }
        idleWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.updateFrameRate()
        }
        idleWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: item)
    }

    // MARK: 初始化

    init() {
        super.init(frame: .zero, options: nil)
        build()
    }

    required init?(coder: NSCoder) { fatalError("未实现") }

    // MARK: 场景构建

    private func build() {
        let scene = SCNScene()
        self.scene = scene
        self.backgroundColor = .clear
        self.wantsLayer = true
        self.layer?.isOpaque = false
        self.antialiasingMode = .multisampling2X
        self.isPlaying = true
        self.rendersContinuously = true
        self.preferredFramesPerSecond = 30
        self.allowsCameraControl = false

        scene.background.contents = nil
        scene.lightingEnvironment.contents = Self.environmentImage()
        scene.lightingEnvironment.intensity = 1.15

        let root = SCNNode()
        scene.rootNode.addChildNode(root)

        buildContactShadow(root)
        buildChassis(root)
        buildKeyboard(root)
        buildZones(root)
        buildLights(scene)
        buildCamera(scene)
        prepareExplode()
    }

    private let bodyWidth: CGFloat = 42.4
    private let bodyDepth: CGFloat = 33.2
    private let deckTop: CGFloat = 2.00

    /// 触控板几何：官方 100 mm × 56 mm；中心相对键盘中线左偏，与 AWCC 热区图一致
    /// （AWCC 17 R4 热区图里触控板中心在键盘中线左侧约 4.3 个模型单位）
    private let touchpadWidth: CGFloat = 10.0
    private let touchpadDepth: CGFloat = 5.6
    private let touchpadCenterX: CGFloat = -4.4
    private let touchpadCenterZ: CGFloat = 9.7

    private func buildFloor(_ root: SCNNode) {
        let floor = SCNFloor()
        floor.reflectivity = 0.22
        floor.reflectionFalloffEnd = 70
        floor.reflectionFalloffStart = 6
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor(calibratedRed: 0.018, green: 0.022, blue: 0.03, alpha: 1)
        mat.metalness.contents = 0.15
        mat.roughness.contents = 0.42
        floor.materials = [mat]
        let node = SCNNode(geometry: floor)
        node.position = SCNVector3(0, -1.4, 0)
        node.categoryBitMask = 2
        root.addChildNode(node)
    }

    private func buildContactShadow(_ root: SCNNode) {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size)
        image.lockFocus()
        let gradient = NSGradient(colorsAndLocations:
            (NSColor(calibratedWhite: 0.0, alpha: 0.85), 0.0),
            (NSColor(calibratedWhite: 0.0, alpha: 0.45), 0.35),
            (NSColor(calibratedWhite: 0.0, alpha: 0.0), 1.0)
        )
        gradient?.draw(in: NSRect(origin: .zero, size: size), relativeCenterPosition: .zero)
        image.unlockFocus()

        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.diffuse.contents = image
        mat.blendMode = .multiply
        mat.writesToDepthBuffer = false
        mat.isDoubleSided = true
        let plane = SCNPlane(width: 58, height: 50)
        plane.materials = [mat]
        let node = SCNNode(geometry: plane)
        node.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0)
        node.position = SCNVector3(0.5, -0.35, 2.0)
        node.categoryBitMask = 2
        node.renderingOrder = -10
        root.addChildNode(node)
    }

    // MARK: 机身

    private func shellMaterial(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat,
                               metal: CGFloat, rough: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
        m.metalness.contents = metal
        m.roughness.contents = rough
        return m
    }

    private func buildChassis(_ root: SCNNode) {
        // 对齐官方渲染：机身是偏浅的石墨灰（官方样张 palm rest 约 #5E~#67），不是纯黑
        let bodyMat = shellMaterial(0.300, 0.302, 0.305, metal: 0.58, rough: 0.42)
        let deckMat = shellMaterial(0.340, 0.342, 0.345, metal: 0.62, rough: 0.38)
        let darkMat = shellMaterial(0.036, 0.036, 0.037, metal: 0.28, rough: 0.66)

        // 底座
        let base = SCNBox(width: bodyWidth, height: 1.45, length: bodyDepth, chamferRadius: 0.72)
        base.materials = [bodyMat]
        let baseNode = SCNNode(geometry: base)
        baseNode.position = SCNVector3(0, 0.72, 0)
        baseNode.categoryBitMask = 2
        root.addChildNode(baseNode)

        // 后部散热罩：整块黑色底座 + 中间带台阶的凸台（官方是分层罩体，不是一块方砖）
        let shroudMat = shellMaterial(0.055, 0.058, 0.062, metal: 0.15, rough: 0.62)
        let rearBase = SCNBox(width: bodyWidth - 0.5, height: 1.30, length: 6.0, chamferRadius: 0.88)
        rearBase.materials = [shroudMat]
        let rearNode = SCNNode(geometry: rearBase)
        rearNode.position = SCNVector3(0, 0.84, -13.6)
        rearNode.categoryBitMask = 2
        root.addChildNode(rearNode)

        // 中间凸台：截面为「前低台阶 + 后高台面」的梯形，沿 x 拉伸
        do {
            let profile = NSBezierPath()
            profile.move(to: NSPoint(x: -2.75, y: 0))
            profile.line(to: NSPoint(x: -2.75, y: 0.34))
            profile.line(to: NSPoint(x: -1.55, y: 0.40))
            profile.line(to: NSPoint(x: -1.55, y: 0.98))
            profile.line(to: NSPoint(x: 0.55, y: 1.12))
            // 面板上沿靠后一侧做 20° 倒角压边，官方实拍这里是斜切过渡，不是硬直角
            profile.line(to: NSPoint(x: 2.40, y: 1.12))
            profile.line(to: NSPoint(x: 2.75, y: 0.92))
            profile.line(to: NSPoint(x: 2.75, y: 0))
            profile.close()
            let hump = SCNShape(path: profile, extrusionDepth: 25.6)
            hump.chamferRadius = 0.10
            hump.materials = [shroudMat]
            let humpNode = SCNNode(geometry: hump)
            humpNode.eulerAngles = SCNVector3(0, CGFloat.pi / 2, 0)
            // 官方后部特写：接口面板比两侧散热鳍片区矮一档，形成明显台阶
            humpNode.position = SCNVector3(0, 0.82, -13.35)
            humpNode.categoryBitMask = 2
            root.addChildNode(humpNode)
        }

        // 左右两翼：比中间凸台低一档，托住外侧散热鳍片
        for side in [CGFloat(-1), CGFloat(1)] {
            let wing = SCNBox(width: 6.4, height: 0.95, length: 5.6, chamferRadius: 0.22)
            wing.materials = [shroudMat]
            let node = SCNNode(geometry: wing)
            node.position = SCNVector3(side * 17.4, 1.52, -13.6)
            node.categoryBitMask = 2
            root.addChildNode(node)
        }

        // 前缘字标
        let wordMat = SCNMaterial()
        wordMat.lightingModel = .constant
        wordMat.diffuse.contents = NSColor(calibratedWhite: 0.55, alpha: 0.9)
        let word = SCNText(string: "ALIENWARE", extrusionDepth: 0.01)
        word.font = NSFont.systemFont(ofSize: 1.0, weight: .semibold)
        word.flatness = 0.1
        word.materials = [wordMat]
        let wordNode = SCNNode(geometry: word)
        let (wMin, wMax) = wordNode.boundingBox
        wordNode.pivot = SCNMatrix4MakeTranslation((wMin.x + wMax.x) / 2, (wMin.y + wMax.y) / 2, 0)
        wordNode.scale = SCNVector3(0.32, 0.32, 1)
        wordNode.position = SCNVector3(0, 0.78, bodyDepth / 2 + 0.055)
        wordNode.categoryBitMask = 2
        root.addChildNode(wordNode)

        // 掌托面板
        let deck = SCNBox(width: bodyWidth - 0.8, height: 0.38, length: bodyDepth - 2.6, chamferRadius: 0.30)
        deck.materials = [deckMat]
        let deckNode = SCNNode(geometry: deck)
        deckNode.position = SCNVector3(0, 1.82, 0.9)
        deckNode.categoryBitMask = 2
        root.addChildNode(deckNode)

        // 键盘凹槽（官方是深灰凹槽，不是纯黑，凹槽比掌托深一档）
        let well = SCNBox(width: 37.4, height: 0.24, length: 11.6, chamferRadius: 0.32)
        well.materials = [shellMaterial(0.168, 0.170, 0.176, metal: 0.45, rough: 0.55)]
        let wellNode = SCNNode(geometry: well)
        // 官方顶视图：键盘区是往下凹约 3mm 的槽，槽顶低于掌托面；中心按宏键列到数字键盘右缘的实际跨度微调到 +0.17
        wellNode.position = SCNVector3(0.17, 1.86, -1.85)
        wellNode.categoryBitMask = 2
        root.addChildNode(wellNode)

        // 官方俯视实拍：键盘凹槽四周有一圈很细的浅色收边，四角圆润，槽沿不是硬切边
        let kbRimMat = shellMaterial(0.30, 0.305, 0.32, metal: 0.35, rough: 0.55)
        let rimW: CGFloat = 37.70, rimL: CGFloat = 11.90, rimT: CGFloat = 0.14
        for (rw, rl, px, pz) in [(rimW, rimT, 0.17, -7.72), (rimW, rimT, 0.17, 4.02),
                                 (rimT, rimL, -18.62 + 0.17, -1.85), (rimT, rimL, 18.62 + 0.17, -1.85)] {
            let rim = SCNBox(width: rw, height: 0.035, length: rl, chamferRadius: 0.05)
            rim.materials = [kbRimMat]
            let rn = SCNNode(geometry: rim)
            rn.position = SCNVector3(px, 1.992, pz)
            rn.categoryBitMask = 2
            root.addChildNode(rn)
        }

        // 触控板（深色玻璃面）
        let padGlass = SCNMaterial()
        padGlass.lightingModel = .physicallyBased
        padGlass.diffuse.contents = NSColor(calibratedWhite: 0.085, alpha: 1)
        padGlass.metalness.contents = 0.1
        padGlass.roughness.contents = 0.18
        // 官方规格：触控板 100 mm × 56 mm（尺寸与位置统一取 touchpad* 常量）
        let pad = SCNBox(width: touchpadWidth, height: 0.08, length: touchpadDepth, chamferRadius: 0.35)
        pad.materials = [padGlass]
        let padNode = SCNNode(geometry: pad)
        padNode.position = SCNVector3(touchpadCenterX, deckTop, touchpadCenterZ)
        padNode.categoryBitMask = 1
        padNode.name = "zone-\(LightZone.touchpad.rawValue)"
        root.addChildNode(padNode)

        // 掌托右下角：外星人头标 + 苹果 logo 两块标贴（白底圆角牌 + 独立透明图层面片，图层与 A 面头标同一套加载方式）
        do {
            let items: [(String, CGFloat)] = [("sticker_glyph_alien", 17.05), ("sticker_glyph_apple", 19.05)]
            for (tex, x) in items {
                guard let url = Bundle.main.url(forResource: tex, withExtension: "png"),
                      let img = NSImage(contentsOf: url) else { continue }
                let gm = SCNMaterial()
                gm.lightingModel = .constant
                gm.diffuse.contents = img
                gm.diffuse.mipFilter = .none
                gm.transparent.contents = img
                gm.transparencyMode = .aOne
                gm.isDoubleSided = true
                gm.writesToDepthBuffer = false
                let plane = SCNPlane(width: 2.05, height: 2.05)
                plane.materials = [gm]
                let gn = SCNNode(geometry: plane)
                gn.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0)
                gn.position = SCNVector3(x, deckTop + 0.024, 14.55)
                gn.categoryBitMask = 2
                root.addChildNode(gn)
            }
        }

        // 底盖：官方 17 R4 后半段是几道横向长散热槽，中间贴服务编号标签
        do {
            let bottomVent = SCNMaterial()
            bottomVent.lightingModel = .physicallyBased
            bottomVent.diffuse.contents = NSColor(calibratedWhite: 0.015, alpha: 1)
            bottomVent.roughness.contents = 0.9
            // 官方底壳（UsRlxV1VZ3）：不是 5 道通长细缝，而是横向排开的 6 块矩形格栅，每块内是竖向鳍片
            let ribMat = shellMaterial(0.16, 0.162, 0.17, metal: 0.3, rough: 0.7)
            for b in 0..<6 {
                let panel = SCNBox(width: 6.10, height: 0.07, length: 5.00, chamferRadius: 0.10)
                panel.materials = [bottomVent]
                let pn = SCNNode(geometry: panel)
                pn.position = SCNVector3(-16.30 + CGFloat(b) * 6.52, -0.02, -11.60)
                pn.categoryBitMask = 2
                root.addChildNode(pn)

                for i in 0..<9 {
                    let rib = SCNBox(width: 0.10, height: 0.05, length: 4.70, chamferRadius: 0.02)
                    rib.materials = [ribMat]
                    let rn = SCNNode(geometry: rib)
                    rn.position = SCNVector3(-16.30 + CGFloat(b) * 6.52 - 2.55 + CGFloat(i) * 0.64,
                                             -0.012, -11.60)
                    rn.categoryBitMask = 2
                    root.addChildNode(rn)
                }
            }

            let tag = SCNPlane(width: 4.2, height: 1.05)
            tag.cornerRadius = 0.06
            let tm = SCNMaterial()
            tm.lightingModel = .physicallyBased
            tm.diffuse.contents = NSColor(calibratedWhite: 0.62, alpha: 1)
            tm.roughness.contents = 0.5
            tag.materials = [tm]
            let tagNode = SCNNode(geometry: tag)
            tagNode.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
            tagNode.position = SCNVector3(0, -0.026, -4.6)
            tagNode.categoryBitMask = 2
            root.addChildNode(tagNode)
        }

        // 掌托前缘圆润收边：官方正面/侧面看掌托最前端是一道向内收的圆弧，不是直切边
        do {
            let fillet = SCNBox(width: bodyWidth - 1.2, height: 0.56, length: 1.05, chamferRadius: 0.46)
            fillet.materials = [bodyMat]
            let fn = SCNNode(geometry: fillet)
            fn.position = SCNVector3(0, deckTop - 0.15, bodyDepth / 2 - 0.44)
            fn.categoryBitMask = 2
            root.addChildNode(fn)
        }

        // 前缘斜面（楔形感）
        let lipWedge = SCNBox(width: bodyWidth - 1.4, height: 0.72, length: 3.2, chamferRadius: 0.34)
        lipWedge.materials = [bodyMat]
        let lipWedgeNode = SCNNode(geometry: lipWedge)
        lipWedgeNode.eulerAngles = SCNVector3(-0.32, 0, 0)
        lipWedgeNode.position = SCNVector3(0, 0.95, bodyDepth / 2 - 1.3)
        lipWedgeNode.categoryBitMask = 2
        root.addChildNode(lipWedgeNode)

        // 底座与掌托之间的分缝
        let groove = SCNBox(width: bodyWidth - 1.0, height: 0.12, length: bodyDepth - 1.2, chamferRadius: 0.05)
        groove.materials = [darkMat]
        let grooveNode = SCNNode(geometry: groove)
        grooveNode.position = SCNVector3(0, 1.52, 0.2)
        grooveNode.categoryBitMask = 2
        root.addChildNode(grooveNode)

        // 前缘装饰条
        // 前端银灰楔形面（官方正面图：底座前脸是一段浅银灰斜面，两端各有一组散热槽）
        do {
            let face = SCNBox(width: bodyWidth - 2.2, height: 0.34, length: 0.16, chamferRadius: 0.08)
            face.materials = [shellMaterial(0.80, 0.802, 0.805, metal: 0.20, rough: 0.34)]
            let node = SCNNode(geometry: face)
            node.position = SCNVector3(0, 1.16, bodyDepth / 2 - 0.06)
            node.eulerAngles = SCNVector3(-0.30, 0, 0)
            node.categoryBitMask = 2
            root.addChildNode(node)
        }
        // 前脸两端不是几道小缝，而是两组长条格栅（官方正面照 BdFPesaqfg / kHQFY3ibnf 各一侧一整段）
        for side in [CGFloat(-1), CGFloat(1)] {
            let grille = SCNBox(width: 7.6, height: 0.30, length: 0.07, chamferRadius: 0.04)
            grille.materials = [darkMat]
            let g = SCNNode(geometry: grille)
            g.position = SCNVector3(side * 13.6, 1.36, bodyDepth / 2 - 0.03)
            g.categoryBitMask = 2
            root.addChildNode(g)

            let ribMat = shellMaterial(0.22, 0.222, 0.23, metal: 0.25, rough: 0.6)
            for i in 0..<11 {
                let rib = SCNBox(width: 0.09, height: 0.26, length: 0.05, chamferRadius: 0.02)
                rib.materials = [ribMat]
                let rn = SCNNode(geometry: rib)
                rn.position = SCNVector3(side * 13.6 - 3.4 + CGFloat(i) * 0.68,
                                         1.36, bodyDepth / 2 - 0.005)
                rn.categoryBitMask = 2
                root.addChildNode(rn)
            }
        }

        let trim = SCNBox(width: bodyWidth - 3.4, height: 0.38, length: 1.8, chamferRadius: 0.20)
        trim.materials = [darkMat]
        let trimNode = SCNNode(geometry: trim)
        trimNode.position = SCNVector3(0, 0.42, bodyDepth / 2 - 0.6)
        trimNode.categoryBitMask = 2
        root.addChildNode(trimNode)

        // 键盘上方的抬高台面：官方是贯穿全宽的钢琴黑亮面，电源键头标就嵌在这条台面上
        let ledgeMat = shellMaterial(0.034, 0.036, 0.042, metal: 0.12, rough: 0.12)
        let ledge = SCNBox(width: bodyWidth - 1.4, height: 0.24, length: 4.35,
                           chamferRadius: 0.10)
        ledge.materials = [ledgeMat]
        let ledgeNode = SCNNode(geometry: ledge)
        ledgeNode.position = SCNVector3(0, deckTop + 0.12, -11.85)
        ledgeNode.categoryBitMask = 2
        root.addChildNode(ledgeNode)

        // 铰链
        let hingeMat = shellMaterial(0.07, 0.07, 0.08, metal: 0.8, rough: 0.35)
        let hinge = SCNCylinder(radius: 0.62, height: bodyWidth - 3.2)
        hinge.materials = [hingeMat]
        let hingeNode = SCNNode(geometry: hinge)
        hingeNode.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
        hingeNode.position = SCNVector3(0, 2.40, -bodyDepth / 2 + 1.4)
        hingeNode.categoryBitMask = 2
        root.addChildNode(hingeNode)

        // 官方实拍（UEnlbIC0uu / jksyDUNlXv）：不是一根通长光轴，而是左右两块宽黑转轴盖，
        // 各宽约 8.4cm，中心 x=±10.5，把铰链面盖成两段，中间留出散热口
        let hingeCapMat = shellMaterial(0.085, 0.086, 0.092, metal: 0.55, rough: 0.42)
        for hx in [CGFloat(-10.5), CGFloat(10.5)] {
            let cap = SCNBox(width: 8.4, height: 1.02, length: 1.34, chamferRadius: 0.12)
            cap.materials = [hingeCapMat]
            let cn = SCNNode(geometry: cap)
            cn.position = SCNVector3(hx, 2.44, -bodyDepth / 2 + 1.52)
            cn.categoryBitMask = 2
            root.addChildNode(cn)
        }

        // 顶盖
        lidPivot = SCNNode()
        lidPivot.position = SCNVector3(0, 2.50, -bodyDepth / 2 + 1.3)
        root.addChildNode(lidPivot)

        // 官方顶盖是磨砂铝：金属度高但粗糙度也高，主光会摊成整片泛光而不是一块亮斑
        let lidMat = shellMaterial(0.760, 0.760, 0.762, metal: 0.50, rough: 0.56)

        // 官方顶盖：与机身等宽、两边竖直，前缘（屏幕上方）中心略凸成浅 V，合盖能盖住底座
        func lidPolygon(_ inset: CGFloat) -> NSBezierPath {
            let hw: CGFloat = 21.3 - inset
            let shoulderY: CGFloat = 25.4 - inset
            let shoulderHalf: CGFloat = 20.4 - inset
            let apexY: CGFloat = 27.6 - inset * 1.4
            let path = NSBezierPath()
            path.move(to: NSPoint(x: -hw, y: inset))
            path.line(to: NSPoint(x: hw, y: inset))
            path.line(to: NSPoint(x: hw, y: 22.4))
            path.line(to: NSPoint(x: shoulderHalf, y: shoulderY))
            path.line(to: NSPoint(x: 0, y: apexY))
            path.line(to: NSPoint(x: -shoulderHalf, y: shoulderY))
            path.line(to: NSPoint(x: -hw, y: 22.4))
            path.close()
            return path
        }

        // 只用一块银色壳体（不再在外面留一圈浅灰边框，那圈灰边会挡住侧边灯带）
        let bodyShape = SCNShape(path: lidPolygon(0.0), extrusionDepth: 0.60)
        bodyShape.chamferRadius = 0.08
        bodyShape.materials = [lidMat]
        let bodyBB = bodyShape.boundingBox
        let lidBackZ = bodyBB.min.z - bodyBB.max.z
        let lidBody = SCNNode(geometry: bodyShape)
        lidBody.position = SCNVector3(0, 0, -bodyBB.max.z)
        lidBody.name = "lid"
        lidBody.categoryBitMask = 2
        lidPivot.addChildNode(lidBody)
        lidAFaceZ = lidBackZ - 0.05

        // A 面折面与分割线（官方顶盖的三角切割质感）
        // 官方 A 面是柔和磨砂银：主光在折面上是缓慢过渡的泛光，不是一块死白高光
        let facetSilver = shellMaterial(0.900, 0.902, 0.908, metal: 0.10, rough: 0.44)
        let seamSilver = shellMaterial(0.34, 0.35, 0.37, metal: 0.2, rough: 0.45)

        // 顶边到分叉点的竖脊
        do {
            let bar = SCNBox(width: 0.22, height: 9.0, length: 0.16, chamferRadius: 0.02)
            bar.materials = [seamSilver]
            let node = SCNNode(geometry: bar)
            node.position = SCNVector3(0, 23.2, lidAFaceZ + 0.05)
            node.name = "lid"
            node.categoryBitMask = 2
            lidPivot.addChildNode(node)
        }

        // 分叉点向左右下角的斜缝
        // 官方背面照：缝线交点落在 A 面头标（y≈19）处，两道斜缝从头标分向左右下角
        // 端点要求：上端落在头标上沿 (0, 19.0)，下端必须顶到折肩（±21.0, 0.9）——原来只到 ±19.05 就断了
        let splitY: CGFloat = 18.4
        let seamLen: CGFloat = 27.72
        for (cx, ang) in [(CGFloat(-10.5), CGFloat(0.710)), (CGFloat(10.5), CGFloat(-0.710))] {
            let bar = SCNBox(width: seamLen, height: 0.22, length: 0.16, chamferRadius: 0.02)
            bar.materials = [seamSilver]
            let node = SCNNode(geometry: bar)
            node.position = SCNVector3(cx, 9.95, lidAFaceZ + 0.05)
            node.eulerAngles = SCNVector3(0, 0, ang)
            node.name = "lid"
            node.categoryBitMask = 2
            lidPivot.addChildNode(node)
        }

        // A 面顶边黑色饰条：官方合盖背面照里顶盖最上沿是一条贯穿全宽的黑色亮带宽约 1.5cm
        do {
            let bandMat = shellMaterial(0.045, 0.047, 0.05, metal: 0.18, rough: 0.34)
            let path = NSBezierPath()
            // 按实拍（XhLutzDyyF / rl7wG2TtCQ）量取：黑饰条垂直厚度约 2.1cm，比原先 1.5cm 更厚
            path.move(to: NSPoint(x: -21.3, y: 20.3))
            path.line(to: NSPoint(x: -21.3, y: 22.4))
            path.line(to: NSPoint(x: -20.4, y: 25.4))
            path.line(to: NSPoint(x: 0, y: 27.6))
            path.line(to: NSPoint(x: 20.4, y: 25.4))
            path.line(to: NSPoint(x: 21.3, y: 22.4))
            path.line(to: NSPoint(x: 21.3, y: 20.3))
            path.line(to: NSPoint(x: 20.4, y: 23.3))
            path.line(to: NSPoint(x: 0, y: 25.5))
            path.line(to: NSPoint(x: -20.4, y: 23.3))
            path.close()
            let shape = SCNShape(path: path, extrusionDepth: 0.05)
            shape.chamferRadius = 0.04
            shape.materials = [bandMat]
            let node = SCNNode(geometry: shape)
            node.position = SCNVector3(0, 0, lidAFaceZ + 0.04)
            node.name = "lid"
            node.categoryBitMask = 2
            lidPivot.addChildNode(node)
        }

        // 内侧边框（黑色玻璃感）
        let bezelMat = SCNMaterial()
        bezelMat.lightingModel = .physicallyBased
        bezelMat.diffuse.contents = NSColor(calibratedWhite: 0.022, alpha: 1)
        bezelMat.roughness.contents = 0.28
        bezelMat.metalness.contents = 0.05
        // 官方内框：黑色一直压到顶盖底边（屏幕下方那条“下巴”也是黑的，只留最外一圈银边）
        let bezelPath = NSBezierPath(roundedRect: NSRect(x: -20.0, y: 0.30, width: 40.0, height: 26.1),
                                     xRadius: 0.8, yRadius: 0.8)
        let bezel = SCNShape(path: bezelPath, extrusionDepth: 0.10)
        bezel.chamferRadius = 0.06
        bezel.materials = [bezelMat]
        let bezelNode = SCNNode(geometry: bezel)
        bezelNode.position = SCNVector3(0, 0, 0.02 - bezel.boundingBox.max.z)
        bezelNode.name = "lid"
        bezelNode.categoryBitMask = 2
        lidPivot.addChildNode(bezelNode)

        // 屏幕：优先用内置的 Alien Logo 动效壁纸循环播放，缺失时退回静态壁纸
        let wall = Self.screenWallpaper()
        let screenMat = SCNMaterial()
        screenMat.lightingModel = .constant

        if let videoURL = Bundle.main.url(forResource: "alien_wallpaper", withExtension: "mp4") {
            let item = AVPlayerItem(url: videoURL)
            let player = AVQueuePlayer()
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            wallpaperLooper = AVPlayerLooper(player: player, templateItem: item)
            wallpaperPlayer = player
            player.play()
            let skScene = SKScene(size: CGSize(width: 960, height: 540))
            skScene.scaleMode = .aspectFit
            skScene.backgroundColor = .black
            let videoNode = SKVideoNode(avPlayer: player)
            videoNode.size = CGSize(width: 960, height: 540)
            videoNode.position = CGPoint(x: 480, y: 270)
            videoNode.yScale = -1
            skScene.addChild(videoNode)
            videoNode.play()
            screenMat.diffuse.contents = skScene
            screenMat.emission.contents = NSColor.black
            screenMat.emission.intensity = 0
        } else {
            screenMat.diffuse.contents = wall
            screenMat.emission.contents = wall
            screenMat.emission.intensity = 0.42
        }
        let screen = SCNBox(width: 38.6, height: 21.7, length: 0.05, chamferRadius: 0.06)
        screen.materials = [screenMat]
        let screenNode = SCNNode(geometry: screen)
        screenNode.position = SCNVector3(0, 14.4, 0.12)
        screenNode.name = "screen-link"
        screenNode.categoryBitMask = 3
        lidPivot.addChildNode(screenNode)

        // 摄像头
        let camMat = SCNMaterial()
        camMat.diffuse.contents = NSColor.black
        let camera = SCNCylinder(radius: 0.14, height: 0.05)
        camera.materials = [camMat]
        let cameraNode = SCNNode(geometry: camera)
        cameraNode.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        cameraNode.position = SCNVector3(0, 25.8, 0.26)
        cameraNode.categoryBitMask = 2
        lidPivot.addChildNode(cameraNode)

        // 后部排气格栅
        let ventMat = SCNMaterial()
        ventMat.lightingModel = .physicallyBased
        ventMat.diffuse.contents = NSColor(calibratedWhite: 0.015, alpha: 1)
        ventMat.roughness.contents = 0.9
        // 后部“尾翼”导轨：官方合盖/开盖渲染里，铰链后方有一道高出桌面线的黑色散热翼
        do {
            let rail = SCNBox(width: bodyWidth - 0.6, height: 0.72, length: 1.45, chamferRadius: 0.18)
            rail.materials = [shroudMat]
            let node = SCNNode(geometry: rail)
            node.position = SCNVector3(0, 1.86, -16.02)
            node.categoryBitMask = 2
            root.addChildNode(node)
        }

        // 导轨上的密集散热鳍片：左右两组，中间留出接口面板
        for side in [CGFloat(-1), CGFloat(1)] {
            for i in 0..<18 {
                // 官方后部是一整排密集鳍片（18 道/侧），之前 11 道、间距 0.82 太稀
                let rib = SCNBox(width: 0.29, height: 1.15, length: 0.72, chamferRadius: 0.04)
                rib.materials = [ventMat]
                let node = SCNNode(geometry: rib)
                node.position = SCNVector3(side * (1.25 + CGFloat(i) * 0.56), 2.66, -16.22)
                node.categoryBitMask = 2
                root.addChildNode(node)
            }
        }
        // 后部 I/O 两侧竖向散热鳍片
        for side in [CGFloat(-1), CGFloat(1)] {
            for i in 0..<9 {
                let fin = SCNBox(width: 0.09, height: 1.15, length: 0.62, chamferRadius: 0.02)
                fin.materials = [ventMat]
                let node = SCNNode(geometry: fin)
                node.position = SCNVector3(side * (bodyWidth / 2 - 0.30), 1.56, -16.4 + CGFloat(i) * 0.62)
                node.categoryBitMask = 2
                root.addChildNode(node)
            }
        }

        // 后部接口：官方实拍每个口外面有一圈浅灰金属边框，口内是纯黑凹槽；最后两个音频口是圆形
        let portMat = SCNMaterial()
        portMat.lightingModel = .physicallyBased
        portMat.diffuse.contents = NSColor(calibratedWhite: 0.02, alpha: 1)
        let rimMat = SCNMaterial()
        rimMat.lightingModel = .physicallyBased
        rimMat.diffuse.contents = NSColor(calibratedWhite: 0.30, alpha: 1)
        rimMat.metalness.contents = 0.55
        rimMat.roughness.contents = 0.45
        // 官方后部接口顺序（从左到右）：RJ45 → mini-DP → HDMI → Thunderbolt 3 → 外置显卡扩充口 → 电源
        let portWidths: [CGFloat] = [1.55, 0.95, 1.45, 0.80, 1.35, 1.20]
        let gap: CGFloat = 0.62
        let totalW = portWidths.reduce(0, +) + gap * CGFloat(portWidths.count - 1)
        // 官方后 3/4 渲染里这组口整体落在后缘左半侧，右半侧留给中段散热格栅与铰链
        var portX: CGFloat = -totalW / 2 - 2.0
        for w in portWidths {
            let cx = portX + w / 2
            let rim = SCNBox(width: w + 0.12, height: 0.68, length: 0.08, chamferRadius: 0.05)
            rim.materials = [rimMat]
            let rimNode = SCNNode(geometry: rim)
            rimNode.position = SCNVector3(cx, 1.02, -bodyDepth / 2 - 0.01)
            rimNode.categoryBitMask = 2
            root.addChildNode(rimNode)

            let port = SCNBox(width: w, height: 0.58, length: 0.12, chamferRadius: 0.05)
            port.materials = [portMat]
            let portNode = SCNNode(geometry: port)
            portNode.position = SCNVector3(cx, 1.02, -bodyDepth / 2 - 0.03)
            portNode.categoryBitMask = 2
            root.addChildNode(portNode)
            portX += w + gap
        }

        // 后部圆角尾翼（官方侧视：铰链后方是圆弧收尾，不是直角）
        do {
            let tail = SCNCylinder(radius: 1.10, height: bodyWidth - 1.0)
            tail.materials = [shroudMat]
            let node = SCNNode(geometry: tail)
            node.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
            node.position = SCNVector3(0, 1.30, -15.62)
            node.categoryBitMask = 2
            root.addChildNode(node)
        }

        // 左右两侧排气格栅：按 17 R4 后 3/4 官方渲染（1220×440）改成 6 道窄而高的槽
        func sideVents(_ side: CGFloat, centerZ: CGFloat) {
            do {
                let plate = SCNBox(width: 0.06, height: 0.66, length: 4.1, chamferRadius: 0.10)
                plate.materials = [shellMaterial(0.38, 0.382, 0.386, metal: 0.55, rough: 0.34)]
                let node = SCNNode(geometry: plate)
                node.position = SCNVector3(side * (bodyWidth / 2 - 0.02), 1.02, centerZ)
                node.categoryBitMask = 2
                root.addChildNode(node)
            }
            for i in 0..<6 {
                let slot = SCNBox(width: 0.12, height: 0.42, length: 0.40, chamferRadius: 0.03)
                slot.materials = [ventMat]
                let slotNode = SCNNode(geometry: slot)
                slotNode.position = SCNVector3(side * (bodyWidth / 2 - 0.05), 1.02,
                                               centerZ - 1.70 + CGFloat(i) * 0.68)
                slotNode.categoryBitMask = 2
                root.addChildNode(slotNode)
            }
        }
        sideVents(-1, centerZ: -7.9)    // 左侧：锁孔与 USB-C 之间
        sideVents(1, centerZ: -8.6)     // 右侧：USB 3.0 之后

        // 侧面接口：位置按 Dell 官方左右侧视图量出来的 z 坐标（后 → 前）
        let sidePortMat = SCNMaterial()
        sidePortMat.lightingModel = .physicallyBased
        sidePortMat.diffuse.contents = NSColor(calibratedWhite: 0.03, alpha: 1)
        sidePortMat.roughness.contents = 0.75
        func sideHole(_ side: CGFloat, z: CGFloat, len: CGFloat, hgt: CGFloat) {
            let hole = SCNBox(width: 0.16, height: hgt, length: len, chamferRadius: 0.06)
            hole.materials = [sidePortMat]
            let node = SCNNode(geometry: hole)
            node.position = SCNVector3(side * (bodyWidth / 2 - 0.02), 0.70, z)
            node.categoryBitMask = 2
            root.addChildNode(node)
        }
        // 左侧（-x）：Noble 锁 -13.7、USB-C -1.5、USB 3.0 0.6、耳机 2.5、麦克风 4.0
        sideHole(-1, z: -13.7, len: 0.85, hgt: 0.32)      // Noble 锁孔
        sideHole(-1, z: -1.9, len: 0.85, hgt: 0.38)       // USB-C
        sideHole(-1, z: 0.3, len: 0.72, hgt: 0.44)        // USB 3.0 PowerShare
        sideHole(-1, z: 1.75, len: 0.55, hgt: 0.55)       // 耳机
        sideHole(-1, z: 3.15, len: 0.55, hgt: 0.55)       // 麦克风
        // 右侧（+x）：USB 3.0 -3.6，排气格栅在其后
        sideHole(1, z: -3.6, len: 0.85, hgt: 0.44)
        // 后部电源接口（官方后部清单第 6 项）
        do {
            let hole = SCNBox(width: 1.15, height: 0.45, length: 0.1, chamferRadius: 0.05)
            hole.materials = [sidePortMat]
            let node = SCNNode(geometry: hole)
            node.position = SCNVector3(12.2, 1.15, -bodyDepth / 2 - 0.02)
            node.categoryBitMask = 2
            root.addChildNode(node)
        }

    }


    /// 生成宽字距品牌字标贴图（透明底），SCNText 在 SceneKit 里太细不显影，必须走贴图
    private static func wordmarkImage(_ text: String, kern: CGFloat, color: NSColor) -> NSImage? {
        let font = NSFont.systemFont(ofSize: 40, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
        let str = text as NSString
        let ts = str.size(withAttributes: attrs)
        let size = NSSize(width: ceil(ts.width) + 8, height: ceil(ts.height) + 8)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        str.draw(at: NSPoint(x: 4, y: 4), withAttributes: attrs)
        image.unlockFocus()
        return image
    }

    /// 生成键帽丝印贴图（透明底 + 浅灰字），供 SCNPlane 贴面使用
    private static func silkscreenImage(_ text: String) -> NSImage? {
        let size = NSSize(width: 128, height: 128)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 96, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.72, alpha: 1)
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let textSize = str.size()
        str.draw(at: NSPoint(x: (size.width - textSize.width) / 2,
                             y: (size.height - textSize.height) / 2))
        image.unlockFocus()
        return image
    }


    /// 主键区每行 14 列的键帽铭牌（US 布局，空格与空白格用空串）
    private static let keyLegends: [[String]] = [
        ["Esc", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12", "PrtSc"],
        ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "⌫"],
        ["Tab", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]", "\\"],
        ["Caps", "A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'", "Enter", "Enter"],
        ["Shift", "Z", "X", "C", "Space", "", "", "V", "B", "N", "M", "", "", ""]
    ]

    /// 数字键盘 5 行 4 列铭牌
    private static let numpadLegends: [[String]] = [
        ["NumLk", "/", "*", "-"],
        ["7", "8", "9", "+"],
        ["4", "5", "6", "+"],
        ["1", "2", "3", "⏎"],
        ["0", "0", ".", "⏎"]
    ]

    private static var legendCache: [String: NSImage] = [:]

    /// 生成键帽铭牌贴图（透明底浅灰字），供 SCNPlane 贴到键帽顶面
    private static func legendImage(_ text: String) -> NSImage? {
        if let cached = legendCache[text] { return cached }
        let size = NSSize(width: 256, height: 160)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        let fontSize: CGFloat = text.count >= 4 ? 38 : (text.count >= 3 ? 54 : 88)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.93, alpha: 1)
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let textSize = str.size()
        str.draw(at: NSPoint(x: (size.width - textSize.width) / 2,
                             y: (size.height - textSize.height) / 2))
        image.unlockFocus()
        legendCache[text] = image
        return image
    }

    private func buildKeyboard(_ root: SCNNode) {
        // 按 Dell 官方 17 R4 顶视图重建键位：左侧 6 颗宏键列、数字键盘含顶部 4 颗宏键共 6 行、
        // 方向键为 3×2 半高小键（PgUp ▲ PgDn / ◄ ▼ ►）
        let keyY: CGFloat = 2.05
        let u: CGFloat = 1.80              // 1 键位单位
        // 官方顶视：键盘块更贴铰链，掌托留白更宽 → 整体后移 1.2cm
        let startZ: CGFloat = -7.55
        let rowPitch: CGFloat = 1.80
        let keyGap: CGFloat = 0.14
        let blockGap: CGFloat = 0.3 * 1.80

        let mainLeft: CGFloat = -16.2       // 宏键列之后，主键区 15u
        let numpadLeft: CGFloat = 11.34     // 数字键盘起始
        let macroX: CGFloat = -17.45        // 宏键列中心（比主键窄一圈，且紧贴主键区）

        func zoneFor(x: CGFloat) -> LightZone {
            if x < -7.2 { return .keyboardLeft }
            if x < 1.8 { return .keyboardMidLeft }
            return .keyboardMidRight
        }

        func key(_ x: CGFloat, _ z: CGFloat, _ w: CGFloat, _ d: CGFloat, zone: LightZone?, id: String,
                 label: String = "") {
            let cap = SCNMaterial()
            cap.lightingModel = .physicallyBased
            // 官方键帽比掌托浅一档（#888D90 vs #676767）
            cap.diffuse.contents = NSColor(calibratedWhite: 0.395, alpha: 1)
            cap.roughness.contents = 0.68
            cap.metalness.contents = 0.06
            cap.emission.contents = NSColor.black
            cap.emission.intensity = 0

            // 官方实拍（laptopmedia 1000×653 正视）键帽顶面是哑光浅灰，会随光线有明暗，不是一块死白发亮的面
            let top = SCNMaterial()
            top.lightingModel = .physicallyBased
            top.diffuse.contents = NSColor(calibratedWhite: 0.470, alpha: 1)
            top.roughness.contents = 0.78
            top.metalness.contents = 0.03
            top.emission.contents = NSColor.black
            top.emission.intensity = 0.0

            let box = SCNBox(width: w, height: 0.24, length: d, chamferRadius: 0.10)
            box.materials = [cap, cap, cap, cap, top, cap]
            let node = SCNNode(geometry: box)
            node.position = SCNVector3(x, keyY, z)
            if let zone = zone {
                node.categoryBitMask = 1
                node.name = "zone-\(zone.rawValue)#key-\(id)"

                let glow = SCNMaterial()
                glow.lightingModel = .constant
                glow.diffuse.contents = NSColor.black
                glow.emission.contents = NSColor.black
                glow.emission.intensity = 0
                glow.isDoubleSided = true
                let halo = SCNPlane(width: w + 0.10, height: d + 0.10)
                halo.cornerRadius = 0.05
                halo.materials = [glow]
                let haloNode = SCNNode(geometry: halo)
                haloNode.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0)
                haloNode.position = SCNVector3(x, keyY + 0.11, z)
                haloNode.categoryBitMask = 2
                haloNode.name = "zone-\(zone.rawValue)#halo-\(id)"
                root.addChildNode(haloNode)

                registerKeyTop(glow, zone: zone, id: id)
            } else {
                node.categoryBitMask = 2
            }
            root.addChildNode(node)

            if !label.isEmpty, let legend = Self.legendImage(label) {
                let mat = SCNMaterial()
                mat.lightingModel = .constant
                mat.diffuse.contents = legend
                // 官方暗场实拍里键帽字标本身是发光的：字标材质带自发光并跟随所在灯区颜色
                mat.emission.contents = NSColor.black
                mat.emission.intensity = 0
                mat.name = "keyLegend"
                if let zone = zone { registerKeyTop(mat, zone: zone, id: id) }
                mat.transparencyMode = .aOne
                mat.isDoubleSided = true
                mat.writesToDepthBuffer = false
                // 官方键帽上的字标只占键面宽度的六成左右（此前 0.85 偏大，顶视里几乎压满键面）
                let planeW = min(w * 0.58, 2.2)
                let plane = SCNPlane(width: planeW, height: planeW * 0.625)
                plane.materials = [mat]
                let textNode = SCNNode(geometry: plane)
                textNode.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0)
                textNode.position = SCNVector3(x, keyY + 0.135, z)
                textNode.categoryBitMask = 2
                root.addChildNode(textNode)
            }
        }

        func layoutRow(_ row: Int, _ items: [(String, CGFloat)]) {
            var cursor = mainLeft
            let z = startZ + CGFloat(row) * rowPitch
            for (label, units) in items {
                let w = units * u - keyGap
                let x = cursor + units * u / 2
                key(x, z, w, rowPitch - 0.16, zone: zoneFor(x: x),
                    id: "main-r\(row)c\(Int(cursor * 10))", label: label)
                cursor += units * u
            }
        }

        layoutRow(0, [("Esc", 1.0)] + (1...12).map { ("F\($0)", 1.0) }
                  + [("Home", 0.75), ("End", 0.65), ("Del", 0.6)])
        layoutRow(1, [("`", 1.0), ("1", 1.0), ("2", 1.0), ("3", 1.0), ("4", 1.0), ("5", 1.0),
                      ("6", 1.0), ("7", 1.0), ("8", 1.0), ("9", 1.0), ("0", 1.0), ("-", 1.0),
                      ("=", 1.0), ("⌫", 2.0)])
        layoutRow(2, [("Tab", 1.5), ("Q", 1.0), ("W", 1.0), ("E", 1.0), ("R", 1.0), ("T", 1.0),
                      ("Y", 1.0), ("U", 1.0), ("I", 1.0), ("O", 1.0), ("P", 1.0), ("[", 1.0),
                      ("]", 1.0), ("\\", 1.5)])
        layoutRow(3, [("Caps", 1.75), ("A", 1.0), ("S", 1.0), ("D", 1.0), ("F", 1.0), ("G", 1.0),
                      ("H", 1.0), ("J", 1.0), ("K", 1.0), ("L", 1.0), (";", 1.0), ("'", 1.0),
                      ("Enter", 2.25)])
        layoutRow(4, [("Shift", 2.25), ("Z", 1.0), ("X", 1.0), ("C", 1.0), ("V", 1.0), ("B", 1.0),
                      ("N", 1.0), ("M", 1.0), (",", 1.0), (".", 1.0), ("/", 1.0), ("Shift", 2.75)])
        layoutRow(5, [("Ctrl", 1.25), ("Fn", 1.25), ("Win", 1.25), ("Alt", 1.25), ("", 4.5),
                      ("Alt", 1.25), ("Ctrl", 1.25)])

        // 左侧宏键列：6 颗，与六行一一对应
        let macroLabels = ["ΔX", "Δ1", "Δ2", "Δ3", "Δ4", "Δ5"]
        for row in 0..<6 {
            key(macroX, startZ + CGFloat(row) * rowPitch, 1.58, rowPitch - 0.16,
                zone: .macroKeys, id: "macro-\(row)", label: macroLabels[row])
        }

        // 方向键簇：官方 17 R4 顶视实拍里，它是主键区右下角与数字键盘之间的一块 3×2 小键区
        // 上排 PAGE UP / ▲ / PAGE DN 与主键盘底排（Ctrl 行）齐平，下排 ◄ ▼ ► 再往下一行探进槽底
        do {
            let arrowLeft: CGFloat = 5.85       // 主键区底排右缘 5.40 之后留 0.45 的缝
            let pitch: CGFloat = 1.65
            let smallW: CGFloat = 1.50
            let smallD: CGFloat = 1.36
            let topZ = startZ + 5.0 * rowPitch
            let botZ = topZ + 1.45
            let tops = ["PgUp", "▲", "PgDn"]
            let bots = ["◄", "▼", "►"]
            for col in 0..<3 {
                let x = arrowLeft + pitch * CGFloat(col) + smallW / 2
                key(x, topZ, smallW, smallD, zone: .keyboardMidRight, id: "arrow-t\(col)", label: tops[col])
                key(x, botZ, smallW, smallD, zone: .keyboardMidRight, id: "arrow-b\(col)", label: bots[col])
            }
        }

        // 数字键盘：4 列 × 6 行（顶行 4 颗宏键），+ / Enter / 0 跨行跨列
        do {
            let kd = rowPitch - 0.16
            let kw = u - 0.14
            func np(_ col: CGFloat, _ row: CGFloat, _ label: String, w: CGFloat, d: CGFloat) {
                let x = numpadLeft + u * col
                let z = startZ + row * rowPitch
                key(x, z, w, d, zone: .keyboardRight, id: "num-\(Int(col))-\(Int(row))", label: label)
            }
            let npTopLabels = ["Δ6", "Δ7", "Δ8", "Δ9"]
            for col in 0..<4 {
                np(CGFloat(col) + 0.5, 0, npTopLabels[col], w: kw, d: kd)
            }
            np(0.5, 1, "NumLk", w: kw, d: kd)
            np(1.5, 1, "/", w: kw, d: kd)
            np(2.5, 1, "*", w: kw, d: kd)
            np(3.5, 1, "-", w: kw, d: kd)
            np(0.5, 2, "7", w: kw, d: kd)
            np(1.5, 2, "8", w: kw, d: kd)
            np(2.5, 2, "9", w: kw, d: kd)
            np(3.5, 2.5, "+", w: kw, d: 2 * rowPitch - 0.16)
            np(0.5, 3, "4", w: kw, d: kd)
            np(1.5, 3, "5", w: kw, d: kd)
            np(2.5, 3, "6", w: kw, d: kd)
            np(0.5, 4, "1", w: kw, d: kd)
            np(1.5, 4, "2", w: kw, d: kd)
            np(2.5, 4, "3", w: kw, d: kd)
            np(3.5, 4.5, "Enter", w: kw, d: 2 * rowPitch - 0.16)
            np(1.0, 5, "0", w: 2 * u - 0.14, d: kd)
            np(2.5, 5, ".", w: kw, d: kd)
            _ = blockGap
        }
    }

    // MARK: 灯区

    private func buildZones(_ root: SCNNode) {
        addScreenLogo()
        addAlienHead()
        addPowerButton(root)
        addStrips(root)
        addTouchpadFrame(root)
        addKeyboardOutlines(root)
    }

    /// 每个键顶面的材质，用于单键配色
    private var keyMaterials: [(id: String, zone: LightZone, material: SCNMaterial)] = []
    /// 触摸板整面背光材质
    private var touchpadPadMaterial: SCNMaterial?
    /// 触摸板四薄条边光材质
    private var touchpadEdgeMaterials: [SCNMaterial] = []
    /// 电源键外圈与外星头图标材质
    private var powerButtonMaterials: [SCNMaterial] = []
    /// 按下电源键的时间，用于长按识别
    private var powerPressStartedAt = Date()

    private func registerKeyTop(_ material: SCNMaterial, zone: LightZone, id: String) {
        keyMaterials.append((id: id, zone: zone, material: material))
    }

    private func addKeyboardOutlines(_ root: SCNNode) {
        let zCenter: CGFloat = -1.85
        let zSize: CGFloat = 11.0
        addOutline(zone: .keyboardLeft, root: root,
                   center: SCNVector3(-11.7, 2.28, zCenter), size: SCNVector3(9.0, 0.5, zSize))
        addOutline(zone: .keyboardMidLeft, root: root,
                   center: SCNVector3(-2.7, 2.28, zCenter), size: SCNVector3(9.0, 0.5, zSize))
        addOutline(zone: .keyboardMidRight, root: root,
                   center: SCNVector3(6.3, 2.28, zCenter), size: SCNVector3(9.0, 0.5, zSize))
        addOutline(zone: .keyboardRight, root: root,
                   center: SCNVector3(14.94, 2.28, zCenter), size: SCNVector3(7.2, 0.5, zSize))
        addOutline(zone: .macroKeys, root: root,
                   center: SCNVector3(-17.64, 2.28, zCenter), size: SCNVector3(1.8, 0.5, zSize))
    }

    private func addOutline(zone: LightZone, root: SCNNode, center: SCNVector3, size: SCNVector3,
                            parent: SCNNode? = nil) {
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.diffuse.contents = NSColor(calibratedRed: 0.3, green: 0.95, blue: 1.0, alpha: 0.5)
        mat.emission.contents = NSColor(calibratedRed: 0.3, green: 0.95, blue: 1.0, alpha: 1)
        mat.emission.intensity = 0.7
        mat.isDoubleSided = true
        mat.writesToDepthBuffer = false
        mat.readsFromDepthBuffer = true
        mat.blendMode = .alpha

        // 贴合表面的细边框：四条薄条，避免出现悬空的线框盒
        let node = SCNNode()
        let barThickness: CGFloat = 0.12
        let barHeight: CGFloat = 0.03
        let bars: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0,  size.z / 2, size.x, barThickness),
            (0, -size.z / 2, size.x, barThickness),
            (-size.x / 2, 0, barThickness, size.z),
            ( size.x / 2, 0, barThickness, size.z)
        ]
        for (x, z, w, d) in bars {
            let bar = SCNBox(width: w, height: barHeight, length: d, chamferRadius: 0.02)
            bar.materials = [mat]
            let barNode = SCNNode(geometry: bar)
            barNode.position = SCNVector3(x, 0, z)
            node.addChildNode(barNode)
        }
        node.position = center
        node.name = "outline-\(zone.rawValue)"
        node.categoryBitMask = 4
        node.renderingOrder = 120
        node.isHidden = true
        (parent ?? root).addChildNode(node)

        var visual = zoneEntries[zone] ?? ZoneVisual(node: node, materials: [], outline: node, glowIntensity: 1)
        visual = ZoneVisual(node: visual.node, materials: visual.materials, outline: node,
                            glowIntensity: visual.glowIntensity)
        zoneEntries[zone] = visual
    }

    private func ensureEntry(_ zone: LightZone, materials: [SCNMaterial]) {
        if var visual = zoneEntries[zone] {
            visual = ZoneVisual(node: visual.node, materials: visual.materials + materials,
                                outline: visual.outline, glowIntensity: visual.glowIntensity)
            zoneEntries[zone] = visual
        } else {
            // 占位节点，outline 稍后补
            let holder = SCNNode()
            let placeholder = SCNNode()
            zoneEntries[zone] = ZoneVisual(node: holder, materials: materials,
                                           outline: placeholder, glowIntensity: 1)
        }
    }

    private func addScreenLogo() {
        // 官方下巴上的 ALIENWARE 字标：字距很宽、浅灰、贴在黑色下巴上
        let mat = SCNMaterial()
        mat.name = "screenWord"
        mat.lightingModel = .constant
        let img = Self.wordmarkImage("ALIENWARE", kern: 22,
                                     color: NSColor(calibratedWhite: 0.92, alpha: 0.96))
        mat.diffuse.contents = img
        mat.diffuse.mipFilter = .none
        mat.transparent.contents = img
        mat.transparencyMode = .aOne
        mat.emission.contents = NSColor.black
        mat.emission.intensity = 0
        mat.isDoubleSided = true
        mat.writesToDepthBuffer = false

        let wordW: CGFloat = 11.0
        let ratio: CGFloat = (img?.size.height ?? 1) / max(img?.size.width ?? 1, 1)
        let plane = SCNPlane(width: wordW, height: wordW * ratio)
        plane.materials = [mat]
        let node = SCNNode(geometry: plane)
        // 官方下巴：字标贴近屏幕下沿，下面留一大片黑，不是居中
        node.position = SCNVector3(0, 2.58, 0.17)
        node.categoryBitMask = 1
        node.name = "zone-\(LightZone.screenLogo.rawValue)"
        lidPivot.addChildNode(node)

        ensureEntry(.screenLogo, materials: [mat])
        addOutline(zone: .screenLogo, root: lidPivot,
                   center: SCNVector3(0, 2.58, 0.13), size: SCNVector3(11.2, 1.7, 0.16), parent: lidPivot)
    }

    private func addAlienHead() {
        // 真实 Alienware 头标贴图（用户提供，带透明通道）
        let logoMat = SCNMaterial()
        logoMat.name = "logoTexture"
        logoMat.lightingModel = .constant
        logoMat.diffuse.contents = Self.lidLogo()
        logoMat.diffuse.wrapS = .clamp
        logoMat.diffuse.wrapT = .clamp
        logoMat.diffuse.minificationFilter = .linear
        logoMat.diffuse.magnificationFilter = .linear
        logoMat.diffuse.mipFilter = .none
        logoMat.transparent.contents = Self.lidLogo()
        logoMat.transparencyMode = .aOne
        logoMat.emission.contents = NSColor.black
        logoMat.emission.intensity = 0
        logoMat.isDoubleSided = true
        logoMat.writesToDepthBuffer = false

        let plane = SCNPlane(width: 3.3, height: 4.68)
        plane.materials = [logoMat]
        let logoNode = SCNNode(geometry: plane)
        logoNode.position = SCNVector3(0, 19.0, lidAFaceZ - 0.075)
        logoNode.eulerAngles = SCNVector3(0, CGFloat.pi, 0)
        logoNode.name = "zone-\(LightZone.alienHead.rawValue)"
        logoNode.categoryBitMask = 1
        lidPivot.addChildNode(logoNode)
        lidLogoNode = logoNode

        ensureEntry(.alienHead, materials: [logoMat])
    }

    private func addPowerButton(_ root: SCNNode) {
        // 官方口径：键盘正上方黑板条中央、与键盘水平居中的外星人头标；
        // 用与 A 面同一张 lid_logo 贴图（文件级透明通道，比运行时画的贴图可靠）
        let stripTop: CGFloat = deckTop + 0.24
        let buttonZ: CGFloat = -11.75
        let logoW: CGFloat = 1.42                      // 官方电源键直径约 2.1cm，头标约占 1.4cm
        let logoH: CGFloat = logoW * 580 / 408

        let mat = SCNMaterial()
        mat.name = "powerLogo"
        mat.lightingModel = .constant
        mat.diffuse.contents = Self.lidLogo()
        mat.diffuse.wrapS = .clamp
        mat.diffuse.wrapT = .clamp
        mat.diffuse.minificationFilter = .linear
        mat.diffuse.magnificationFilter = .linear
        mat.diffuse.mipFilter = .none
        // 关键：用同一张图当透明度贴图，quads 才有真正的透明通道
        mat.transparent.contents = Self.lidLogo()
        mat.transparencyMode = .aOne
        mat.emission.contents = NSColor.black
        mat.emission.intensity = 0
        mat.isDoubleSided = true
        mat.writesToDepthBuffer = false

        // 官方实拍：电源键是嵌在黑板条上的圆形键帽——圆形底座 + 一圈金属环，头标在圆内
        let disc = SCNCylinder(radius: 1.05, height: 0.10)
        let discMat = SCNMaterial()
        discMat.lightingModel = .physicallyBased
        discMat.diffuse.contents = NSColor(calibratedWhite: 0.035, alpha: 1)
        discMat.metalness.contents = 0.25
        discMat.roughness.contents = 0.55
        disc.materials = [discMat]
        let discNode = SCNNode(geometry: disc)
        discNode.position = SCNVector3(0, stripTop + 0.006, buttonZ)
        discNode.categoryBitMask = 2
        root.addChildNode(discNode)

        let ring = SCNTorus(ringRadius: 1.05, pipeRadius: 0.06)
        let ringMat = SCNMaterial()
        ringMat.lightingModel = .physicallyBased
        ringMat.diffuse.contents = NSColor(calibratedWhite: 0.38, alpha: 1)
        ringMat.metalness.contents = 0.65
        ringMat.roughness.contents = 0.38
        ring.materials = [ringMat]
        let ringNode = SCNNode(geometry: ring)
        ringNode.position = SCNVector3(0, stripTop + 0.058, buttonZ)
        ringNode.categoryBitMask = 2
        root.addChildNode(ringNode)

        let plane = SCNPlane(width: logoW, height: logoH)
        plane.materials = [mat]
        let node = SCNNode(geometry: plane)
        node.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0)
        node.position = SCNVector3(0, stripTop + 0.062, buttonZ)
        node.categoryBitMask = 1
        node.name = "zone-\(LightZone.powerButton.rawValue)"
        root.addChildNode(node)

        ensureEntry(.powerButton, materials: [mat])
        powerButtonMaterials = [mat]
        addOutline(zone: .powerButton, root: root,
                   center: SCNVector3(0, stripTop + 0.05, buttonZ),
                   size: SCNVector3(1.9, 0.5, 1.9))
    }

    private func addStrips(_ root: SCNNode) {
        func strip(zone: LightZone, x: CGFloat, z: CGFloat, width: CGFloat, y: CGFloat) {
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.diffuse.contents = NSColor(calibratedWhite: 0.05, alpha: 1)
            mat.emission.contents = NSColor.black
            mat.emission.intensity = 0

            let bar = SCNBox(width: width, height: 0.14, length: 0.30, chamferRadius: 0.06)
            bar.materials = [mat]
            let node = SCNNode(geometry: bar)
            node.position = SCNVector3(x, y, z)
            if z > 0 { node.eulerAngles = SCNVector3(-0.16, 0, 0) }
            node.categoryBitMask = 1
            node.name = "zone-\(zone.rawValue)"
            root.addChildNode(node)

            ensureEntry(zone, materials: [mat])
            addOutline(zone: zone, root: root,
                       center: SCNVector3(x, y, z), size: SCNVector3(width + 1.0, 0.7, 1.2))
        }

        // 基座左右侧边灯条：靠单条光线贯穿整个侧边（与官方侧视图一致）
        for (side, zone) in [(CGFloat(-1), LightZone.tronLeft), (CGFloat(1), LightZone.tronRight)] {
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.diffuse.contents = NSColor(calibratedWhite: 0.05, alpha: 1)
            mat.emission.contents = NSColor.black
            mat.emission.intensity = 0

            // 官方侧视图两条红线：侧面上缘一条、下缘一条，都贯通全长
            let bar = SCNBox(width: 0.30, height: 0.13, length: 30.2, chamferRadius: 0.05)
            bar.materials = [mat]
            let node = SCNNode(geometry: bar)
            node.position = SCNVector3(side * (bodyWidth / 2), 0.72, 0.6)
            node.categoryBitMask = 1
            node.name = "zone-\(zone.rawValue)"
            root.addChildNode(node)

            ensureEntry(zone, materials: [mat])
            addOutline(zone: zone, root: root,
                       center: SCNVector3(side * (bodyWidth / 2), 0.72, 0.6),
                       size: SCNVector3(0.9, 0.6, 31.1))
        }

        // 顶盖左右侧边竖条（真实机是盖上的侧边灯条，不在后部散热口上）
        for (side, zone) in [(CGFloat(-1), LightZone.lcdPanelLeft), (CGFloat(1), LightZone.lcdPanelRight)] {
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.diffuse.contents = NSColor(calibratedWhite: 0.05, alpha: 1)
            mat.emission.contents = NSColor.black
            mat.emission.intensity = 0

            // 官方纯侧视实拍（YeU7VUX65v 625×599）：顶盖侧灯条几乎整条顶盖高度都亮，
            // 下到铰链上方约 1.2cm，上到折肩前约 0.2cm，只在最上端的收角处断开
            let bar = SCNBox(width: 0.12, height: 21.2, length: 0.5, chamferRadius: 0.06)
            bar.materials = [mat]
            let node = SCNNode(geometry: bar)
            node.position = SCNVector3(side * (21.30 + 0.02), 11.80, -0.34)
            node.categoryBitMask = 1
            node.name = "zone-\(zone.rawValue)"
            lidPivot.addChildNode(node)

            // 折肩以上机身边缘往内收，灯条跟着这条斜边继续走到折肩前 0.2cm，不能悬在轮廓外
            let slopeLen: CGFloat = 3.13
            let slopeBox = SCNBox(width: 0.12, height: slopeLen, length: 0.5, chamferRadius: 0.05)
            slopeBox.materials = [mat]
            let slopeNode = SCNNode(geometry: slopeBox)
            slopeNode.position = SCNVector3(side * 20.99, 23.9, -0.34)
            slopeNode.eulerAngles = SCNVector3(0, 0, side * 0.291)
            slopeNode.categoryBitMask = 1
            slopeNode.name = "zone-\(zone.rawValue)"
            lidPivot.addChildNode(slopeNode)

            ensureEntry(zone, materials: [mat])
            addOutline(zone: zone, root: lidPivot,
                       center: SCNVector3(side * (21.30 + 0.02), 13.20, -0.34),
                       size: SCNVector3(0.7, 24.2, 0.9))
        }
    }

    private func addTouchpadFrame(_ root: SCNNode) {
        // 官方 17 R4：窄长触控板 + 下方左右两颗独立按键，不是一块大板
        let padMat = SCNMaterial()
        padMat.lightingModel = .constant
        padMat.diffuse.contents = NSColor(calibratedWhite: 0.06, alpha: 1)
        padMat.emission.contents = NSColor.black
        padMat.emission.intensity = 0

        let edgeMat = SCNMaterial()
        edgeMat.lightingModel = .constant
        edgeMat.diffuse.contents = NSColor(calibratedWhite: 0.06, alpha: 1)
        edgeMat.emission.contents = NSColor.black
        edgeMat.emission.intensity = 0

        // 发光面必须与玻璃面板完全重合，否则点亮时红块会偏出触控板本体
        let padW = touchpadWidth
        let padD = touchpadDepth
        let padX = touchpadCenterX
        let padZ = touchpadCenterZ

        let pad = SCNPlane(width: padW, height: padD)
        pad.cornerRadius = 0.35
        pad.materials = [padMat]
        let padNode = SCNNode(geometry: pad)
        padNode.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0)
        padNode.position = SCNVector3(padX, deckTop + 0.045, padZ)
        padNode.categoryBitMask = 1
        padNode.name = "zone-\(LightZone.touchpad.rawValue)"
        root.addChildNode(padNode)

        // 触控板四周一圈亮边
        let thickness: CGFloat = 0.18
        let parts: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0, padD / 2, padW, thickness),
            (0, -padD / 2, padW, thickness),
            (-padW / 2, 0, thickness, padD),
            (padW / 2, 0, thickness, padD)
        ]
        let group = SCNNode()
        group.name = "zone-\(LightZone.touchpad.rawValue)"
        group.categoryBitMask = 1
        for (x, z, w, d) in parts {
            let box = SCNBox(width: w, height: 0.06, length: d, chamferRadius: 0.03)
            box.materials = [edgeMat]
            let child = SCNNode(geometry: box)
            child.position = SCNVector3(x + padX, deckTop + 0.055, padZ + z)
            child.categoryBitMask = 1
            child.name = "zone-\(LightZone.touchpad.rawValue)"
            group.addChildNode(child)
        }
        root.addChildNode(group)

        // 板沿外侧一圈极细的泄光带（实拍里触控板点亮时边缘有一层很淡的彩光外溢，不是硬边）
        let haloMat = SCNMaterial()
        haloMat.lightingModel = .constant
        haloMat.diffuse.contents = NSColor(calibratedWhite: 0.055, alpha: 1)
        haloMat.emission.contents = NSColor.black
        haloMat.emission.intensity = 0
        let haloW = padW + 0.62, haloD = padD + 0.62
        let haloParts: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0, haloD / 2, haloW, 0.10),
            (0, -haloD / 2, haloW, 0.10),
            (-haloW / 2, 0, 0.10, haloD),
            (haloW / 2, 0, 0.10, haloD)
        ]
        for (x, z, w, d) in haloParts {
            let box = SCNBox(width: w, height: 0.035, length: d, chamferRadius: 0.02)
            box.materials = [haloMat]
            let hn = SCNNode(geometry: box)
            hn.position = SCNVector3(x + padX, deckTop + 0.018, padZ + z)
            hn.categoryBitMask = 2
            root.addChildNode(hn)
        }

        // 下方左右两颗实体按键
        let btnMat = SCNMaterial()
        btnMat.lightingModel = .constant
        btnMat.diffuse.contents = NSColor(calibratedWhite: 0.07, alpha: 1)
        btnMat.emission.contents = NSColor.black
        btnMat.emission.intensity = 0
        for (idx, dx) in [CGFloat(-2.50), CGFloat(2.50)].enumerated() {
            // 官方近拍（chiphell rLIEQMjlpQ 980×653）：左右键落在触控板下沿，各自占板宽一半，中间只有一条细缝
            let btn = SCNBox(width: 4.90, height: 0.10, length: 0.98, chamferRadius: 0.08)
            btn.materials = [btnMat]
            let node = SCNNode(geometry: btn)
            node.position = SCNVector3(padX + dx, deckTop + 0.03, padZ + padD / 2 + 0.55)
            node.categoryBitMask = 1
            node.name = "zone-\(LightZone.touchpad.rawValue)#btn-\(idx)"
            root.addChildNode(node)
        }

        touchpadPadMaterial = padMat
        touchpadEdgeMaterials = [edgeMat, haloMat]
        // 选中描边要与板体同心：之前 z 上多偏 0.60、深度多 2.4，看起来像"框歪到下沿"
        addOutline(zone: .touchpad, root: root,
                   center: SCNVector3(padX, deckTop + 0.07, padZ),
                   size: SCNVector3(padW + 0.5, 0.4, padD + 0.5))
    }

    // MARK: 灯光

    private func buildLights(_ scene: SCNScene) {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = NSColor(calibratedRed: 0.55, green: 0.62, blue: 0.78, alpha: 1)
        ambient.light?.intensity = 260
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.color = NSColor(calibratedRed: 0.95, green: 0.97, blue: 1.0, alpha: 1)
        key.light?.intensity = 420
        key.light?.attenuationStartDistance = 10
        key.light?.attenuationEndDistance = 140
        key.position = SCNVector3(-22, 42, 28)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .omni
        fill.light?.color = NSColor(calibratedRed: 0.90, green: 0.93, blue: 1.0, alpha: 1)
        fill.light?.intensity = 110
        fill.light?.attenuationEndDistance = 120
        fill.position = SCNVector3(30, 16, -26)
        scene.rootNode.addChildNode(fill)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.color = NSColor(calibratedRed: 0.85, green: 0.9, blue: 1.0, alpha: 1)
        sun.light?.intensity = 520
        sun.light?.castsShadow = false
        sun.position = SCNVector3(-26, 46, 34)
        sun.eulerAngles = SCNVector3(-0.62, -0.45, 0)
        scene.rootNode.addChildNode(sun)

        // 顶盖 A 面补光：合盖/看顶盖时给银色面板拉出明暗渐变
        let lidFill = SCNNode()
        lidFill.light = SCNLight()
        lidFill.light?.type = .omni
        lidFill.light?.color = NSColor(calibratedRed: 0.98, green: 0.98, blue: 0.985, alpha: 1)
        lidFill.light?.intensity = 620
        lidFill.light?.attenuationStartDistance = 8
        lidFill.light?.attenuationEndDistance = 150
        lidFill.position = SCNVector3(-2, 52, -64)
        scene.rootNode.addChildNode(lidFill)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .omni
        rim.light?.color = NSColor(calibratedRed: 0.80, green: 0.84, blue: 1.0, alpha: 1)
        rim.light?.intensity = 110
        rim.light?.attenuationEndDistance = 110
        rim.position = SCNVector3(2, 10, 34)
        scene.rootNode.addChildNode(rim)
    }

    // MARK: 相机

    private func buildCamera(_ scene: SCNScene) {
        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.projectionDirection = .vertical
        camera.zNear = 5
        camera.zFar = 600
        camera.wantsHDR = true
        camera.bloomIntensity = 0.3
        camera.bloomThreshold = 0.92
        camera.bloomBlurRadius = 12
        camera.vignettingIntensity = 0.55
        camera.vignettingPower = 2.0
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = 0
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        cameraReady = true
        updateCamera()
    }

    /// 视图被 SwiftUI 重建时用于恢复用户拖出来的机位
    struct CameraState { let theta: CGFloat; let phi: CGFloat; let targetY: CGFloat; let zoom: CGFloat }
    static var lastCamera: CameraState?

    func restoreCamera(_ state: CameraState) {
        theta = state.theta
        phi = state.phi
        targetY = state.targetY
        zoomScale = state.zoom
        updateCamera()
    }

    private func updateCamera() {
        Self.lastCamera = CameraState(theta: theta, phi: phi, targetY: targetY, zoom: zoomScale)
        let r = baseRadius * zoomScale
        let cosPhi = cos(phi)
        let position = SCNVector3(
            r * cosPhi * sin(theta),
            targetY + r * sin(phi),
            r * cosPhi * cos(theta)
        )
        cameraNode.position = position
        cameraNode.look(at: SCNVector3(0, targetY, 0), up: SCNVector3(0, 1, 0),
                        localFront: SCNVector3(0, 0, -1))
    }

    override func layout() {
        super.layout()
        guard cameraReady, bounds.width > 10, bounds.height > 10 else { return }
        let fov = CGFloat((cameraNode.camera?.fieldOfView ?? 30) * .pi / 180)
        let aspect = bounds.width / bounds.height
        let needH: CGFloat = 38
        let needW: CGFloat = 44
        let rH = (needW / 2) / tan(fov / 2)
        let rV = ((needH * aspect) / 2) / tan(fov / 2)
        baseRadius = max(rV, rH) * 1.04
        updateCamera()

    }

    /// 摄像头手势：把角度增量并入当前机位（与鼠标拖动共享同一套 theta / phi）
    func applyGestureOrbit(dTheta: CGFloat, dPhi: CGFloat) {
        theta -= dTheta
        phi = min(1.35, max(-0.10, phi + dPhi))
        updateCamera()
    }

    func setPose(_ pose: ScenePose, animated: Bool) {
        if animated { noteInteraction() }
        let target = pose.orbit
        theta = target.theta
        phi = target.phi
        targetY = target.targetY
        updateCamera()
    }

    // MARK: 开合盖

    func setLid(open: Bool, animated: Bool) {
        guard open != lidIsOpen else { return }
        if animated { noteInteraction() }
        lidIsOpen = open
        // 合盖时屏幕看不见，暂停动效壁纸省电；开盖继续
        if open { wallpaperPlayer?.play() } else { wallpaperPlayer?.pause() }
        let angle = open ? CGFloat(-0.08) : CGFloat.pi / 2
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.7 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        lidPivot.eulerAngles = SCNVector3(angle, 0, 0)
        SCNTransaction.commit()
    }

    // MARK: - 3D 拆解

    private func prepareExplode() {
        lidBasePosition = lidPivot.position
        scene?.rootNode.enumerateChildNodes { node, _ in
            guard let name = node.name else { return }
            var raw: Int?
            if name.hasPrefix("zone-") {
                raw = Int(name.dropFirst(5).split(separator: "#").first ?? "")
            } else if name.hasPrefix("outline-") {
                raw = Int(name.dropFirst(8))
            }
            guard let zoneRaw = raw else { return }
            explodeParts.append(ExplodePart(node: node, base: node.position, zoneRaw: zoneRaw))
        }
    }

    private func explodeOffset(_ zoneRaw: Int) -> SCNVector3 {
        let zone = LightZone(rawValue: UInt32(zoneRaw))
        if zone == .keyboardRight { return SCNVector3(11.0, 9.2, -3.2) }
        if zone == .keyboardMidRight { return SCNVector3(5.2, 9.2, -2.6) }
        if zone == .keyboardMidLeft { return SCNVector3(0, 9.2, -1.0) }
        if zone == .keyboardLeft { return SCNVector3(-5.6, 9.2, -0.4) }
        if zone == .macroKeys { return SCNVector3(-10.4, 9.2, 1.4) }
        if zone == .touchpad { return SCNVector3(0, 5.2, 6.0) }
        if zone == .powerButton { return SCNVector3(-6.5, 11.0, -4.0) }
        if zone == .tronLeft { return SCNVector3(-2.6, 3.2, 8.0) }
        if zone == .tronRight { return SCNVector3(2.6, 3.2, 8.0) }
        if zone == .lcdPanelLeft { return SCNVector3(-2.6, 3.2, -8.0) }
        if zone == .lcdPanelRight { return SCNVector3(2.6, 3.2, -8.0) }
        return SCNVector3Zero
    }

    /// 进入 / 退出 3D 拆解
    func setExploded(_ value: Bool, animated: Bool = true) {
        guard value != isExploded else { return }
        if animated { noteInteraction() }
        isExploded = value

        if value {
            lidBeforeExplode = lidIsOpen
            if lidIsOpen { setLid(open: false, animated: animated) }
        }

        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.8 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        if value {
            lidPivot.position = SCNVector3(lidBasePosition.x, lidBasePosition.y + 20.0, lidBasePosition.z - 2.0)
            for part in explodeParts {
                let offset = explodeOffset(part.zoneRaw)
                part.node.position = SCNVector3(part.base.x + offset.x,
                                                part.base.y + offset.y,
                                                part.base.z + offset.z)
            }
            zoomBeforeExplode = zoomScale
            thetaBeforeExplode = theta
            phiBeforeExplode = phi
            targetYBeforeExplode = targetY
            theta = 0.52
            phi = 0.30
            targetY = 19.0
            zoomScale = min(zoomScale, 1.42)
        } else {
            lidPivot.position = lidBasePosition
            for part in explodeParts {
                part.node.position = part.base
            }
            zoomScale = zoomBeforeExplode
            theta = thetaBeforeExplode
            phi = phiBeforeExplode
            targetY = targetYBeforeExplode
        }

        SCNTransaction.commit()
        updateCamera()

        if !value, lidBeforeExplode {
            setLid(open: true, animated: animated)
        }
    }

    // MARK: 每帧刷新

    func tick() {
        if window != nil && shouldSuspendRendering { return }
        refreshLighting()
    }

    private func refreshLighting() {
        guard let vm = viewModel else { return }
        let brightness = CGFloat(vm.brightness / 100.0)
        let time = CACurrentMediaTime()

        for (zone, visual) in zoneEntries {
            let color = vm.zoneColors[zone] ?? Color(red: 0.9, green: 0.2, blue: 0.9)
            var ns = NSColor(color).usingColorSpace(.sRGB) ?? .magenta
            var intensity: CGFloat = vm.isLightsOff ? 0 : 1.0

            if let animated = vm.animatedColor(for: zone, at: time) {
                ns = NSColor(animated).usingColorSpace(.sRGB) ?? ns
            } else {
            switch vm.effect(for: zone) {
            case .color, .spectrum, .wave, .scanner:
                break
            case .pulse:
                let phase = CGFloat(sin(time * 2.4))
                intensity *= 0.55 + 0.45 * abs(phase)
            case .breathing:
                let phase = CGFloat(sin(time * 0.9))
                intensity *= 0.3 + 0.7 * ((phase + 1) / 2)
            case .morph:
                let secondary = NSColor(vm.secondaryColor).usingColorSpace(.sRGB) ?? .black
                let t = CGFloat((sin(time * 0.55) + 1) / 2)
                ns = NSColor(red: ns.redComponent + (secondary.redComponent - ns.redComponent) * t,
                             green: ns.greenComponent + (secondary.greenComponent - ns.greenComponent) * t,
                             blue: ns.blueComponent + (secondary.blueComponent - ns.blueComponent) * t,
                             alpha: 1)
            }
            }

            let selected = vm.selectedZones.contains(zone)
            let hovered = vm.hoveredZone == zone
            var boost: CGFloat = 1
            if selected { boost += 0.25 }
            if hovered { boost += 0.35 }

            for material in visual.materials {
                if material.name == "powerLogo" {
                    // 与 A 面同一张贴图：保留原本的霓虹质感，只加一层很弱的灯色辉光
                    let k = intensity * boost * brightness
                    material.emission.contents = (ns.usingColorSpace(.deviceRGB) ?? ns)
                    material.emission.intensity = 0.06 * k
                    continue
                }
                if material.name == "logoTexture" {
                    let k = intensity * boost * brightness * 1.35
                    let base = ns.usingColorSpace(.deviceRGB) ?? .magenta
                    // 保留原画质感的轻度染色
                    let tint = NSColor(red: (1 - 0.55 * (1 - base.redComponent)) * k,
                                       green: (1 - 0.55 * (1 - base.greenComponent)) * k,
                                       blue: (1 - 0.55 * (1 - base.blueComponent)) * k,
                                       alpha: 1)
                    material.multiply.contents = tint
                    continue
                }
                material.emission.contents = ns
                material.emission.intensity = intensity * visual.glowIntensity * boost * 0.95 * brightness * (zone == .alienHead ? 0.38 : 1.0)
                material.diffuse.contents = ns.blended(withFraction: 0.82, of: .black) ?? ns
            }

            visual.outline.isHidden = !(selected || hovered)
            let outlineColor = selected
                ? NSColor(calibratedRed: 0.3, green: 0.95, blue: 1.0, alpha: 1)
                : NSColor(calibratedWhite: 0.8, alpha: 1)
            visual.outline.enumerateChildNodes { child, _ in
                child.geometry?.firstMaterial?.emission.contents = outlineColor
                child.geometry?.firstMaterial?.emission.intensity = selected ? 0.9 : 0.35
                child.geometry?.firstMaterial?.diffuse.contents = outlineColor
            }
        }

        // 键盘每个键的顶面：单键有自定义颜色时优先用它
        for entry in keyMaterials {
            let zone = entry.zone
            let color = vm.keyColors[entry.id]
                ?? vm.animatedColor(for: zone, at: time)
                ?? vm.zoneColors[zone]
                ?? Color(red: 0.9, green: 0.2, blue: 0.9)
            var ns = NSColor(color).usingColorSpace(.sRGB) ?? .magenta
            var intensity: CGFloat = vm.isLightsOff ? 0 : 1.0
            switch vm.effect(for: zone) {
            case .spectrum, .wave, .scanner:
                break
            case .color:
                break
            case .pulse:
                intensity *= 0.6 + 0.4 * abs(CGFloat(sin(time * 2.4)))
            case .breathing:
                intensity *= 0.35 + 0.65 * ((CGFloat(sin(time * 0.9)) + 1) / 2)
            case .morph:
                let secondary = NSColor(vm.secondaryColor).usingColorSpace(.sRGB) ?? .black
                let t = CGFloat((sin(time * 0.55) + 1) / 2)
                ns = NSColor(red: ns.redComponent + (secondary.redComponent - ns.redComponent) * t,
                             green: ns.greenComponent + (secondary.greenComponent - ns.greenComponent) * t,
                             blue: ns.blueComponent + (secondary.blueComponent - ns.blueComponent) * t,
                             alpha: 1)
            }
            var boost: CGFloat = vm.selectedZones.contains(zone) ? 1.15 : 1
            if vm.selectedKeys.contains(entry.id) { boost *= 1.5 }
            if vm.hoveredKey == entry.id { boost *= 1.3 }
            entry.material.emission.contents = ns
            entry.material.emission.intensity = intensity * 1.15 * brightness * boost
            // 字标保持原图（黑字透明底），只改自发光颜色，不跟着键面一起染黑
            if entry.material.name != "keyLegend" {
                entry.material.diffuse.contents = ns.blended(withFraction: 0.72, of: .black) ?? ns
            }
        }

        // 触摸板：整面背光与边光各自跟随「触摸板细调」
        let touchpadEffect = vm.effect(for: .touchpad)
        var touchpadEnvelope: CGFloat = 1
        switch touchpadEffect {
        case .color, .morph, .spectrum, .wave, .scanner:
            touchpadEnvelope = 1
        case .pulse:
            touchpadEnvelope = 0.55 + 0.45 * abs(CGFloat(sin(time * 2.4)))
        case .breathing:
            touchpadEnvelope = 0.3 + 0.7 * ((CGFloat(sin(time * 0.9)) + 1) / 2)
        }
        let touchpadBoost: CGFloat = vm.selectedZones.contains(.touchpad)
            ? 1.15
            : (vm.hoveredZone == .touchpad ? 1.25 : 1)
        let touchpadOn = !vm.isLightsOff

        func morphIfNeeded(_ base: NSColor) -> NSColor {
            guard case .morph = touchpadEffect else { return base }
            let secondary = NSColor(vm.secondaryColor).usingColorSpace(.sRGB) ?? .black
            let t = CGFloat((sin(time * 0.55) + 1) / 2)
            return NSColor(red: base.redComponent + (secondary.redComponent - base.redComponent) * t,
                           green: base.greenComponent + (secondary.greenComponent - base.greenComponent) * t,
                           blue: base.blueComponent + (secondary.blueComponent - base.blueComponent) * t,
                           alpha: 1)
        }

        if let padMaterial = touchpadPadMaterial {
            let base = NSColor(vm.animatedColor(for: .touchpad, at: time) ?? vm.touchpadPadDisplayColor())
                .usingColorSpace(.sRGB) ?? .cyan
            let color = morphIfNeeded(base)
            padMaterial.emission.contents = color
            let padIntensity: CGFloat = touchpadOn
                ? touchpadEnvelope * brightness * CGFloat(vm.touchpad.padBrightness / 100) * touchpadBoost
                : 0
            padMaterial.emission.intensity = padIntensity * 0.22
            padMaterial.diffuse.contents = padIntensity < 0.05
                ? NSColor(calibratedWhite: 0.05, alpha: 1)
                : (color.blended(withFraction: 0.82, of: .black) ?? color)
        }

        if !touchpadEdgeMaterials.isEmpty {
            let base = NSColor(vm.animatedColor(for: .touchpad, at: time) ?? vm.touchpadEdgeDisplayColor())
                .usingColorSpace(.sRGB) ?? .cyan
            let color = morphIfNeeded(base)
            let intensity: CGFloat = (touchpadOn && vm.touchpad.edgeEnabled)
                ? touchpadEnvelope * brightness * CGFloat(vm.touchpad.edgeBrightness / 100) * touchpadBoost * 1.25
                : 0
            for material in touchpadEdgeMaterials {
                material.emission.contents = color
                material.emission.intensity = intensity
                material.diffuse.contents = intensity < 0.05
                    ? NSColor(calibratedWhite: 0.05, alpha: 1)
                    : (color.blended(withFraction: 0.6, of: .black) ?? color)
            }
        }

        // 电源键：跟随灯区色或使用独立颜色 / 亮度
        if !powerButtonMaterials.isEmpty {
            let powerEffect = vm.effect(for: .powerButton)
            var powerEnvelope: CGFloat = 1
            switch powerEffect {
            case .color, .morph, .spectrum, .wave, .scanner:
                powerEnvelope = 1
            case .pulse:
                powerEnvelope = 0.55 + 0.45 * abs(CGFloat(sin(time * 2.4)))
            case .breathing:
                powerEnvelope = 0.3 + 0.7 * ((CGFloat(sin(time * 0.9)) + 1) / 2)
            }
            let boost: CGFloat = vm.selectedZones.contains(.powerButton)
                ? 1.15
                : (vm.hoveredZone == .powerButton ? 1.25 : 1)
            var base = NSColor(vm.animatedColor(for: .powerButton, at: time) ?? vm.powerButtonDisplayColor())
                .usingColorSpace(.sRGB) ?? .cyan
            if case .morph = powerEffect {
                let secondary = NSColor(vm.secondaryColor).usingColorSpace(.sRGB) ?? .black
                let t = CGFloat((sin(time * 0.55) + 1) / 2)
                base = NSColor(red: base.redComponent + (secondary.redComponent - base.redComponent) * t,
                               green: base.greenComponent + (secondary.greenComponent - base.greenComponent) * t,
                               blue: base.blueComponent + (secondary.blueComponent - base.blueComponent) * t,
                               alpha: 1)
            }
            let intensity: CGFloat = vm.isLightsOff
                ? 0
                : powerEnvelope * brightness * CGFloat(vm.powerButton.lightBrightness / 100) * boost
            for material in powerButtonMaterials {
                if material.name == "powerLogo" {
                    // 贴图版头标：和 A 面同一张图自发光，看上去就是同一块霓虹头标
                    material.multiply.contents = NSColor(calibratedWhite: 1, alpha: 1)
                    material.emission.contents = material.diffuse.contents
                    material.emission.intensity = 0.85 * intensity
                    continue
                }
                material.emission.contents = base
                material.emission.intensity = intensity
                material.diffuse.contents = intensity < 0.05
                    ? NSColor(calibratedWhite: 0.05, alpha: 1)
                    : (base.blended(withFraction: 0.78, of: .black) ?? base)
            }
        }
    }

    // MARK: 交互

    /// 从节点名解析灯区：形如 zone-<raw>#key-<id>
    private func zone(fromName name: String) -> LightZone? {
        guard name.hasPrefix("zone-") else { return nil }
        let body = name.dropFirst("zone-".count)
        let digits = body.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
        guard let raw = UInt32(digits), raw != 0 else { return nil }
        return LightZone(rawValue: raw)
    }

    /// 从节点名解析按键 id：形如 zone-<raw>#key-<id>
    private func keyID(fromName name: String) -> String? {
        guard let range = name.range(of: "#key-") else { return nil }
        return String(name[range.upperBound...])
    }

    private func zone(at point: NSPoint) -> LightZone? {
        let hits = hitTest(point, options: [
            .searchMode: SCNHitTestSearchMode.all.rawValue,
            .categoryBitMask: 1,
            .ignoreHiddenNodes: true
        ])
        for hit in hits {
            var node: SCNNode? = hit.node
            while let current = node {
                if let name = current.name, let zone = zone(fromName: name) { return zone }
                node = current.parent
            }
        }
        return nil
    }

    private func keyID(at point: NSPoint) -> String? {
        let hits = hitTest(point, options: [
            .searchMode: SCNHitTestSearchMode.all.rawValue,
            .categoryBitMask: 1,
            .ignoreHiddenNodes: true
        ])
        for hit in hits {
            var node: SCNNode? = hit.node
            while let current = node {
                if let name = current.name, let id = keyID(fromName: name) { return id }
                node = current.parent
            }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        powerPressStartedAt = Date()
        dragOrigin = convert(event.locationInWindow, from: nil)
        lastDrag = dragOrigin
        didDrag = false
        noteInteraction()
        NSCursor.closedHand.set()
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // 旋转过程中收起屏幕悬停提示
        if hoveringScreen {
            hoveringScreen = false
            onScreenHover?(nil)
        }
        let dx = point.x - lastDrag.x
        let dy = point.y - lastDrag.y
        if abs(point.x - dragOrigin.x) > 2 || abs(point.y - dragOrigin.y) > 2 { didDrag = true }
        theta -= dx * 0.0075
        phi = min(1.35, max(-0.10, phi - dy * 0.0055))
        lastDrag = point
        noteInteraction()
        updateCamera()
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.arrow.set()
        let point = convert(event.locationInWindow, from: nil)
        let hit = hitTest(point, options: [.ignoreHiddenNodes: true]).first
        // 松开鼠标后立刻重算屏幕悬停，避免停在屏幕上却不弹提示
        let overScreen = isScreenHit(hit?.node)
        hoveringScreen = overScreen
        onScreenHover?(overScreen ? point : nil)
        guard !didDrag else { return }

        // 盖合状态下点顶盖 logo：选中「顶盖头像」灯区，绝不能触发开合盖
        if !lidIsOpen, isLogoPick(point) {
            onZoneTap?(.alienHead)
            return
        }

        // 屏幕壁纸区域：交给系统默认浏览器打开官网
        if isScreenHit(hit?.node) {
            NSWorkspace.shared.open(Self.screenLink)
            return
        }

        // 键盘上的单个按键：单键映射（选中即用当前颜色上色）
        if let key = keyID(at: point) {
            onKeyTap?(key)
            return
        }
        if hit == nil || zone(at: point) == nil {
            if hit?.node.name == "lid" || hit?.node.parent?.name == "lid" {
                setLid(open: !lidIsOpen, animated: true)
                return
            }
        }
        let tapped = zone(at: point)
        // 电源键功能：双击 / 长按优先，其次单击动作；都未配置时保持原来的「选灯区上色」
        if tapped == .powerButton, let vm = viewModel {
            let config = vm.powerButton
            let held = Date().timeIntervalSince(powerPressStartedAt)
            if event.clickCount >= 2, config.doubleClickAction != .none {
                vm.runPowerAction(config.doubleClickAction)
                return
            }
            if held >= 1.2, config.holdAction != .none {
                vm.runPowerAction(config.holdAction)
                return
            }
            if config.clickAction != .none {
                vm.runPowerAction(config.clickAction)
                return
            }
        }
        onZoneTap?(tapped)
    }

    /// logo 是否被点到：投影顶盖头标包围盒到视口坐标判断，避免被盖板遮挡时误判成开合盖
    private func isLogoPick(_ point: NSPoint) -> Bool {
        guard let logo = lidLogoNode else { return false }
        let (minB, maxB) = logo.boundingBox
        var xs: [CGFloat] = []
        var ys: [CGFloat] = []
        for x in [minB.x, maxB.x] {
            for y in [minB.y, maxB.y] {
                for z in [minB.z, maxB.z] {
                    let p = logo.convertPosition(SCNVector3(x, y, z), to: nil)
                    let projected = projectPoint(p)
                    guard projected.x.isFinite, projected.y.isFinite else { return false }
                    xs.append(CGFloat(projected.x))
                    ys.append(CGFloat(projected.y))
                }
            }
        }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max(),
              maxX - minX > 4, maxY - minY > 4 else { return false }
        let rect = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -4, dy: -4)
        return rect.contains(point)
    }

    /// 判断命中的节点是否属于屏幕面
    private func isScreenHit(_ node: SCNNode?) -> Bool {
        var current: SCNNode? = node
        while let n = current {
            if n.name == "screen-link" { return true }
            current = n.parent
        }
        return false
    }

    override func scrollWheel(with event: NSEvent) {
        noteInteraction()
        zoomScale = min(2.5, max(0.55, zoomScale + event.scrollingDeltaY * 0.012))
        updateCamera()
    }

    override func magnify(with event: NSEvent) {
        noteInteraction()
        zoomScale = min(2.5, max(0.55, zoomScale - event.magnification * 0.8))
        updateCamera()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        resumeVideoIfFrozen()
        scheduleVideoIdleFreeze()
        if !needsFastTick { tick() }
        let point = convert(event.locationInWindow, from: nil)
        let zone = zone(at: point)
        if zone != hovered {
            hovered = zone
            onZoneHover?(zone)
        }
        // 单键悬停高亮
        let key = keyID(at: point)
        if key != hoveredKey {
            hoveredKey = key
            onKeyHover?(key)
        }
        // 屏幕（壁纸）区域悬停：弹出跳转博客的胶囊提示
        let overScreen = isScreenHit(hitTest(point, options: [.ignoreHiddenNodes: true]).first?.node)
        if overScreen {
            onScreenHover?(point)
        } else if hoveringScreen {
            onScreenHover?(nil)
        }
        hoveringScreen = overScreen

        if overScreen || zone != nil || key != nil { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
    }

    override func mouseExited(with event: NSEvent) {
        if hovered != nil {
            hovered = nil
            onZoneHover?(nil)
        }
        if hoveringScreen {
            hoveringScreen = false
            onScreenHover?(nil)
        }
        if hoveredKey != nil {
            hoveredKey = nil
            onKeyHover?(nil)
        }
        NSCursor.arrow.set()
    }

    // MARK: 贴图

    private static func backgroundImage(size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor(calibratedRed: 0.012, green: 0.014, blue: 0.022, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()

        let center = NSPoint(x: size.width * 0.5, y: size.height * 0.5)
        let glow = NSGradient(colorsAndLocations:
            (NSColor(calibratedRed: 0.05, green: 0.11, blue: 0.19, alpha: 1), 0.0),
            (NSColor(calibratedRed: 0.025, green: 0.04, blue: 0.075, alpha: 1), 0.45),
            (NSColor(calibratedRed: 0.008, green: 0.011, blue: 0.018, alpha: 1), 1.0)
        )
        glow?.draw(fromCenter: center, radius: 0,
                   toCenter: center, radius: size.width * 0.66, options: [])

        // 顶部与底部渐隐，避免出现硬边
        let vignette = NSGradient(colorsAndLocations:
            (NSColor.black.withAlphaComponent(0.85), 0.0),
            (NSColor.black.withAlphaComponent(0.0), 0.22),
            (NSColor.black.withAlphaComponent(0.0), 0.78),
            (NSColor.black.withAlphaComponent(0.9), 1.0)
        )
        vignette?.draw(in: NSRect(origin: .zero, size: size), angle: -90)

        image.unlockFocus()
        return image
    }

    private static func environmentImage() -> NSImage {
        let size = NSSize(width: 800, height: 400)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedWhite: 0.02, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()

        let top = NSGradient(colorsAndLocations:
            (NSColor(calibratedWhite: 0.55, alpha: 0.9), 0.0),
            (NSColor(calibratedWhite: 0.1, alpha: 0.0), 1.0)
        )
        top?.draw(in: NSRect(x: 40, y: 210, width: 720, height: 130), angle: -90)

        NSColor(calibratedRed: 0.1, green: 0.4, blue: 0.6, alpha: 0.4).setFill()
        NSRect(x: 0, y: 0, width: 220, height: 400).fill()
        NSColor(calibratedRed: 0.3, green: 0.1, blue: 0.5, alpha: 0.35).setFill()
        NSRect(x: 560, y: 0, width: 240, height: 400).fill()

        image.unlockFocus()
        return image
    }

    /// 屏幕壁纸（随包资源），缺失时回退到内置生成的渐变图
    static func screenWallpaper() -> NSImage {
        if let url = Bundle.main.url(forResource: "screen_wallpaper", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return screenImage()
    }

    /// 点击屏幕打开的项目主页
    static let screenLink = URL(string: "https://rockjesus.cn")!

    /// 官方 Alienware 头标（白线 + 两道斜眼缝，透明底），用于电源键贴图
    static func powerHeadLogoImage(fill: NSColor = NSColor(calibratedWhite: 1, alpha: 1)) -> NSImage? {
        let canvas = NSSize(width: 300, height: 420)
        let image = NSImage(size: canvas)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: canvas).fill()

        let cx: CGFloat = 150
        let cy: CGFloat = 210
        let scale: CGFloat = 36.0

        // 官方 Alienware 外星人头：实心剪影 + 镂空两道斜眼
        func hp(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: cx + x * scale, y: cy + y * scale) }
        let head = NSBezierPath()
        head.move(to: hp(0, 5.30))
        head.curve(to: hp(2.15, 4.55), controlPoint1: hp(1.00, 5.35), controlPoint2: hp(1.75, 5.05))
        head.curve(to: hp(3.55, 1.55), controlPoint1: hp(2.90, 3.70), controlPoint2: hp(3.55, 2.70))
        head.curve(to: hp(3.72, -0.90), controlPoint1: hp(3.90, 0.60), controlPoint2: hp(3.92, -0.20))
        head.curve(to: hp(2.20, -3.60), controlPoint1: hp(3.50, -1.80), controlPoint2: hp(3.00, -2.90))
        head.curve(to: hp(0, -5.30), controlPoint1: hp(1.30, -4.35), controlPoint2: hp(0.50, -5.00))
        head.curve(to: hp(-2.20, -3.60), controlPoint1: hp(-1.30, -4.35), controlPoint2: hp(-0.50, -5.00))
        head.curve(to: hp(-3.72, -0.90), controlPoint1: hp(-3.00, -2.90), controlPoint2: hp(-3.50, -1.80))
        head.curve(to: hp(-3.55, 1.55), controlPoint1: hp(-3.92, -0.20), controlPoint2: hp(-3.90, 0.60))
        head.curve(to: hp(-2.15, 4.55), controlPoint1: hp(-3.55, 2.70), controlPoint2: hp(-2.90, 3.70))
        head.curve(to: hp(0, 5.30), controlPoint1: hp(-1.75, 5.05), controlPoint2: hp(-1.00, 5.35))
        fill.setFill()
        head.fill()

        NSGraphicsContext.current?.compositingOperation = .clear
        for side in [CGFloat(-1), 1] {
            let eye = NSBezierPath()
            eye.lineWidth = 34
            eye.lineCapStyle = .round
            eye.move(to: NSPoint(x: cx + side * 92, y: cy + 34))
            eye.line(to: NSPoint(x: cx + side * 30, y: cy - 6))
            NSColor(calibratedWhite: 1, alpha: 1).setStroke()
            eye.stroke()
        }
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        image.unlockFocus()
        return image
    }

    /// 外星人头轮廓（用于电源键等小标志），scale = 1 时半宽 3.85
    static func alienHeadPath(scale: CGFloat) -> NSBezierPath {
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * scale, y: y * scale) }
        let path = NSBezierPath()
        path.move(to: p(0, 5.30))
        path.curve(to: p(2.15, 4.55), controlPoint1: p(1.00, 5.35), controlPoint2: p(1.75, 5.05))
        path.curve(to: p(3.55, 1.55), controlPoint1: p(2.90, 3.70), controlPoint2: p(3.55, 2.70))
        path.curve(to: p(3.72, -0.90), controlPoint1: p(3.90, 0.60), controlPoint2: p(3.92, -0.20))
        path.curve(to: p(2.20, -3.60), controlPoint1: p(3.50, -1.80), controlPoint2: p(3.00, -2.90))
        path.curve(to: p(0, -5.30), controlPoint1: p(1.30, -4.35), controlPoint2: p(0.50, -5.00))
        path.curve(to: p(-2.20, -3.60), controlPoint1: p(-1.30, -4.35), controlPoint2: p(-0.50, -5.00))
        path.curve(to: p(-3.72, -0.90), controlPoint1: p(-3.00, -2.90), controlPoint2: p(-3.50, -1.80))
        path.curve(to: p(-3.55, 1.55), controlPoint1: p(-3.92, -0.20), controlPoint2: p(-3.90, 0.60))
        path.curve(to: p(-2.15, 4.55), controlPoint1: p(-3.55, 2.70), controlPoint2: p(-2.90, 3.70))
        path.curve(to: p(0, 5.30), controlPoint1: p(-1.75, 5.05), controlPoint2: p(-1.00, 5.35))
        return path
    }

    /// A 面 Alienware 头标贴图
    static func lidLogo() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "lid_logo", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        return image
    }

    private static func screenImage() -> NSImage {
        let size = NSSize(width: 1200, height: 675)
        let image = NSImage(size: size)
        image.lockFocus()

        let gradient = NSGradient(colorsAndLocations:
            (NSColor(calibratedRed: 0.02, green: 0.05, blue: 0.12, alpha: 1), 0.0),
            (NSColor(calibratedRed: 0.04, green: 0.18, blue: 0.32, alpha: 1), 0.45),
            (NSColor(calibratedRed: 0.16, green: 0.05, blue: 0.3, alpha: 1), 1.0)
        )
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: -40)

        // 高光斜带
        NSColor.white.withAlphaComponent(0.05).setFill()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: 0))
        path.line(to: NSPoint(x: size.width * 0.55, y: 0))
        path.line(to: NSPoint(x: 0, y: size.height * 0.75))
        path.close()
        path.fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 34, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.78, alpha: 0.55),
            .kern: 8
        ]
        let text = "ALIENWARE" as NSString
        let textSize = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (size.width - textSize.width) / 2, y: size.height / 2 - 22),
                  withAttributes: attrs)

        image.unlockFocus()
        return image
    }
}
