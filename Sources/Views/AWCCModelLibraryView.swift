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

    private var models: [AWCCModelInfo] { AWCCCatalogStore.shared.models }

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
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            HStack(alignment: .top, spacing: 16) {
                modelList
                if let selected {
                    detail(selected)
                }
            }

            Text("只有 17 R4 的灯区表经过真机逐盏核对；其余机型的区域号/组号/掩码来自官方资源文件，标「未验证」，仅作对照，不参与颜色下发。")
                .font(.system(size: 12.5 * AppTheme.fontScale))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 860, height: 640)
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
                                .fill(model.verified ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(model.name)
                                    .font(.system(size: 13 * AppTheme.fontScale, weight: .medium))
                                Text("\(model.addressableZoneCount) 灯 · \(model.id)")
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
                    Text(model.verified ? "已上机验证" : "未验证")
                        .font(.system(size: 11.5 * AppTheme.fontScale, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill((model.verified ? Color.green : Color.orange).opacity(0.18)))
                        .foregroundStyle(model.verified ? Color.green : Color.orange)
                }

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
                cell("组号", width: 50, header: true)
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
