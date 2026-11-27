//
//  FXMockRunView.swift
//  AlienMAC
//
//  没有真机的协议试跑面板：左边逐帧报文，右边 Mock 设备回读出来的灯态。
//  用一致性（App 想设的色 == 设备解出来的色）和零违规来替代实机验证。
//

import SwiftUI

struct FXMockRunView: View {

    let result: FXMockRunResult

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(alignment: .top, spacing: 14) {
                transcript
                deviceState
            }
                .frame(maxHeight: .infinity)

            footer
        }
        .padding(20)
        .frame(width: 980, height: 640)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(result.family.title.uppercased()) Mock 试跑")
                .font(.system(size: 17.5 * AppTheme.fontScale, weight: .semibold))
            Label(result.passed ? "结构与回读一致" : "有 \(result.violations.count) 处违规",
                  systemImage: result.passed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12 * AppTheme.fontScale, weight: .medium))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill((result.passed ? Color.green : Color.red).opacity(0.16)))
                .foregroundStyle(result.passed ? .green : .red)
            Text("\(result.packets.count) 帧 · 无 HID 通道")
                .font(.system(size: 12 * AppTheme.fontScale))
                .foregroundStyle(.secondary)
            Spacer()
            Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }

    // MARK: - 报文

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("下发报文")
                .font(.system(size: 13 * AppTheme.fontScale, weight: .semibold))

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(result.packets.enumerated()), id: \.element.id) { index, packet in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(String(format: "%02d", index + 1))
                                    .font(.system(size: 11 * AppTheme.fontScale, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(packet.transport.rawValue)
                                    .font(.system(size: 10.5 * AppTheme.fontScale, weight: .medium))
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Capsule().fill(Color.cyan.opacity(0.14)))
                                    .foregroundStyle(.cyan)
                                Text(packet.note)
                                    .font(.system(size: 11.5 * AppTheme.fontScale))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(packet.payload.count) B")
                                    .font(.system(size: 10.5 * AppTheme.fontScale, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Text(packet.hex)
                                .font(.system(size: 11 * AppTheme.fontScale, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.82))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.04)))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 设备回读

    private var deviceState: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mock 设备回读")
                    .font(.system(size: 13 * AppTheme.fontScale, weight: .semibold))
                Spacer()
                Text("亮度 \(result.brightness)%")
                    .font(.system(size: 12 * AppTheme.fontScale, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(result.lights, id: \.id) { light in
                    HStack(spacing: 10) {
                        Text("灯 \(String(format: "%02X", light.id))")
                            .font(.system(size: 11.5 * AppTheme.fontScale, design: .monospaced))
                            .frame(width: 46, alignment: .leading)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(swiftUIColor(light.color))
                            .frame(width: 26, height: 14)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.12), lineWidth: 0.8))
                        Text(light.color.hex)
                            .font(.system(size: 11.5 * AppTheme.fontScale, design: .monospaced))
                        Text(light.effect.title)
                            .font(.system(size: 11 * AppTheme.fontScale))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 5)
                    Divider().opacity(0.12)
                }
            }

            if !result.violations.isEmpty {
                Text("违规")
                    .font(.system(size: 12 * AppTheme.fontScale, weight: .semibold))
                    .foregroundStyle(.red)
                ForEach(result.violations, id: \.self) { v in
                    Text(v)
                        .font(.system(size: 11 * AppTheme.fontScale, design: .monospaced))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
        .frame(width: 330, alignment: .leading)
    }

    // MARK: - 说明

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("试跑口径")
                .font(.system(size: 12 * AppTheme.fontScale, weight: .semibold))
            ForEach(result.notes, id: \.self) { note in
                Text("· \(note)")
                    .font(.system(size: 11.5 * AppTheme.fontScale))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Mock 只验证“帧带得出、设备解得回、结构不违规”，不能替代真机：真实设备是否认这套包，仍需对应机型接上后抓包核对。")
                .font(.system(size: 11.5 * AppTheme.fontScale))
                .foregroundStyle(.orange.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func swiftUIColor(_ c: FXRGBA) -> Color {
        Color(red: Double(c.r) / 255.0, green: Double(c.g) / 255.0, blue: Double(c.b) / 255.0)
    }
}
