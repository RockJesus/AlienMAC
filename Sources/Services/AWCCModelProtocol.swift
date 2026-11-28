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
