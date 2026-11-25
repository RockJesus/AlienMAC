//
//  AlienModule.swift
//  AlienMAC
//
//  AWCC 四模块外壳：AlienFX / AlienFusion / TactX / AlienAdrenaline
//

import SwiftUI

enum AlienModule: String, CaseIterable, Identifiable {
    case fx
    case fusion
    case tactx
    case adrenaline

    var id: String { rawValue }

    /// 面板顶部的短标签
    var shortTitle: String {
        switch self {
        case .fx:         return "AlienFX"
        case .fusion:     return "Fusion"
        case .tactx:      return "TactX"
        case .adrenaline: return "Adrenaline"
        }
    }

    var icon: String {
        switch self {
        case .fx:         return "lightbulb.fill"
        case .fusion:     return "bolt.fill"
        case .tactx:      return "keyboard"
        case .adrenaline: return "gamecontroller.fill"
        }
    }

    /// 模块说明（与 AWCC 的定位对齐）
    var subtitle: String {
        switch self {
        case .fx:         return "灯光"
        case .fusion:     return "电源"
        case .tactx:      return "宏键"
        case .adrenaline: return "游戏档案"
        }
    }
}
