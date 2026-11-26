//
//  MQTTClient.swift
//  AlienMAC
//
//  极简 MQTT 3.1.1 客户端（TCP，QoS0 订阅 + QoS0/1 发布），只依赖 Network.framework。
//  足够把灯光状态接入 Home Assistant 的 Mosquitto 加载项。
//

import Foundation
import Network

final class MQTTClient {

    struct Config {
        var host: String
        var port: UInt16
        var username: String
        var password: String
        var clientID: String
        var willTopic: String = ""
        var willPayload: String = ""
    }

    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    /// 第一次连不上 / 连接被拒时回调，用来在界面上给出「连接失败」而不是一直转圈
    var onFailure: ((String) -> Void)?
    var onMessage: ((String, String) -> Void)?

    private(set) var isConnected = false
    private var connection: NWConnection?
    private var buffer = Data()
    private var subscribeQueue: [String] = []
    private var packetID: UInt16 = 1
    private var pingTimer: Timer?
    private var reconnectTimer: Timer?
    private var connectTimeoutTimer: Timer?
    /// 当前这一轮连接是否已经报过错，避免 .waiting 反复触发时刷屏
    private var reportedFailure = false
    private var config: Config?
    private var wantConnected = false
    private let queue = DispatchQueue(label: "com.alienmac.mqtt")

    // MARK: - 连接

    func connect(_ config: Config) {
        self.config = config
        wantConnected = true
        openSocket(config)
    }

    private func openSocket(_ config: Config) {
        closeSocket()
        buffer.removeAll()
        reportedFailure = false

        guard let port = NWEndpoint.Port(rawValue: config.port) else { return }
        let conn = NWConnection(host: NWEndpoint.Host(config.host), port: port, using: .tcp)
        connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.queue.async { self.sendConnectPacket(config) }
            case .waiting(let error):
                // 端口不通 / 被防火墙拦下时 NWConnection 会一直停在 waiting，
                // 以前这里什么都不做，界面就永远显示「正在连接」。
                self.queue.async { self.reportFailure(Self.describe(error)) }
            case .failed, .cancelled:
                self.queue.async { self.handleDrop() }
            default:
                break
            }
        }
        conn.start(queue: queue)
        startConnectTimeout(config)
        receiveLoop(on: conn)
    }

    /// 建链超时：TCP 握手 10 秒还没进 MQTT 会话就给个明确的失败提示
    private func startConnectTimeout(_ config: Config) {
        connectTimeoutTimer?.invalidate()
        let timer = Timer(timeInterval: 10, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                guard !self.isConnected else { return }
                self.reportFailure("10 秒内没连上 \(config.host):\(config.port)")
                self.handleDrop()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        connectTimeoutTimer = timer
    }

    private func reportFailure(_ reason: String) {
        guard !reportedFailure else { return }
        reportedFailure = true
        DispatchQueue.main.async { self.onFailure?(reason) }
    }

    private static func describe(_ error: NWError) -> String {
        switch error {
        case .posix(let code):
            switch code {
            case .ECONNREFUSED: return "对方端口拒绝连接（端口没开放）"
            case .ETIMEDOUT:    return "连接超时（网络不通或被防火墙拦了）"
            case .ENETUNREACH, .EHOSTUNREACH: return "主机不可达（地址写错了或不在同一网络）"
            default: return "网络错误 \(code.rawValue)"
            }
        default:
            return error.debugDescription
        }
    }

    func disconnect() {
        wantConnected = false
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        connectTimeoutTimer?.invalidate()
        connectTimeoutTimer = nil
        closeSocket()
        isConnected = false
    }

    private func closeSocket() {
        pingTimer?.invalidate(); pingTimer = nil
        connectTimeoutTimer?.invalidate(); connectTimeoutTimer = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }

    private func handleDrop() {
        let wasConnected = isConnected
        isConnected = false
        pingTimer?.invalidate(); pingTimer = nil
        if wasConnected { DispatchQueue.main.async { self.onDisconnected?() } }
        guard wantConnected else { return }
        reconnectTimer?.invalidate()
        let timer = Timer(timeInterval: 6, repeats: false) { [weak self] _ in
            guard let self, let cfg = self.config, self.wantConnected else { return }
            self.openSocket(cfg)
        }
        RunLoop.main.add(timer, forMode: .common)
        reconnectTimer = timer
    }

    // MARK: - 收包

    private func receiveLoop(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.queue.async {
                    self.buffer.append(data)
                    self.processBuffer()
                }
            }
            if isComplete || error != nil {
                self.queue.async { self.handleDrop() }
                return
            }
            if self.connection === conn {
                self.receiveLoop(on: conn)
            }
        }
    }

    private func processBuffer() {
        while true {
            guard buffer.count >= 2 else { return }
            let first = buffer[buffer.startIndex]
            var index = buffer.startIndex + 1
            var multiplier = 1
            var length = 0
            var byte: UInt8 = 0x80
            while (byte & 0x80) != 0 {
                guard index < buffer.endIndex else { return }
                byte = buffer[index]
                index += 1
                length += Int(byte & 0x7F) * multiplier
                multiplier *= 128
                if multiplier > 128 * 128 * 128 { return }
            }
            guard buffer.count >= (index - buffer.startIndex) + length else { return }
            let body = buffer.subdata(in: index..<(index + length))
            buffer.removeSubrange(buffer.startIndex..<(index + length))
            handlePacket(first: first, body: body)
        }
    }

    private func handlePacket(first: UInt8, body: Data) {
        let type = first >> 4
        switch type {
        case 2:  // CONNACK
            guard body.count >= 2, body[1] == 0 else {
                handleDrop()
                return
            }
            isConnected = true
            DispatchQueue.main.async { self.onConnected?() }
            for topic in subscribeQueue { sendSubscribe(topic) }
            startPing()
        case 3:  // PUBLISH
            let qos = (first >> 1) & 0x03
            var idx = 0
            if qos > 0 { idx += 2 }
            guard body.count >= idx + 2 else { return }
            let topicLen = Int(body[idx]) << 8 | Int(body[idx + 1])
            idx += 2
            guard body.count >= idx + topicLen else { return }
            let topic = String(data: body.subdata(in: idx..<(idx + topicLen)), encoding: .utf8) ?? ""
            idx += topicLen
            let payload = String(data: body.subdata(in: idx..<body.count), encoding: .utf8) ?? ""
            DispatchQueue.main.async { self.onMessage?(topic, payload) }
        default:
            break
        }
    }

    // MARK: - 发包

    private func startPing() {
        pingTimer?.invalidate()
        let timer = Timer(timeInterval: 25, repeats: true) { [weak self] _ in
            self?.queue.async { self?.sendPing() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pingTimer = timer
    }

    private func send(_ data: Data) {
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    private func sendConnectPacket(_ config: Config) {
        var payload = Data()
        payload.appendString(config.clientID)
        var flags: UInt8 = 0x02  // clean session
        if !config.willTopic.isEmpty {
            flags |= 0x04 | 0x20  // will + will retain
            payload.appendString(config.willTopic)
            payload.append(contentsOf: Array(config.willPayload.utf8))
        }
        if !config.username.isEmpty {
            flags |= 0x80
            payload.appendString(config.username)
            if !config.password.isEmpty {
                flags |= 0x40
                payload.appendString(config.password)
            }
        }

        var body = Data()
        body.append(0x00); body.append(0x04)
        body.append(contentsOf: Array("MQTT".utf8))
        body.append(0x04)          // protocol level 3.1.1
        body.append(flags)
        body.append(0x00); body.append(0x1E)  // keepalive 30s
        body.append(payload)

        var packet = Data([0x10])
        packet.append(mqttLength(body.count))
        packet.append(body)
        send(packet)
    }

    func publish(topic: String, payload: String, retain: Bool) {
        guard topic.isEmpty == false else { return }
        queue.async {
            guard self.isConnected else { return }
            var body = Data()
            body.appendString(topic)
            body.append(contentsOf: Array(payload.utf8))
            var packet = Data([0x30 | (retain ? 0x01 : 0x00)])
            packet.append(self.mqttLength(body.count))
            packet.append(body)
            self.send(packet)
        }
    }

    func subscribe(_ topic: String) {
        if subscribeQueue.contains(topic) { return }
        subscribeQueue.append(topic)
        guard isConnected else { return }
        queue.async { self.sendSubscribe(topic) }
    }

    private func sendSubscribe(_ topic: String) {
        var body = Data()
        body.append(0x00); body.append(0x01)
        body.appendString(topic)
        body.append(0x00)  // QoS0
        var packet = Data([0x82])
        packet.append(mqttLength(body.count))
        packet.append(body)
        send(packet)
    }

    private func sendPing() {
        guard isConnected else { return }
        send(Data([0xC0, 0x00]))
    }

    private func mqttLength(_ length: Int) -> Data {
        var value = length
        var out = Data()
        repeat {
            var byte = UInt8(value % 128)
            value /= 128
            if value > 0 { byte |= 0x80 }
            out.append(byte)
        } while value > 0
        return out
    }
}

private extension Data {
    /// MQTT 的 UTF-8 Encoded String：2 字节长度前缀 + 内容
    mutating func appendString(_ string: String) {
        let bytes = Array(string.utf8)
        append(UInt8((bytes.count >> 8) & 0xFF))
        append(UInt8(bytes.count & 0xFF))
        append(contentsOf: bytes)
    }
}
