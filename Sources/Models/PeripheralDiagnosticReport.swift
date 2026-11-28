//
//  PeripheralDiagnosticReport.swift
//  AlienMAC
//
//  一份可以直接贴给作者的诊断文本：接口能力 + 自检结论 + 回读十六进制 + 参考帧。
//  不含任何路径、用户名、序列号等个人信息。
//

import Foundation

enum PeripheralDiagnosticReport {

    static func text(deviceName: String,
                     vid: Int, pid: Int,
                     family: PeripheralFamily,
                     capability: String,
                     report: ProbeReport?,
                     frames: [PeripheralExportFrame],
                     appVersion: String,
                     date: String) -> String {
        var lines: [String] = []
        lines.append("AlienMAC 外设诊断")
        lines.append("App 版本：\(appVersion)    生成：\(date)")
        lines.append("设备：\(deviceName)  \(String(format: "%04X:%04X", vid, pid))")
        lines.append("协议族：\(family.title)")
        lines.append("接口：\(capability)")
        lines.append("")

        if let r = report {
            lines.append("## 自检结论")
            lines.append("结论：\(r.verdict.rawValue)")
            lines.append("耗时：\(r.elapsedMS)ms    out \(r.maxOutput)B / feature \(r.maxFeature)B")
            lines.append("说明：\(r.detail)")
            lines.append("FEATURE ← \(r.featureHex.isEmpty ? "（无数据）" : r.featureHex)")
            lines.append("RX ← \(r.responseHex.isEmpty ? "（无回应）" : r.responseHex)")
        } else {
            lines.append("## 自检结论")
            lines.append("这台设备还没有做过自检。先在调试台点一次「自检」再导出，数据才完整。")
        }
        lines.append("")

        lines.append("## 参考帧（App 内置编码器按官方协议表生成，未在你的设备上验证）")
        if frames.isEmpty {
            lines.append("该协议族暂没有内置编码器，不猜帧。")
        } else {
            for (i, f) in frames.enumerated() {
                lines.append("[\(i + 1)] \(f.name) · \(f.reportType) · reportID \(f.reportID) · \(f.bytes.count)B")
                lines.append("    \(f.hex)")
                if !f.note.isEmpty { lines.append("    注：\(f.note)") }
            }
        }
        lines.append("")
        lines.append("## 说明")
        lines.append("本文件只包含接口编号、十六进制收发与帧数据，不含用户名、路径、序列号。")
        lines.append("贴到 issue 时请补一句「插上这台设备时灯效表现如何」，方便对照判断是哪一步没生效。")
        return lines.joined(separator: "\n")
    }
}
