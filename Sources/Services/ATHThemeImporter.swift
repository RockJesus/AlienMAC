//
//  ATHThemeImporter.swift
//  AlienMAC
//
//  AWCC 主题文件（.ath）导入
//
//  .ath 是 .NET DataSet 序列化出来的 XML：一份 xsd schema + 若干数据表。
//  实测（AWCC 4.8，17 R4）里真正跟灯有关的只有 Actions 表：
//
//    <Actions>
//      <ZoneID>2</ZoneID>            // AWCC 区域号，1=电源壳，2..12=十一盏灯
//      <ActionID>3</ActionID>        // 同一区域内按序号排成动作序列
//      <ActionTypeID>3</ActionTypeID>// 1=Morph(渐变) 2=Pulse(脉冲) 3=SetColor(常亮) 4=Loop 15=PlayPowerStatus
//      <Color1>#FF00F0F0</Color1>    // ARGB，两位 alpha 在前
//      <Color2>#FF000000</Color2>
//      <Duration>0</Duration>
//    </Actions>
//
//  实际表名：Theme / Actions / ZonesGroups / Zones / Groups / Leds / Visualizations …
//  （注意数据行标签是 <Theme>、<Groups>，不是「Basic Theme」「Keyboard Left」，那些是 Name 字段）
//  ZonesGroups / Zones / Leds 三张表给的是同一套区域编号的佐证
//  （ZoneID 2→Group01 依次到 ZoneID 12→Group13，跳过 9，和真机灯区表一致）。
//

import Foundation

/// 一个从 .ath 里读出来的主题
struct ATHTheme {
    /// 主题名（取自 Theme 行的 Name 字段）
    var name: String
    /// 效果速度（毫秒），取自 Basic Theme 的 ActionDuration
    var tempoMs: UInt16
    /// 区域 → 每区动作
    var actions: [LightZone: ZoneAction]
}

enum ATHThemeError: LocalizedError {
    case unreadable(String)
    case badXML
    case noActions

    var errorDescription: String? {
        switch self {
        case .unreadable(let reason): return "读不了这个文件：\(reason)"
        case .badXML:                 return "不是有效的 AWCC 主题 XML"
        case .noActions:              return "主题里没有可用的灯区配色"
        }
    }
}

enum ATHThemeImporter {

    /// AWCC 区域号 → 灯区。1 是电源壳（没有颜色通道），13..18 是各电源状态专用区
    static let zoneMap: [Int: LightZone] = [
        2: .keyboardLeft, 3: .keyboardMidLeft, 4: .keyboardMidRight, 5: .keyboardRight,
        6: .alienHead, 7: .screenLogo, 8: .touchpad,
        9: .tronLeft, 10: .tronRight, 11: .lcdPanelLeft, 12: .lcdPanelRight
    ]

    static func parse(url: URL) throws -> ATHTheme {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ATHThemeError.unreadable(error.localizedDescription)
        }
        return try parse(data: data)
    }

    static func parse(data: Data) throws -> ATHTheme {
        let delegate = ThemeXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw ATHThemeError.badXML
        }
        let theme = delegate.makeTheme()
        guard !theme.actions.isEmpty else { throw ATHThemeError.noActions }
        return theme
    }

    /// "#FF00F0F0" → RGBColor(0, 240, 240)；也兼容 "#RRGGBB"
    static func color(from hex: String) -> RGBColor {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 8 { text = String(text.suffix(6)) }   // 丢掉 alpha
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return .off }
        return RGBColor(
            r: UInt8((value >> 16) & 0xFF),
            g: UInt8((value >> 8) & 0xFF),
            b: UInt8(value & 0xFF)
        )
    }

    /// ActionTypeID → 我们的效果标识
    static func effectCode(forActionType type: Int) -> String? {
        switch type {
        case 1:  return "morph"
        case 2:  return "pulse"
        case 3:  return "color"
        default: return nil   // 4=Loop、15=PlayPowerStatus 都不是配色
        }
    }
}

// MARK: - XML 解析

private final class ThemeXMLDelegate: NSObject, XMLParserDelegate {

    private var stack: [String] = []
    private var buffer = ""
    private var row: [String: String] = [:]

    private var themeName = ""
    private var tempoMs: UInt16 = 2000
    /// Actions 表按出现顺序保存
    private var actionRows: [[String: String]] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        stack.append(elementName)
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        defer {
            if !stack.isEmpty { stack.removeLast() }
            buffer = ""
        }

        let depth = stack.count
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)

        // ThemeDataset > 行 > 字段
        if depth == 3 {
            row[elementName] = text
            return
        }
        guard depth == 2 else { return }

        // 一行结束，按表名收走
        switch elementName {
        case "Actions":
            actionRows.append(row)
        case "Theme":
            themeName = row["Name"] ?? ""
            if let duration = Double(row["ActionDuration"] ?? ""), duration > 0 {
                tempoMs = UInt16(min(10_000, max(300, duration * 1000)))
            }
        default:
            break
        }
        row.removeAll()
    }

    func makeTheme() -> ATHTheme {
        // 按 ZoneID 归组，保持 ActionID 顺序
        var byZone: [Int: [(id: Int, type: Int, c1: String, c2: String)]] = [:]
        for item in actionRows {
            guard let zoneText = item["ZoneID"], let zoneID = Int(zoneText),
                  let typeText = item["ActionTypeID"], let type = Int(typeText) else { continue }
            let actionID = Int(item["ActionID"] ?? "") ?? 0
            byZone[zoneID, default: []].append(
                (id: actionID, type: type,
                 c1: item["Color1"] ?? "#FF000000",
                 c2: item["Color2"] ?? "#FF000000")
            )
        }

        var actions: [LightZone: ZoneAction] = [:]
        for (zoneID, entries) in byZone {
            guard let zone = ATHThemeImporter.zoneMap[zoneID] else { continue }
            let ordered = entries.sorted { $0.id < $1.id }
            guard let first = ordered.first(where: { ATHThemeImporter.effectCode(forActionType: $0.type) != nil }),
                  let code = ATHThemeImporter.effectCode(forActionType: first.type) else { continue }

            actions[zone] = ZoneAction(
                zone: zone,
                primary: ATHThemeImporter.color(from: first.c1),
                secondary: ATHThemeImporter.color(from: first.c2),
                effectCode: code,
                tempo: tempoMs,
                durationMs: 0,
                loop: true
            )
        }

        let resolvedName = themeName.isEmpty ? "AWCC 主题" : themeName
        return ATHTheme(name: resolvedName, tempoMs: tempoMs, actions: actions)
    }
}
