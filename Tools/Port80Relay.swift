//
//  Port80Relay.swift
//  AlienMAC
//
//  以 root 运行的极简转发器：监听 80，把请求原样转给 App 内置的 Web 服务，
//  这样手机只要输入 http://alien.local 就能打开，不用带端口。
//  由 /Library/LaunchDaemons/com.alienmac.web80.plist 拉起，KeepAlive 常驻。
//
//  App 每次启动会把实际端口写进 /tmp/alienmac-web-port，这里读它，端口漂移也不会断。
//

import Foundation
import Network

let queue = DispatchQueue.global(qos: .utility)
let portFile = "/tmp/alienmac-web-port"
let defaultPort: UInt16 = 8899

func upstreamPort() -> UInt16 {
    if let text = try? String(contentsOfFile: portFile, encoding: .utf8),
       let value = UInt16(text.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 {
        return value
    }
    return defaultPort
}

func pump(from source: NWConnection, to target: NWConnection) {
    source.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, complete, error in
        if let data = data, !data.isEmpty {
            target.send(content: data, completion: .contentProcessed { _ in })
        }
        if complete || error != nil {
            target.cancel()
            source.cancel()
            return
        }
        pump(from: source, to: target)
    }
}

let params = NWParameters.tcp
params.allowLocalEndpointReuse = true
guard let listenPort = NWEndpoint.Port(rawValue: 80) else { exit(2) }

let listener: NWListener
do {
    listener = try NWListener(using: params, on: listenPort)
} catch {
    NSLog("AlienMACPort80 bind failed: \(error)")
    exit(1)
}

listener.newConnectionHandler = { client in
    client.start(queue: queue)
    guard let upstream = NWEndpoint.Port(rawValue: upstreamPort()) else {
        client.cancel()
        return
    }
    let server = NWConnection(host: NWEndpoint.Host("localhost"), port: upstream, using: .tcp)
    server.start(queue: queue)
    pump(from: client, to: server)
    pump(from: server, to: client)
}

listener.start(queue: queue)
RunLoop.main.run()
