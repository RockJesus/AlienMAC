//
//  AppTheme.swift
//  AlienMAC
//
//  全局 UI 尺寸：字号统一按 fontScale 放大，布局宽度同步放大，
//  改一处即可整体调大/调小界面。
//

import Foundation
import CoreGraphics

enum AppTheme {
    /// 字号缩放（1.0 = 原始）。当前整体放大约 15%
    static let fontScale: CGFloat = 1.15

    /// 右侧控制面板宽度
    static let panelWidth: CGFloat = 330

    /// 3D 区域右侧留白（面板宽度 + 间距）
    static let sceneInset: CGFloat = 362

    /// 主窗口建议尺寸
    static let defaultWindowWidth: CGFloat = 1180
    static let defaultWindowHeight: CGFloat = 820
}
