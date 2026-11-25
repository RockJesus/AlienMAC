//
//  PowerInfo.swift
//  AlienMAC
//
//  AlienFusion 模块读取的 macOS 电源信息
//

import Foundation

struct PowerInfo: Equatable {
    var isAC: Bool = true
    var batteryPercent: Int?
    var batteryCharging: Bool = false
    var systemSleepMinutes: Int?
    var displaySleepMinutes: Int?
    var diskSleepMinutes: Int?
    var lowPowerMode: Bool = false

    static func read() -> PowerInfo {
        var info = PowerInfo()

        // pmset -g batt
        if let batt = run("/usr/bin/pmset", ["-g", "batt"]) {
            info.isAC = batt.contains("AC Power")
            if let range = batt.range(of: "([0-9]+)%", options: .regularExpression) {
                info.batteryPercent = Int(batt[range].replacingOccurrences(of: "%", with: ""))
            }
            info.batteryCharging = batt.contains("charging") && !batt.contains("discharging")
        }

        // pmset -g custom：取第一组（电池/交流任一组）的休眠时长
        if let custom = run("/usr/bin/pmset", ["-g", "custom"]) {
            info.systemSleepMinutes = intValue(in: custom, key: "SystemSleepTimer")
            info.displaySleepMinutes = intValue(in: custom, key: "displaysleep")
            info.diskSleepMinutes = intValue(in: custom, key: "disksleep")
        }

        // 低电量模式
        if let low = run("/usr/bin/pmset", ["-g"]), low.contains("lowpowermode") {
            info.lowPowerMode = low.range(of: "lowpowermode\\s+1", options: .regularExpression) != nil
        }
        return info
    }

    /// 把分钟数转成中文表述
    static func minutesText(_ minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "从不" }
        if minutes < 60 { return "\(minutes) 分钟" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) 小时" : "\(h) 小时 \(m) 分"
    }

    private static func intValue(in text: String, key: String) -> Int? {
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 2, parts[0] == Substring(key) {
                return Int(parts[1])
            }
        }
        return nil
    }

    private static func run(_ path: String, _ args: [String]) -> String? {
        let task = Process()
        task.launchPath = path
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
