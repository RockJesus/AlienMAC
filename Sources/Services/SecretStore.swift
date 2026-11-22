//
//  SecretStore.swift
//  AlienMAC
//
//  凭据落盘：~/Library/Application Support/AlienMAC/secrets.json
//  目录 0700、文件 0600，仅当前用户可读。
//  改用文件存储是因为 ad-hoc 签名每次构建都会变，钥匙串 ACL 随之失效，
//  每次升级首次启动都会弹密码框。
//

import Foundation

enum SecretStore {
    private static let queue = DispatchQueue(label: "com.alienmac.secrets")

    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AlienMAC", isDirectory: true)
    }

    private static var fileURL: URL {
        directoryURL.appendingPathComponent("secrets.json")
    }

    private static func ensureDirectory() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directoryURL.path) {
            try fm.createDirectory(at: directoryURL,
                                   withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        } else {
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        }
    }

    private static func loadAll() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }

    private static func writeAll(_ dict: [String: String]) -> Bool {
        do {
            try ensureDirectory()
            let data = try JSONEncoder().encode(dict)
            try data.write(to: fileURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        queue.sync {
            var dict = loadAll()
            if value.isEmpty {
                dict.removeValue(forKey: account)
            } else {
                dict[account] = value
            }
            return writeAll(dict)
        }
    }

    static func get(account: String) -> String? {
        queue.sync {
            loadAll()[account]
        }
    }
}
