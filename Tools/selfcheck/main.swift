//
//  main.swift — 免 Xcode 自检（scripts/selfcheck.sh 编译运行）
//
//  只在 CLT 的 swiftc 下就能跑，覆盖不依赖外部框架的纯逻辑：
//  通道排序、错误码格式化、鼠标 0x5A 帧形状。用于替代“没装 Xcode 时跑不了 XCTest”的空档。
//

import Foundation

var failed = 0
var passed = 0

func check(_ cond: Bool, _ name: String) {
    if cond {
        passed += 1
        print("PASS  \(name)")
    } else {
        failed += 1
        print("FAIL  \(name)")
    }
}

// MARK: - 通道选择（AW558 真机三接口）

let aw558: [LightChannelPlan.Channel] = [
    .init(usagePage: 0x01, usage: 0x06, maxInput: 8, maxOutput: 0),
    .init(usagePage: 0x0C, usage: 0x01, maxInput: 64, maxOutput: 0),
    .init(usagePage: 0x01, usage: 0x02, maxInput: 8, maxOutput: 0)
]
check(LightChannelPlan.bestIndex(aw558, payload: 64) == 1, "AW558 灯控落在消费控制接口 000C/01")
check(LightChannelPlan.ordered(aw558, payload: 64) == [1, 2, 0], "通道按得分排序为 1,2,0")
check(!LightChannelPlan.declaresCapacity(aw558[1], payload: 64), "消费接口输出长度读到 0 仍可试写")

let declared: [LightChannelPlan.Channel] = [
    .init(usagePage: 0x0C, usage: 0x01, maxInput: 64, maxOutput: 0),
    .init(usagePage: 0xFF00, usage: 0x01, maxInput: 0, maxOutput: 64)
]
check(LightChannelPlan.bestIndex(declared, payload: 64) == 1, "有真实 64B 输出管道的接口优先")
check(LightChannelPlan.declaresCapacity(declared[1], payload: 64), "64B 输出接口判定为已声明")

let twins: [LightChannelPlan.Channel] = [
    .init(usagePage: 0xFF00, usage: 0x02, maxInput: 0, maxOutput: 0),
    .init(usagePage: 0xFF00, usage: 0x03, maxInput: 0, maxOutput: 0)
]
check(LightChannelPlan.ordered(twins, payload: 64) == [0, 1], "同分时保持原顺序")
check(LightChannelPlan.bestIndex([], payload: 64) == nil, "空通道列表返回 nil")

// MARK: - 错误码文案

check(IOReturnText.code(Int32(bitPattern: 0xE00002E2)) == "0xE00002E2", "权限码按无符号打印")
check(!IOReturnText.code(Int32(bitPattern: 0xE00002E2)).contains("-"), "错误码不带负号")
check(IOReturnText.describe(Int32(bitPattern: 0xE00002E2)).contains("权限不足"), "权限码有中文解释")
check(IOReturnText.describe(Int32(bitPattern: 0xE00002C5)).contains("独占"), "独占码有中文解释")
check(IOReturnText.line(0) == "0x00000000（成功）", "成功码可读")

// MARK: - 鼠标 0x5A 帧形状

let green = FXMouseCodec.singleColor(r: 0, g: 255, b: 0)
check(green.count == FXMouseCodec.defaultPayloadLength, "单色帧长度 64")
check(Array(green.prefix(4)) == [0x07, 0x5A, 0x03, 0x01], "单色帧头 07 5A 03 01")
check(green[7] == FXMouseCodec.terminator, "单色帧第 8 字节是 A5")
check(Array(green[8...].prefix(8)) == Array(repeating: 0, count: 8), "尾部补零到 64")

let reset = FXMouseCodec.resetDefault()
check(Array(reset.prefix(4)) == [0x09, 0x5A, 0x10, 0x00], "恢复默认帧头 09 5A 10 00")
check(Array(reset[4...8].prefix(5)) == Array("Reset".utf8), "恢复默认载荷是 Reset")

print("")
print(failed == 0 ? "ALL \(passed) PASS" : "\(failed) FAILED / \(passed) PASS")
exit(failed == 0 ? 0 : 1)
