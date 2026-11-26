# AWCC 主题文件（.ath）格式说明

来源：17 R4 上 AWCC 保存的 `Documents\AlienFX\Themes\*.ath`（三份样本，其中两份内容一致）。
`.ath` 不是压缩包，是 .NET `DataSet` 直接序列化出来的 XML：先一整段 `xs:schema`，后面才是数据行。

## 表结构（数据行标签 → 字段）

| 数据行标签 | 字段 | 说明 |
|---|---|---|
| `Theme` | ThemeID / Name / Version / Mode / ActionDuration / Tempo / ReadOnly | 主题本身，`ActionDuration` 是动作时长（秒），`Tempo` 是速度量 |
| `Actions` | ZoneID / ActionID / ActionTypeID / Color1 / Color2 / Duration | **唯一跟灯有关的表**，每行是某区域的一个动作 |
| `ZonesGroups` | ZoneID / GroupID | 区域号 → 官方 Group（1..12 主区域，13..18 电源状态，20..30 重复 1..12） |
| `Zones` | VisualizationID / ZoneID / Name / Loop / Flags / Fixed / ID | 可视化的区域实例 |
| `Groups` | ID / GroupID / Name | 组名表：Group01=Keyboard Left … Group08=Power … Group13=LCD Panel Right（跳过 9） |
| `Leds` | ID / LedID / Name / Description / GroupID | 灯表，`LedID` 是灯序号 |
| `Visualizations` | VisualizationID / Name / VisualizationTypeID / ThemeID / ApplicationName / DeviceID | 默认可视化、AC/DC 各电源状态、新邮件等 |
| `VisualizationTypes` | VisualizationTypeID / Name / Token / Hidden | 1=Default、3=New Email、4=Applications 等 |
| `ActionTypes` | ActionTypeID / Name / PseudoAction | 1=Morph、2=Pulse、3=SetColor、4=Loop、15=PlayPowerStatus |
| `Devices` / `DeviceTypes` | DeviceID / Description / DeviceTypeID / PID / Model / VID | 设备声明，17 R4 为 `Alienware17R4` |

注意：数据行标签没有空格，`Basic Theme`、`Keyboard Left` 这类名字出现在 **Name 字段**里，不是标签名。

## Actions 表怎么读

```xml
<Actions>
  <ZoneID>2</ZoneID>            <!-- AWCC 区域号 -->
  <ActionID>3</ActionID>        <!-- 同区域内的动作顺序 -->
  <ActionTypeID>3</ActionTypeID><!-- 1 渐变 / 2 脉冲 / 3 常亮 -->
  <Color1>#FF00F0F0</Color1>    <!-- ARGB，两位 alpha 在前 -->
  <Color2>#FF000000</Color2>    <!-- 渐变/脉冲的副色 -->
  <Duration>0</Duration>
</Actions>
```

同一区域出现两条 `Morph`（A→B、B→A）时，就是一对来回渐变，取第一条的 `Color1`/`Color2` 当主副色即可。

## 区域号 → 灯区

| ZoneID | 灯区 | Group |
|---|---|---|
| 1 | 电源壳（无颜色通道） | 8 |
| 2 | 键盘左 | 1 |
| 3 | 键盘中左 | 2 |
| 4 | 键盘中右 | 3 |
| 5 | 键盘右 | 4 |
| 6 | 顶盖头像 | 5 |
| 7 | 屏幕 Logo | 6 |
| 8 | 触摸板 | 7 |
| 9 | 左侧灯带 | 10 |
| 10 | 右侧灯带 | 11 |
| 11 | 屏下左灯条 | 12 |
| 12 | 屏下右灯条 | 13 |
| 13–18 | 各电源状态专用区（AC 睡眠/AC 满电/AC 充电/DC 睡眠/DC 工作/DC 低电） | 8 |

## AlienMAC 的读法

`Sources/Services/ATHThemeImporter.swift`：只读 `Theme` 与 `Actions` 两张表，
把 2..12 号区域的颜色/效果转成「每区动作」再走正常下发；1 号与 13..18 号直接跳过。
