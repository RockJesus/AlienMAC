# AlienFX 线缆协议（USBPcap 实抓确认）

> 面向开发者的实现说明。用户使用只要看 README。
>
> 证据来源：Windows 侧用 USBPcap 抓 `AlienwareAlienFXController.exe` 启动瞬间发出的 HID 输出报文
> （17 R4 / VID `0x187C` PID `0x0530`，报文 12 字节），并在真机上肉眼复核。

## 1. 寻址：chain = ZoneID，mask = 1 << LedID

颜色帧结构（11 字节数据，前面由 HID 层补 Report ID `0x02`）：

```
02 03 <chain> <maskH> <maskM> <maskL> <R> <G> <B>
```

- `chain` 是 AWCC 模型 XML 里的 **ZoneID**（17 R4 为 2..12），不是 Groups 的序号
- `mask` 是 **1 << LedID**（LedID 来自 `Leds` 表），三字节大端

17 R4 的 11 条与抓包逐条一致：

| ZoneID | LED | 帧 |
|---|---|---|
| 2 | 键盘左 (LedID 3) | `02 03 02 00 00 08` |
| 3 | 键盘中左 (2) | `02 03 03 00 00 04` |
| 4 | 键盘中右 (1) | `02 03 04 00 00 02` |
| 5 | 键盘右 (0) | `02 03 05 00 00 01` |
| 6 | 顶盖头像 (5) | `02 03 06 00 00 20` |
| 7 | 屏幕 Logo (6) | `02 03 07 00 00 40` |
| 8 | 触摸板 (7) | `02 03 08 00 00 80` |
| 9 | 左灯带 (10) | `02 03 09 00 04 00` |
| 10 | 右灯带 (11) | `02 03 0A 00 08 00` |
| 11 | 屏下左 (12) | `02 03 0B 00 10 00` |
| 12 | 屏下右 (13) | `02 03 0C 00 20 00` |

宏键 `1x5 Macro Keys`（LedID 14）只有亮度位，无颜色通道；ZoneID 1 的 Power 区没有 LED 条目。

## 2. 必须包在写会话里

裸发 `02 03` 设备不执行（写 API 返回成功但灯不变，这就是长期误判的根源）。AWCC 的顺序是：

```
02 07 04                    复位
02 06 00                    查状态
02 08 01                    写开始（DataID 01 = 实时颜色）
  02 03 …（可多条）
02 08 01                    写结束
02 04 00                    锁存
02 09 00                    保存
02 05 00                    提交
```

其它已确认帧：定时 `02 0E 00 <lo> <hi>`、过渡 `02 1D 03`、清剩余区 `02 03 0D 0F 02 10 00 00 00`。

## 3. 设备就绪序列

设备必须先跑完 AWCC 启动时那 **134 帧**初始化，才认实时颜色。序列随 App 分发为
`Resources/awcc-device-init.json`（schema `alienmac.awcc-device-init/1`，逐帧 `bytes`），
设备连上后由 `AlienFXHIDManager.replayDeviceInit` 自动重放；资源缺失时降级为普通直连并在日志里标注。

## 4. 亮度与电池位

```
02 1C <20..100> <mode>
```

- `mode=01` 全局亮度
- `mode=00` 仅电池档（AC 供电时不变暗，设备存两套值；对应 `NO_DIM_LIGTHS_ON_BATTERY_PERC=100`）
- `mode=02`（PerZone）在 `02 1C` 上无效；`mode=03` 越界被忽略

亮度状态读回恒为 `10 00 00 00 00 00 00 00 34 42 F2 02`，当前亮度只能靠肉眼/光照判断。

## 5. 全机型坐标表

`Resources/awcc-wire-mapping.json` 由 `scripts/build_wire_mapping.py` 从 `awcc-catalog.json`
（AWCC 安装目录内嵌模型 XML）生成，覆盖 31 个机型，每条含 `chain / mask3Hex / frameTemplate`。
重新生成：

```bash
python3 scripts/build_wire_mapping.py
```

17 R4 的输出必须与上表 11 条一致，这是每次改生成器后的回归基线。
