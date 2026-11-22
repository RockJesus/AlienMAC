# AlienMAC — Alienware 灯光控制 for macOS

把 Alienware 17 R4 的 AlienFX 灯效搬进 macOS 菜单栏。纯用户态实现，基于 IOKit HID，不需要 kext、不需要关闭 SIP，专门为黑苹果环境打磨。

![platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue) ![swift](https://img.shields.io/badge/Swift-5.9-orange) ![license](https://img.shields.io/badge/license-MIT-green)

## 功能

- **13 个灯区独立控制**：顶盖头像、屏幕 Logo、电源键、触摸板、键盘四区、快捷键区、前后灯带
- **触摸板细调**：整面背光与四薄条边光分开控制——各自可跟随灯区色或单独指定颜色，整面亮度与边光强度独立调节，边光可整条关闭，一键恢复默认
- **单键映射**：95 个按键（主键区 67 + 数字键盘 20 + 导航键 3 + 宏键 5）逐个上色，3D 键盘与映射面板实时同步；17 R4 硬件只有 4 区背光，单键颜色在本机预览，下发时取该键所在分区出现最多的颜色
- **3D 实机模型交互**：按 424×332×30 mm 真实尺寸参数化建模的 17 R4，直接在灯光所在的立体位置点选，支持旋转、缩放、开合盖、一键视角
- **七种灯效**：常亮、脉冲、渐变、呼吸（硬件），外加光谱、光波、扫描三种软件逐帧灯效，速度可调；并内置 8 个 AWCC 对齐主题与 16 色预设色板
- **自定义预设**：任意配色 + 效果 + 范围组合，一键保存、随时切换，重启不丢
- **启动恢复**：打开应用并连上控制器后，自动还原上次的灯光状态
- **登录自启**：开机 / 登录后自动接管灯光；已签名的 app 走系统「登录项」，未签名的开发版自动回退到 LaunchAgent
- **全局快捷键**：`⌥⌘L` 开关灯、`⌥⌘↑↓` 调节亮度，任何界面都能用，不需要辅助功能权限
- **菜单栏常驻**：快捷颜色、我的预设、亮度滑杆、开灯关灯
- **屏幕 Logo 亮度补偿**：导光条偏暗时单独提亮，系数可调
- **检查更新**：启动自动检查 GitHub 最新 Release（12 小时一次，可关），也可手动检查；有新版本时顶栏出提示，可直接下载 dmg
- **逐灯测试**：按 bit 依次点亮，快速核对灯区映射
- **实时 HID 日志**：全部收发字节可见，方便调试协议

## 硬件参数

| 项目 | 值 |
|------|-----|
| 设备 | Alienware 17 R4 (2016) |
| 控制器 | AlienFX USB HID |
| VID / PID | `0x187C` / `0x0530` |
| 协议 | APIv3（12 字节 HID Report） |
| Report ID | `0x02` |
| 颜色深度 | 8-bit per channel |
| 灯区 | 最多 24 位掩码（本机实测 13 个） |

## 安装

### DMG（推荐）

下载 [Releases](https://github.com/RockJesus/AlienMAC/releases) 里的 `AlienMAC-x.y.z.dmg`，拖进「应用程序」即可。首次打开若被 Gatekeeper 拦截，右键 → 打开，或在终端执行：

```bash
xattr -dr com.apple.quarantine /Applications/AlienMAC.app
```

### 从源码编译

```bash
brew install xcodegen
git clone https://github.com/RockJesus/AlienMAC.git
cd AlienMAC
./build.sh          # 编译 Release
./create_dmg.sh     # 编译并打包 DMG
```

产物在 `build/Build/Products/Release/AlienMAC.app`。Xcode 里开发直接 `open AlienMAC.xcodeproj`，Cmd+R 运行。

签名使用 Ad-hoc（Sign to Run Locally），无需 Apple 开发者账号。请把 `AlienMAC.app` 放进 `/Applications`：`SMAppService` 只在已签名、且位于应用程序目录时才会登记登录项；从 `build/` 目录直接运行未签名产物时，登录自启会退回 LaunchAgent 方式。

## 使用

**触摸板细调**：顶栏点「触摸板」或直接在 3D 里点触摸板，右侧面板会出现「触摸板细调」。整面背光与四薄条边光分开控制：勾选「整面跟随灯区色」时整面跟灯区颜色走，取消后可用色块单独指定；「整面亮度」按全局亮度的百分比缩放。「边光」同理，另有「显示」开关可整条关掉，`恢复默认` 把六项参数一起复位。所有改动即时生效并落盘，硬件侧仍按触摸板这一个灯区下发整面颜色。

**单键映射**：顶栏点「按键」打开键盘按键映射，在键帽网格里点选任意按键（可多选），再从左侧主颜色挑色——选中的按键立刻记下当前颜色，只作用于这些键，同区其它键不受影响；3D 键盘上对应的键会同时变色，方便逐键排布配色。`用主颜色填充` 把当前颜色刷到所有被选中的键，`清除单键配色` 让它们回到所属灯区颜色。17 R4 的硬件只有四区背光（左、中、右、数字键盘），所以单键颜色仅在本机预览，真正下发时按该键所在分区里出现最多的颜色走——想让硬件接近预览效果，就把同区的键刷成同一种颜色。

**开机键功能**：设置页新增「开机键」分组，把 3D 机身键盘上方那颗外星人头按键拆成单击 / 双击 / 长按三种触发，动作可选「无动作（只选灯区）/ 锁定屏幕 / 进入睡眠 / 关闭全部灯光 / 重新启动 / 关机」。默认三个都是「无动作」，所以点它仍然只是选中电源键灯区上色，不会误触关机；重启与关机默认先弹窗二次确认（可在同一分组里关掉）。单击与双击互斥：给双击设了动作，单击会自动回到「无动作」。灯效侧可以「跟随灯区颜色」，也可以单独指定颜色与亮度，只对外圈光与外星人头图标生效，0% 即熄灭。

**灯光控制**：在 3D 模型上点击灯光所在的部位（键盘、灯带、电源键、触摸板整面、顶盖 Logo）即可选中灯区，可多选；也可以点底部的灯区胶囊。选中后挑主颜色、效果（渐变 / 呼吸会出现次色与速度），改动即时生效、自动保存，不用再点应用；没选用任何灯区时调色作用于全部灯区。

### 3D 模型怎么用

| 操作 | 效果 |
|------|------|
| 左键拖动 | 自由旋转机身：左右拖绕机身转，上下拖调俯仰（向上拖压低视角看正面，向下拖抬起视角看键盘顶面），拖动时鼠标变抓手 |
| 滚轮 / 触控板双指 | 缩放 |
| 左键点击灯区 | 选中 / 取消该灯区（`⌘` 或直接点多处即多选） |
| 左键点击屏幕画面 | 用系统默认浏览器打开 rockjesus.cn |
| 顶栏「开合盖」 | 盖子开合动画，合盖时可编辑顶盖头像与屏幕 Logo |
| 顶盖机位 + 合盖 | 顶盖 A 面为真实 Alienware 头标，可点选「顶盖头像」灯区调色 |
| 顶栏「正面 / 俯视 / 顶盖」 | 三个预设机位，点击后平滑过渡 |
| 顶栏「全选 / 清空」 | 底部胶囊旁，一次性选中全部灯区或清空选择 |

键盘按实机做了键帽漏光处理：键帽本体是哑光黑，背光只从键缝和键帽四周一圈透出来，而不是整块键帽发光；机身左侧与右侧补了斜切散热口，键盘上方加了一条抬高台面，电源键就装在这条台面上（这也是它之前被后部散热腔整个盖住的原因，已一并修正）。

模型依据官方规格（424 × 332 × 29.99 mm、4.42 kg、17.3 英寸屏幕、103 键四区 RGB 键盘）按真实比例建模，包含楔形前缘、后部散热腔与排气格栅、铰链、触控板、数字键盘与左侧宏键列。它不是厂商提供的资产，而是随本项目一起开源的参数化模型，因此可随灯区定义自由演进。

**预设主题**：内置 18 套主题（含 8 套 AWCC 对齐主题）一键应用；调好想要的灯光后点「保存当前」，起个名字，就出现在「我的预设」和菜单栏里。右键预设可以删除。

**设置**：启动恢复、登录自启、全局快捷键开关、屏幕 Logo 补偿系数、开机键动作与灯效、触摸板细调都在这一页。

**调试**：逐灯测试会按 bit 0-15 依次点亮红灯，用来核对哪一位对应哪个物理灯区；HID 日志会打印每一次发送的原始字节。

### 快捷键

| 快捷键 | 动作 |
|--------|------|
| `⌥⌘L` | 灯光开 / 关切换 |
| `⌥⌘↑` | 亮度 +10% |
| `⌥⌘↓` | 亮度 −10% |

### 配置文件

所有设置保存在 `~/Library/Application Support/AlienMAC/settings.json`（亮度、上次灯光、自定义预设、启动行为）。删除该文件即可恢复默认。

## 黑苹果前置检查

AlienFX 控制器挂在主板内部 USB 总线上，黑苹果需要确认端口已正确驱动：

```bash
system_profiler SPUSBDataType | grep -A 5 -i alien
ioreg -p IOUSB -l | grep -i 187c
```

看不到设备时，用 [USBMap](https://github.com/corpnewt/USBMap) 或 [USBToolBox](https://github.com/USBToolBox/tool) 重新定制 USB 端口，确保 AlienFX 所在的内部 USB 2.0 端口（通常是 HSxx）已启用。

## 故障排除

**显示未检测到控制器** — 先确认上面的 USB 检查；点击「重新扫描」；确认系统报告里存在 VID `0x187C` 的设备。

**连上了但灯没反应** — 点「重置控制器」，再看调试日志里是否有 TX 行。APIv3 控制器短时间接收过多请求会假死，完全断电（关机拔电源 10 秒）可恢复。

**某个灯区控制了错误的灯** — 用逐灯测试记录实际 bit，然后改 `Sources/Models/AlienFXTypes.swift` 里 `LightZone` 的位定义。

**登录自启点不动 / 打开后自动弹回** — 旧版本构建时关闭了代码签名，`SMAppService` 无法登记，开关会瞬间复位。v1.1.1 起构建改为 Ad-hoc 签名，并把 app 放进 `/Applications` 后再打开即可；仍失败时设置页会直接显示原因，并可点「打开登录项设置」手动添加。

## 灯区映射（17 R4 实测）

| bit | 灯区 | 说明 |
|-----|------|------|
| 0 | 数字键盘 | 小键盘区域 |
| 1 | 键盘右区 | |
| 2 | 键盘中区 | |
| 3 | 键盘左区 | |
| 5 | 顶盖头像 | A 面外星人 Logo |
| 6 | 屏幕 Logo | 屏幕下方 Alienware 字样 |
| 7 | 触摸板 | 触摸板整面背光 |
| 8 | 电源按钮 | 需按电源状态块逐个写入 |
| 10 / 11 | 前左 / 前右灯带 | |
| 12 / 13 | 后左 / 后右灯带 | |
| 14 | 快捷键区 | 左侧宏键列 |

不同批次可能存在差异，以逐灯测试结果为准。

## 协议速记（APIv3）

颜色命令 11 字节（不含 Report ID）：

```
[0] opcode  3=常亮 2=脉冲 1=渐变/呼吸
[1] chain   1-255 自增
[2] mask_hi [3] mask_mid [4] mask_lo
[5-7] R1 G1 B1
[8-10] R2 G2 B2
```

常用命令：`0x05` 提交更新、`0x07 0x04` 重置开灯、`0x1C [0-100] 0x01` 亮度、`0x09` 保存到闪存、`0x08 [state]` 切换保存块（电源按钮专用）。每次发送间隔 20-30ms，避免控制器崩溃。

## 项目结构

```
AlienMAC/
├── project.yml                       # XcodeGen 配置
├── build.sh / create_dmg.sh          # 编译与打包
├── Resources/
│   ├── Info.plist
│   ├── AlienMAC.entitlements
│   └── AppIcon.icns
└── Sources/
    ├── AlienMACApp.swift             # App 入口 + 菜单栏
    ├── ContentView.swift             # 3D 主画面 / 玻璃面板 / 预设 / 设置 / 调试
    ├── Models/
    │   ├── AlienFXTypes.swift        # 颜色 / 效果 / 灯区 / 命令码
    │   └── CustomPreset.swift        # 自定义预设模型
    ├── Services/
    │   ├── AlienFXHIDManager.swift   # IOKit HID 通信
    │   ├── AlienFXController.swift   # 高层控制 API
    │   ├── SettingsStore.swift       # 本地持久化
    │   ├── LaunchAtLogin.swift       # 登录项
    │   └── HotKeyCenter.swift        # 全局快捷键
    ├── ViewModels/
    │   └── LightingViewModel.swift
    └── Views/
        └── LaptopSceneView.swift     # 3D 机身建模 + 灯区命中 + 相机与开合
```

## 参考资料

- [T-Troll/alienfx-tools](https://github.com/T-Troll/alienfx-tools) — AlienFX 协议逆向
- [OpenRGB Alienware 文档](https://gitlab.com/OpenRGBDevelopers/OpenRGB-Wiki/-/blob/stable/Device-Documentation/Alienware-AlienFX.md)
- [trackmastersteve/alienfx](https://github.com/trackmastersteve/alienfx) — Linux 版实现

## 许可证

MIT，详见 [LICENSE](LICENSE)。
