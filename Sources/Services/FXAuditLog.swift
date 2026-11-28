//
//  FXAuditLog.swift
//  AlienMAC
//
//  v4 / v8 实机验收用的下发流水：每帧的传输方式、Report ID、返回码、耗时、原始报文
//  都落到 ~/Library/Application Support/AlienMAC/diagnostics/hid-tx-YYYYMMDD.log。
//
//  17 R4 的 v3 路径已有 AWCC 抓包对照，这份流水只为“没有抓包条件”的 v4/v8 留证据：
//  接上机器后先在协议族面板点「最小试发 1 盏灯」，再把这个文件拿出来核对。
//

import Foundation

enum FXAuditLog {

    private static let queue = DispatchQueue(label: "com.alienmac.auditlog", qos: .utility)

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return f
    }()

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent("AlienMAC", isDirectory: true)
            .appendingPathComponent("diagnostics", isDirectory: true)
    }

    static func fileURL(for date: Date = Date()) -> URL {
        directory.appendingPathComponent("hid-tx-\(dayFormatter.string(from: date)).log")
    }

    /// 一帧的流水：成功与失败都记，失败要能看出是协议不符、长度不符还是 IO 返回非 0
    static func record(proto: String,
                       transport: String,
                       reportID: Int,
                       length: Int,
                       result: IOReturn?,
                       elapsedMS: Double,
                       payload: [UInt8],
                       attempt: Int = 1) {
        let stamp = stampFormatter.string(from: Date())
        let hex = payload.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
        let tail = payload.count > 8 ? " …(\(payload.count)B)" : ""
        let ret = result.map { String(format: "0x%X", $0) } ?? "skip"
        append("\(stamp)\t\(proto)\t\(transport)\trid=\(reportID)\tlen=\(length)\tret=\(ret)\t\(String(format: "%.2f", elapsedMS))ms\t#\(attempt)\t\(hex)\(tail)")
    }

    /// 场景级事件（开始 / 结束 / 被开关拦下）
    static func note(_ message: String) {
        let stamp = stampFormatter.string(from: Date())
        append("\(stamp)\t\(message)")
    }

    static func logPath() -> String {
        fileURL().path
    }

    private static func append(_ line: String) {
        let url = fileURL()
        let dir = directory
        queue.async {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                if let data = (line + "\n").data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } catch {
                // 流水写不进去不该影响灯效下发，静默失败
            }
        }
    }
}
