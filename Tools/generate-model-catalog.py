#!/usr/bin/env python3
# 由 AWCC 设备库 v3 生成 AlienMAC 内置机型库：
#   11-机型-灯区明细全表.csv  -> 每个机型的灯区（索引 / 名称 / LED 数）
#   10-机型-具名机型与灯区汇总.csv -> 机型汇总（灯区数 / 逐键 LED 总数）
#   12-机型-第三方实测协议对照.csv -> Tron / 键盘 / 风扇协议
#   src-来源文件/devices.csv -> 逐键 LED 索引映射（键名 -> LED 索引）
#
# 用法: python3 Tools/generate-model-catalog.py <v3 包目录> Resources/ModelCatalog.json
# 口径: 原表直录，不推断、不补空；没有逐键映射的机型 keys 为空。

import csv, re, json, sys, datetime

V3 = sys.argv[1]
OUT = sys.argv[2]

def rows(p):
    with open(p, encoding='utf-8-sig') as f:
        return [r for r in csv.reader(f) if r]

zr = rows(f'{V3}/11-机型-灯区明细全表.csv')
models = {}
order = []
for r in zr[1:]:
    name = r[0]
    if name not in models:
        models[name] = {'name': name, 'typeCode': int(r[1] or 0), 'controllers': [], 'zones': []}
        order.append(name)
    m = models[name]
    if r[6] == '' and r[7] == '':
        if r[4]:
            m['controllers'].append({'vid': r[2], 'pid': r[3], 'name': r[4]})
    else:
        m['zones'].append({'index': int(r[5]), 'name': r[6], 'leds': int(r[7] or 0),
                           'controller': r[4] or ''})

for r in rows(f'{V3}/10-机型-具名机型与灯区汇总.csv')[1:]:
    name = r[0]
    if name in models:
        models[name]['summaryZones'] = int(r[3] or 0)
        models[name]['summaryLedTotal'] = int(r[4] or 0)

txt = open(f'{V3}/src-来源文件/devices.csv', encoding='utf-8-sig').read().splitlines()
cur = None
per = {}
for ln in txt:
    t = re.findall(r"'([^']*)'", ln)
    if not t:
        continue
    if t[0] == '3':
        cur = t[1].strip()
        per.setdefault(cur, [])
    elif t[0] == '1' and cur is not None and len(t) >= 4:
        name = t[3].strip()
        pairs = [int(t[i + 1]) for i in range(4, len(t) - 1, 2) if t[i] == '1']
        if not name or not pairs:
            continue
        per[cur].append({'id': int(t[1]), 'name': name, 'leds': sorted(set(pairs))})

proto = {}
for r in rows(f'{V3}/12-机型-第三方实测协议对照.csv')[1:]:
    proto[r[1].strip()] = {'category': r[0], 'tron': r[2], 'keyboard': r[3], 'fan': r[4], 'note': r[5]}

for name, m in models.items():
    m['keys'] = per.get(name, [])
    m['protocol'] = proto.get(name)
    m['zoneCount'] = len(m['zones'])
    m['zoneLedTotal'] = sum(z['leds'] for z in m['zones'])
    m['perKeyCount'] = len(m['keys'])
    m['keyLedTotal'] = sum(len(k['leds']) for k in m['keys'])
    m.setdefault('summaryZones', m['zoneCount'])
    m.setdefault('summaryLedTotal', max(m['zoneLedTotal'], m['keyLedTotal']))

doc = {
    'schema': 'alienmac.models/3',
    'source': 'AWCC 设备库 v3：T-Troll devices.csv（逐键 LED 索引）+ 10/11 机型灯区表 + 12 协议对照',
    'provenance': '第三方社区实测，非 Dell 官方；灯区名与 LED 索引按原表直录，未做推断',
    'generatedAt': datetime.date.today().isoformat(),
    'models': [models[n] for n in order],
    'unmatchedProtocols': [dict(model=k, **v) for k, v in proto.items() if k not in models],
}
json.dump(doc, open(OUT, 'w'), ensure_ascii=False, indent=1)
print(f"models {len(doc['models'])} / zones {sum(m['zoneCount'] for m in doc['models'])}"
      f" / keys {sum(m['perKeyCount'] for m in doc['models'])}"
      f" / {len(json.dumps(doc))} bytes -> {OUT}")
