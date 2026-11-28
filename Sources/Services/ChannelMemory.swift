//
//  ChannelMemory.swift
//  AlienMAC
//
//  灯控通道记忆：一次试出来的可用接口记进偏好，下次点色直接先试它。
//
//  设计要点：
//  - 记忆条目带"设备接口签名"（usagePage/usage/maxInput 的组合）。插拔后接口表变了签名就对不上，
//    自动退回按得分排序——不需要额外监听插拔事件，也不会拿旧通道硬撞。
//  - 排序逻辑是纯函数，selfcheck 能直接断言。
//

import Foundation

enum ChannelMemory {
    /// 一条记忆：哪个通道、当时的接口签名
    struct Entry: Codable, Equatable {
        var channel: String
        var signature: String
    }

    /// 偏好里的键，形如 "04CA:00A5"
    static func key(vid: Int, pid: Int) -> String {
        String(format: "%04X:%04X", vid, pid)
    }

    /// 单个接口的短名，形如 "000C/01"
    static func channelKey(_ c: LightChannelPlan.Channel) -> String {
        String(format: "%04X/%02X", c.usagePage, c.usage)
    }

    /// 接口签名：每个接口一个 token，排序后拼接，只跟"接口集合"有关，与枚举顺序无关
    static func signature(_ channels: [LightChannelPlan.Channel]) -> String {
        channels
            .map { String(format: "%04X/%02X:%d", $0.usagePage, $0.usage, $0.maxInput) }
            .sorted()
            .joined(separator: "|")
    }

    /// 通道尝试顺序：签名一致且记忆里的通道还在，就把它提到最前；否则退回按得分排序
    static func order(channels: [LightChannelPlan.Channel],
                      payload: Int,
                      entry: Entry?) -> [Int] {
        let ranked = LightChannelPlan.ordered(channels, payload: payload)
        guard let entry,
              entry.signature == signature(channels),
              let hit = channels.firstIndex(where: { channelKey($0) == entry.channel })
        else { return ranked }
        return [hit] + ranked.filter { $0 != hit }
    }

    /// 记忆是否仍然有效（签名一致 + 通道还在）
    static func matches(_ entry: Entry?, channels: [LightChannelPlan.Channel]) -> Bool {
        guard let entry, entry.signature == signature(channels) else { return false }
        return channels.contains { channelKey($0) == entry.channel }
    }

    /// UserDefaults 持久化（偏好键 peripheralChannelMemory）
    final class Store {
        static let shared = Store()

        private let defaultsKey = "peripheralChannelMemory"
        private let defaults: UserDefaults
        private var entries: [String: Entry] = [:]

        init(defaults: UserDefaults = .standard) {
            self.defaults = defaults
            load()
        }

        func entry(vid: Int, pid: Int) -> Entry? {
            entries[key(vid: vid, pid: pid)]
        }

        /// 记下成功用的通道，同时把当时的接口签名一起存
        func remember(channel: String, channels: [LightChannelPlan.Channel], vid: Int, pid: Int) {
            let k = key(vid: vid, pid: pid)
            let new = Entry(channel: channel, signature: signature(channels))
            guard entries[k] != new else { return }
            entries[k] = new
            save()
        }

        /// 记忆失效（通道打不开或写入失败）立刻忘掉，避免下次又先撞它
        func forget(vid: Int, pid: Int) {
            let k = key(vid: vid, pid: pid)
            guard entries[k] != nil else { return }
            entries.removeValue(forKey: k)
            save()
        }

        func all() -> [String: Entry] {
            entries
        }

        private func load() {
            guard let data = defaults.data(forKey: defaultsKey),
                  let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
            else { return }
            entries = decoded
        }

        private func save() {
            guard let data = try? JSONEncoder().encode(entries) else { return }
            defaults.set(data, forKey: defaultsKey)
        }
    }
}
