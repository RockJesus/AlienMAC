//
//  PeripheralDebugPanel.swift
//  AlienMAC
//
//  调试台：全量 HID 扫描 + 本机自检（读 Feature、发只读 query、收回应），
//  不需要 Windows 抓包，也不用装 AWCC。
//

import SwiftUI

struct PeripheralDebugPanel: View {
    @ObservedObject private var probe = PeripheralProbe.shared
    @ObservedObject private var store = PeripheralOverridesStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var sheetNote = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("调试台")
                    .font(.system(size: 17.5 * AppTheme.fontScale, weight: .semibold))
                Text("\(probe.interfaces.count) 个接口 · \(probe.reports.count) 份报告")
                    .font(.system(size: 11 * AppTheme.fontScale, design: .monospaced))
                    .foregroundColor(.cyan)
                Spacer()
                Button {
                    probe.scan()
                } label: {
                    Label("扫描全部 HID", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 11.5 * AppTheme.fontScale))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Text("自检只读：读一次 Feature 报表，鼠标族再发一条只读的「读按键状态」query（04 5A 17 00 A5），不会改灯效或配置。")
                .font(.system(size: 11 * AppTheme.fontScale))
                .foregroundColor(Color.secondary.opacity(0.6))
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

            Divider().opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if probe.interfaces.isEmpty {
                        Text("还没有扫描结果。点右上「扫描全部 HID」列出本机所有带报表的接口。")
                            .font(.system(size: 12 * AppTheme.fontScale))
                            .foregroundColor(Color.secondary.opacity(0.65))
                            .padding(.vertical, 10)
                    } else {
                        ForEach(probe.interfaces) { device in
                            row(device)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }

            Divider().opacity(0.4)

            logSection
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
        }
        .frame(width: 660, height: 620)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.98))
        .onAppear {
            if probe.interfaces.isEmpty { probe.scan() }
        }
    }

    private func row(_ device: PeripheralDevice) -> some View {
        let cap = probe.capability(for: device)
        let raw = cap.map { PeripheralProbeRules.family(usagePage: $0.usagePage, usage: $0.usage, maxOutput: $0.maxOut, maxFeature: $0.maxFeature, vid: device.vendorID) } ?? .none
        // 本接口形状判不出时，退回设备库/用户档案里登记的族，避免把整机接口写成「无灯效」
        let inCatalog = PeripheralCatalog.shared.device(vid: device.vendorID, pid: device.productID) != nil
        let alienwareVID = [0x187C, 0x413C, 0x04CA, 0x0461, 0x04F2, 0x0D62, 0x0424].contains(device.vendorID)
        let guess: PeripheralFamily = (raw == .none && (inCatalog || alienwareVID))
            ? PeripheralCatalog.shared.family(for: device) : raw
        let report = probe.reports.first { $0.id == String(format: "%04X:%04X-%02X%02X", device.vendorID, device.productID, device.usagePage, device.usage) }

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Text(String(format: "%04X:%04X", device.vendorID, device.productID))
                    .font(.system(size: 10.5 * AppTheme.fontScale, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 74, alignment: .leading)
                Text(device.product.isEmpty ? "未命名接口" : device.product)
                    .font(.system(size: 12 * AppTheme.fontScale, weight: .medium))
                    .lineLimit(1)
                Text(guess == .none ? "未识别" : guess.title)
                    .font(.system(size: 10 * AppTheme.fontScale))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background((guess.canSend ? Color.cyan : Color.white).opacity(guess.canSend ? 0.16 : 0.08), in: Capsule())
                    .foregroundColor(guess.canSend ? .cyan : .secondary)
                Spacer(minLength: 0)
                if let report {
                    Text(report.verdict.rawValue)
                        .font(.system(size: 10 * AppTheme.fontScale))
                        .foregroundColor(tone(report.verdict))
                }
                Button("自检") { runProbe(device) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11 * AppTheme.fontScale))
                    .foregroundColor(.cyan)
                if let report, report.verdict == .replied || report.verdict == .written {
                    Button(store.override(vid: device.vendorID, pid: device.productID) == nil ? "存为档案" : "已存档案") {
                        save(report, device: device)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5 * AppTheme.fontScale))
                    .foregroundColor(store.override(vid: device.vendorID, pid: device.productID) == nil ? .orange : .secondary)
                }
            }
            Text(capText(cap, device))
                .font(.system(size: 10.5 * AppTheme.fontScale, design: .monospaced))
                .foregroundColor(Color.secondary.opacity(0.65))
            if let report {
                if !report.featureHex.isEmpty {
                    Text("FEATURE ← \(report.featureHex)")
                        .font(.system(size: 10 * AppTheme.fontScale, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if !report.responseHex.isEmpty {
                    Text("RX ← \(report.responseHex)")
                        .font(.system(size: 10 * AppTheme.fontScale, design: .monospaced))
                        .foregroundColor(.green.opacity(0.85))
                        .lineLimit(1)
                }
                Text(report.detail)
                    .font(.system(size: 10.5 * AppTheme.fontScale))
                    .foregroundColor(Color.secondary.opacity(0.7))
            }
        }
        .padding(9)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("现场日志")
                    .font(.system(size: 12 * AppTheme.fontScale, weight: .medium))
                Text("\(probe.log.count) 条")
                    .font(.system(size: 10 * AppTheme.fontScale))
                    .foregroundColor(.secondary)
                Spacer()
                Button("导出档案") {
                    if let url = store.export() {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                        sheetNote = "已导出 \(url.lastPathComponent)"
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5 * AppTheme.fontScale))
                .foregroundColor(.cyan)
                Button("导入档案") {
                    importOverrides()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5 * AppTheme.fontScale))
                .foregroundColor(.cyan)
                Button("清空") { probe.clearLog() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5 * AppTheme.fontScale))
                    .foregroundColor(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(probe.log.suffix(14).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 10 * AppTheme.fontScale, design: .monospaced))
                            .foregroundColor(Color.secondary.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(height: 96)
            .padding(8)
            .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            if !sheetNote.isEmpty {
                Text(sheetNote)
                    .font(.system(size: 10 * AppTheme.fontScale))
                    .foregroundColor(.green.opacity(0.8))
            }
        }
    }

    private func capText(_ cap: PeripheralProbe.Capability?, _ device: PeripheralDevice) -> String {
        guard let cap else { return "usage \(device.usageText) · 输入 \(device.maxInputReportSize)B" }
        return String(format: "usage %02X/%02X · out %dB · feature %dB · in %dB · %@",
                      cap.usagePage, cap.usage, cap.maxOut, cap.maxFeature, cap.maxInput, cap.transport)
    }

    private func tone(_ v: ProbeVerdict) -> Color {
        switch v {
        case .replied: return .green
        case .written: return .orange
        default:       return .secondary
        }
    }

    private func runProbe(_ device: PeripheralDevice) {
        let report = probe.probe(device)
        sheetNote = "\(device.product)：\(report.verdict.rawValue) · \(report.elapsedMS)ms"
    }

    private func save(_ report: ProbeReport, device: PeripheralDevice) {
        let scale: Int
        switch report.familyGuess {
        case .keyboardV8: scale = 10
        case .keyboardV5: scale = 255
        case .none:       scale = 100
        default:          scale = 100
        }
        let payload: Int = report.maxOutput > 0 ? min(report.maxOutput, 64) : 64
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd"
        let item = PeripheralOverride(
            vid: report.vid, pid: report.pid,
            name: device.product,
            family: report.familyGuess,
            reportID: 0, payload: payload, brightnessScale: scale,
            verified: report.verdict == .replied,
            note: report.detail,
            updatedAt: stamp.string(from: Date()))
        store.upsert(item)
        sheetNote = "已存档案 \(item.id) · \(item.family.title)"
    }

    private func importOverrides() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            let added = store.importFile(url)
            sheetNote = "导入 \(added) 台新设备档案"
        }
    }
}
