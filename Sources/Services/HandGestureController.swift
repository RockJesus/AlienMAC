//
//  HandGestureController.swift
//  AlienMAC
//
//  摄像头手势旋转：用 Vision 检测手掌位置，横向移动绕机身转、纵向移动调俯仰
//  画面只在本机做推理，不落盘、不上传
//

import Foundation
import AVFoundation
import Vision
import Combine

final class HandGestureController: NSObject, ObservableObject {
    static let shared = HandGestureController()

    enum Status: Equatable {
        case idle
        case requesting
        case running
        case denied
        case noCamera
        case failed(String)

        var label: String {
            switch self {
            case .idle: return "未开启"
            case .requesting: return "等待摄像头授权…"
            case .running: return "正在跟踪手掌"
            case .denied: return "摄像头权限被拒绝，请到系统设置 → 隐私与安全性 → 摄像头里打开"
            case .noCamera: return "没有找到可用的摄像头"
            case .failed(let message): return "启动失败：\(message)"
            }
        }

        var isRunning: Bool { self == .running }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var handPresent = false

    /// 开关：打开即申请权限并启动摄像头
    @Published var enabled: Bool = false {
        didSet {
            guard oldValue != enabled else { return }
            enabled ? start() : stop()
        }
    }

    /// 灵敏度（0.5 ~ 2.0），越大手移动同样距离转得越多
    @Published var sensitivity: Double = 1.0 {
        didSet { UserDefaults.standard.set(sensitivity, forKey: Self.sensitivityKey) }
    }

    /// 输出：绕 Y 轴角度增量、俯仰角增量（弧度）
    var onOrbit: ((CGFloat, CGFloat) -> Void)?

    private static let sensitivityKey = "AlienMAC.gestureSensitivity"

    private let session = AVCaptureSession()
    private let videoQueue = DispatchQueue(label: "AlienMAC.gesture.video", qos: .userInitiated)
    private var configured = false
    private var lastCenter: CGPoint?
    private var lastSeenAt: CFAbsoluteTime = 0

    private override init() {
        super.init()
        let saved = UserDefaults.standard.double(forKey: Self.sensitivityKey)
        sensitivity = saved > 0 ? saved : 1.0
    }

    // MARK: - 生命周期

    func start() {
        guard !session.isRunning else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            status = .requesting
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.configureAndRun()
                    } else {
                        self.status = .denied
                        self.enabled = false
                    }
                }
            }
        case .denied, .restricted:
            status = .denied
            enabled = false
        @unknown default:
            status = .denied
            enabled = false
        }
    }

    func stop() {
        if session.isRunning { session.stopRunning() }
        status = .idle
        handPresent = false
        lastCenter = nil
    }

    private func configureAndRun() {
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
        guard let device else {
            status = .noCamera
            enabled = false
            return
        }

        if !configured {
            session.beginConfiguration()
            session.sessionPreset = .low
            defer { session.commitConfiguration() }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else {
                    status = .failed("无法添加摄像头输入")
                    enabled = false
                    return
                }
                session.addInput(input)

                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                output.setSampleBufferDelegate(self, queue: videoQueue)
                guard session.canAddOutput(output) else {
                    status = .failed("无法添加视频输出")
                    enabled = false
                    return
                }
                session.addOutput(output)
                configured = true
            } catch {
                status = .failed(error.localizedDescription)
                enabled = false
                return
            }
        }

        let running = session
        videoQueue.async {
            running.startRunning()
            DispatchQueue.main.async {
                self.status = running.isRunning ? .running : .failed("摄像头未能启动")
            }
        }
    }

    // MARK: - 帧处理

    private func process(pixelBuffer: CVPixelBuffer) {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .leftMirrored,
                                            options: [:])
        do {
            try handler.perform([request])
        } catch {
            return
        }

        guard let observation = request.results?.first else {
            publishHand(present: false)
            return
        }

        let points = (try? observation.recognizedPoints(.all))?.values.filter { $0.confidence > 0.3 } ?? []
        guard points.count >= 5 else {
            publishHand(present: false)
            return
        }

        // 掌根 + 四个掌指关节的平均位置，比单点稳
        let anchors: [VNHumanHandPoseObservation.JointName] = [.wrist, .indexMCP, .middleMCP, .ringMCP, .littleMCP]
        let chosen = anchors.compactMap { observation.recognizedPointIfAvailable($0) }
            .filter { $0.confidence > 0.3 }
        let usable = chosen.isEmpty ? points : chosen
        let center = CGPoint(
            x: usable.map { $0.location.x }.reduce(0, +) / CGFloat(usable.count),
            y: usable.map { $0.location.y }.reduce(0, +) / CGFloat(usable.count)
        )

        let now = CFAbsoluteTimeGetCurrent()
        if let last = lastCenter, now - lastSeenAt < 0.45 {
            let dx = center.x - last.x
            let dy = center.y - last.y
            let deadzone: CGFloat = 0.0025
            if abs(dx) > deadzone || abs(dy) > deadzone {
                let gain = CGFloat(2.4 * sensitivity)
                // 画面坐标原点在左下：手向上 → dy 为正 → 视角压低，与拖动方向一致
                let dTheta = -dx * gain
                let dPhi = -dy * gain
                DispatchQueue.main.async {
                    self.onOrbit?(dTheta, dPhi)
                }
            }
        }
        lastCenter = center
        lastSeenAt = now
        publishHand(present: true)
    }

    private func publishHand(present: Bool) {
        if present {
            if !handPresent { DispatchQueue.main.async { self.handPresent = true } }
        } else {
            lastCenter = nil
            if handPresent { DispatchQueue.main.async { self.handPresent = false } }
        }
    }
}

extension HandGestureController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard status == .running, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        process(pixelBuffer: buffer)
    }
}

private extension VNHumanHandPoseObservation {
    /// 某些关节在部分帧里缺失，取不到就返回 nil
    func recognizedPointIfAvailable(_ joint: VNHumanHandPoseObservation.JointName) -> VNRecognizedPoint? {
        try? recognizedPoint(joint)
    }
}
