//
//  WebBridge.swift
//  AlienMAC
//
//  手机访问：内置 HTTP + SSE 服务，同一局域网里手机扫码即可打开控制页面。
//  - GET  /            手机端控制页面
//  - GET  /api/state   当前状态快照
//  - GET  /api/events  SSE 事件流（状态变化实时推送）
//  - POST /api/action  手机端操作，转发给主界面同一套逻辑
//

import Foundation
import Network
import Combine
import AppKit
import SceneKit
import SpriteKit
import CoreImage
import SystemConfiguration

final class WebBridge: ObservableObject {

    static let shared = WebBridge()

    @Published private(set) var isRunning = false
    @Published private(set) var clientCount = 0
    @Published private(set) var address: String = ""
    /// 直连 IP 地址（域名没生效时的备用路径）
    @Published private(set) var ipAddress: String = ""
    /// 网页里展示的模型快照（app 里的同一套 3D 建模）
    private var modelCache: Data?
    private var modelCacheDate = Date.distantPast

    private let queue = DispatchQueue(label: "com.alienmac.web")
    private var listener: NWListener?
    private var port: UInt16 = 0

    private final class Connection {
        let id = UUID()
        let nw: NWConnection
        var buffer = Data()
        var streaming = false
        var userAgent = ""
        init(nw: NWConnection) { self.nw = nw }
    }

    private var connections: [UUID: Connection] = [:]
    private var streams: [UUID: NWConnection] = [:]

    private var snapshot: (() -> [String: Any])?
    private var action: (([String: Any]) -> Void)?
    private var cancellable: AnyCancellable?
    private var pendingBroadcast = false
    private var heartbeat: Timer?
    private var port80Cancellable: AnyCancellable?

    // MARK: - 生命周期

    /// 绑定主视图模型：状态来源 + 操作入口
    func bind(_ vm: LightingViewModel) {
        snapshot = { [weak vm] in vm?.webSnapshot() ?? [:] }
        action = { [weak vm] in vm?.handleWebAction($0) }
        cancellable = vm.objectWillChange.sink { [weak self] _ in
            self?.scheduleBroadcast()
        }
    }

    func start() {
        if port80Cancellable == nil {
            port80Cancellable = Port80Bridge.shared.objectWillChange.sink { [weak self] _ in
                DispatchQueue.main.async { self?.refreshAddresses() }
            }
        }
        guard listener == nil else { return }
        startAttempt(0)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        queue.async { [weak self] in
            self?.connections.values.forEach { $0.nw.cancel() }
            self?.connections.removeAll()
            self?.streams.removeAll()
        }
        heartbeat?.invalidate(); heartbeat = nil
        DispatchQueue.main.async { self.isRunning = false; self.clientCount = 0 }
    }

    private func startAttempt(_ index: Int) {
        let candidates: [UInt16] = [8899, 8900, 8901, 8890, 8080, 8091, 9090]
        guard index < candidates.count else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            guard let nwPort = NWEndpoint.Port(rawValue: candidates[index]) else { return }
            let l = try NWListener(using: params, on: nwPort)
            // 顺手广播一个 Bonjour 服务名，方便高级用户在「本地网络」里找到
            l.service = NWListener.Service(name: "AlienMAC", type: "_http._tcp")
            l.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.listener = l
                    self.port = candidates[index]
                    let host = WebBridge.lanIPv4() ?? "localhost"
                    WebBridge.writePort(candidates[index])
                    DispatchQueue.main.async {
                        self.isRunning = true
                        self.refreshAddresses()
                    }
                    // 让 alien.mac 在局域网里也能解析（路由器 DNS 没配时靠组播兜底）
                    LocalDNSResponder.shared.start(hostNames: ["alien.mac"], address: host)
                    self.startHeartbeat()
                case .failed, .cancelled:
                    self.listener = nil
                    DispatchQueue.main.async { self.isRunning = false }
                    self.startAttempt(index + 1)
                default:
                    break
                }
            }
            l.newConnectionHandler = { [weak self] conn in
                self?.accept(conn)
            }
            l.start(queue: queue)
        } catch {
            startAttempt(index + 1)
        }
    }

    private func startHeartbeat() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.heartbeat == nil else { return }
            self.heartbeat = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                self?.queue.async {
                    guard let self = self else { return }
                    for nw in self.streams.values {
                        nw.send(content: Data(": ping\n\n".utf8), completion: .contentProcessed { _ in })
                    }
                }
                self?.scheduleBroadcast()
            }
        }
    }

    // MARK: - 连接

    private func accept(_ nw: NWConnection) {
        let conn = Connection(nw: nw)
        connections[conn.id] = conn
        nw.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.close(conn.id)
            default:
                break
            }
        }
        nw.start(queue: queue)
        receive(conn)
    }

    private func receive(_ conn: Connection) {
        conn.nw.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty { conn.buffer.append(data) }
            if error != nil || isComplete {
                self.close(conn.id)
                return
            }
            self.process(conn)
        }
    }

    private func process(_ conn: Connection) {
        guard let headerRange = conn.buffer.range(of: Data("\r\n\r\n".utf8)) else {
            if conn.buffer.count > 65536 { close(conn.id) } else { receive(conn) }
            return
        }
        let headData = conn.buffer.subdata(in: 0..<headerRange.lowerBound)
        let head = String(data: headData, encoding: .utf8) ?? ""
        let lines = head.components(separatedBy: "\r\n")
        let requestParts = (lines.first ?? "").split(separator: " ")
        let method = requestParts.count > 0 ? String(requestParts[0]) : "GET"
        let path = requestParts.count > 1 ? String(requestParts[1]) : "/"

        var contentLength = 0
        conn.userAgent = ""
        for line in lines.dropFirst() {
            let lower = line.lowercased()
            if lower.hasPrefix("user-agent:") {
                conn.userAgent = line.split(separator: ":", maxSplits: 1).last
                    .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            }
            if lower.hasPrefix("content-length:") {
                let value = line.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
                contentLength = Int(value.trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }

        let bodyStart = headerRange.upperBound
        if conn.buffer.count - bodyStart < contentLength {
            receive(conn)
            return
        }
        let body = contentLength > 0 ? conn.buffer.subdata(in: bodyStart..<(bodyStart + contentLength)) : Data()
        route(conn, method: method, path: path, body: body)
    }

    private func close(_ id: UUID) {
        connections[id]?.nw.cancel()
        connections.removeValue(forKey: id)
        streams.removeValue(forKey: id)
        let count = streams.count
        DispatchQueue.main.async { self.clientCount = count }
    }

    // MARK: - 路由

    private func route(_ conn: Connection, method: String, path: String, body: Data) {
        let routePath = path.components(separatedBy: "?").first ?? path

        switch (method, routePath) {
        case ("GET", "/"), ("GET", "/index.html"):
            let html = Self.prefersPhonePage(conn.userAgent) ? MobileWebPage.html : DesktopWebPage.html
            respond(conn, status: 200, type: "text/html; charset=utf-8", body: Data(html.utf8))

        case ("GET", "/mobile"):
            respond(conn, status: 200, type: "text/html; charset=utf-8", body: Data(MobileWebPage.html.utf8))

        case ("GET", "/desktop"):
            respond(conn, status: 200, type: "text/html; charset=utf-8", body: Data(DesktopWebPage.html.utf8))

        case ("GET", "/api/state"):
            respond(conn, status: 200, type: "application/json; charset=utf-8", body: Data(currentJSON().utf8))

        case ("GET", "/api/events"):
            startStream(conn)

        case ("POST", "/api/action"):
            if let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] {
                DispatchQueue.main.async { [weak self] in self?.action?(object) }
            }
            respond(conn, status: 200, type: "application/json; charset=utf-8", body: Data("{\"ok\":true}".utf8))
            scheduleBroadcast(force: true)

        case ("GET", "/api/model.jpg"):
            modelJPEG { [weak self] data in
                self?.respond(conn, status: 200, type: "image/jpeg", body: data ?? Data())
            }

        case ("GET", "/api/logo.png"), ("GET", "/favicon.ico"):
            respond(conn, status: 200, type: "image/png", body: Self.appLogoPNG())

        default:
            respond(conn, status: 404, type: "text/plain; charset=utf-8", body: Data("not found".utf8))
        }
    }

    private func respond(_ conn: Connection, status: Int, type: String, body: Data) {
        let phrase = status == 200 ? "OK" : (status == 204 ? "No Content" : "Not Found")
        var head = "HTTP/1.1 \(status) \(phrase)\r\n"
        head += "Content-Type: \(type)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-cache, no-store\r\n"
        head += "Connection: close\r\n\r\n"
        var packet = Data(head.utf8)
        packet.append(body)
        let id = conn.id
        conn.nw.send(content: packet, completion: .contentProcessed { [weak self] _ in
            self?.close(id)
        })
    }

    /// 网页左上角与 favicon 共用的 logo
    /// 优先用网页专用版（Resources/app_logo_web.png：4 倍分辨率 + 提亮 + 青紫光晕，
    /// 因为原图 47×57 偏暗，缩到 40px 左右在深色底上几乎看不清），没有则退回原图
    private static let logoData: Data = {
        for name in ["app_logo_web", "app_logo"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let data = try? Data(contentsOf: url) { return data }
        }
        return Data()
    }()

    static func appLogoPNG() -> Data { logoData }

    // MARK: - SSE

    private func startStream(_ conn: Connection) {
        guard !conn.streaming else { close(conn.id); return }
        conn.streaming = true
        let head = "HTTP/1.1 200 OK\r\n"
            + "Content-Type: text/event-stream; charset=utf-8\r\n"
            + "Cache-Control: no-cache\r\n"
            + "Connection: keep-alive\r\n\r\n"
            + "retry: 3000\n\n"
        conn.nw.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
        streams[conn.id] = conn.nw
        let count = streams.count
        DispatchQueue.main.async { self.clientCount = count }

        // 连上就先给一份完整状态
        let json = currentJSON()
        sendEvent(conn.nw, json)

        // 只监听断开
        conn.nw.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] _, _, isComplete, error in
            if isComplete || error != nil { self?.close(conn.id) }
        }
    }

    private func sendEvent(_ nw: NWConnection, _ json: String) {
        let packet = "event: state\ndata: \(json)\n\n"
        nw.send(content: Data(packet.utf8), completion: .contentProcessed { _ in })
    }

    // MARK: - 推送

    private func currentJSON() -> String {
        let object = snapshot?() ?? [:]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private func scheduleBroadcast(force: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if force {
                self.fire()
                return
            }
            guard !self.pendingBroadcast else { return }
            self.pendingBroadcast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                self.pendingBroadcast = false
                self.fire()
            }
        }
    }

    private func fire() {
        guard !streams.isEmpty else { return }
        let json = currentJSON()
        queue.async { [weak self] in
            guard let self = self else { return }
            for nw in self.streams.values { self.sendEvent(nw, json) }
        }
    }

    // MARK: - 模型快照（网页里显示 app 同一套 3D 建模）

    private func modelJPEG(_ completion: @escaping (Data?) -> Void) {
        DispatchQueue.main.async {
            if Date().timeIntervalSince(self.modelCacheDate) < 1.2, let cached = self.modelCache {
                completion(cached)
                return
            }
            // 屏幕材质里贴的是实时帧位图，snapshot 能直接拍到，不需要再换纹理，
            // 所以前台后台都可以正常刷新，主界面也不会因为网页轮询闪一下
            // 直接截 app 这块 3D 视图：角度、灯光、屏幕里的动态壁纸都和主界面一致
            guard let view = LaptopSceneNSView.shared, view.bounds.width > 4, view.bounds.height > 4 else {
                completion(nil)
                return
            }
            let bounds = view.bounds
            let width: CGFloat = 1240
            let canvasSize = NSSize(width: width, height: (width * bounds.height / bounds.width).rounded())
            let contactShadow = view.scene?.rootNode.childNodes.first { node in
                guard let plane = node.geometry as? SCNPlane else { return false }
                return abs(plane.width - 58) < 0.2
            }
            let shadowWasHidden = contactShadow?.isHidden ?? true
            contactShadow?.isHidden = true
            let shot = view.snapshot()
            contactShadow?.isHidden = shadowWasHidden
            let accent = Self.previewAccent(self.snapshot?()["primary"] as? String)
            let composed = Self.composePreview(shot, size: canvasSize, accent: accent)
            guard let tiff = composed.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let fullCG = rep.cgImage,
                  let cropped = fullCG.cropping(to: CGRect(x: CGFloat(fullCG.width) * 0.13,
                                                           y: CGFloat(fullCG.height) * 0.04,
                                                           width: CGFloat(fullCG.width) * 0.75,
                                                           height: CGFloat(fullCG.height) * 0.92)) else {
                completion(nil)
                return
            }
            let croppedRep = NSBitmapImageRep(cgImage: cropped)
            guard let data = croppedRep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else {
                completion(nil)
                return
            }
            self.modelCache = data
            self.modelCacheDate = Date()
            completion(data)
        }
    }

    /// 网页预览的主色（灯效主色也参与背景辉光，看着和 app 一致）
    private static func previewAccent(_ hex: String?) -> NSColor {
        guard let hex else { return NSColor(calibratedRed: 0, green: 0.55, blue: 1, alpha: 1) }
        let text = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard text.count == 6, let value = UInt32(text, radix: 16) else {
            return NSColor(calibratedRed: 0, green: 0.55, blue: 1, alpha: 1)
        }
        return NSColor(calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255,
                       alpha: 1)
    }

    /// 把离屏渲染的机身叠到 app 同款深色辉光背景上
    private static func composePreview(_ shot: NSImage, size: NSSize, accent: NSColor) -> NSImage {
        let canvas = NSImage(size: size)
        canvas.lockFocus()
        defer { canvas.unlockFocus() }

        let rect = NSRect(origin: .zero, size: size)
        NSColor.black.setFill()
        rect.fill()

        // 主界面同款径向底色（中心偏上）
        let base = NSGradient(colorsAndLocations:
            (NSColor(calibratedRed: 0.06, green: 0.14, blue: 0.25, alpha: 1), 0.0),
            (NSColor(calibratedRed: 0.02, green: 0.04, blue: 0.08, alpha: 1), 0.55),
            (NSColor.black, 1.0))
        let center = NSPoint(x: size.width * 0.42, y: size.height * 0.58)
        base?.draw(fromCenter: center, radius: 0,
                   toCenter: center, radius: size.width * 0.66, options: [])

        // 右下角的紫调，和主界面一致
        let purple = NSGradient(colorsAndLocations:
            (NSColor(calibratedRed: 0.55, green: 0.10, blue: 0.70, alpha: 0.16), 0.0),
            (NSColor(calibratedRed: 0.55, green: 0.10, blue: 0.70, alpha: 0), 1.0))
        let corner = NSPoint(x: size.width * 0.86, y: size.height * 0.06)
        purple?.draw(fromCenter: corner, radius: 0,
                     toCenter: corner, radius: size.width * 0.62, options: [])

        // 机身背后的主色辉光：灯是什么色，底下就亮什么色
        let glow = NSGradient(colorsAndLocations:
            (accent.withAlphaComponent(0.22), 0.0),
            (accent.withAlphaComponent(0.10), 0.45),
            (accent.withAlphaComponent(0), 1.0))
        let glowCenter = NSPoint(x: size.width * 0.5, y: size.height * 0.30)
        glow?.draw(fromCenter: glowCenter, radius: 0,
                   toCenter: glowCenter, radius: size.width * 0.46, options: [])

        NSGraphicsContext.current?.imageInterpolation = .high
        shot.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        return canvas
    }


    /// 手机 / 平板走手机版页面，电脑浏览器走桌面版
    static func prefersPhonePage(_ userAgent: String) -> Bool {
        let ua = userAgent.lowercased()
        if ua.isEmpty { return true }
        let phoneMarkers = ["iphone", "ipod", "android", "mobile", "windows phone",
                            "harmonyos", "micromessenger"]
        if phoneMarkers.contains(where: { ua.contains($0) }) { return true }
        // iPad 走桌面版（屏幕够大，桌面布局更好用），其余桌面浏览器一律桌面版
        return false
    }

    // MARK: - 工具

    /// 本机 Bonjour 主机名（SCDynamicStore 里取，改了不用重启就生效）
    static func localHostName() -> String {
        if let name = SCDynamicStoreCopyLocalHostName(nil) as String?, !name.isEmpty {
            return name
        }
        return "localhost"
    }

    /// 把实际端口写给 80 端口转发器读（它跑在 root 下，读不了用户域的偏好设置）
    static func writePort(_ port: UInt16) {
        try? String(port).write(toFile: "/tmp/alienmac-web-port", atomically: true, encoding: .utf8)
    }

    /// 按「有没有装 80 端口守护」重算展示地址
    func refreshAddresses() {
        Port80Bridge.shared.refresh()
        let host = WebBridge.lanIPv4() ?? "localhost"
        let name = WebBridge.localHostName()
        if Port80Bridge.shared.enabled {
            address = "http://\(name).local"
            ipAddress = "http://\(host)"
        } else {
            address = "http://\(name).local:\(port)"
            ipAddress = "http://\(host):\(port)"
        }
    }

    /// 局域网 IPv4（优先 en0 / en1，跳过回环）
    static func lanIPv4() -> String? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }
        var fallback: String?
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let item = current {
            let flags = Int32(item.pointee.ifa_flags)
            if item.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_INET), (flags & IFF_UP) != 0 {
                let name = String(cString: item.pointee.ifa_name)
                var address = item.pointee.ifa_addr!.pointee
                var host = [CChar](repeating: 0, count: 64)
                getnameinfo(&address, socklen_t(address.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                let ip = String(cString: host)
                if !ip.isEmpty, !ip.hasPrefix("127."), !ip.hasPrefix("169.254.") {
                    if name == "en0" || name == "en1" { return ip }
                    if fallback == nil { fallback = ip }
                }
            }
            current = item.pointee.ifa_next
        }
        return fallback
    }

    /// 生成二维码（扫描直接打开，不用手输 IP）
    static func qrImage(_ text: String, size: CGFloat) -> NSImage? {
        let context = CIContext()
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }
}
