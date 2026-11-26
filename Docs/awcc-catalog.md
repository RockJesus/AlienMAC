# AWCC 机型资源目录

`Resources/awcc-catalog.json` 是从 Windows 版 AWCC 安装目录里抽出来的机型灯控资源，
随 App 打包；`Sources/Services/AWCCCatalog.swift` 负责读取，`Sources/Views/AWCCModelLibraryView.swift`
是界面（顶栏「机型」按钮）。

## 来源

Windows 上 AWCC 的机型资源是 `AlienFX.ModelResources.<机型>.dll`（本机安装里 34 个，去掉无灯机型剩 31 个）。
每个 DLL 内嵌若干 XML 文档，按顺序是：

| 文档 | 用途 |
| --- | --- |
| `ModelDataClass` | 能力开关：节奏范围、亮度范围、GoDark 及快捷键、预览、扩展时长、数字键盘 |
| `Leds`（`LedIndex/LedID/Description/Position`） | 灯位表：灯名 + 32 位掩码；`OnlyForBrightnessSupport` 标出只吃亮度的位（17 R4 的宏键） |
| `Leds`（`GroupID/Path`）、`Masks`、`HotSpots`、`CallOuts` | AWCC 面板的素材映射（控件、热点、提示图） |
| `ArrayOfColorData` | 该机型自带的 20 色官方调色板（ARGB） |
| `ThemeDataset` | 该机型自带的默认主题，结构同 `.ath`：Groups / Zones / ZonesGroups / Leds / Actions |

预置主题另有 `Predefined Themes/*.apt`，同样是 `ThemeDataset` 结构，13 套可用
（Advanced 6 套、Basic 7 套）。

## 目录结构

```json
{
  "schema": 1,
  "models": [ { "id": "Alienware17R4", "name": "Alienware 17 R4", "verified": true,
               "capabilities": { ... }, "leds": [ ... ], "groups": [ ... ],
               "zoneGroups": { "2": "1", ...  }, "zones": [ ... ],
               "defaultTheme": { "name": "Basic Theme", "actions": [ ... ] },
               "palette": [ { "name": "Quasar Blue", "argb": "FF0000F0" } ] } ],
  "themes": [ { "name": "Advanced - ColorWheel", "family": "Advanced", "actions": [ ... ] } ],
  "pidModules": [ { "pid": "0x530", "models": ["Alienware15R3", "Alienware17R4"] } ]
}
```

灯区行（`AWCCModelInfo.zoneRows`）由 `zones` + `zoneGroups` + `groups` + `leds` 推导：

- 区域号 = `ZoneID`（1 是电源壳，2…12 是灯；13…18 是 AC/DC 各电源状态专用区）
- 组号 = `zoneGroups[ZoneID]`（= AWCC `Groups` 的编号，跳过 9）
- 掩码 = `Position`；大于 3 字节的（`Alienhead` 的 `0x02000000`）右移 8 位成 `02 00 00`

## 验证状态

- `verified = true`：17 R4。灯区表与掩码已在真机逐盏点亮核对（11 盏全对）。
- 其余机型：灯区/掩码/调色板/默认主题都来自官方资源文件，**未上机验证**，
  在机型库里标「未验证」，只作对照，不参与颜色下发。

## 主题怎么用

预设面板的「AWCC 自带主题」把 13 套预置主题列出来，点一下就走
`AWCCThemeBridge.zoneActions(from:)` 折成每区动作：

- Pulse(2) → 脉冲
- Morph(1) → 渐变（首色 → 次色）
- 只有 SetColor(3) 且一区多种颜色 → 压成渐变（首色 → 末色）
- 只有 SetColor 且同色 → 常亮

高级主题本来是逐帧动画序列，压成一条动作是当前实现的边界；要做逐帧回放需要给
`ZoneAction` 加时间轴，那是下一版的事。
