//
//  ZoneGridView.swift
//  AlienMAC
//
//  灯区选择网格，可视化展示 Alienware 17 R4 各灯区位置
//

import SwiftUI

/// 灯区网格视图
struct ZoneGridView: View {
    @ObservedObject var viewModel: LightingViewModel

    var body: some View {
        VStack(spacing: 12) {
            // 顶部操作栏
            HStack {
                Text("灯区选择")
                    .font(.headline)
                Spacer()
                Button("全选") { viewModel.toggleSelectAll() }
                    .buttonStyle(.bordered)
                Button("键盘") { viewModel.selectKeyboard() }
                    .buttonStyle(.bordered)
            }

            // 笔记本俯视示意图
            laptopTopView

            // 灯区列表
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LightZone.allIndividual) { zone in
                        ZoneChip(
                            zone: zone,
                            isSelected: viewModel.selectedZones.contains(zone),
                            currentColor: viewModel.zoneColors[zone] ?? .black
                        ) {
                            viewModel.toggleZone(zone)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - 笔记本俯视示意图

    private var laptopTopView: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // 笔记本外壳
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: w * 0.9, height: h * 0.85)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                    )

                // 屏幕区域
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.8))
                    .frame(width: w * 0.8, height: h * 0.45)
                    .offset(y: -h * 0.15)

                // 屏幕下方 Logo
                ZoneDot(
                    zone: .screenLogo,
                    size: CGSize(width: 30, height: 10),
                    viewModel: viewModel
                )
                .offset(x: 0, y: -h * 0.38)

                // 顶盖外星人头像（在屏幕上方表示）
                ZoneDot(
                    zone: .alienHead,
                    size: CGSize(width: 16, height: 16),
                    viewModel: viewModel
                )
                .offset(x: 0, y: -h * 0.46)

                // 键盘区域
                VStack(spacing: 3) {
                    // 快捷键 + 键盘左中右 + 数字键盘
                    HStack(spacing: 3) {
                        ZoneDot(zone: .macroKeys, size: CGSize(width: w*0.08, height: h*0.12), viewModel: viewModel)
                        ZoneDot(zone: .keyboardLeft, size: CGSize(width: w*0.16, height: h*0.12), viewModel: viewModel)
                        ZoneDot(zone: .keyboardMid, size: CGSize(width: w*0.16, height: h*0.12), viewModel: viewModel)
                        ZoneDot(zone: .keyboardRight, size: CGSize(width: w*0.16, height: h*0.12), viewModel: viewModel)
                        ZoneDot(zone: .numpad, size: CGSize(width: w*0.11, height: h*0.12), viewModel: viewModel)
                    }
                    // 触摸板
                    ZoneDot(zone: .touchpad, size: CGSize(width: w*0.25, height: h*0.08), viewModel: viewModel)
                }
                .offset(y: h * 0.12)

                // 电源按钮（屏幕logo下方居中）
                ZoneDot(
                    zone: .powerButton,
                    size: CGSize(width: 14, height: 14),
                    viewModel: viewModel
                )
                .offset(x: 0, y: -h * 0.28)

                // 前部灯带
                HStack(spacing: 4) {
                    ZoneDot(zone: .frontLeft, size: CGSize(width: w*0.2, height: 6), viewModel: viewModel)
                    ZoneDot(zone: .frontRight, size: CGSize(width: w*0.2, height: 6), viewModel: viewModel)
                }
                .offset(y: h * 0.38)

                // 后部灯带
                HStack(spacing: 4) {
                    ZoneDot(zone: .rearLeft, size: CGSize(width: w*0.2, height: 6), viewModel: viewModel)
                    ZoneDot(zone: .rearRight, size: CGSize(width: w*0.2, height: 6), viewModel: viewModel)
                }
                .offset(y: -h * 0.42)
            }
        }
        .frame(height: 220)
    }
}

// MARK: - 灯区圆点/方块组件

/// 可点击的灯区指示块
struct ZoneDot: View {
    let zone: LightZone
    let size: CGSize
    @ObservedObject var viewModel: LightingViewModel

    var body: some View {
        let isSelected = viewModel.selectedZones.contains(zone)
        let color = viewModel.zoneColors[zone] ?? .black

        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: size.width, height: size.height)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isSelected ? Color.white : Color.gray.opacity(0.4),
                            lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: color.opacity(0.6), radius: isSelected ? 6 : 2)
            .onTapGesture {
                viewModel.toggleZone(zone)
            }
            .help(zone.displayName)
    }
}

// MARK: - 灯区标签芯片

/// 灯区选择标签
struct ZoneChip: View {
    let zone: LightZone
    let isSelected: Bool
    let currentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(currentColor)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.gray.opacity(0.5), lineWidth: 1))
                Text(zone.displayName)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
