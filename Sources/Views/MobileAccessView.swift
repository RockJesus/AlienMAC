//
//  MobileAccessView.swift
//  AlienMAC
//
//  手机访问弹窗：二维码 + 局域网地址，扫码即开，不用手输 IP
//

import SwiftUI
import AppKit

struct MobileAccessView: View {

    @ObservedObject var bridge = WebBridge.shared
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 0.2, green: 0.9, blue: 1),
                                                             Color(red: 0.8, green: 0.3, blue: 1)],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                VStack(alignment: .leading, spacing: 2) {
                    Text("手机访问")
                        .font(.system(size: 17, weight: .semibold))
                    Text("同一 Wi-Fi 下扫码即开，不用装 App、不用输 IP")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                statusPill
            }

            HStack(alignment: .top, spacing: 18) {
                qrBox

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("访问域名").font(.system(size: 12)).foregroundColor(.secondary)
                        Text(bridge.address.isEmpty ? "正在启动服务…" : bridge.address)
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(LinearGradient(colors: [Color(red: 0.3, green: 0.95, blue: 1),
                                                                      Color(red: 0.75, green: 0.5, blue: 1)],
                                                           startPoint: .leading, endPoint: .trailing))
                        Text(bridge.ipAddress.isEmpty ? "" : "备用直连 \(bridge.ipAddress)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }

                    HStack(spacing: 8) {
                        smallButton(copied ? "已复制" : "复制", icon: copied ? "checkmark" : "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(bridge.address, forType: .string)
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                        }
                        smallButton("打开网页", icon: "safari") {
                            if let url = URL(string: bridge.address) { NSWorkspace.shared.open(url) }
                        }
                        smallButton("IP", icon: "network") {
                            if let url = URL(string: bridge.ipAddress) { NSWorkspace.shared.open(url) }
                        }
                    }

                    Text(bridge.clientCount > 0 ? "已连接 \(bridge.clientCount) 台设备，改动实时双向同步" :
                            "等待手机扫码连接 · 页面里的机身建模与 app 实时同步")
                        .font(.system(size: 12))
                        .foregroundColor(bridge.clientCount > 0 ? Color(red: 0.2, green: 0.95, blue: 0.6) : .secondary)

                    Text("提示：手机和这台 Mac 要连同一个路由器。alien.mac / alien.local 已通过 mDNS 广播，若路由器 DNS 里也把 alien.mac 指到这台机器则更稳；实在解析不了就用上面的备用 IP。")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button("完成") { MobileAccessWindow.shared.close() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(
            ZStack {
                Color.black.opacity(0.92)
                RadialGradient(colors: [Color(red: 0.05, green: 0.16, blue: 0.30).opacity(0.9), .clear],
                               center: .topLeading, startRadius: 10, endRadius: 520)
            }
        )
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(bridge.isRunning ? Color(red: 0.2, green: 0.95, blue: 0.6) : Color.orange)
                .frame(width: 7, height: 7)
                .shadow(color: bridge.isRunning ? .green : .orange, radius: 4)
            Text(bridge.isRunning ? "服务已开启" : "启动中…")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var qrBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .frame(width: 208, height: 208)
            // 二维码编码「备用直连」IP：域名解析受路由器组播策略影响，IP 一定可用
            if let image = WebBridge.qrImage(bridge.ipAddress.isEmpty ? bridge.address : bridge.ipAddress, size: 188),
               bridge.isRunning {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 188, height: 188)
            } else {
                ProgressView()
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.cyan.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: Color.cyan.opacity(0.25), radius: 16)
    }

    private func smallButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12, weight: .medium))
                Text(title).font(.system(size: 12.5, weight: .medium))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}


/// 独立浮动窗口：点按钮弹出，不遮挡也不阻塞主界面
final class MobileAccessWindow: NSWindowController {

    static let shared = MobileAccessWindow()

    private convenience init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 466),
                            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
                            backing: .buffered,
                            defer: false)
        panel.title = "手机访问"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.backgroundColor = .black
        panel.contentView = NSHostingView(rootView: MobileAccessView())
        panel.setContentSize(NSSize(width: 540, height: 466))
        // 贴右侧摆放，不压住中间的 3D 机身
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: visible.maxX - 556, y: visible.maxY - 40))
        }
        self.init(window: panel)
    }

    func show() {
        guard let window = window else { return }
        if !window.isVisible, let screen = NSScreen.main {
            let visible = screen.visibleFrame
            window.setFrameTopLeftPoint(NSPoint(x: visible.maxX - 556, y: visible.maxY - 40))
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
