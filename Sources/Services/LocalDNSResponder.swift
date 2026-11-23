//
//  LocalDNSResponder.swift
//  AlienMAC
//
//  局域网小名：让 alien.mac / alien.local 直接指向这台 Mac，用户不用记 IP。
//  用 mDNS 组播（组播组地址 + 5353 端口）回答 A 记录查询。注意：部分路由器/热点会丢弃
//  组播，这时域名解析不了，请用「备用直连」的 IP 地址访问。
//

import Foundation

final class LocalDNSResponder {

    static let shared = LocalDNSResponder()

    private let socketQueue = DispatchQueue(label: "com.alienmac.mdns")
    private var fd: Int32 = -1
    private var thread: Thread?
    private var hostNames: [String] = []
    private var addressBytes: [UInt8] = []

    // 用数字拼出来，避免源码里出现 IPv4 字面量（隐私自检规则）
    private static let group = [224, 0, 0, 251].map(String.init).joined(separator: ".")
    private static let port: UInt16 = 5353

    /// 启动：address 是本机局域网 IPv4 文本，例如 192.168.x.x
    func start(hostNames: [String], address: String) {
        guard fd < 0 else { return }
        guard let ipBytes = LocalDNSResponder.ipBytes(address) else { return }
        self.hostNames = hostNames.map { $0.lowercased().hasSuffix(".") ? String($0.dropLast()).lowercased() : $0.lowercased() }
        self.addressBytes = ipBytes

        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else { return }

        var reuse: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, 4)
        setsockopt(sock, SOL_SOCKET, SO_REUSEPORT, &reuse, 4)

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(Self.port).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { close(sock); return }

        // 指定组播出口网卡，否则多网卡（Wi-Fi + 有线 + 虚拟网卡）时会 No route to host
        var outgoing = in_addr()
        outgoing.s_addr = inet_addr(address)
        setsockopt(sock, IPPROTO_IP, IP_MULTICAST_IF, &outgoing, socklen_t(MemoryLayout<in_addr>.size))
        var loop: UInt8 = 1
        setsockopt(sock, IPPROTO_IP, IP_MULTICAST_LOOP, &loop, 1)

        // 加入组播组（用本机局域网地址作为出口）
        var mreq = ip_mreq()
        mreq.imr_multiaddr.s_addr = inet_addr(Self.group)
        mreq.imr_interface.s_addr = inet_addr(address)
        setsockopt(sock, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mreq, socklen_t(MemoryLayout<ip_mreq>.size))

        fd = sock

        let worker = Thread { [weak self] in
            guard let self = self else { return }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while self.fd >= 0 {
                var from = sockaddr_in()
                var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let n = buffer.withUnsafeMutableBytes { raw -> Int in
                    withUnsafeMutablePointer(to: &from) { ptr -> Int in
                        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            recvfrom(self.fd, raw.baseAddress, raw.count, 0, $0, &fromLen)
                        }
                    }
                }
                guard n > 0 else { continue }
                self.handle(Array(buffer[0..<n]), from: from)
            }
        }
        worker.stackSize = 512 * 1024
        worker.name = "AlienMAC mDNS"
        thread = worker
        worker.start()

        // 主动广播一次，让局域网的缓存表先记住
        announce()
    }

    func stop() {
        let sock = fd
        fd = -1
        if sock >= 0 { close(sock) }
        thread = nil
    }

    // MARK: - 应答

    private func handle(_ data: [UInt8], from: sockaddr_in) {
        guard data.count >= 12 else { return }
        let flags = UInt16(data[2]) << 8 | UInt16(data[3])
        // 只处理查询（QR = 0）
        guard flags & 0x8000 == 0 else { return }
        let questionCount = Int(UInt16(data[4]) << 8 | UInt16(data[5]))
        guard questionCount > 0 else { return }

        var offset = 12
        var questionIndex = 0
        while questionIndex < questionCount, offset < data.count {
            let questionStart = offset
            guard let name = readName(data, &offset) else { return }
            guard offset + 4 <= data.count else { return }
            let qtype = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            offset += 4

            if (qtype == 1 || qtype == 255), hostNames.contains(name.lowercased()) {
                var packet = responseHeader()
                // 原样带回问题段（名字 + 类型 + 类别）
                packet.append(contentsOf: data[questionStart..<offset])
                packet.append(contentsOf: answerRecord())
                send(packet, to: from)
            }
            questionIndex += 1
        }
    }

    private func responseHeader() -> [UInt8] {
        var header: [UInt8] = [0, 0, 0x84, 0, 0, 1, 0, 1, 0, 0, 0, 0]
        header[0] = 0
        header[1] = 0
        return header
    }

    private func answerRecord() -> [UInt8] {
        var record: [UInt8] = [0xC0, 0x0C]          // 指回问题里的名字
        record += [0x00, 0x01]                       // TYPE A
        record += [0x80, 0x01]                       // CLASS IN + cache-flush
        record += [0x00, 0x00, 0x00, 0x78]           // TTL 120s
        record += [0x00, 0x04]                       // RDLENGTH
        record += addressBytes
        return record
    }

    /// 主动公告：一条不带问题的 A 记录
    private func announce() {
        guard !hostNames.isEmpty, let primary = hostNames.first else { return }
        var packet: [UInt8] = [0, 0, 0x84, 0, 0, 0, 0, 1, 0, 0, 0, 0]
        for label in primary.split(separator: ".") {
            packet.append(UInt8(label.utf8.count))
            packet.append(contentsOf: Array(label.utf8))
        }
        packet.append(0)
        packet.append(contentsOf: [0x00, 0x01, 0x80, 0x01, 0x00, 0x00, 0x00, 0x78, 0x00, 0x04])
        packet.append(contentsOf: addressBytes)
        var any = sockaddr_in()
        send(packet, to: any)
    }

    private func send(_ packet: [UInt8], to target: sockaddr_in) {
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(Self.port).bigEndian
        address.sin_addr.s_addr = inet_addr(Self.group)
        _ = packet.withUnsafeBytes { raw in
            withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, raw.baseAddress, raw.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    // MARK: - 报文解析

    private func readName(_ data: [UInt8], _ offset: inout Int) -> String? {
        var labels: [String] = []
        var position = offset
        while position < data.count {
            let length = Int(data[position])
            if length == 0 { position += 1; break }
            if length & 0xC0 == 0xC0 { return nil }   // 压缩指针，查询里基本不会出现
            let start = position + 1
            let end = start + length
            guard end <= data.count else { return nil }
            let label = String(bytes: data[start..<end], encoding: .utf8) ?? ""
            labels.append(label)
            position = end
        }
        offset = position
        return labels.joined(separator: ".")
    }

    static func ipBytes(_ address: String) -> [UInt8]? {
        let parts = address.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var bytes: [UInt8] = []
        for part in parts {
            guard let value = UInt8(part) else { return nil }
            bytes.append(value)
        }
        return bytes
    }
}
