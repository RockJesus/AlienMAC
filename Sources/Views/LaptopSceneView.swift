//
//  LaptopSceneView.swift
//  AlienMAC
//
//  Alienware 17 R4 真实比例三维模型（424 × 332 × 30 mm，17.3" 屏）
//  灯区直接可点，支持自由旋转、缩放、开合盖与视角切换
//

import SwiftUI
import SceneKit
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
        case .back: return (.pi - 0.56, 0.18, 15.0)
        }
    }
}

// MARK: - SwiftUI 封装

struct LaptopSceneView: NSViewRepresentable {

    @ObservedObject var viewModel: LightingViewModel
    @Binding var lidOpen: Bool
    var pose: ScenePose = .hero

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, lidOpen: $lidOpen)
    }

    func makeNSView(context: Context) -> LaptopSceneNSView {
        let view = LaptopSceneNSView()
        view.viewModel = viewModel
        view.onZoneTap = { zone in
            if let zone = zone {
                viewModel.toggleZone(zone)
            } else {
                viewModel.selectedZones.removeAll()
            }
        }
        view.onZoneHover = { zone in
            viewModel.hoveredZone = zone
        }
        context.coordinator.view = view
        view.setLid(open: lidOpen, animated: false)
        view.setPose(pose, animated: false)
        context.coordinator.startTimer()
        return view
    }

    func updateNSView(_ view: LaptopSceneNSView, context: Context) {
        view.setLid(open: lidOpen, animated: true)
        view.setPose(pose, animated: true)
    }

    static func dismantleNSView(_ nsView: LaptopSceneNSView, coordinator: Coordinator) {
        coordinator.stopTimer()
    }

    final class Coordinator {
        let viewModel: LightingViewModel
        let lidOpen: Binding<Bool>
        weak var view: LaptopSceneNSView?
        private var timer: Timer?

        init(viewModel: LightingViewModel, lidOpen: Binding<Bool>) {
            self.viewModel = viewModel
            self.lidOpen = lidOpen
        }

        func startTimer() {
            timer?.invalidate()
            let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                self?.view?.tick()
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

    var onZoneTap: ((LightZone?) -> Void)?
    var onZoneHover: ((LightZone?) -> Void)?
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
    private var lidIsOpen = false
    private var zoneEntries: [LightZone: ZoneVisual] = [:]

    // 交互
    private var dragOrigin: NSPoint = .zero
    private var lastDrag: NSPoint = .zero
    private var didDrag = false
    private var trackingArea: NSTrackingArea?
    private var hovered: LightZone?

    private struct ZoneVisual {
        let node: SCNNode
        let materials: [SCNMaterial]
        let outline: SCNNode
        var glowIntensity: CGFloat
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
        self.antialiasingMode = .multisampling4X
        self.isPlaying = true
        self.rendersContinuously = true
        self.preferredFramesPerSecond = 60
        self.allowsCameraControl = false

        scene.background.contents = nil
        scene.lightingEnvironment.contents = Self.environmentImage()
        scene.lightingEnvironment.intensity = 0.6

        let root = SCNNode()
        scene.rootNode.addChildNode(root)

        buildContactShadow(root)
        buildChassis(root)
        buildKeyboard(root)
        buildZones(root)
        buildLights(scene)
        buildCamera(scene)
    }

    private let bodyWidth: CGFloat = 42.4
    private let bodyDepth: CGFloat = 33.2
    private let deckTop: CGFloat = 3.30

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
        let bodyMat = shellMaterial(0.135, 0.141, 0.158, metal: 0.34, rough: 0.46)
        let deckMat = shellMaterial(0.152, 0.158, 0.175, metal: 0.3, rough: 0.4)
        let darkMat = shellMaterial(0.035, 0.038, 0.045, metal: 0.2, rough: 0.7)

        // 底座
        let base = SCNBox(width: bodyWidth, height: 2.55, length: bodyDepth, chamferRadius: 0.85)
        base.materials = [bodyMat]
        let baseNode = SCNNode(geometry: base)
        baseNode.position = SCNVector3(0, 1.35, 0)
        baseNode.categoryBitMask = 2
        root.addChildNode(baseNode)

        // 后部厚重段（散热腔）
        let rear = SCNBox(width: bodyWidth - 0.6, height: 4.7, length: 8.6, chamferRadius: 0.55)
        rear.materials = [bodyMat]
        let rearNode = SCNNode(geometry: rear)
        rearNode.position = SCNVector3(0, 2.15, -bodyDepth / 2 + 4.3)
        rearNode.categoryBitMask = 2
        root.addChildNode(rearNode)

        // 前缘字标
        let wordMat = SCNMaterial()
        wordMat.lightingModel = .constant
        wordMat.diffuse.contents = NSColor(calibratedWhite: 0.55, alpha: 0.9)
        let word = SCNText(string: "ALIENWARE", extrusionDepth: 0.01)
        word.font = NSFont.systemFont(ofSize: 1.0, weight: .medium)
        word.flatness = 0.1
        word.materials = [wordMat]
        let wordNode = SCNNode(geometry: word)
        let (wMin, wMax) = wordNode.boundingBox
        wordNode.pivot = SCNMatrix4MakeTranslation((wMin.x + wMax.x) / 2, (wMin.y + wMax.y) / 2, 0)
        wordNode.scale = SCNVector3(0.32, 0.32, 1)
        wordNode.position = SCNVector3(0, 1.0, bodyDepth / 2 + 0.055)
        wordNode.categoryBitMask = 2
        root.addChildNode(wordNode)

        // 掌托面板
        let deck = SCNBox(width: bodyWidth - 1.6, height: 0.55, length: bodyDepth - 2.6, chamferRadius: 0.35)
        deck.materials = [deckMat]
        let deckNode = SCNNode(geometry: deck)
        deckNode.position = SCNVector3(0, 3.0, 0.9)
        deckNode.categoryBitMask = 2
        root.addChildNode(deckNode)

        // 键盘凹槽
        let well = SCNBox(width: 35.6, height: 0.24, length: 13.6, chamferRadius: 0.25)
        well.materials = [darkMat]
        let wellNode = SCNNode(geometry: well)
        wellNode.position = SCNVector3(-0.2, 3.24, -4.9)
        wellNode.categoryBitMask = 2
        root.addChildNode(wellNode)

        // 触控板（深色玻璃面）
        let padGlass = SCNMaterial()
        padGlass.lightingModel = .physicallyBased
        padGlass.diffuse.contents = NSColor(calibratedWhite: 0.045, alpha: 1)
        padGlass.metalness.contents = 0.1
        padGlass.roughness.contents = 0.18
        let pad = SCNBox(width: 10.6, height: 0.08, length: 6.6, chamferRadius: 0.35)
        pad.materials = [padGlass]
        let padNode = SCNNode(geometry: pad)
        padNode.position = SCNVector3(0, deckTop, 7.4)
        padNode.categoryBitMask = 1
        padNode.name = "zone-\(LightZone.touchpad.rawValue)"
        root.addChildNode(padNode)

        // 前缘斜面（楔形感）
        let lipWedge = SCNBox(width: bodyWidth - 1.4, height: 0.9, length: 3.2, chamferRadius: 0.4)
        lipWedge.materials = [bodyMat]
        let lipWedgeNode = SCNNode(geometry: lipWedge)
        lipWedgeNode.eulerAngles = SCNVector3(-0.32, 0, 0)
        lipWedgeNode.position = SCNVector3(0, 1.3, bodyDepth / 2 - 1.3)
        lipWedgeNode.categoryBitMask = 2
        root.addChildNode(lipWedgeNode)

        // 底座与掌托之间的分缝
        let groove = SCNBox(width: bodyWidth - 1.0, height: 0.12, length: bodyDepth - 1.2, chamferRadius: 0.05)
        groove.materials = [darkMat]
        let grooveNode = SCNNode(geometry: groove)
        grooveNode.position = SCNVector3(0, 2.62, 0.2)
        grooveNode.categoryBitMask = 2
        root.addChildNode(grooveNode)

        // 前缘装饰条
        let trim = SCNBox(width: bodyWidth - 3.4, height: 0.5, length: 1.8, chamferRadius: 0.22)
        trim.materials = [darkMat]
        let trimNode = SCNNode(geometry: trim)
        trimNode.position = SCNVector3(0, 0.55, bodyDepth / 2 - 0.6)
        trimNode.categoryBitMask = 2
        root.addChildNode(trimNode)

        // 铰链
        let hingeMat = shellMaterial(0.07, 0.07, 0.08, metal: 0.8, rough: 0.35)
        let hinge = SCNCylinder(radius: 0.85, height: bodyWidth - 3.2)
        hinge.materials = [hingeMat]
        let hingeNode = SCNNode(geometry: hinge)
        hingeNode.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
        hingeNode.position = SCNVector3(0, 3.7, -bodyDepth / 2 + 1.4)
        hingeNode.categoryBitMask = 2
        root.addChildNode(hingeNode)

        // 顶盖
        lidPivot = SCNNode()
        lidPivot.position = SCNVector3(0, 3.8, -bodyDepth / 2 + 1.3)
        root.addChildNode(lidPivot)

        let lidMat = shellMaterial(0.105, 0.111, 0.126, metal: 0.3, rough: 0.46)
        let lid = SCNBox(width: bodyWidth - 0.8, height: 27.4, length: 1.05, chamferRadius: 0.5)
        lid.materials = [lidMat]
        let lidBody = SCNNode(geometry: lid)
        lidBody.position = SCNVector3(0, 13.7, -0.35)
        lidBody.name = "lid"
        lidBody.categoryBitMask = 2
        lidPivot.addChildNode(lidBody)

        // 顶盖外圈金属倒角
        let rimMat = shellMaterial(0.33, 0.338, 0.36, metal: 0.55, rough: 0.3)
        let lidRim = SCNBox(width: bodyWidth - 0.2, height: 27.7, length: 0.45, chamferRadius: 0.22)
        lidRim.materials = [rimMat]
        let lidRimNode = SCNNode(geometry: lidRim)
        lidRimNode.position = SCNVector3(0, 13.7, -0.3)
        lidRimNode.name = "lid"
        lidRimNode.categoryBitMask = 2
        lidPivot.addChildNode(lidRimNode)

        // 内侧边框（黑色玻璃感）
        let bezelMat = SCNMaterial()
        bezelMat.lightingModel = .physicallyBased
        bezelMat.diffuse.contents = NSColor(calibratedWhite: 0.022, alpha: 1)
        bezelMat.roughness.contents = 0.28
        bezelMat.metalness.contents = 0.05
        let bezel = SCNBox(width: bodyWidth - 2.2, height: 25.4, length: 0.09, chamferRadius: 0.2)
        bezel.materials = [bezelMat]
        let bezelNode = SCNNode(geometry: bezel)
        bezelNode.position = SCNVector3(0, 13.9, 0.18)
        bezelNode.name = "lid"
        bezelNode.categoryBitMask = 2
        lidPivot.addChildNode(bezelNode)

        // 屏幕
        let wall = Self.screenWallpaper()
        let screenMat = SCNMaterial()
        screenMat.lightingModel = .constant
        screenMat.diffuse.contents = wall
        screenMat.emission.contents = wall
        screenMat.emission.intensity = 0.42
        let screen = SCNBox(width: 38.6, height: 21.7, length: 0.05, chamferRadius: 0.06)
        screen.materials = [screenMat]
        let screenNode = SCNNode(geometry: screen)
        screenNode.position = SCNVector3(0, 15.5, 0.24)
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
        cameraNode.position = SCNVector3(0, 25.4, 0.26)
        cameraNode.categoryBitMask = 2
        lidPivot.addChildNode(cameraNode)

        // 后部排气格栅
        let ventMat = SCNMaterial()
        ventMat.lightingModel = .physicallyBased
        ventMat.diffuse.contents = NSColor(calibratedWhite: 0.015, alpha: 1)
        ventMat.roughness.contents = 0.9
        for i in 0..<11 {
            let slot = SCNBox(width: 1.55, height: 0.07, length: 1.1, chamferRadius: 0.03)
            slot.materials = [ventMat]
            let slotNode = SCNNode(geometry: slot)
            slotNode.position = SCNVector3(-9.5 + CGFloat(i) * 1.9, 4.48, -bodyDepth / 2 + 1.6)
            slotNode.categoryBitMask = 2
            root.addChildNode(slotNode)
        }
        // 后部接口
        let portMat = SCNMaterial()
        portMat.lightingModel = .physicallyBased
        portMat.diffuse.contents = NSColor(calibratedWhite: 0.02, alpha: 1)
        for (idx, w) in [2.2, 1.3, 1.3, 1.8, 2.4].enumerated() {
            let port = SCNBox(width: w, height: 0.55, length: 0.1, chamferRadius: 0.05)
            port.materials = [portMat]
            let portNode = SCNNode(geometry: port)
            portNode.position = SCNVector3(-7.4 + CGFloat(idx) * 3.0, 2.0, -bodyDepth / 2 - 0.02)
            portNode.categoryBitMask = 2
            root.addChildNode(portNode)
        }

        // 顶部深色唇边
        let lip = SCNBox(width: bodyWidth - 1.2, height: 1.7, length: 0.35, chamferRadius: 0.18)
        lip.materials = [darkMat]
        let lipNode = SCNNode(geometry: lip)
        lipNode.position = SCNVector3(0, 27.0, 0.1)
        lipNode.name = "lid"
        lipNode.categoryBitMask = 2
        lidPivot.addChildNode(lipNode)
    }

    private func buildKeyboard(_ root: SCNNode) {
        let keyY: CGFloat = 3.42
        let cols = 14
        let rows = 5
        let startX: CGFloat = -15.0
        let stepX: CGFloat = 1.66
        let startZ: CGFloat = -9.6
        let stepZ: CGFloat = 1.62

        func zoneFor(col: Int) -> LightZone {
            if col <= 3 { return .keyboardLeft }
            if col <= 8 { return .keyboardMid }
            return .keyboardRight
        }

        func key(_ x: CGFloat, _ z: CGFloat, _ w: CGFloat, _ d: CGFloat, zone: LightZone?) {
            let cap = SCNMaterial()
            cap.lightingModel = .physicallyBased
            cap.diffuse.contents = NSColor(calibratedWhite: 0.085, alpha: 1)
            cap.roughness.contents = 0.62
            cap.metalness.contents = 0.08
            cap.emission.contents = NSColor.black
            cap.emission.intensity = 0

            let top = SCNMaterial()
            top.lightingModel = .constant
            top.diffuse.contents = NSColor(calibratedWhite: 0.16, alpha: 1)
            top.emission.contents = NSColor.black
            top.emission.intensity = 0.0

            let box = SCNBox(width: w, height: 0.30, length: d, chamferRadius: 0.13)
            box.materials = [cap, cap, cap, cap, top, cap]
            let node = SCNNode(geometry: box)
            node.position = SCNVector3(x, keyY, z)
            if let zone = zone {
                node.categoryBitMask = 1
                node.name = "zone-\(zone.rawValue)"
                registerKeyTop(top, zone: zone)
            } else {
                node.categoryBitMask = 2
            }
            root.addChildNode(node)
        }

        for row in 0..<rows {
            for col in 0..<cols {
                var w: CGFloat = 1.46
                var x = startX + CGFloat(col) * stepX
                if row == 4 && (col == 4 || col == 5 || col == 6) { continue }
                if row == 4 && col == 4 {
                    w = 4.6
                    x += 1.6
                }
                var d: CGFloat = 1.44
                if row == 0 { d = 1.16 }
                key(x, startZ + CGFloat(row) * stepZ, w, d, zone: zoneFor(col: col))
            }
        }

        // 数字键盘
        for row in 0..<rows {
            for col in 0..<4 {
                key(11.6 + CGFloat(col) * 1.66, startZ + CGFloat(row) * stepZ, 1.46, 1.44, zone: .numpad)
            }
        }

        // 导航键
        for i in 0..<3 {
            key(9.2, startZ + CGFloat(i) * stepZ, 1.46, 1.44, zone: .numpad)
        }

        // 宏键列
        for i in 0..<5 {
            key(-17.0, startZ + CGFloat(i) * stepZ, 1.18, 1.18, zone: .macroKeys)
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

    private var keyTopMaterials: [LightZone: [SCNMaterial]] = [:]

    private func registerKeyTop(_ material: SCNMaterial, zone: LightZone) {
        keyTopMaterials[zone, default: []].append(material)
    }

    private func addKeyboardOutlines(_ root: SCNNode) {
        let zCenter: CGFloat = -4.9
        let zSize: CGFloat = 14.2
        addOutline(zone: .keyboardLeft, root: root,
                   center: SCNVector3(-9.2, 3.6, zCenter), size: SCNVector3(11.0, 0.5, zSize))
        addOutline(zone: .keyboardMid, root: root,
                   center: SCNVector3(-0.9, 3.6, zCenter), size: SCNVector3(10.0, 0.5, zSize))
        addOutline(zone: .keyboardRight, root: root,
                   center: SCNVector3(5.6, 3.6, zCenter), size: SCNVector3(7.2, 0.5, zSize))
        addOutline(zone: .numpad, root: root,
                   center: SCNVector3(12.6, 3.6, zCenter), size: SCNVector3(7.6, 0.5, zSize))
        addOutline(zone: .macroKeys, root: root,
                   center: SCNVector3(-17.0, 3.6, zCenter), size: SCNVector3(2.0, 0.5, 11.0))
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
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.diffuse.contents = NSColor(calibratedWhite: 0.08, alpha: 1)
        mat.emission.contents = NSColor.black
        mat.emission.intensity = 0

        let text = SCNText(string: "ALIENWARE", extrusionDepth: 0.03)
        text.font = NSFont.systemFont(ofSize: 1.0, weight: .medium)
        text.flatness = 0.15
        text.materials = [mat]

        let node = SCNNode(geometry: text)
        let (minB, maxB) = node.boundingBox
        node.pivot = SCNMatrix4MakeTranslation((minB.x + maxB.x) / 2, (minB.y + maxB.y) / 2, 0)
        node.scale = SCNVector3(0.46, 0.46, 1)
        node.position = SCNVector3(0, 2.6, 0.28)
        node.categoryBitMask = 1
        node.name = "zone-\(LightZone.screenLogo.rawValue)"
        lidPivot.addChildNode(node)

        ensureEntry(.screenLogo, materials: [mat])
        addOutline(zone: .screenLogo, root: lidPivot,
                   center: SCNVector3(0, 2.6, 0.16), size: SCNVector3(11.6, 2.0, 0.16), parent: lidPivot)
    }

    private func addAlienHead() {
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.diffuse.contents = NSColor(calibratedWhite: 0.06, alpha: 1)
        mat.emission.contents = NSColor.black
        mat.emission.intensity = 0

        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: 4.4))
        path.curve(to: NSPoint(x: 2.6, y: 2.6), controlPoint1: NSPoint(x: 1.4, y: 4.0), controlPoint2: NSPoint(x: 2.2, y: 3.4))
        path.curve(to: NSPoint(x: 3.2, y: 0.2), controlPoint1: NSPoint(x: 3.0, y: 1.9), controlPoint2: NSPoint(x: 3.2, y: 1.1))
        path.curve(to: NSPoint(x: 1.3, y: -3.5), controlPoint1: NSPoint(x: 3.1, y: -1.3), controlPoint2: NSPoint(x: 2.3, y: -2.6))
        path.curve(to: NSPoint(x: 0, y: -4.3), controlPoint1: NSPoint(x: 0.7, y: -4.0), controlPoint2: NSPoint(x: 0.3, y: -4.3))
        path.curve(to: NSPoint(x: -1.3, y: -3.5), controlPoint1: NSPoint(x: -0.3, y: -4.3), controlPoint2: NSPoint(x: -0.7, y: -4.0))
        path.curve(to: NSPoint(x: -3.2, y: 0.2), controlPoint1: NSPoint(x: -2.3, y: -2.6), controlPoint2: NSPoint(x: -3.1, y: -1.3))
        path.curve(to: NSPoint(x: -2.6, y: 2.6), controlPoint1: NSPoint(x: -3.2, y: 1.1), controlPoint2: NSPoint(x: -3.0, y: 1.9))
        path.curve(to: NSPoint(x: 0, y: 4.4), controlPoint1: NSPoint(x: -2.2, y: 3.4), controlPoint2: NSPoint(x: -1.4, y: 4.0))

        let shape = SCNShape(path: path, extrusionDepth: 0.1)
        shape.materials = [mat]
        shape.chamferRadius = 0.05
        let head = SCNNode(geometry: shape)
        head.scale = SCNVector3(0.72, 0.72, 1)
        head.categoryBitMask = 1
        head.name = "zone-\(LightZone.alienHead.rawValue)"

        // 眼睛
        let eyeMat = SCNMaterial()
        eyeMat.lightingModel = .constant
        eyeMat.diffuse.contents = NSColor.black
        let eyes = SCNNode()
        for side in [-1.0, 1.0] {
            let eye = SCNBox(width: 1.2, height: 0.42, length: 0.14, chamferRadius: 0.2)
            eye.materials = [eyeMat]
            let eyeNode = SCNNode(geometry: eye)
            eyeNode.position = SCNVector3(side * 0.95, 0.5, 0.03)
            eyeNode.eulerAngles = SCNVector3(0, 0, side > 0 ? -0.32 : 0.32)
            eyes.addChildNode(eyeNode)
        }
        eyes.scale = SCNVector3(0.72, 0.72, 1)
        head.addChildNode(eyes)

        let mount = SCNNode()
        mount.addChildNode(head)
        mount.position = SCNVector3(0, 14.6, -0.86)
        mount.eulerAngles = SCNVector3(0, CGFloat.pi, 0)
        mount.name = "zone-\(LightZone.alienHead.rawValue)"
        mount.categoryBitMask = 1
        lidPivot.addChildNode(mount)

        ensureEntry(.alienHead, materials: [mat])
        addOutline(zone: .alienHead, root: lidPivot,
                   center: SCNVector3(0, 14.6, -0.95), size: SCNVector3(6.4, 7.6, 2.0), parent: lidPivot)
    }

    private func addPowerButton(_ root: SCNNode) {
        let ringMat = SCNMaterial()
        ringMat.lightingModel = .constant
        ringMat.diffuse.contents = NSColor(calibratedWhite: 0.1, alpha: 1)
        ringMat.emission.contents = NSColor.black
        ringMat.emission.intensity = 0

        let outer = SCNCylinder(radius: 1.0, height: 0.09)
        outer.materials = [ringMat]
        let outerNode = SCNNode(geometry: outer)
        outerNode.position = SCNVector3(-12.4, deckTop + 0.05, -12.0)
        outerNode.categoryBitMask = 1
        outerNode.name = "zone-\(LightZone.powerButton.rawValue)"
        root.addChildNode(outerNode)

        let innerMat = SCNMaterial()
        innerMat.lightingModel = .physicallyBased
        innerMat.diffuse.contents = NSColor(calibratedWhite: 0.03, alpha: 1)
        innerMat.roughness.contents = 0.3
        let inner = SCNCylinder(radius: 0.66, height: 0.1)
        inner.materials = [innerMat]
        let innerNode = SCNNode(geometry: inner)
        innerNode.position = SCNVector3(-12.4, deckTop + 0.09, -12.0)
        innerNode.categoryBitMask = 2
        root.addChildNode(innerNode)

        ensureEntry(.powerButton, materials: [ringMat])
        addOutline(zone: .powerButton, root: root,
                   center: SCNVector3(-12.4, deckTop + 0.1, -12.0), size: SCNVector3(2.5, 0.5, 2.5))
    }

    private func addStrips(_ root: SCNNode) {
        func strip(zone: LightZone, x: CGFloat, z: CGFloat, width: CGFloat, y: CGFloat) {
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.diffuse.contents = NSColor(calibratedWhite: 0.05, alpha: 1)
            mat.emission.contents = NSColor.black
            mat.emission.intensity = 0

            let bar = SCNBox(width: width, height: 0.16, length: 0.28, chamferRadius: 0.07)
            bar.materials = [mat]
            let node = SCNNode(geometry: bar)
            node.position = SCNVector3(x, y, z)
            node.categoryBitMask = 1
            node.name = "zone-\(zone.rawValue)"
            root.addChildNode(node)

            ensureEntry(zone, materials: [mat])
            addOutline(zone: zone, root: root,
                       center: SCNVector3(x, y, z), size: SCNVector3(width + 1.0, 0.7, 1.2))
        }

        strip(zone: .frontLeft, x: -11.6, z: bodyDepth / 2 + 0.16, width: 13.0, y: 1.15)
        strip(zone: .frontRight, x: 11.6, z: bodyDepth / 2 + 0.16, width: 13.0, y: 1.15)
        strip(zone: .rearLeft, x: -11.6, z: -bodyDepth / 2 + 0.04, width: 10.8, y: 2.3)
        strip(zone: .rearRight, x: 11.6, z: -bodyDepth / 2 + 0.04, width: 10.8, y: 2.3)
    }

    private func addTouchpadFrame(_ root: SCNNode) {
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.diffuse.contents = NSColor(calibratedWhite: 0.06, alpha: 1)
        mat.emission.contents = NSColor.black
        mat.emission.intensity = 0

        let thickness: CGFloat = 0.14
        let width: CGFloat = 10.7
        let depth: CGFloat = 6.7
        let parts: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0, depth / 2, width, thickness),
            (0, -depth / 2, width, thickness),
            (-width / 2, 0, thickness, depth),
            (width / 2, 0, thickness, depth)
        ]
        let group = SCNNode()
        group.name = "zone-\(LightZone.touchpad.rawValue)"
        group.categoryBitMask = 1
        for (x, z, w, d) in parts {
            let box = SCNBox(width: w, height: 0.1, length: d, chamferRadius: 0.04)
            box.materials = [mat]
            let child = SCNNode(geometry: box)
            child.position = SCNVector3(x, deckTop + 0.03, 7.4 + z)
            child.categoryBitMask = 1
            child.name = "zone-\(LightZone.touchpad.rawValue)"
            group.addChildNode(child)
        }
        root.addChildNode(group)

        ensureEntry(.touchpad, materials: [mat])
        addOutline(zone: .touchpad, root: root,
                   center: SCNVector3(0, deckTop + 0.06, 7.4), size: SCNVector3(11.9, 0.4, 7.9))
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
        fill.light?.color = NSColor(calibratedRed: 0.25, green: 0.6, blue: 1.0, alpha: 1)
        fill.light?.intensity = 150
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

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .omni
        rim.light?.color = NSColor(calibratedRed: 0.62, green: 0.28, blue: 1.0, alpha: 1)
        rim.light?.intensity = 140
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

    private func updateCamera() {
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

    func setPose(_ pose: ScenePose, animated: Bool) {
        let target = pose.orbit
        theta = target.theta
        phi = target.phi
        targetY = target.targetY
        updateCamera()
    }

    // MARK: 开合盖

    func setLid(open: Bool, animated: Bool) {
        guard open != lidIsOpen else { return }
        lidIsOpen = open
        let angle = open ? CGFloat(-0.08) : CGFloat.pi / 2
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.7 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        lidPivot.eulerAngles = SCNVector3(angle, 0, 0)
        SCNTransaction.commit()
    }

    // MARK: 每帧刷新

    func tick() {
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

            switch vm.effect(for: zone) {
            case .color:
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

            let selected = vm.selectedZones.contains(zone)
            let hovered = vm.hoveredZone == zone
            var boost: CGFloat = 1
            if selected { boost += 0.25 }
            if hovered { boost += 0.35 }

            for material in visual.materials {
                material.emission.contents = ns
                material.emission.intensity = intensity * visual.glowIntensity * boost * 0.95 * brightness
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

        // 键盘每个键的顶面
        for (zone, materials) in keyTopMaterials {
            let color = vm.zoneColors[zone] ?? Color(red: 0.9, green: 0.2, blue: 0.9)
            var ns = NSColor(color).usingColorSpace(.sRGB) ?? .magenta
            var intensity: CGFloat = vm.isLightsOff ? 0 : 1.0
            switch vm.effect(for: zone) {
            case .color: break
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
            let boost: CGFloat = (vm.selectedZones.contains(zone) ? 1.2 : 1) * (vm.hoveredZone == zone ? 1.25 : 1)
            for material in materials {
                material.emission.contents = ns
                material.emission.intensity = intensity * 1.15 * brightness * boost
                material.diffuse.contents = ns.blended(withFraction: 0.7, of: .black) ?? ns
            }
        }
    }

    // MARK: 交互

    private func zone(at point: NSPoint) -> LightZone? {
        let hits = hitTest(point, options: [
            .searchMode: SCNHitTestSearchMode.closest.rawValue,
            .categoryBitMask: 1,
            .ignoreHiddenNodes: true
        ])
        for hit in hits {
            var node: SCNNode? = hit.node
            while let current = node {
                if let name = current.name, name.hasPrefix("zone-"),
                   let raw = UInt32(name.dropFirst("zone-".count)), raw != 0 {
                    return LightZone(rawValue: raw)
                }
                node = current.parent
            }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = convert(event.locationInWindow, from: nil)
        lastDrag = dragOrigin
        didDrag = false
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let dx = point.x - lastDrag.x
        let dy = point.y - lastDrag.y
        if abs(point.x - dragOrigin.x) > 2 || abs(point.y - dragOrigin.y) > 2 { didDrag = true }
        theta -= dx * 0.0075
        phi = min(1.35, max(-0.10, phi + dy * 0.0055))
        lastDrag = point
        updateCamera()
    }

    override func mouseUp(with event: NSEvent) {
        guard !didDrag else { return }
        let point = convert(event.locationInWindow, from: nil)
        let hit = hitTest(point, options: [.ignoreHiddenNodes: true]).first

        // 屏幕壁纸区域：交给系统默认浏览器打开官网
        if isScreenHit(hit?.node) {
            NSWorkspace.shared.open(Self.screenLink)
            return
        }
        if hit == nil || zone(at: point) == nil {
            if hit?.node.name == "lid" || hit?.node.parent?.name == "lid" {
                setLid(open: !lidIsOpen, animated: true)
                return
            }
        }
        onZoneTap?(zone(at: point))
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
        zoomScale = min(2.5, max(0.55, zoomScale + event.scrollingDeltaY * 0.012))
        updateCamera()
    }

    override func magnify(with event: NSEvent) {
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
        let point = convert(event.locationInWindow, from: nil)
        let zone = zone(at: point)
        if zone != hovered {
            hovered = zone
            onZoneHover?(zone)
        }
        if zone != nil { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
    }

    override func mouseExited(with event: NSEvent) {
        if hovered != nil {
            hovered = nil
            onZoneHover?(nil)
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
