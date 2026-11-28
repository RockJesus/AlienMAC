//
//  ProbeArchive.swift
//  AlienMAC
//
//  可分享的自检档案：别人在自己机器上导出一份，你导入后能按同一 VID/PID 比对回读差异。
//  纯数据 + 纯比较规则，方便单测。
//

import Foundation

struct ProbeArchive: Codable, Identifiable, Hashable {
    var schema: String
    var appVersion: String
    var generatedAt: String
    var deviceName: String
    var vid: Int
    var pid: Int
    var family: PeripheralFamily
    var capability: String
    /// 没做过自检就留空，不伪造结论
    var report: ProbeReport?

    var id: String { String(format: "%04X:%04X", vid, pid) }

    init(schema: String = ProbeArchive.schemaVersion,
         appVersion: String, generatedAt: String, deviceName: String,
         vid: Int, pid: Int, family: PeripheralFamily,
         capability: String, report: ProbeReport?) {
        self.schema = schema
        self.appVersion = appVersion
        self.generatedAt = generatedAt
        self.deviceName = deviceName
        self.vid = vid
        self.pid = pid
        self.family = family
        self.capability = capability
        self.report = report
    }

    static let schemaVersion = "alienmac.probe/1"
}

struct ProbeArchiveFile: Codable {
    var schema: String
    var items: [ProbeArchive]
}

enum ProbeArchiveCompare {

    /// 同一 VID/PID 的结论比对：一致 / 不一致 / 本机没有
    static func summary(local: [ProbeArchive], remote: ProbeArchive) -> String {
        guard let mine = local.first(where: { $0.vid == remote.vid && $0.pid == remote.pid }) else {
            return "本机还没有这台设备的自检记录，先点一次「自检」再来比"
        }
        let mineText = mine.report?.verdict.rawValue ?? "未自检"
        let remoteText = remote.report?.verdict.rawValue ?? "未自检"
        if mineText == remoteText {
            return "结论一致：\(remoteText)（对方 \(remote.deviceName) · \(remote.appVersion)）"
        }
        return "结论不一致：本机 \(mineText) / 对方 \(remoteText)"
    }
}
