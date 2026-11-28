//
//  MouseCyclePlan.swift
//  AlienMAC
//
//  巡回的纯逻辑：预设序列、自定义十六进制序列解析、间隔与轮次夹取。
//  全部不碰 IOKit，selfcheck 可直接断言；UI 只负责把结果按间隔发出去。
//

import Foundation

enum MouseCyclePlan {
    /// 预设序列
    enum Preset: String, CaseIterable, Identifiable {
        case four
        case duo
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .four:   return "四色"
            case .duo:    return "双色"
            case .custom: return "自定义"
            }
        }
    }

    struct Step: Equatable {
        var name: String
        var r: Int
        var g: Int
        var b: Int
    }

    /// 青 → 琥珀 → 红 → 绿：四个色差异大，肉眼一次看完就知道通道通不通
    static let four: [Step] = [
        Step(name: "青", r: 0, g: 210, b: 255),
        Step(name: "琥珀", r: 255, g: 96, b: 0),
        Step(name: "红", r: 255, g: 40, b: 60),
        Step(name: "绿", r: 60, g: 220, b: 120)
    ]

    /// 青 → 红：只有两发，赶时间时用
    static let duo: [Step] = [
        Step(name: "青", r: 0, g: 210, b: 255),
        Step(name: "红", r: 255, g: 40, b: 60)
    ]

    /// 可选间隔（秒）。写灯后设备有 1 帧左右的缓冲，低于 0.3 秒容易看不出变化
    static let intervals: [Double] = [0.6, 1.2, 2.5, 5.0]

    static func intervalTitle(_ value: Double) -> String {
        String(format: "%.1f s", clampedInterval(value))
    }

    /// 夹到 0.3…10 s；传进来的怪值（0、NaN、负数）都收进安全带
    static func clampedInterval(_ value: Double) -> Double {
        guard value.isFinite else { return 2.5 }
        return min(max(value, 0.3), 10)
    }

    /// 轮次 1…9（版本号规则同款：不超过 9）
    static func clampedRounds(_ value: Int) -> Int {
        min(max(value, 1), 9)
    }

    /// 按预设取序列；自定义序列为空时退回四色，避免点了按钮什么都不发
    static func steps(preset: String, custom: String) -> [Step] {
        switch Preset(rawValue: preset) ?? .four {
        case .four:   return four
        case .duo:    return duo
        case .custom:
            let parsed = parseHex(custom)
            return parsed.isEmpty ? four : parsed
        }
    }

    /// 解析 "FF0000,00A0FF" / "#FF0000;#00A0FF" / "青:00D2FF" / "00D2FF:青" 这类写法。
    /// 名称与色值谁在前都认（哪半边能当 RGB 就哪半边是色值），非法 token 直接跳过，最多 12 个。
    static func parseHex(_ text: String) -> [Step] {
        let tokens = text
            .replacingOccurrences(of: "；", with: ";")
            .replacingOccurrences(of: "，", with: ",")
            .split(whereSeparator: { ",; \t\n".contains($0) })
            .map(String.init)

        var steps: [Step] = []
        for token in tokens {
            let raw = token.trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { continue }

            var name = ""
            var hex = raw
            if let sep = raw.firstIndex(where: { $0 == ":" || $0 == "=" }) {
                let left = String(raw[raw.startIndex..<sep]).trimmingCharacters(in: .whitespaces)
                let right = String(raw[raw.index(after: sep)...]).trimmingCharacters(in: .whitespaces)
                if parseRGB(left) != nil {
                    hex = left
                    name = right
                } else {
                    hex = right
                    name = left
                }
            }

            guard let rgb = parseRGB(hex) else { continue }
            let label = name.isEmpty ? hex.replacingOccurrences(of: "#", with: "").uppercased() : name
            steps.append(Step(name: label, r: rgb.0, g: rgb.1, b: rgb.2))
            if steps.count >= 12 { break }
        }
        return steps
    }

    /// "RRGGBB" 或 "#RRGGBB"，大小写都认
    static func parseRGB(_ text: String) -> (Int, Int, Int)? {
        var hex = text.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6,
              let value = Int(hex, radix: 16)
        else { return nil }
        return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
    }

    /// 总共会发几发：序列长度 × 轮次
    static func totalSends(stepCount: Int, rounds: Int) -> Int {
        max(stepCount, 0) * clampedRounds(rounds)
    }

    /// 结束回执：说清几发、停在什么色
    static func endSummary(last: Step?, sends: Int) -> String {
        let stops = last.map { "灯停在最后一个色（\($0.name)）" } ?? "没有发出任何一帧"
        return "巡回结束：\(sends) 发已发完，\(stops)"
    }
}

/// 回执日志：最后 5 条、带时间戳、可整段复制
enum ReceiptLog {
    static let limit = 5

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static func stamp(_ date: Date) -> String {
        formatter.string(from: date)
    }

    /// 统一成「22:07:31 · 已写 000C/01 …」，和调试台日志一眼能对上
    static func line(_ text: String, at date: Date = Date()) -> String {
        "\(stamp(date)) · \(text)"
    }

    /// 只留最近 limit 条，新的在末尾
    static func append(_ line: String, to list: [String], limit: Int = limit) -> [String] {
        var next = list
        next.append(line)
        let cap = max(limit, 1)
        if next.count > cap { next = Array(next.suffix(cap)) }
        return next
    }

    /// 复制按钮用：按时间正序拼成多行
    static func text(_ list: [String]) -> String {
        list.joined(separator: "\n")
    }
}
