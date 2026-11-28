//
//  FXKeyboardZoneRule.swift
//  AlienMAC
//
//  键盘四盏灯的列划分规则。分界线固定落在主键区的列边界上，
//  不依赖 3D/UI 类型，便于单测；视图层再把段位映射成 LightZone。
//

import CoreGraphics

enum FXKeyboardZoneRule {
    /// 左段 / 中左段分界（主键区第 5 列，坐标与 3D 场景一致）
    static let leftSplit: CGFloat = -7.2
    /// 中左段 / 中右段分界（主键区第 10 列）
    static let middleSplit: CGFloat = 1.8

    enum Segment: Int {
        case left
        case middleLeft
        case middleRight
    }

    /// 按键帽横向占位（左右沿）判断归属：跨界的键整体归入中心所在的一侧
    static func segment(left: CGFloat, right: CGFloat) -> Segment {
        let center = (left + right) / 2
        if center < leftSplit { return .left }
        if center < middleSplit { return .middleLeft }
        return .middleRight
    }
}
