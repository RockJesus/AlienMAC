//
//  LightChannelPlanTests.swift
//  AlienMACTests
//
//  v2.7.9：鼠标灯控接口选择的纯函数回归（AW558 实测：消费控制接口才是灯控落点）
//

import XCTest

final class LightChannelPlanTests: XCTestCase {
    /// AW558 真机三接口：键盘 0001/06（8B 输入）、消费 000C/01（64B 输入、0B 输出）、鼠标 0001/02（8B 输入/8B feature）
    private let aw558: [LightChannelPlan.Channel] = [
        .init(usagePage: 0x01, usage: 0x06, maxInput: 8, maxOutput: 0),
        .init(usagePage: 0x0C, usage: 0x01, maxInput: 64, maxOutput: 0),
        .init(usagePage: 0x01, usage: 0x02, maxInput: 8, maxOutput: 0)
    ]

    func testPrefersConsumerControlForAW558() {
        let idx = LightChannelPlan.bestIndex(aw558, payload: 64)
        XCTAssertEqual(idx, 1, "灯控必须落在消费控制接口 000C/01，不是鼠标主接口")
    }

    func testConsumerWinsEvenWhenItDeclaresNoOutput() {
        // 消费接口 maxOutput 读到 0（AW558 就是这种），仍应胜出并可试写
        let c = aw558[1]
        XCTAssertFalse(LightChannelPlan.declaresCapacity(c, payload: 64))
        XCTAssertGreaterThan(LightChannelPlan.score(c, payload: 64), LightChannelPlan.score(aw558[2], payload: 64))
    }

    func testDeclaredOutputBeatsUndeclared() {
        let declared: [LightChannelPlan.Channel] = [
            .init(usagePage: 0x0C, usage: 0x01, maxInput: 64, maxOutput: 0),
            .init(usagePage: 0xFF00, usage: 0x01, maxInput: 0, maxOutput: 64)
        ]
        XCTAssertEqual(LightChannelPlan.bestIndex(declared, payload: 64), 1, "有真实 64B 输出管道的厂商接口优先")
        XCTAssertTrue(LightChannelPlan.declaresCapacity(declared[1], payload: 64))
    }

    func testEmptyChannelListGivesNil() {
        XCTAssertNil(LightChannelPlan.bestIndex([], payload: 64))
    }
}
