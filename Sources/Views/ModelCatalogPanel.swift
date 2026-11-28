//
//  ModelCatalogPanel.swift
//  AlienMAC
//  v2.7.5：机型库面板。29 款具名机型的灯区表 + 逐键 LED 索引，按 VID:PID 反查本机型号。
//

import SwiftUI

struct ModelCatalogPanel: View {
    @ObservedObject private var catalog = ModelCatalog.shared
    @ObservedObject private var monitor = PeripheralMonitor.shared
    @Environment(\.dismiss) private var dismiss

    @State private var keyword = ""
    @State private var selectedName: String?
    @State private var selectedKeyIDs: Set<Int> = []
    @State private var toast: String?

    private var rows: [ModelEntry] { catalog.search(keyword) }

    private var selected: ModelEntry? {
        if let n = selectedName, rows.contains(where: { $0.name == n }), let m = catalog.model(named: n) {
            return m
        }
        return rows.first
    }

    /// 本机正在连接的 Alienware/Dell 设备（优先取设备库里的整机控制器）
    private var localDevice: PeripheralDevice? {
        monitor.devices.first { $0.vendorID == 0x187C || $0.vendorID == 0x0D62 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            localCoverageLine
            Divider().opacity(0.25)
            HStack(alignment: .top, spacing: 0) {
                list
                Divider().opacity(0.25)
                detail
            }
            Divider().opacity(0.25)
            footer
        }
        .frame(width: 840, height: 640)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.98))
        .onAppear {
            if selectedName == nil {
                if let d = localDevice, let hit = catalog.models(vid: UInt32(d.vendorID), pid: UInt32(d.productID)).first {
                    selectedName = hit.name
                } else {
                    selectedName = rows.first?.name
                }
            }
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 8) {
            Text("机型库")
                .font(.system(size: 17.5 * AppTheme.fontScale, weight: .semibold))
            Text(verbatim: "\(catalog.modelCount) 机型 / \(catalog.zoneTotal) 灯区 / \(catalog.keyTotal) 逐键 LED")
                .font(.system(size: 11 * AppTheme.fontScale, design: .monospaced))
                .foregroundColor(.cyan)
            Spacer()
            if let m = selected {
                Button("导出 JSON") { exportJSON(m) }
                Button("复制灯区表") { copyTSV(m) }
            }
            Button("导入对照") { importAliases() }
            Button("对照模板") { exportAliasTemplate() }
            Button("关闭") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 6)
        .overlay(alignment: .bottomLeading) { EmptyView() }
    }

    private var localCoverageLine: some View {
        Group {
            if let d = localDevice {
                let hit = catalog.models(vid: UInt32(d.vendorID), pid: UInt32(d.productID))
                HStack(spacing: 6) {
                    Image(systemName: hit.isEmpty ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .font(.system(size: 9.5 * AppTheme.fontScale))
                    Text(catalog.coverageNote(vid: UInt32(d.vendorID), pid: UInt32(d.productID)))
                        .font(.system(size: 10 * AppTheme.fontScale))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .foregroundColor(hit.isEmpty ? .orange : .green)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    // MARK: - 左侧列表

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11 * AppTheme.fontScale))
                    .foregroundColor(.secondary)
                TextField("搜机型 / VID:PID / 协议", text: $keyword)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12 * AppTheme.fontScale))
                if !keyword.isEmpty {
                    Button {
                        keyword = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10 * AppTheme.fontScale))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(rows) { m in
                        rowView(m)
                    }
                    if rows.isEmpty {
                        Text("没有匹配的机型")
                            .font(.system(size: 11 * AppTheme.fontScale))
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .frame(width: 320)
    }

    private func rowView(_ m: ModelEntry) -> some View {
        let isSelected = (selected?.name == m.name)
        let isLocal = localDevice.map { d in
            catalog.models(vid: UInt32(d.vendorID), pid: UInt32(d.productID)).contains { $0.name == m.name }
        } ?? false
        return Button {
            selectedName = m.name
            selectedKeyIDs = []
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(m.name)
                        .font(.system(size: 12 * AppTheme.fontScale, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if isLocal {
                        Text("本机")
                            .font(.system(size: 9 * AppTheme.fontScale))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.green.opacity(0.18)))
                            .foregroundColor(.green)
                    }
                    Spacer(minLength: 0)
                    if m.hasPerKey {
                        Text("逐键")
                            .font(.system(size: 9 * AppTheme.fontScale))
                            .foregroundColor(.orange)
                    }
                }
                Text(verbatim: "\(m.controllersText) · \(m.zoneCount) 区 · \(m.summaryLedTotal) LED")
                    .font(.system(size: 9.5 * AppTheme.fontScale, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.cyan.opacity(0.16) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 右侧详情

    @ViewBuilder
    private var detail: some View {
        if let m = selected {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(m.name)
                        .font(.system(size: 15 * AppTheme.fontScale, weight: .semibold))
                    Text("类型码 \(m.typeCode)")
                        .font(.system(size: 9.5 * AppTheme.fontScale, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                HStack(spacing: 6) {
                    ForEach(m.controllers) { c in
                        Text("\(c.key) \(c.name)")
                            .font(.system(size: 9.5 * AppTheme.fontScale, design: .monospaced))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.07)))
                            .foregroundColor(.cyan)
                    }
                }

                HStack(spacing: 8) {
                    let isExternal = m.protocolRule?.category == "外部对照"
                    protocolChip("Tron", m.protocolRule?.tron, external: isExternal)
                    protocolChip("键盘", m.protocolRule?.keyboard, external: isExternal)
                    protocolChip("风扇", m.protocolRule?.fan, external: isExternal)
                    if let p = m.protocolRule, p.source != nil {
                        Text("12 表行：\(p.source ?? "")")
                            .font(.system(size: 9 * AppTheme.fontScale))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                if let basis = m.protocolRule?.basis {
                    Text("协议对照依据：\(basis)")
                        .font(.system(size: 9 * AppTheme.fontScale))
                        .foregroundColor(.secondary.opacity(0.85))
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    Text(verbatim: "灯区 \(m.zoneCount) 条 · \(m.zoneLedTotal) LED")
                        .font(.system(size: 10.5 * AppTheme.fontScale))
                        .foregroundColor(.secondary)
                    if m.hasPerKey {
                        Text(verbatim: "逐键 \(m.perKeyCount) 键 · 占用 \(m.keyLedTotal) LED")
                            .font(.system(size: 10.5 * AppTheme.fontScale))
                            .foregroundColor(.orange)
                    }
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(m.zones, id: \.self) { z in
                            HStack(spacing: 8) {
                                Text(String(format: "%03d", z.index))
                                    .font(.system(size: 9.5 * AppTheme.fontScale, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 28, alignment: .trailing)
                                Text(z.name)
                                    .font(.system(size: 11 * AppTheme.fontScale))
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(verbatim: "\(z.leds) LED")
                                    .font(.system(size: 9.5 * AppTheme.fontScale, design: .monospaced))
                                    .foregroundColor(z.leds > 0 ? .secondary : .secondary.opacity(0.5))
                                Text(z.controller)
                                    .font(.system(size: 8.5 * AppTheme.fontScale))
                                    .foregroundColor(.secondary.opacity(0.7))
                                    .lineLimit(1)
                                    .frame(width: 120, alignment: .trailing)
                            }
                            .padding(.vertical, 1)
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                if m.hasPerKey {
                    perKeySection(m)
                } else {
                    Text("这款机型在 v3 表里只有灯区级 LED 数，没有逐键 LED 索引 —— 不画假的键位，等下一版数据。")
                        .font(.system(size: 10 * AppTheme.fontScale))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 12)
        } else {
            Text("选一款机型")
                .font(.system(size: 12 * AppTheme.fontScale))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func protocolChip(_ title: String, _ value: String?, external: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 9 * AppTheme.fontScale))
                .foregroundColor(.secondary)
            Text(value?.isEmpty == false ? value! : "—")
                .font(.system(size: 9.5 * AppTheme.fontScale, design: .monospaced))
                .foregroundColor(value?.isEmpty == false ? (external ? .orange : .green) : .secondary)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.05)))
    }

    // MARK: - 逐键 LED

    private func perKeySection(_ m: ModelEntry) -> some View {
        let picked = m.keys.filter { selectedKeyIDs.contains($0.id) }
        let used = Set(picked.flatMap { $0.leds })
        let focused = picked.count == 1 ? picked.first : nil
        let ceiling = max(m.ledIndexCeiling, 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("逐键 LED 索引")
                    .font(.system(size: 10.5 * AppTheme.fontScale, weight: .medium))
                if let c = focused {
                    Text("\(c.name) → \(c.leds.map(String.init).joined(separator: ","))")
                        .font(.system(size: 9.5 * AppTheme.fontScale, design: .monospaced))
                        .foregroundColor(.orange)
                } else if picked.isEmpty {
                    Text("点键名开始选（可多选）")
                        .font(.system(size: 9.5 * AppTheme.fontScale))
                        .foregroundColor(.secondary)
                } else {
                    Text(verbatim: "已选 \(picked.count) 键 · \(used.count) 颗 LED")
                        .font(.system(size: 9.5 * AppTheme.fontScale, design: .monospaced))
                        .foregroundColor(.orange)
                }
                Spacer()
                if !picked.isEmpty {
                    Button("导出选区") { exportSelection(m) }
                        .buttonStyle(.borderless)
                }
            }
            Text(m.ledAudit.summary)
                .font(.system(size: 9.5 * AppTheme.fontScale, design: .monospaced))
                .foregroundColor(.secondary)

            if !picked.isEmpty {
                let preview = ModelExport.selectFramePreview(indices: Array(used))
                HStack(spacing: 6) {
                    Text(verbatim: preview.frames.isEmpty
                         ? "试排帧：无"
                         : "试排选灯帧 \(preview.frames.count) 帧 · 未验证")
                        .font(.system(size: 9.5 * AppTheme.fontScale))
                        .foregroundColor(.yellow)
                        .help(preview.note)
                        .fixedSize()
                    if let f = preview.frames.first {
                        Text(f.hex)
                            .font(.system(size: 8.5 * AppTheme.fontScale, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                    Button("复制帧") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(preview.frames.map { $0.hex }.joined(separator: "\n"), forType: .string)
                        flash("已复制 \(preview.frames.count) 帧 hex")
                    }
                    .buttonStyle(.borderless)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(m.keys) { k in
                        Button {
                            if selectedKeyIDs.contains(k.id) { selectedKeyIDs.remove(k.id) } else { selectedKeyIDs.insert(k.id) }
                        } label: {
                            Text(k.name)
                                .font(.system(size: 9 * AppTheme.fontScale))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(selectedKeyIDs.contains(k.id) ? Color.orange.opacity(0.22) : Color.white.opacity(0.06)))
                                .foregroundColor(selectedKeyIDs.contains(k.id) ? .orange : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 26)

            // LED 索引条：每格一颗 LED，被当前键占用的格亮起
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(0...ceiling, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(used.contains(i) ? Color.orange : Color.white.opacity(0.09))
                            .frame(width: 4, height: used.contains(i) ? 14 : 8)
                            .overlay(alignment: .bottom) {
                                if i % 10 == 0 {
                                    Text("\(i)")
                                        .font(.system(size: 7.5, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .fixedSize()
                                        .offset(y: 9)
                                }
                            }
                    }
                }
                .frame(height: 24, alignment: .top)
                .padding(.bottom, 12)
            }
            .frame(height: 42)
        }
    }

    // MARK: - 导出

    private func exportJSON(_ m: ModelEntry) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ModelExport.fileName(for: m)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try ModelExport.jsonData(m)
            try data.write(to: url)
            flash("已导出 \(m.name)")
        } catch {
            flash("导出失败：\(error.localizedDescription)")
        }
    }

    private func exportSelection(_ m: ModelEntry) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ModelExport.keySelectionFileName(for: m)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try ModelExport.keySelection(m, keyIDs: selectedKeyIDs, generatedAt: catalog.generatedAt)
            try data.write(to: url)
            flash("已导出 \(selectedKeyIDs.count) 键的 LED 索引")
        } catch {
            flash("导出失败：\(error.localizedDescription)")
        }
    }

    private func exportAliasTemplate() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "AlienMAC-对照模板.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try ModelExport.aliasTemplate(unmatched: catalog.unmatchedProtocols)
            try data.write(to: url)
            flash("模板已导出（\(catalog.unmatchedProtocols.count) 行待填）")
        } catch {
            flash("导出失败：\(error.localizedDescription)")
        }
    }

    private func importAliases() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["json"]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ExternalAliasFile.self, from: data),
              file.schema == "alienmac.aliases/1" else {
            flash("读不了：只认 alienmac.aliases/1")
            return
        }
        let applied = catalog.applyExternalAliases(file.aliases)
        flash(applied > 0 ? "外部对照补上 \(applied) 款（未验证）" : "没有可补的机型（已内置的不覆盖）")
    }

    private func copyTSV(_ m: ModelEntry) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(ModelExport.tsv(m), forType: .string)
        flash("灯区表已复制（\(m.zoneCount) 行）")
    }

    private func flash(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if toast == text { toast = nil }
        }
    }

    // MARK: - 底栏

    private var footer: some View {
        HStack(spacing: 8) {
            Text("数据源：AWCC 设备库 v3（\(catalog.generatedAt)）· 社区实测，非 Dell 官方；灯区与 LED 索引原表直录")
                .font(.system(size: 9.5 * AppTheme.fontScale))
                .foregroundColor(.secondary)
                .lineLimit(2)
            Spacer()
            if let t = toast {
                Text(t)
                    .font(.system(size: 9.5 * AppTheme.fontScale))
                    .foregroundColor(.green)
                    .lineLimit(1)
            }
            if !catalog.source.isEmpty {
                Text(verbatim: "\(catalog.perKeyModelCount) 款带逐键 · 协议 \(catalog.builtInProtocolCount)/\(catalog.withProtocolCount + catalog.unmatchedProtocols.count)"
                     + (catalog.externalAliases.isEmpty ? "" : " · 外部对照 \(catalog.externalAliases.count) 条（未验证）"))
                    .font(.system(size: 9 * AppTheme.fontScale, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }
}
