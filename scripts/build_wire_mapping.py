#!/usr/bin/env python3
"""从 Resources/awcc-catalog.json 生成线缆坐标表 Resources/awcc-wire-mapping.json

规则（USBPcap 抓 AWCC 真机报文后确认，17 R4 11 条与抓包逐字一致）：
    chain = 模型 XML 的 ZoneID
    mask  = 1 << LedID
颜色帧        02 03 <chain> <mask 3 字节> <R> <G> <B>
整段写会话    02 08 01 → 颜色帧… → 02 08 01 → 02 04 00 → 02 09 00 → 02 05 00
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CAT = ROOT / "Resources" / "awcc-catalog.json"
OUT = ROOT / "Resources" / "awcc-wire-mapping.json"


def tokens(text):
    """CamelCase 与空格混排的名字切成小写词集合：KeyboardLeft -> {keyboard, left}"""
    text = re.sub(r"[_\-]+", " ", text or "")
    parts = re.findall(r"[A-Z]?[a-z]+|[A-Z]+(?![a-z])|\d+", text)
    return {p.lower() for p in parts if p}


def led_tokens(led):
    return tokens(led.get("description"))


def match_led(zone, leds):
    """zone 名与 led 描述做词集包含匹配，返回 (led, 说明) 或 (None, 原因)"""
    zt = tokens(zone.get("name"))
    cands = []
    for led in leds:
        lt = led_tokens(led)
        if not lt or not zt:
            continue
        # 双向兼容：zone 名可能比 LED 描述短（LCD Left ↔ LCD Panel Left），也可能更长
        if lt <= zt or zt <= lt:
            # 完全同名最优，其次差得最少（Keyboard Left 优先于 Keyboard Middle Left）
            cands.append(((0 if lt == zt else 1, len(lt ^ zt)), led))
    if not cands:
        return None, "无同名 LED（该区可能只有亮度位 / 是复制区）"
    cands.sort(key=lambda x: x[0])
    if len(cands) > 1 and cands[0][0] == cands[1][0]:
        return None, "多个 LED 同名匹配，需人工确认"
    return cands[0][1], "词集匹配"


def build_model(model):
    leds = model.get("leds", [])
    zones = model.get("zones", [])
    out_zones = []
    for zone in zones:
        zid = int(zone.get("zoneID", 0))
        led, why = match_led(zone, leds)
        if led is None:
            out_zones.append({"zoneID": str(zid), "name": zone.get("name"),
                              "ledID": None, "mask": None, "note": why})
            continue
        led_id = int(led.get("ledID", -1))
        mask = 1 << led_id
        out_zones.append({
            "zoneID": str(zid),
            "chain": zid,
            "name": zone.get("name"),
            "ledDescription": led.get("description"),
            "ledID": led_id,
            "ledIndex": int(led.get("ledIndex", -1)),
            "brightnessOnly": led.get("brightnessOnly", False),
            "groupPosition": led.get("position"),
            "mask": "0x%06X" % mask,
            "mask3Hex": "%02X %02X %02X" % ((mask >> 16) & 0xFF, (mask >> 8) & 0xFF, mask & 0xFF),
            "frameTemplate": "02 03 %02X %02X %02X %02X <R> <G> <B>" % (
                zid, (mask >> 16) & 0xFF, (mask >> 8) & 0xFF, mask & 0xFF),
            "matchRule": why,
        })
    addressable = [z for z in out_zones if z.get("mask")]
    return {
        "id": model.get("id"),
        "model": model.get("name"),
        "verified": model.get("id") == "Alienware17R4",
        "lcdCount": len(leds),
        "zoneCount": len(zones),
        "addressable": len(addressable),
        "zones": out_zones,
    }


doc = {
    "schema": "alienmac.awcc-wire-mapping/1",
    "source": "Resources/awcc-catalog.json（AWCC 安装目录内嵌模型 XML）+ USBPcap 实抓",
    "rule": "chain = ZoneID；mask = 1 << LedID",
    "session": {
        "writeStart": "02 08 <DataID>",
        "color": "02 03 <chain> <mask3> <R> <G> <B>",
        "writeFinished": "02 08 <DataID> → 02 04 00",
        "save": "02 09 00",
        "commit": "02 05 00",
        "realtimeDataID": "01",
        "reset": "02 07 04",
        "brightness": "02 1C <20..100> <01 全局 | 00 电池>",
        "tempo": "02 0E 00 <lo> <hi>",
        "transition": "02 1D 03",
    },
    "hardwareConfirmed": [{
        "model": "Alienware17R4",
        "evidence": "USBPcap 实抓 AWCC 启动序列，11 条 (chain, mask) 逐条一致；chain 02 / mask 00 00 08 经肉眼确认点亮键盘左段",
        "frames": 11,
    }],
    "modelCount": 0,
    "models": [],
}

models = [m for m in CAT.read_text(encoding="utf-8") and json.loads(CAT.read_text(encoding="utf-8"))["models"]]
built = [build_model(m) for m in models]
built.sort(key=lambda m: (-m["addressable"], m["model"]))
doc["models"] = built
doc["modelCount"] = len(built)
OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")
print("写入", OUT, OUT.stat().st_size, "字节，机型", len(built))

r4 = next(m for m in built if m["id"] == "Alienware17R4")
print("\n17 R4（应为抓包里的 11 条）:")
for z in r4["zones"]:
    if z.get("mask"):
        print("  zone %-3s %-22s %s" % (z["zoneID"], z["ledDescription"], z["frameTemplate"].split(" <")[0]))
print("  可寻址", r4["addressable"], "/ 区数", r4["zoneCount"])
print("\n地址最多机型:", [(m["model"], m["addressable"]) for m in built[:5]])
