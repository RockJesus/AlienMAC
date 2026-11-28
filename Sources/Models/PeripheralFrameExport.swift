//
//  PeripheralFrameExport.swift
//  AlienMAC
//
//  把「这个型号该发什么帧」导出成可读文本：给没有 Windows 抓包条件的用户做对照，
//  也方便把数据贴进 issue。帧全部来自 App 内置编码器，不代表该型号已硬件验证。
//

import Foundation

/// 一帧参考数据
struct PeripheralExportFrame: Equatable {
    var name: String
    var reportType: String       // Output / Feature
    var reportID: Int
    var bytes: [UInt8]
    var note: String = ""

    var hex: String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

enum PeripheralFrameExport {

    /// 鼠标 0x5A、键盘 v8、整机 v4 有内置编码器；其余族不猜帧，返回空并给说明
    static func frames(family: PeripheralFamily,
                       color: (r: Int, g: Int, b: Int) = (0, 200, 255),
                       brightnessPercent: Int = 100) -> [PeripheralExportFrame] {
        switch family {
        case .mouse5A:
            return [
                PeripheralExportFrame(name: "单色常亮", reportType: "Output", reportID: 0,
                                      bytes: FXMouseCodec.singleColor(r: color.r, g: color.g, b: color.b,
                                                                      brightness: brightnessPercent),
                                      note: "64 字节载荷，首字节是长度，末字节 0xA5，其余补 0"),
                PeripheralExportFrame(name: "恢复默认", reportType: "Output", reportID: 0,
                                      bytes: FXMouseCodec.resetDefault(),
                                      note: "对应说明书 Reset 命令，可把灯效恢复出厂"),
                PeripheralExportFrame(name: "读按键状态（只读）", reportType: "Output", reportID: 0,
                                      bytes: FXMouseCodec.buttonState(),
                                      note: "自检用的只读 query，不改配置")
            ]
        case .keyboardV8:
            return [
                PeripheralExportFrame(name: "握手 READY", reportType: "Feature", reportID: Int(FXv8Codec.reportID),
                                      bytes: FXv8Codec.ready(),
                                      note: "首字节即 Report ID 0x01，chain 0x51 = 主键盘"),
                PeripheralExportFrame(name: "亮度", reportType: "Feature", reportID: Int(FXv8Codec.reportID),
                                      bytes: FXv8Codec.brightness(FXv8Codec.brightnessPercent(brightnessPercent)),
                                      note: "外置键盘亮度 0–0x0A，不是 0–100"),
                PeripheralExportFrame(name: "单块颜色包", reportType: "Feature", reportID: Int(FXv8Codec.reportID),
                                      bytes: FXv8Codec.colorPacket(seq: 0, blocks: [
                                        FXv8Codec.LightBlock(id: 0x01, effect: 0x01, tempo: 0x00, duration: 0x00,
                                                             color: FXRGBA(r: UInt8(color.r), g: UInt8(color.g), b: UInt8(color.b)),
                                                             color2: FXRGBA(r: UInt8(color.r), g: UInt8(color.g), b: UInt8(color.b)))
                                      ]) ?? [],
                                      note: "一包四块，块内 13 字节，块间 2 字节空位")
            ]
        case .chassisV4:
            let ids: [UInt8] = [0x01]
            var list: [PeripheralExportFrame] = []
            if let select = FXv4Codec.selectLights(loop: false, ids: ids) {
                list.append(PeripheralExportFrame(name: "选灯（第 1 颗）", reportType: "Output", reportID: 0,
                                                  bytes: FXv4Codec.pad(select) ?? select,
                                                  note: "03 23 <loop> <count> <LightID…>；LightID 是序号不是位掩码"))
            }
            if let color = FXv4Codec.oneColor(FXRGBA(r: UInt8(color.r), g: UInt8(color.g), b: UInt8(color.b)), ids: ids) {
                list.append(PeripheralExportFrame(name: "单色快写", reportType: "Output", reportID: 0,
                                                  bytes: FXv4Codec.pad(color) ?? color,
                                                  note: "03 27 命令只在 alien-tools 的字段注释里出现，未实机验证"))
            }
            if let dim = FXv4Codec.dim(FXv4Codec.dimming(forPercent: brightnessPercent), ids: ids) {
                list.append(PeripheralExportFrame(name: "亮度（整组压暗）", reportType: "Output", reportID: 0,
                                                  bytes: FXv4Codec.pad(dim) ?? dim,
                                                  note: "03 26 的 dim 是压暗量：0 = 最亮，0x64 = 全灭；v4 没有单灯亮度"))
            }
            return list
        default:
            return []
        }
    }

    /// 导出文本：设备信息 + 说明 + 每帧一段
    static func text(deviceName: String, vid: Int, pid: Int, family: PeripheralFamily,
                     color: (r: Int, g: Int, b: Int) = (0, 200, 255),
                     brightnessPercent: Int = 100) -> String {
        var lines: [String] = []
        lines.append("AlienMAC 外设参考帧")
        lines.append("设备：\(deviceName)  \(String(format: "%04X:%04X", vid, pid))")
        lines.append("协议族：\(family.title)")
        lines.append("亮度：\(brightnessPercent)%" + (family == .keyboardV8 ? "（编码为 0–0x0A）" : ""))
        lines.append("")
        lines.append("说明：帧由 App 内置编码器按官方协议表生成，未在你的这台设备上验证；")
        lines.append("      只作对照与你反馈问题时附上的记录，不保证生效，也不含任何个人信息。")
        lines.append("")
        let list = frames(family: family, color: color, brightnessPercent: brightnessPercent)
        if list.isEmpty {
            lines.append("该协议族（\(family.title)）暂没有内置编码器，导出不了帧。")
            lines.append("可先用「调试台」的只读自检记录 Feature / RX 的十六进制，一起贴给作者核对。")
        } else {
            for (i, f) in list.enumerated() {
                lines.append("[\(i + 1)] \(f.name)")
                lines.append("    \(f.reportType) · reportID \(f.reportID) · \(f.bytes.count)B")
                lines.append("    \(f.hex)")
                if !f.note.isEmpty { lines.append("    注：\(f.note)") }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }
}
