//
//  ScheduleController.swift
//  AlienMAC
//
//  定时任务：按「时间 + 星期」循环执行灯光动作（关键盘灯 / 开键盘灯 / 全关 / 全开）。
//  规则存 UserDefaults，每 20 秒对表一次，同一分钟内不会重复触发。
//

import Foundation
import Combine

/// 定时任务可执行的动作
enum ScheduleAction: String, Codable, CaseIterable, Identifiable {
    case keyboardOff = "关闭键盘灯"
    case keyboardOn  = "打开键盘灯"
    case allOff      = "关闭全部灯"
    case allOn       = "打开全部灯"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .keyboardOff: return "keyboard.badge.ellipsis"
        case .keyboardOn:  return "keyboard"
        case .allOff:      return "lightbulb.slash"
        case .allOn:       return "lightbulb.fill"
        }
    }
}

/// 一条定时规则
struct ScheduleRule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var hour: Int
    var minute: Int
    /// 位 0 = 周日 … 位 6 = 周六；0 表示每天
    var weekdayMask: Int = 0
    var action: ScheduleAction = .keyboardOff
    var enabled: Bool = true

    var timeText: String { String(format: "%02d:%02d", hour, minute) }

    var repeatText: String {
        if weekdayMask == 0 { return "每天" }
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        var parts: [String] = []
        for bit in 0..<7 where weekdayMask & (1 << bit) != 0 {
            parts.append("周" + names[bit])
        }
        return parts.isEmpty ? "每天" : parts.joined(separator: " ")
    }
}

/// 定时任务单例
final class ScheduleController: ObservableObject {
    static let shared = ScheduleController()

    private let rulesKey = "AlienMAC.scheduleRules"
    private let enabledKey = "AlienMAC.scheduleEnabled"

    @Published var rules: [ScheduleRule] = [] {
        didSet { saveRules() }
    }

    @Published var masterEnabled: Bool {
        didSet {
            UserDefaults.standard.set(masterEnabled, forKey: enabledKey)
            masterEnabled ? startTimer() : stopTimer()
        }
    }

    /// 真正执行动作的回调（由 App 注入到 LightingViewModel）
    var executor: ((ScheduleAction) -> Void)?

    private var timer: Timer?
    private var firedKeys: Set<String> = []
    private var lastFireDescriptions: [String] = []

    /// 最近一次触发记录（供设置页显示）
    @Published private(set) var lastFiredText: String = ""

    private init() {
        masterEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        loadRules()
        if masterEnabled { startTimer() }
    }

    // MARK: - 增删改

    func add(_ rule: ScheduleRule) {
        rules.append(rule)
        // 新规则立即可用
        if masterEnabled { startTimer() }
    }

    func remove(_ rule: ScheduleRule) {
        rules.removeAll { $0.id == rule.id }
    }

    func setEnabled(_ enabled: Bool, for rule: ScheduleRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index].enabled = enabled
    }

    // MARK: - 定时器

    private func startTimer() {
        stopTimer()
        let t = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            self?.runDue()
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // 启动即对一次表，避免刚打开时错过本分钟
        runDue()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// 对表并执行到点的规则（可注入 now 方便测试）
    func runDue(now: Date = Date()) {
        guard masterEnabled else { return }
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: now)
        guard let hour = comps.hour, let minute = comps.minute,
              let weekday = comps.weekday,
              let y = comps.year, let m = comps.month, let d = comps.day else { return }

        let weekdayBit = weekday - 1           // 1=周日 → 位 0
        let stamp = String(format: "%04d%02d%02d%02d%02d", y, m, d, hour, minute)

        for rule in rules where rule.enabled {
            guard rule.hour == hour, rule.minute == minute else { continue }
            if rule.weekdayMask != 0, rule.weekdayMask & (1 << weekdayBit) == 0 { continue }
            let key = stamp + "-" + rule.id.uuidString
            guard !firedKeys.contains(key) else { continue }
            firedKeys.insert(key)
            execute(rule, key: key)
        }

        // 只保留最近两天的触发键，避免无限增长
        if firedKeys.count > 500 {
            firedKeys = Set(firedKeys.suffix(200))
        }
    }

    private func execute(_ rule: ScheduleRule, key: String) {
        NSLog("SCHEDULE_FIRE %@ %@", rule.timeText, rule.action.rawValue)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let stamp = formatter.string(from: Date())
        lastFiredText = "\(stamp) \(rule.action.rawValue)"
        executor?(rule.action)
    }

    // MARK: - 持久化

    private func saveRules() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        UserDefaults.standard.set(data, forKey: rulesKey)
    }

    private func loadRules() {
        guard let data = UserDefaults.standard.data(forKey: rulesKey),
              let decoded = try? JSONDecoder().decode([ScheduleRule].self, from: data) else {
            rules = []
            return
        }
        rules = decoded
    }
}
