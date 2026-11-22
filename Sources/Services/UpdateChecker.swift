//
//  UpdateChecker.swift
//  AlienMAC
//
//  检查 GitHub Releases 上的新版本，支持启动自动检查与手动检查
//

import Foundation
import AppKit

final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate(String)
        case available(version: String, notes: String, pageURL: URL, downloadURL: URL?)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    /// 自动检查（默认开），间隔 12 小时
    @Published var autoCheckEnabled: Bool {
        didSet { UserDefaults.standard.set(autoCheckEnabled, forKey: Keys.autoCheck) }
    }

    private let repo = "RockJesus/AlienMAC"
    private let checkInterval: TimeInterval = 12 * 3600

    private enum Keys {
        static let autoCheck = "AlienMAC.autoCheckUpdate"
        static let lastCheck = "AlienMAC.lastUpdateCheck"
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    init() {
        if UserDefaults.standard.object(forKey: Keys.autoCheck) == nil {
            autoCheckEnabled = true
        } else {
            autoCheckEnabled = UserDefaults.standard.bool(forKey: Keys.autoCheck)
        }
    }

    /// 启动时调用：自动检查开启且距上次检查超过 12 小时才发请求
    func checkOnLaunchIfNeeded() {
        guard autoCheckEnabled else { return }
        let last = UserDefaults.standard.double(forKey: Keys.lastCheck)
        guard Date().timeIntervalSince1970 - last > checkInterval else { return }
        check()
    }

    func check() {
        guard state != .checking else { return }
        state = .checking

        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AlienMAC/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            DispatchQueue.main.async {
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Keys.lastCheck)

                if let error {
                    self.state = .failed(error.localizedDescription)
                    return
                }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String else {
                    self.state = .failed("返回内容无法解析")
                    return
                }

                let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let notes = (json["body"] as? String) ?? ""
                let page = (json["html_url"] as? String).flatMap(URL.init(string:))
                    ?? URL(string: "https://github.com/\(self.repo)/releases")!

                var download: URL?
                if let assets = json["assets"] as? [[String: Any]] {
                    let dmg = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
                    download = (dmg?["browser_download_url"] as? String).flatMap(URL.init(string:))
                }

                if Self.isNewer(latest, than: Self.currentVersion) {
                    self.state = .available(version: latest, notes: notes, pageURL: page, downloadURL: download)
                } else {
                    self.state = .upToDate(latest)
                }
            }
        }.resume()
    }

    /// 语义化版本比较：1.2.3 > 1.2.2，1.3.0 > 1.2.9
    static func isNewer(_ remote: String, than local: String) -> Bool {
        let a = remote.split(separator: ".").map { Int($0) ?? 0 }
        let b = local.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    func openDownloadPage() {
        guard case .available(_, _, let page, let download) = state else { return }
        NSWorkspace.shared.open(download ?? page)
    }

    func openReleasePage() {
        guard case .available(_, _, let page, _) = state else { return }
        NSWorkspace.shared.open(page)
    }
}
