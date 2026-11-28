//
//  PeripheralCatalogPanel.swift
//  AlienMAC
//
//  设备库面板：225 条 AWCC 授权设备 / 11 款元数据 / 343 条官方灯区
//

import SwiftUI

struct PeripheralCatalogPanel: View {
    @ObservedObject private var catalog = PeripheralCatalog.shared
    @Environment(\.dismiss) private var dismiss

    @State private var keyword: String = ""
    @State private var category: String = "全部"

    private var categories: [String] {
        var list = ["全部", "有元数据"]
        for c in Set(catalog.devices.map { $0.category }).sorted() where !list.contains(c) {
            list.append(c)
        }
        return list
    }

    private var rows: [CatalogDevice] {
        var list = catalog.search(keyword)
        if category == "有元数据" {
            list = list.filter { catalog.models[$0.model] != nil }
        } else if category != "全部" {
            list = list.filter { $0.category == category }
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("设备库")
                    .font(.system(size: 17.5 * AppTheme.fontScale, weight: .semibold))
                Text("\(catalog.devices.count) 授权 / \(catalog.modelCount) 元数据 / \(catalog.ledCount) 灯区")
                    .font(.system(size: 11 * AppTheme.fontScale, design: .monospaced))
                    .foregroundColor(.cyan)
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 10)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11 * AppTheme.fontScale))
                    .foregroundColor(.secondary)
                TextField("搜型号 / 类别 / VID:PID", text: $keyword)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12 * AppTheme.fontScale))
                Picker("", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: 150)
                Text("\(rows.count) 条")
                    .font(.system(size: 11 * AppTheme.fontScale))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)

            Divider().opacity(0.4)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(rows) { row in
                        rowView(row)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }

            Divider().opacity(0.4)
            Text("数据源：AWCC 5.2.42 反解设备库。鼠标族 0x5A 已硬件验证可直接下发；键盘 v8、显示器 v6 目前只做识别与灯区展示。标「6.x 待补」的型号只有名称与 VID/PID，灯区与按键元数据在 AWCC 6.x 安装包内，尚未提取。")
                .font(.system(size: 10.5 * AppTheme.fontScale))
                .foregroundColor(Color.secondary.opacity(0.55))
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
        }
        .frame(width: 620, height: 560)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.98))
        .onAppear {
            if ProcessInfo.processInfo.environment["ALIENMAC_CATALOG_MOUSE"] == "1" {
                keyword = "鼠标"
            }
        }
    }

    /// AWCC 6.x 安装包独占的外设型号（5.2.42 只有 VID/PID，没有灯区与按键元数据）
    private static let awcc6OnlyModels = ["AW420K", "AW920K", "AW320M", "AW620M", "AW720M"]

    private static func needsAWCC6Metadata(_ row: CatalogDevice) -> Bool {
        let text = (row.model + " " + row.codeName + " " + row.category).uppercased()
        if awcc6OnlyModels.contains(where: { text.contains($0) }) { return true }
        return row.category.contains("鼠标") || row.category.contains("键盘")
    }

    private func rowView(_ row: CatalogDevice) -> some View {
        let profile = catalog.models[row.model]
        return HStack(spacing: 8) {
            Text(row.id)
                .font(.system(size: 10.5 * AppTheme.fontScale, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 74, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.model)
                    .font(.system(size: 12 * AppTheme.fontScale, weight: profile != nil ? .semibold : .regular))
                    .lineLimit(1)
                Text(profile != nil
                     ? "\(profile!.leds.count) 灯区 · \(profile!.keys.count) 按键 · 档位 \(profile!.profileSlots)"
                     : row.category)
                    .font(.system(size: 10.5 * AppTheme.fontScale))
                    .foregroundColor(Color.secondary.opacity(0.65))
            }
            Spacer(minLength: 0)
            Text(row.family.title)
                .font(.system(size: 10 * AppTheme.fontScale))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background((row.family.canSend ? Color.cyan : Color.white).opacity(row.family.canSend ? 0.16 : 0.08), in: Capsule())
                .foregroundColor(row.family.canSend ? .cyan : .secondary)
            if profile == nil && Self.needsAWCC6Metadata(row) {
                Text("6.x 待补")
                    .font(.system(size: 9.5 * AppTheme.fontScale))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
                    .foregroundColor(.secondary)
                    .help("这条只在 AWCC 5.2.42 授权表里，灯区/按键元数据要从 6.x 安装包提取，暂缺")
            }
            if profile != nil {
                Text("元数据")
                    .font(.system(size: 9.5 * AppTheme.fontScale))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.orange.opacity(0.16), in: Capsule())
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(profile != nil ? 0.07 : 0.03), in: RoundedRectangle(cornerRadius: 6))
    }
}
