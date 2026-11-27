//
//  FXProtocolCatalog.swift
//  AlienMAC
//
//  AlienFX 全协议族参考表：把 v2～v8 与 ACPI 通道的报文格式、传输方式和命令码
//  统一收在一处，供机型库对照，也给后续接新机型留出落点。
//
//  证据来源：
//  - APIv3（12 字节）本机 Alienware 17 R4 实抓报文逐条核对，颜色/提交/亮度顺序已在
//    `AWCC-LightFX-帧节奏分析.md` 里对齐。
//  - v4 / v5 / v6 / v7 / v8 的命令表来自开源实现 alienfx-linux（AlienFX_SDK 的
//    `alienfx_control.h`，按 max packet size 与 VID 区分版本），字段语义按原注释整理，
//    未在对应实机上复核过，所以每个协议都标注了自己的验证状态。
//

import Foundation

// MARK: - 单条命令

struct FXCommand: Identifiable, Hashable {
    let name: String
    /// 报文数据部分（不含 Report ID），用十六进制书写，尖括号是占位字段
    let bytes: String
    let note: String

    var id: String { name + bytes }
}

// MARK: - 协议

enum FXProtocol: String, CaseIterable, Identifiable {
    case v2, v3, v4, v5, v6, v7, v8, acpi, unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .v2:      return "APIv2"
        case .v3:      return "APIv3"
        case .v4:      return "APIv4"
        case .v5:      return "APIv5"
        case .v6:      return "APIv6"
        case .v7:      return "APIv7"
        case .v8:      return "APIv8"
        case .acpi:    return "ACPI"
        case .unknown: return "未知"
        }
    }

    /// 单包长度（含 Report ID，Windows 口径；v4 不带 Report ID，为 33 字节载荷）
    var packetLength: Int {
        switch self {
        case .v2:      return 9
        case .v3:      return 12
        case .v4:      return 33
        case .v5:      return 64
        case .v6, .v7, .v8: return 65
        case .acpi:    return 128
        case .unknown: return 0
        }
    }

    /// Report ID（v4 起部分设备不带 Report ID）
    var reportIDText: String {
        switch self {
        case .v2, .v3:  return "0x02"
        case .v4, .v6, .v7: return "无"
        case .v5:       return "0xCC"
        case .v8:       return "0x01"
        case .acpi:     return "—"
        case .unknown:  return "—"
        }
    }

    /// 传输方式
    var transport: String {
        switch self {
        case .v2, .v3, .v4: return "SET_REPORT (0x21/0x09, wValue 0x0202)"
        case .v5:           return "SET_FEATURE"
        case .v6:           return "WRITE"
        case .v7:           return "WRITE + READ 回包"
        case .v8:           return "SET_FEATURE 后再 WRITE"
        case .acpi:         return "ACPI/WMI，macOS 用户态无通道"
        case .unknown:      return "—"
        }
    }

    /// 适用设备
    var scope: String {
        switch self {
        case .v2:      return "2011–2014 老机型（M11x/M14x/M17x/M18x 一代）"
        case .v3:      return "2015–2017 笔记本（13 R3 / 15 R3 / 17 R4）"
        case .v4:      return "Tron 与台式线（台式 Aurora、笔记本 m15/m17 一代、51m）"
        case .v5:      return "Darfon 方案的 RGB 键盘笔记本"
        case .v6:      return "显示器（Microchip 方案）"
        case .v7:      return "鼠标（Primax 方案）"
        case .v8:      return "外置键盘（Chicony 方案）"
        case .acpi:    return "台式/一体机中控灯"
        case .unknown: return "未识别"
        }
    }

    enum Verification: String {
        case verified = "已实机核对"
        case mockVerified = "Mock 已验"
        case tableOnly = "命令表已解，未上机"
        case noPath = "无 macOS 通道"

        var color: String {
            switch self {
            case .verified:      return "green"
            case .mockVerified:  return "cyan"
            case .tableOnly:     return "orange"
            case .noPath:        return "gray"
            }
        }
    }

    var verification: Verification {
        switch self {
        case .v3:      return .verified
        case .v4, .v8: return .mockVerified
        case .v2, .v5, .v6, .v7: return .tableOnly
        case .acpi, .unknown: return .noPath
        }
    }

    // MARK: 命令表

    var commands: [FXCommand] {
        switch self {
        case .v2:
            return [
                FXCommand(name: "复位", bytes: "07 04", note: "清空当前会话，设备回到待命"),
                FXCommand(name: "状态查询", bytes: "06 00", note: "设备不回包，只作时序占位"),
                FXCommand(name: "颜色", bytes: "03 ‹效果 1–3› ‹chain› ‹掩码 R/G› ‹掩码 B/R2› ‹掩码 G2/B2›",
                          note: "4-bit 色深，三字节里塞四个色阶，比 v3 省一半体积"),
                FXCommand(name: "提交", bytes: "04 00", note: "把当前帧刷到灯上"),
                FXCommand(name: "结束", bytes: "05 00", note: "关闭写会话"),
                FXCommand(name: "速度", bytes: "0E …", note: "呼吸/渐变的节奏"),
                FXCommand(name: "亮度", bytes: "1C ‹0–100› ‹01 常亮 / 00 仅电池›", note: "v2 亮度色阶上限是 0x64"),
            ]

        case .v3:
            return [
                FXCommand(name: "复位", bytes: "07 04", note: "本机实抓：每次上色前必发"),
                FXCommand(name: "状态查询", bytes: "06 00", note: "17 R4 不回包"),
                FXCommand(name: "颜色", bytes: "03 ‹效果› ‹chain› ‹掩码3› ‹R G B› ‹R2 G2 B2›",
                          note: "chain = AWCC ZoneID，掩码 = 1 << LedID"),
                FXCommand(name: "提交", bytes: "04 00", note: "AWCC 是每区颜色帧后立刻提交，实测帧间隔约 1ms"),
                FXCommand(name: "写开始", bytes: "08 01", note: "AWCC 实际不带，本 App 保留以兼容设备"),
                FXCommand(name: "存槽", bytes: "09 00", note: "测试帧要跳过这一条，否则会被顶掉"),
                FXCommand(name: "结束", bytes: "05 00", note: "会话收尾"),
                FXCommand(name: "速度/亮度前置", bytes: "0E 00 ‹亮度› ‹速度 2 字节›", note: "AWCC 在复位后、首帧前固定发一条，随后留 46ms"),
                FXCommand(name: "亮度", bytes: "1C ‹0–100› ‹01 / 00›", note: "全局亮度，硬下限随机型 MinimumBrightness"),
                FXCommand(name: "应用", bytes: "1D 03", note: "AWCC 收尾标记"),
            ]

        case .v4:
            return [
                FXCommand(name: "控制", bytes: "03 21 00 ‹类型 1–7› ‹ID 2 字节›",
                          note: "1 开始 / 2 结束并存 / 3 结束并播 / 4 移除 / 5 播放 / 6 设默认 / 7 设开机；ID 是两字节大端，0xFFFF 为通用"),
                FXCommand(name: "选灯", bytes: "03 23 ‹loop› ‹灯数 2 字节› ‹LightID…›",
                          note: "传逐颗 LightID 序号，不是 v3 的位掩码；灯数按 humanfx 记两字节（alien-tools 记一字节，代码取 humanfx）"),
                FXCommand(name: "上色", bytes: "03 24 ‹动作 0–2› ‹时长 2 字节› ‹速度 2 字节› ‹R G B›",
                          note: "动作 0 常亮 / 1 脉冲 / 2 渐变；只作用于当前选中的那几颗灯"),
                FXCommand(name: "电源块", bytes: "03 22 ‹类型›", note: "电源/指示灯专用块"),
                FXCommand(name: "亮度", bytes: "03 26 ‹压暗量 0–0x64› ‹灯数› ‹LightID…›",
                          note: "humanfx SET_DIM 是压暗量：0 最亮、0x32 半暗、0x64 全灭"),
                FXCommand(name: "单色快写", bytes: "03 27 ‹R G B› ‹灯数› ‹LightID…›", note: "一次给一组灯刷同色，humanfx 未实现单列"),
            ]

        case .v5:
            return [
                FXCommand(name: "复位", bytes: "94", note: "Darfon 键盘专用"),
                FXCommand(name: "状态", bytes: "93", note: "带回包"),
                FXCommand(name: "颜色组", bytes: "8C 02 ‹子命令 1/2/5/6/7/13›", note: "子命令决定是颜色、区域还是效果"),
                FXCommand(name: "循环/提交", bytes: "8C 13", note: "成帧后刷一次"),
                FXCommand(name: "更新", bytes: "8B 01 FF", note: "整体生效"),
                FXCommand(name: "上电", bytes: "83 38 9C", note: "开灯握手"),
                FXCommand(name: "效果", bytes: "80 02 ‹类型› ‹速度› … ‹R G B› ‹R2 G2 B2›",
                          note: "类型：0 常亮 / 2 呼吸 / 3 单色波 / 4 双色波 / 8 脉冲 / 9 混脉冲 / A 跑马灯"),
            ]

        case .v6:
            return [
                FXCommand(name: "系统复位", bytes: "95 00 00 00", note: "显示器主控"),
                FXCommand(name: "颜色组", bytes: "92 37 ‹长度› ‹子命令› … ‹校验和›",
                          note: "87 常亮 / 88 脉冲 / 8C 渐变（每帧末尾带校验和）"),
            ]

        case .v7:
            return [
                FXCommand(name: "状态", bytes: "40 03 01 00 01", note: "鼠标"),
                FXCommand(name: "控制", bytes: "40 10 0C 00 01 ‹模式› ‹亮度› ‹灯ID› ‹R G B› …",
                          note: "逐灯写，可带第二色"),
                FXCommand(name: "更新", bytes: "40 60 07 00 C0 4E 00 01", note: "最后一位 1 = 提交生效"),
            ]

        case .v8:
            return [
                FXCommand(name: "就绪", bytes: "05 01 51", note: "chain 号，FF 表示复位"),
                FXCommand(name: "准备上色", bytes: "0E 01 00 01 ‹本组灯数›", note: "声明下一批命令要写几颗灯"),
                FXCommand(name: "上色块", bytes: "0E 01 ‹包序号› ‹灯ID› ‹效果› ‹速度› ‹时长› ‹亮度› ‹R G B› ‹R2 G2 B2›",
                          note: "80 关 / 81 常亮 / 82 脉冲 / 83 渐变 / 84 默认蓝 / 87 呼吸 / 88 光谱；一包四块"),
                FXCommand(name: "亮度", bytes: "17 ‹0–A›", note: "外置键盘亮度是 0–10，不是 0–100"),
            ]

        case .acpi:
            return [
                FXCommand(name: "通道", bytes: "ACPI/WMI", note: "Windows 下由 AWCC 服务经 ACPI 下发，macOS 没有对等通道"),
            ]

        case .unknown:
            return []
        }
    }

    // MARK: 版本识别

    /// 按 max packet size + VID 推断协议，规则取自 alienfx-linux 的探测逻辑
    static func detect(packetLengthWithReportID length: Int, vendorID: Int) -> FXProtocol {
        if vendorID == 0x0D62 { return .v5 }       // Darfon 键盘
        if vendorID == 0x187C {                    // Alienware 本体
            switch length {
            case 9:  return .v2
            case 12: return .v3
            case 34: return .v4
            case 65: return .v6
            default: return .unknown
            }
        }
        if length == 65 {
            switch vendorID {
            case 0x0424: return .v6                // Microchip 显示器
            case 0x0461: return .v7                // Primax 鼠标
            case 0x04F2: return .v8                // Chicony 外置键盘
            default: break
            }
        }
        return .unknown
    }
}

// MARK: - 机型 → 协议

extension AWCCModelInfo {
    /// 该机型对应的 AlienFX 协议代际（依据 AWCC 资源年代与公开资料推断）
    var protocolVersion: FXProtocol {
        if AWCCControlTable.verified.contains(id) { return .v3 }
        if AWCCControlTable.sameProtocol.contains(id) { return .v3 }
        if AWCCControlTable.olderNotebooks.contains(id) { return .v2 }
        if AWCCControlTable.desktops.contains(id) { return .acpi }
        return .unknown
    }
}

// MARK: - 与运行时协议枚举对接

extension AlienFXProtocol {
    /// 设备识别出来的协议 → 协议族参考表条目
    var family: FXProtocol {
        switch self {
        case .apiV0:   return .acpi
        case .apiV1, .apiV2: return .v2
        case .apiV3:   return .v3
        case .apiV4:   return .v4
        case .apiV5:   return .v5
        case .apiV8:   return .v8
        case .unknown: return .unknown
        }
    }
}
