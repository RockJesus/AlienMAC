import Foundation

/// AWCC 写会话（USBPcap 实抓确认，2026-11-26）
///
/// AWCC 下发实时颜色时不是「裸发一帧 02 03」，而是把命令包在一个 DataID 写会话里：
///
///     02 08 <DataID>          写开始
///     02 03 <chain> <mask> <RGB> …   会话内的命令帧（可多条）
///     02 08 <DataID>          写结束
///     02 04 00                锁存
///     02 09 00                保存
///     02 05 00                提交
///
/// 缺任何一环设备都不执行：这就是此前「WriteFile 成功、灯不变」的原因。
enum AWCCWire {
    /// 实时颜色会话号（抓包里颜色帧全部走 0x01）
    static let realtimeDataID: UInt8 = 0x01

    /// 写开始：`02 08 <DataID>`
    static func writeStart(_ dataID: UInt8) -> [UInt8] { [0x08, dataID] }
    /// 写结束前的第二次 `02 08 <DataID>`
    static func writeFinished(_ dataID: UInt8) -> [UInt8] { [0x08, dataID] }
    /// 锁存 `02 04 00`
    static let latch: [UInt8] = [0x04, 0x00]
    /// 保存 `02 09 00`
    static let saveSlot: [UInt8] = [0x09, 0x00]
    /// 提交 `02 05 00`
    static let commit: [UInt8] = [0x05, 0x00]
    /// 复位 `02 07 04`
    static let reset: [UInt8] = [0x07, 0x04]
    /// 状态查询 `02 06 00`
    static let statusQuery: [UInt8] = [0x06, 0x00]
    /// 过渡 `02 1D 03`
    static let transition: [UInt8] = [0x1D, 0x03]

    /// 颜色帧：`02 03 <chain> <mask3> <R> <G> <B>`
    static func colorFrame(chain: UInt8, mask: UInt32, opcode: UInt8 = 3,
                           r: UInt8, g: UInt8, b: UInt8,
                           r2: UInt8 = 0, g2: UInt8 = 0, b2: UInt8 = 0) -> [UInt8] {
        [opcode, chain,
         UInt8((mask >> 16) & 0xFF), UInt8((mask >> 8) & 0xFF), UInt8(mask & 0xFF),
         r, g, b, r2, g2, b2]
    }
}

/// 设备就绪序列（AWCC 启动瞬间下发的 134 帧，抓包原样）
///
/// 设备必须先跑完这套初始化才认实时颜色；macOS 上没有 AWCC 替我们跑，
/// 所以序列随 App 一起分发（Resources/awcc-device-init.json）。
struct AWCCDeviceInit {
    static let shared = AWCCDeviceInit()

    private let frames: [[UInt8]]

    private init() {
        let raw: [[UInt8]]
        if let url = Bundle.main.url(forResource: "awcc-device-init", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let list = doc["frames"] as? [[String: Any]] {
            raw = list.compactMap { item in
                guard let bytes = item["bytes"] as? [Int] else { return nil }
                // 抓包存的是完整 12 字节报文，首字节 0x02 就是 Report ID；
                // sendRaw 会自己补 Report ID，这里必须把它去掉，否则整帧错位一格。
                let payload = (bytes.count == 12 && bytes.first == Int(AlienFXDeviceID.reportID))
                    ? Array(bytes.dropFirst())
                    : Array(bytes)
                return payload.prefix(11).map { UInt8(clamping: $0) }
            }
        } else {
            raw = []
        }
        frames = raw
    }

    var isEmpty: Bool { frames.isEmpty }
    var count: Int { frames.count }

    /// 逐帧重放；`send` 返回 false 时立即中断
    @discardableResult
    func replay(send: ([UInt8]) -> Bool, gap: TimeInterval = 0.02) -> Int {
        var sent = 0
        for frame in frames {
            guard send(frame) else { break }
            sent += 1
            if gap > 0 { Thread.sleep(forTimeInterval: gap) }
        }
        return sent
    }
}
