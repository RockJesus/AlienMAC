//
//  VoiceControlController.swift
//  AlienMAC
//
//  语音控制：麦克风实时听写（Speech + AVFoundation），在本机把中文口令映射成灯光动作。
//  画面/音频不上传；优先使用设备端识别。
//

import Foundation
import AVFoundation
import Speech
import Combine

/// 语音口令
enum VoiceCommand: Equatable {
    case keyboardOff
    case keyboardOn
    case allOff
    case allOn
    case brighter
    case dimmer
    case effect(LightEffect)

    var feedback: String {
        switch self {
        case .keyboardOff: return "关闭键盘灯"
        case .keyboardOn:  return "打开键盘灯"
        case .allOff:      return "关闭全部灯"
        case .allOn:       return "打开全部灯"
        case .brighter:    return "调亮"
        case .dimmer:      return "调暗"
        case .effect(let e): return "切换到\(e.rawValue)"
        }
    }
}

/// 语音控制单例
final class VoiceControlController: ObservableObject {
    static let shared = VoiceControlController()

    enum Status: Equatable {
        case idle
        case requesting
        case running
        case denied
        case unavailable
        case failed(String)

        var label: String {
            switch self {
            case .idle:         return "未开启"
            case .requesting:   return "正在请求麦克风与语音识别权限…"
            case .running:      return "正在听"
            case .denied:       return "权限被拒绝"
            case .unavailable:  return "语音识别暂不可用"
            case .failed(let m): return m
            }
        }

        var isRunning: Bool { self == .running }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastText: String = ""
    @Published private(set) var lastCommand: VoiceCommand?

    /// 开关：打开即开始听，关闭即停
    @Published var enabled: Bool = false {
        didSet {
            guard !isSwitching else { return }
            if enabled { activate() } else { stop() }
        }
    }

    /// 识别到口令后的回调（由 App 注入到 LightingViewModel）
    var onCommand: ((VoiceCommand) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var restartWork: DispatchWorkItem?
    private var tapInstalled = false
    private var running = false
    private var isSwitching = false
    private var lastCommandAt = Date.distantPast
    private var lastCommandText = ""

    private init() {}

    // MARK: - 启停

    private func activate() {
        status = .requesting
        lastText = ""
        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            DispatchQueue.main.async {
                guard let self else { return }
                guard speechStatus == .authorized else {
                    self.status = (speechStatus == .denied || speechStatus == .restricted) ? .denied : .unavailable
                    self.forceOff()
                    return
                }
                if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                    self.beginSession()
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        guard granted else {
                            self.status = .denied
                            self.forceOff()
                            return
                        }
                        self.beginSession()
                    }
                }
            }
        }
    }

    private func forceOff() {
        isSwitching = true
        enabled = false
        isSwitching = false
        stop()
    }

    func stop() {
        running = false
        restartWork?.cancel()
        restartWork = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning { engine.stop() }
        if status.isRunning || status == .requesting { status = .idle }
    }

    // MARK: - 识别会话

    private func beginSession() {
        guard enabled else { return }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            status = .denied
            forceOff()
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            status = .unavailable
            forceOff()
            return
        }

        endSessionOnly()

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // 支持设备端识别时强制本机推理，音频不出机器
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            status = .failed("麦克风不可用")
            forceOff()
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            status = .failed("麦克风启动失败：\(error.localizedDescription)")
            forceOff()
            return
        }

        running = true
        status = .running

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    guard self.running else { return }
                    self.lastText = text
                    self.handle(text)
                }
                if result.isFinal {
                    self.scheduleRestart()
                    return
                }
            }
            if error != nil { self.scheduleRestart() }
        }
    }

    private func endSessionOnly() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning { engine.stop() }
    }

    private func scheduleRestart() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.enabled, self.status.isRunning else { return }
            self.restartWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.enabled else { return }
                self.beginSession()
            }
            self.restartWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
        }
    }

    // MARK: - 口令匹配

    private func handle(_ text: String) {
        guard let command = Self.parse(text) else { return }
        // 同一句在 1.2 秒内不重复执行，避免听写抖动连发
        if command == lastCommand, text == lastCommandText,
           Date().timeIntervalSince(lastCommandAt) < 1.2 {
            return
        }
        guard Date().timeIntervalSince(lastCommandAt) > 0.9 else { return }
        lastCommandAt = Date()
        lastCommandText = text
        lastCommand = command
        onCommand?(command)
    }

    /// 中文口令 → 动作
    static func parse(_ text: String) -> VoiceCommand? {
        let t = text.replacingOccurrences(of: " ", with: "")
        let keyboard = t.contains("键盘") || t.contains("按键") || t.contains("背光")
        let wantOff = ["关闭", "关掉", "熄灭", "关灯", "关一下", "关背光", "别亮"].contains { t.contains($0) }
        let wantOn = ["打开", "开启", "点亮", "开灯", "亮起来", "开一下"].contains { t.contains($0) }

        if keyboard, wantOff { return .keyboardOff }
        if keyboard, wantOn { return .keyboardOn }
        if !keyboard, wantOff, t.contains("灯") { return .allOff }
        if !keyboard, wantOn, t.contains("灯") { return .allOn }

        if ["亮一点", "亮一些", "调亮", "更亮", "调高亮度", "加亮"].contains(where: { t.contains($0) }) { return .brighter }
        if ["暗一点", "暗一些", "调暗", "太亮", "降低亮度", "减亮"].contains(where: { t.contains($0) }) { return .dimmer }

        if t.contains("光谱") { return .effect(.spectrum) }
        if t.contains("光波") { return .effect(.wave) }
        if t.contains("扫描") { return .effect(.scanner) }
        if t.contains("呼吸") { return .effect(.breathing) }
        if t.contains("脉冲") { return .effect(.pulse) }
        if t.contains("渐变") { return .effect(.morph) }
        if t.contains("常亮") { return .effect(.color) }
        return nil
    }
}
