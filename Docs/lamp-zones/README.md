# 17 R4 灯区定义（唯一口径）

来源：AWCC 模型资源 `AlienFX.ModelResources.Alienware17R4.dll` 内嵌 XML（Leds / Groups / ZonesGroups）。
`LedID` 就是硬件掩码位，`LedIndex` 就是 LightFX 灯号。**实机只有 12 盏灯**，位 4/8/9 与 15 以上都是死位。

## 12 盏灯

| AWCC Group | 组名 | 掩码位 | LightFX | `.ath` ZoneID |
|---|---|---|---|---|
| 1 | Keyboard Left | 3 | 3 | 2, 20 |
| 2 | Keyboard MiddleLeft | 2 | 2 | 3, 21 |
| 3 | Keyboard MiddleRight | 1 | 1 | 4, 22 |
| 4 | Keyboard Right | 0 | 0 | 5, 23 |
| 5 | Alienhead | 5 | 4 | 6, 24 |
| 6 | Logo | 6 | 5 | 7, 25 |
| 7 | Touchpad | 7 | 6 | 8, 26 |
| 8 | Power | —（0x08 状态块） | — | 1, 13–19 |
| 10 | Tron Left | 10 | 7 | 9, 27 |
| 11 | Tron Right | 11 | 8 | 10, 28 |
| 12 | LCD Panel Left | 12 | 9 | 11, 29 |
| 13 | LCD Panel Right | 13 | 10 | 12, 30 |
| — | 1x5 Macro Keys | 14 | — | —（`OnlyForBrightnessSupport=true`，只吃亮度） |

合并掩码 `0x007CEF`。

## 三条硬约束

- **亮度 20..100**：模型声明 `MinimumBrightness=20 / MaximumBrightness=100`，0 视为关灯。
- **面板编号 = Group ID，跳过 9**：界面热点是 `hotSpot01..08`、`hotSpot10..13`，不是 1–12 连号。
- **电源按钮不是颜色灯**：属于 Group08，需 `0x08 state → reset → color → 0x04 loop → 0x09 save` 四个状态各存一次。

## 原始定义摘录

```xml
<Leds>
  <Led LedIndex="0"  LedID="0"   Description="Keyboard Right"        Position="0x00000004"/>
  <Led LedIndex="1"  LedID="1"   Description="Keyboard Middle Right" Position="0x00000002"/>
  <Led LedIndex="2"  LedID="2"   Description="Keyboard Middle Left"  Position="0x00000002"/>
  <Led LedIndex="3"  LedID="3"   Description="Keyboard Left"         Position="0x00000001"/>
  <Led LedIndex="4"  LedID="5"   Description="Alienhead"             Position="0x02000000"/>
  <Led LedIndex="5"  LedID="6"   Description="Logo"                  Position="0x00000010"/>
  <Led LedIndex="6"  LedID="7"   Description="Touchpad"              Position="0x00000002"/>
  <Led LedIndex="7"  LedID="10"  Description="Left Tron"             Position="0x00000001"/>
  <Led LedIndex="8"  LedID="11"  Description="Right Tron"            Position="0x00000004"/>
  <Led LedIndex="9"  LedID="12"  Description="LCD Panel Left"        Position="0x00000008"/>
  <Led LedIndex="10" LedID="13"  Description="LCD Panel Right"       Position="0x00000020"/>
  <Led LedIndex="11" LedID="14"  Description="1x5 Macro Keys"        Position="0x00000001" OnlyForBrightnessSupport="true"/>
</Leds>
```

ZonesGroups：ZoneID 1→Group8，2→1，3→2，4→3，5→4，6→5，7→6，8→7，9→10，10→11，11→12，12→13；
13–19→Group8；20–30 重复 1–13 的归并。

设备选项：`SupportGoDark=true`、`GoDarkShortcut=[Fn+F12]`、`GoDarkShortcutKeyCode=129`、`SupportKeypad=true`。
