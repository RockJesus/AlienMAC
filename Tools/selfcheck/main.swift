//
//  main.swift — 免 Xcode 自检（scripts/selfcheck.sh 编译运行）
//
//  只在 CLT 的 swiftc 下就能跑，覆盖不依赖外部框架的纯逻辑：
//  通道排序、错误码格式化、鼠标 0x5A 帧形状。用于替代“没装 Xcode 时跑不了 XCTest”的空档。
//

import Foundation

// 崩溃时也别把已跑出来的断言憋在缓冲区里
setbuf(stdout, nil)

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

// MARK: - 通道记忆（v2.8.2）

let sig558 = ChannelMemory.signature(aw558)
check(ChannelMemory.channelKey(aw558[1]) == "000C/01", "通道短名格式 000C/01")
check(ChannelMemory.signature([aw558[2], aw558[0], aw558[1]]) == sig558, "接口签名与枚举顺序无关")
check(ChannelMemory.key(vid: 0x04CA, pid: 0x00A5) == "04CA:00A5", "记忆键格式 04CA:00A5")

let entryHit = ChannelMemory.Entry(channel: "0001/06", signature: sig558)
check(ChannelMemory.order(channels: aw558, payload: 64, entry: entryHit) == [0, 1, 2],
      "记忆命中时把记住的 0001/06 提到最前")
check(ChannelMemory.order(channels: aw558, payload: 64,
                          entry: ChannelMemory.Entry(channel: "0001/06", signature: "X")) == [1, 2, 0],
      "签名不一致（插拔后接口变了）退回按得分排序")
check(ChannelMemory.order(channels: aw558, payload: 64,
                          entry: ChannelMemory.Entry(channel: "9999/01", signature: sig558)) == [1, 2, 0],
      "记住的通道已不在接口表里时忽略记忆")
check(ChannelMemory.order(channels: aw558, payload: 64, entry: nil) == [1, 2, 0], "没有记忆时就是得分排序")
check(ChannelMemory.matches(entryHit, channels: aw558), "签名一致时记忆有效")
check(!ChannelMemory.matches(entryHit, channels: declared), "签名不一致时记忆失效")

// MARK: - 巡回配置（v2.8.2）

check(MouseCyclePlan.steps(preset: "four", custom: "").count == 4, "四色预设 4 发")
check(MouseCyclePlan.steps(preset: "duo", custom: "").count == 2, "双色预设 2 发")

let customSteps = MouseCyclePlan.parseHex("FF0000, 00A0FF:蓝;#00FF00")
check(customSteps.count == 3, "自定义序列解析出 3 个色")
check(customSteps[1].name == "蓝" && customSteps[1].r == 0 && customSteps[1].g == 0xA0 && customSteps[1].b == 0xFF,
      "「名称:色值」写法生效")
check(customSteps[2].name == "00FF00" && customSteps[2].g == 255, "# 前缀可解析，缺省名用色值")
check(MouseCyclePlan.parseHex("青:00D2FF").first?.name == "青", "「名称:色值」反过来也认（青:00D2FF）")
check(MouseCyclePlan.parseHex("ZZZ,12345").isEmpty, "非法色值全部跳过")
check(MouseCyclePlan.parseHex("").isEmpty, "空文本解析为空")
check(MouseCyclePlan.steps(preset: "custom", custom: "bad").count == 4, "自定义写坏时退回四色，不会什么都不发")
check(MouseCyclePlan.parseHex(Array(repeating: "FF0000", count: 20).joined(separator: ",")).count == 12,
      "自定义序列最多 12 发")

check(MouseCyclePlan.clampedRounds(0) == 1 && MouseCyclePlan.clampedRounds(99) == 9, "轮次夹在 1…9")
check(MouseCyclePlan.clampedInterval(0) == 0.3 && MouseCyclePlan.clampedInterval(99) == 10, "间隔夹在 0.3…10 s")
check(MouseCyclePlan.clampedInterval(.nan) == 2.5, "非法间隔退回 2.5 s")
check(MouseCyclePlan.totalSends(stepCount: 4, rounds: 2) == 8, "总发送数 = 序列长度 × 轮次")
check(MouseCyclePlan.endSummary(last: MouseCyclePlan.four.last, sends: 8).contains("绿"),
      "结束回执写明停在哪个色")

// MARK: - 回执日志（v2.8.2）

let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
let receipt = ReceiptLog.line("已写 000C/01", at: fixedDate)
check(receipt.contains(" · 已写 000C/01"), "回执格式是「时间 · 内容」")
check(receipt.prefix(2).allSatisfy { $0.isNumber }, "回执带 HH:mm:ss 时间戳")

var rolling: [String] = []
for i in 0..<8 { rolling = ReceiptLog.append("l\(i)", to: rolling) }
check(rolling.count == 5, "回执只留最近 5 条")
check(rolling.first == "l3" && rolling.last == "l7", "回执丢掉最旧的、保留最新的")
check(ReceiptLog.text(["a", "b"]) == "a\nb", "复制按钮按行拼接")

print("")
print(failed == 0 ? "ALL \(passed) PASS" : "\(failed) FAILED / \(passed) PASS")
exit(failed == 0 ? 0 : 1)