//
//  AWCCModelLibraryView.swift
//  AlienMAC
//
//  AWCC 机型库：把 Windows 版 AWCC 自带的 31 个机型资源（灯区表、能力开关、官方调色板、
//  自带默认主题）在 App 里列出来，方便对照与后续逐机型上机验证。
//

import SwiftUI

struct AWCCModelLibraryView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String?
    @State private var showProtocols = false

    private var models: [AWCCModelInfo] { AWCCCatalogStore.shared.models }

    /// 顶部一行极简统计：31 个机型里到底几个能点
    private var supportSummary: String {
        let counts = AWCCControlSupport.allCases.map { support in
            (support, models.filter { $0.controlSupport == support }.count)
        }
        let parts = counts.filter { $0.1 > 0 }.map { "\($0.0.shortTitle) \($0.1)" }
        return "· " + parts.joined(separator: " / ")
    }

    private func supportColor(_ support: AWCCControlSupport) -> Color {
        switch support {
        case .verifiedControl:        return .green
        case .sameProtocolUnverified: return .cyan
        case .needsOtherProtocol:     return .orange
        case .noUserChannel:          return .gray
        case .unknown:                return .pink
        }
    }

    private var selected: AWCCModelInfo? {
        if let selectedID, let model = AWCCCatalogStore.shared.model(id: selectedID) { return model }
        return models.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("机型库").font(.system(size: 17.5 * AppTheme.fontScale, weight: .semibold))
                Text("AWCC 机型资源 · \(models.count) 个")
                    .font(.system(size: 13 * AppTheme.fontScale))
                    .foregroundStyle(.secondary)
                Text(supportSummary)
                    .font(.system(size: 12.5 * AppTheme.fontScale))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("协议族") { showProtocols = true }
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            HStack(alignment: .top, spacing: 16) {
                modelList
                if let selected {
                    detail(selected)
                }
            }

            HStack(spacing: 6) {
                Text("下发协议：写会话 02 08 01 → 颜色帧 → 02 08 01 → 02 04 00 → 02 09 00 → 02 05 00")
                Text(AWCCDeviceInit.shared.isEmpty ? "· 就绪序列未附带" : "· 就绪序列 \(AWCCDeviceInit.shared.count) 帧")
                    .foregroundStyle(AWCCDeviceInit.shared.isEmpty ? Color.orange : Color.secondary)
            }
            .font(.system(size: 12 * AppTheme.fontScale))
            .foregroundStyle(.secondary)

            Text("链号即 AWCC 的 ZoneID、掩码即 1 << LedID；17 R4 的 11 条与实抓报文逐条一致，其余机型按同一规则从官方资源推导，按「同协议 / 他协议 / 无通道」分级标注，不冒充可控制。")
                .font(.system(size: 12.5 * AppTheme.fontScale))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 1000, height: 660)
        .sheet(isPresented: $showProtocols) {
            FXProtocolReferenceView()
        }
    }

    // MARK: - 机型列表

    private var modelList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(models) { model in
                    Button {
                        selectedID = model.id
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(supportColor(model.controlSupport))
                                .frame(width: 6, height: 6)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(model.name)
                                    .font(.system(size: 13 * AppTheme.fontScale, weight: .medium))
                                Text("\(model.addressableZoneCount) 灯 · \(model.protocolVersion.title) · \(model.controlSupport.shortTitle)")
                                    .font(.system(size: 11 * AppTheme.fontScale))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selected?.id == model.id ? Color.cyan.opacity(0.18) : Color.white.opacity(0.04))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 250)
    }

    // MARK: - 机型详情

    private func detail(_ model: AWCCModelInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.name).font(.system(size: 16 * AppTheme.fontScale, weight: .semibold))
                    Text(model.controlSupport.shortTitle)
                        .font(.system(size: 11.5 * AppTheme.fontScale, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(supportColor(model.controlSupport).opacity(0.18)))
                        .foregroundStyle(supportColor(model.controlSupport))
                    if model.verified {
                        Text("灯表逐盏核对")
                            .font(.system(size: 11.5 * AppTheme.fontScale, weight: .medium))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.green.opacity(0.14)))
                            .foregroundStyle(Color.green)
                    }
                    Text(model.protocolVersion.title)
                        .font(.system(size: 11.5 * AppTheme.fontScale, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.cyan.opacity(0.14)))
                        .foregroundStyle(Color.cyan)
                }

                Text(model.controlReason)
                    .font(.system(size: 12.5 * AppTheme.fontScale))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    chip("灯区 \(model.addressableZoneCount)")
                    chip("组 \(model.groups.count)")
                    if let tempo = model.capabilities.tempo.max {
                        chip("节奏 \(model.capabilities.tempo.min ?? 0)–\(tempo) ms")
                    }
                    if let minB = model.capabilities.brightness.min, let maxB = model.capabilities.brightness.max {
                        chip("亮度 \(minB)–\(maxB)")
                    }
                    if model.capabilities.goDark == true {
                        chip("GoDark \(model.capabilities.goDarkShortcut ?? "")")
                    }
                    if model.capabilities.keypad == true { chip("数字键盘") }
                }

                zoneTable(model)

                VStack(alignment: .leading, spacing: 6) {
                    Text("官方调色板（\(model.palette.count) 色）")
                        .font(.system(size: 13.5 * AppTheme.fontScale, weight: .semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 22), spacing: 6)], spacing: 6) {
                        ForEach(model.palette) { entry in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(ATHThemeImporter.color(from: entry.argb).swiftUIColor)
                                .frame(height: 18)
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.12)))
                                .help(entry.name.isEmpty ? entry.argb : "\(entry.name) · \(entry.argb)")
                        }
                    }
                }

                if !model.defaultTheme.actions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("自带默认主题「\(model.defaultTheme.name ?? "—")」 · \(model.defaultTheme.actions.count) 条动作")
                            .font(.system(size: 13.5 * AppTheme.fontScale, weight: .semibold))
                        Text("在 17 R4 上应用这一套可以走预设面板里的“AWCC 自带主题”那一栏。")
                            .font(.system(size: 12 * AppTheme.fontScale))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.trailing, 4)
        }
    }

    private func zoneTable(_ model: AWCCModelInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                cell("区域", width: 42, header: true)
                cell("灯区", width: 120, header: true)
                cell("chain", width: 50, header: true)
                cell("掩码", width: 90, header: true)
                cell("官方组名", width: 160, header: true)
                Spacer()
            }
            .padding(.vertical, 5)

            ForEach(model.zoneRows) { row in
                HStack(spacing: 0) {
                    cell("\(row.zoneID)", width: 42)
                    cell(row.name, width: 120)
                    cell(row.groupHex, width: 50, mono: true)
                    cell(row.maskHex, width: 90, mono: true)
                    cell(row.officialName, width: 160)
                    if row.zoneID == 1 {
                        Text("电源壳 · 只看电源状态")
                            .font(.system(size: 11 * AppTheme.fontScale))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: 150, alignment: .leading)
                    }
                    Spacer()
                }
                .padding(.vertical, 3)
                Divider().opacity(0.15)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
    }

    private func cell(_ text: String, width: CGFloat, header: Bool = false, mono: Bool = false) -> some View {
        Text(text)
            .font(.system(size: (header ? 11.5 : 12) * AppTheme.fontScale,
                          weight: header ? .semibold : .regular,
                          design: mono ? .monospaced : .default))
            .foregroundStyle(header ? Color.secondary : Color.primary)
            .frame(width: width, alignment: .leading)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5 * AppTheme.fontScale))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}

// MARK: - 协议族参考表

/// 把 v2～v8 与 ACPI 的报文格式、传输、命令表并排列出来。
/// 目的是让「他协议」不再是一句结论：新机型连上时先按包长认出是哪一代，再决定接哪套命令。
struct FXProtocolReferenceView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var mockRun: FXMockRunResult?

    private var protocols: [FXProtocol] { FXProtocol.allCases.filter { $0 != .unknown } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("AlienFX 协议族").font(.system(size: 17.5 * AppTheme.fontScale, weight: .semibold))
                Text("按包长识别 · v3 实机核对 · v4/v8 已过 Mock · 其余为公开实现的命令表")
                    .font(.system(size: 12.5 * AppTheme.fontScale))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(protocols) { proto in
                        card(proto)
                    }
                    Text("识别规则：VID 0x187C 按包长 9/12/34/65 分 v2/v3/v4/v6；VID 0x0D62 为 v5；65 字节再按 VID 分 v6(0x0424)/v7(0x0461)/v8(0x04F2)。命令表来自 alienfx-linux 的 AlienFX_SDK，字段语义按原注释整理；v4/v8 的组包已在 Mock 设备上跑通（逐帧回读一致、零违规），尚未接真机。")
                        .font(.system(size: 12 * AppTheme.fontScale))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .frame(width: 940, height: 640)
        .sheet(item: $mockRun) { run in
            FXMockRunView(result: run)
        }
    }

    private func verifyColor(_ v: FXProtocol.Verification) -> Color {
        switch v {
        case .verified:     return .green
        case .mockVerified: return .cyan
        case .tableOnly:    return .orange
        case .noPath:       return .gray
        }
    }

    /// 只有已经能组包的协议才给试跑入口
    private func mockFamily(_ proto: FXProtocol) -> FXMockFamily? {
        switch proto {
        case .v4: return .v4
        case .v8: return .v8
        default:  return nil
        }
    }

    private func card(_ proto: FXProtocol) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(proto.title).font(.system(size: 14.5 * AppTheme.fontScale, weight: .semibold))
                Text("\(proto.packetLength) 字节 · Report ID \(proto.reportIDText)")
                    .font(.system(size: 11.5 * AppTheme.fontScale))
                    .foregroundStyle(.secondary)
                Text(proto.verification.rawValue)
                    .font(.system(size: 11 * AppTheme.fontScale, weight: .medium))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(verifyColor(proto.verification).opacity(0.16)))
                    .foregroundStyle(verifyColor(proto.verification))
                if let family = mockFamily(proto) {
                    Button {
                        mockRun = FXMockScenario.run(family: family)
                    } label: {
                        Label("Mock 试跑", systemImage: "play.circle")
                            .font(.system(size: 11 * AppTheme.fontScale, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.cyan)
                }
                Spacer()
            }

            Text("\(proto.scope) · \(proto.transport)")
                .font(.system(size: 12 * AppTheme.fontScale))
                .foregroundStyle(.secondary)

            if proto.commands.isEmpty {
                Text("没有可用命令").font(.system(size: 12 * AppTheme.fontScale)).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(proto.commands) { cmd in
                        HStack(alignment: .top, spacing: 10) {
                            Text(cmd.name)
                                .font(.system(size: 11.5 * AppTheme.fontScale, weight: .medium))
                                .frame(width: 88, alignment: .leading)
                            Text(cmd.bytes)
                                .font(.system(size: 11.5 * AppTheme.fontScale, design: .monospaced))
                                .frame(width: 300, alignment: .leading)
                            Text(cmd.note)
                                .font(.system(size: 11.5 * AppTheme.fontScale))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 3)
                        Divider().opacity(0.12)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
    }
}
