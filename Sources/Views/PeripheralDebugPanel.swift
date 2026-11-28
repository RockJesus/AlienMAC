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
    @ObservedObject private var viewModel = LightingViewModel.shared
    @ObservedObject private var archiveStore = ProbeArchiveStore.shared
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
                    probe.toggleAutoMonitor()
                } label: {
                    HStack(spacing: 4) {
                        Circle().fill(probe.isAutoMonitor ? Color.green : Color.secondary).frame(width: 6, height: 6)
                        Text(probe.isAutoMonitor ? "插拔自动重扫" : "自动重扫已关")
                            .font(.system(size: 10.5 * AppTheme.fontScale))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(probe.isAutoMonitor ? .green : .secondary)
                .help("开启后接入或拔掉设备会自动重新扫描，不用手点")
                Button {
                    probe.scan()
                } label: {
                    Label("扫描全部 HID", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 11.5 * AppTheme.fontScale))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                Button {
                    exportProbeArchive()
                } label: {
                    Text("提针导出")
                        .font(.system(size: 11 * AppTheme.fontScale))
                }
                .buttonStyle(.plain)
                .foregroundColor(.orange)
                .help("把这台机器的自检结论导成 .json，别人可以导入比对")
                Button {
                    importProbeArchive()
                } label: {
                    Text("提针导入")
                        .font(.system(size: 11 * AppTheme.fontScale))
                }
                .buttonStyle(.plain)
                .foregroundColor(.orange)
                .help("导入别人导出的自检档案，按同一 VID/PID 比对结论")
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
            probe.startAutoMonitor()
            if probe.interfaces.isEmpty { probe.scan() }
            importFromEnvironmentIfNeeded()
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
                if let o = store.override(vid: device.vendorID, pid: device.productID) {
                    Text(o.verified ? "档案命中·已验证" : "档案命中")
                        .font(.system(size: 9.5 * AppTheme.fontScale))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background((o.verified ? Color.green : Color.orange).opacity(0.16), in: Capsule())
                        .foregroundColor(o.verified ? .green : .orange)
                        .help("本机档案已登记这台设备，协议族按档案走")
                }
                Spacer(minLength: 0)
                if let report {
                    Text(report.verdict.rawValue)
                        .font(.system(size: 10 * AppTheme.fontScale))
                        .foregroundColor(tone(report.verdict))
                }
                Button("导出帧") { exportFrames(device, family: guess) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11 * AppTheme.fontScale))
                    .foregroundColor(.secondary)
                Button("诊断") { exportDiagnostic(device, family: guess) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11 * AppTheme.fontScale))
                    .foregroundColor(.secondary)
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
            updatedAt: stamp.string(from: Date()),
            zones: viewModel.selectedZones.map { Int($0.rawValue) },
            effect: viewModel.currentEffect.code,
            colorHex: hexString(viewModel.currentColor))
        store.upsert(item)
        let zoneNote = item.zones.map { "\($0.count) 灯区" } ?? "0 灯区"
        sheetNote = "已存档案 \(item.id) · \(item.family.title) · \(zoneNote)"
    }

    private func exportFrames(_ device: PeripheralDevice, family: PeripheralFamily) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = String(format: "%@-%04X%04X-参考帧.txt",
                                            device.product.isEmpty ? "外设" : device.product,
                                            device.vendorID, device.productID)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = PeripheralFrameExport.text(deviceName: device.product, vid: device.vendorID,
                                              pid: device.productID, family: family)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            sheetNote = "已导出参考帧 \(url.lastPathComponent)"
        } catch {
            sheetNote = "导出失败：\(error.localizedDescription)"
        }
    }

    private func exportDiagnostic(_ device: PeripheralDevice, family: PeripheralFamily) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = String(format: "AlienMAC-诊断-%@-%04X%04X.txt",
                                            device.product.isEmpty ? "外设" : device.product,
                                            device.vendorID, device.productID)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HH:mm"
        let report = probe.reports.first {
            $0.id == String(format: "%04X:%04X-%02X%02X", device.vendorID, device.productID, device.usagePage, device.usage)
        }
        let cap = probe.capability(for: device)
        let capText: String = cap.map {
            String(format: "usage %02X/%02X · out %dB · feature %dB · in %dB · %@",
                   $0.usagePage, $0.usage, $0.maxOut, $0.maxFeature, $0.maxInput, $0.transport)
        } ?? "usage \(device.usageText) · 输入 \(device.maxInputReportSize)B"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let frames = PeripheralFrameExport.frames(family: family)
        let text = PeripheralDiagnosticReport.text(deviceName: device.product, vid: device.vendorID,
                                                   pid: device.productID, family: family, capability: capText,
                                                   report: report, frames: frames,
                                                   appVersion: version, date: stamp.string(from: Date()))
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            sheetNote = "已导出诊断 \(url.lastPathComponent)"
        } catch {
            sheetNote = "导出失败：\(error.localizedDescription)"
        }
    }

    /// 接口形状判不出族时，退回设备库登记，别把整机写成「无灯效」
    private func familyGuess(for device: PeripheralDevice) -> PeripheralFamily {
        if let report = probe.reports.first(where: {
            $0.id == String(format: "%04X:%04X-%02X%02X", device.vendorID, device.productID,
                            device.usagePage, device.usage)
        }), report.familyGuess != .none { return report.familyGuess }
        let cap = probe.capability(for: device)
        let raw = PeripheralProbeRules.family(usagePage: cap?.usagePage ?? 0, usage: cap?.usage ?? 0,
                                              maxOutput: cap?.maxOut ?? 0, maxFeature: cap?.maxFeature ?? 0,
                                              vid: device.vendorID)
        if raw != .none { return raw }
        let inCatalog = PeripheralCatalog.shared.device(vid: device.vendorID, pid: device.productID) != nil
        let alienwareVID = [0x187C, 0x413C, 0x04CA, 0x0461, 0x04F2, 0x0D62, 0x0424].contains(device.vendorID)
        return (inCatalog || alienwareVID) ? PeripheralCatalog.shared.family(for: device) : raw
    }

    /// SwiftUI Color 转 "#RRGGBB"，转不出来就留空（不编颜色）
    private func hexString(_ color: Color) -> String? {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private func exportProbeArchive() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "AlienMAC-提针-" + DateFormatter.localizedString(
            from: Date(), dateStyle: .short, timeStyle: .none)
            .replacingOccurrences(of: "/", with: "-") + ".json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HH:mm"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        var items: [ProbeArchive] = []
        for device in probe.interfaces {
            let cap = probe.capability(for: device)
            let capText: String = cap.map {
                String(format: "usage %02X/%02X · out %dB · feature %dB · in %dB · %@",
                       $0.usagePage, $0.usage, $0.maxOut, $0.maxFeature, $0.maxInput, $0.transport)
            } ?? "usage \(device.usageText) · 输入 \(device.maxInputReportSize)B"
            let report = probe.reports.first {
                $0.id == String(format: "%04X:%04X-%02X%02X", device.vendorID, device.productID,
                                device.usagePage, device.usage)
            }
            items.append(ProbeArchive(appVersion: version, generatedAt: stamp.string(from: Date()),
                                      deviceName: device.product, vid: device.vendorID,
                                      pid: device.productID,
                                      family: familyGuess(for: device),
                                      capability: capText, report: report))
        }
        let file = ProbeArchiveFile(schema: ProbeArchive.schemaVersion, items: items)
        guard let data = try? JSONEncoder.pretty.encode(file) else { return }
        do {
            try data.write(to: url)
            sheetNote = "已导出 \(items.count) 台设备的提针档案"
        } catch {
            sheetNote = "导出失败：\(error.localizedDescription)"
        }
    }

    private func importProbeArchive() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importArchive(url)
    }

    /// 导入一份提针档案并立刻和本机自检记录比对
    private func importArchive(_ url: URL) {
        let result = archiveStore.importFile(url)
        // 比对优先选设备库里的外星人设备，苹果自带键鼠只是顺带扫到的
        let preferred = probe.interfaces.first { device in
            PeripheralCatalog.shared.device(vid: device.vendorID, pid: device.productID) != nil
                || [0x187C, 0x413C, 0x04CA, 0x0461, 0x04F2, 0x0D62, 0x0424].contains(device.vendorID)
        } ?? probe.interfaces.first
        let remote = preferred.flatMap { archiveStore.firstMatch($0.vendorID, $0.productID) }
        let compare = remote.map { archiveStore.compare($0) } ?? ""
        sheetNote = "导入 \(result.added) 台 / 更新 \(result.updated) 台"
        if !compare.isEmpty { pushNote(compare) }
    }

    private func importFromEnvironmentIfNeeded() {
        guard let path = ProcessInfo.processInfo.environment["ALIENMAC_PROBE_IMPORT"], !path.isEmpty else { return }
        importArchive(URL(fileURLWithPath: path))
    }

    private func pushNote(_ text: String) {
        probe.appendLog("提针对比：\(text)")
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
