# 刘海岛 · NotchIsland

**[English](README.en.md)**

把 MacBook 的刘海变成一个多功能岛：**文件中转**、**找回被遮挡的菜单栏图标**、**实时功耗监测**。

[![最新版本](https://img.shields.io/github/v/release/2922178532/NotchIsland?include_prereleases&label=最新版本&color=black)](https://github.com/2922178532/NotchIsland/releases/latest)
![平台](https://img.shields.io/badge/平台-macOS%2014%2B-black)
![架构](https://img.shields.io/badge/架构-Apple%20Silicon-black)
![依赖](https://img.shields.io/badge/第三方依赖-无-black)
[![许可证](https://img.shields.io/badge/许可证-MIT-black)](LICENSE)

**[下载最新版本 →](https://github.com/2922178532/NotchIsland/releases/latest)**

<div align="center">
  <img src="docs/images/expanded.png" width="760" alt="展开的刘海岛面板：文件卡片、被刘海挡住的图标行、实时功耗">
</div>

## 亮点

- 把文件扔进刘海暂存，切到任意应用再拖出来，不占桌面也不用来回切窗口
- 复制的文件、图片、文本和链接可以自动收进刘海岛，当成一份能往外拖的剪贴板历史
- 找回被刘海挤掉的菜单栏图标，点一下就能弹出它原本的菜单
- 悬停刘海直接看到整机功耗，内置完整的功耗仪表盘
- 完全离线运行，没有任何网络请求、遥测或更新检查
- 零第三方依赖，纯 Swift 实现，应用体积约 3 MB

## 快速开始

1. 从 [Releases](https://github.com/2922178532/NotchIsland/releases/latest) 下载 `.dmg`
2. 打开后把 **刘海岛** 拖进「应用程序」文件夹
3. 首次打开若被系统拦截，在访达里**右键点击应用 → 选择「打开」**

装好后菜单栏会出现一个托盘图标，鼠标移到刘海上即可展开面板。文件中转和快捷键开箱即用，**不需要任何权限**；想用菜单栏图标功能，再按提示授予「辅助功能」权限即可。

预编译包目前只提供 **Apple Silicon（arm64）** 版本，Intel 机型请自行编译。没有物理刘海的机型（或外接显示器）也能用，程序会在屏幕顶部正中模拟一块与菜单栏等高的区域作为岛。

<details>
<summary><b>从源码构建</b></summary>

需要 macOS 14+ 和 Swift 5.9 或更新的工具链（装 Xcode 或 Command Line Tools 即可，不需要完整的 Xcode）。

```bash
git clone https://github.com/2922178532/NotchIsland.git
cd NotchIsland
./build.sh                 # 产物在 dist/刘海岛.app
open dist/刘海岛.app
```

`./build.sh debug` 可以构建调试版本。若要用自己的开发者证书签名，设置环境变量后再构建：

```bash
NOTCHISLAND_SIGN_IDENTITY="Developer ID Application: 你的名字 (TEAMID)" ./build.sh
```

</details>

<details>
<summary><b>权限说明</b></summary>

| 权限 | 是否必须 | 用途 |
| --- | --- | --- |
| 辅助功能 | 使用菜单栏图标功能时必须 | 枚举各应用的状态栏项并模拟点击 |
| 屏幕录制 | 可选 | 把控制中心模块（显示器、声音等）截成真实图标；不给则显示为控制中心的应用图标，功能不受影响 |
| 通知 | 可选 | 异常耗电告警 |
| 管理员密码 | 可选，仅一次 | 开启功耗「精确模式」时创建一条仅限 `powermetrics` 的 sudo 规则 |

如果 Gatekeeper 拦得比较死，也可以手动去掉隔离属性：

```bash
xattr -dr com.apple.quarantine "/Applications/刘海岛.app"
```

> 由于是 ad-hoc 签名，**每次重新构建后系统会把它当成一个新应用**，需要到「系统设置 → 隐私与安全性 → 辅助功能」里删掉旧记录重新授权。用固定证书签名可以避免这个问题。

</details>

## 使用

| 操作 | 效果 |
| --- | --- |
| 鼠标移到刘海 | 岛先轻微放大，停留片刻后展开成完整面板 |
| 拖文件靠近刘海 | 岛立刻展开并高亮，松手即存入 |
| 从卡片往外拖 | 把该文件复制到目标应用 |
| 拖住底部的把手 | 一次取走当前列表里的全部内容 |
| 双击卡片 | 用默认程序打开 |
| 右键卡片 | 打开 / 复制到剪贴板 / 在访达中显示 / 显示原始位置 / 移除 |
| `⌃⌥Space` | 呼出 / 收起刘海岛 |
| `⌃⌥C` | 把剪贴板里的内容存进刘海岛 |

除了文件，从浏览器拖来的图片、选中的文本、网页链接也会被存成对应的文件。拖出时一律是**复制**语义，目标应用拿到的是副本，刘海岛里的内容不会被移走。

<details>
<summary><b>更多界面细节</b></summary>

面板右上角依次是功耗徽章、复制全部、清空、固定展开、设置、收起。点**图钉**可以让面板保持展开，鼠标移开也不收起。

刘海岛里同时存在两种以上类型的内容时，面板上方会出现**分类筛选**（全部 / 文件 / 图片 / 文本），底部的「取走全部」把手会跟随当前筛选。

快捷键用 Carbon 注册，不需要「辅助功能」权限。如果组合已被别的程序占用，菜单里对应项会标注「快捷键被占用」。想更换，改 `Sources/NotchIsland/Core/HotKeyManager.swift` 末尾的两个 `Shortcut` 定义即可。

</details>

## 剪贴板

除了拖拽，刘海岛也能接管剪贴板。

**手动存入**：按 `⌃⌥C`，当前剪贴板里的内容立刻进刘海岛，文件、截图、选中的文本、网页链接都支持。

**自动收存**（默认关闭）：在菜单里打开「自动收存剪贴板内容」之后，你每次复制的东西都会自动存进来，相当于一份可以直接往外拖的剪贴板历史。文本会渲染成便签式卡片显示正文，链接显示域名，不用打开就知道是什么。

自动收存做了几件事来避免添乱：跳过密码管理器标记为私密的内容、排除刘海岛自己的暂存目录以免自我循环、连续复制同一内容只存一次、单次最多收 10 个文件。开关关闭期间它也在跟踪剪贴板变化，所以打开开关不会把你很久之前复制的东西一次性倒进来。

反过来也可以：面板右上角的按钮能把当前全部内容一次复制到剪贴板，右键单个卡片则只复制它。

<details>
<summary><b>菜单栏设置项</b></summary>

点菜单栏的托盘图标（或岛上的齿轮）打开设置菜单：

- **自动清理**：一直保留 / 1 / 3 / 7 / 30 天，默认 7 天。启动时和之后每小时检查一次，删掉超期内容。
- **悬停展开延迟**：立即 / 0.1 / 0.25 / 0.5 / 1 秒，默认 0.25 秒。
- **自动收存剪贴板内容**：默认关闭。开启后会自动把你复制的文件和图片收进刘海岛，详见下面的[数据与隐私](#数据与隐私)。
- **存入提示音**：九种系统音效可选（含关闭），默认「叮 · Tink」，选中即试播。
- **显示被刘海挡住的图标**：菜单栏图标功能的总开关，默认开启。
- **重新显示「不再显示」的图标**：清空你右键排除过的图标名单。
- **全屏应用时隐藏**：有应用进入全屏就把岛收起来让位，默认开启。用快捷键或菜单主动呼出时会临时忽略。如果你本来就把菜单栏设成了自动隐藏，这个让位功能会自动失效。
- **隐藏待机指示条**：只隐藏收起态那条渐变横条，让刘海保持原生外观；悬停、拖拽、快捷键交互都不受影响。
- **开机时自动启动**：要求应用位于「应用程序」文件夹。
- **移动到「应用程序」文件夹**：一键把自己复制过去并重启，完成后此项自动隐藏。

</details>

<details>
<summary><b>被刘海挡住的菜单栏图标</b></summary>

展开面板的「刘海下」一行会列出所有被刘海吞掉的状态栏图标（含控制中心模块）：

- **左键**：等同于点击菜单栏上的原图标——岛先收起让出屏幕顶部，该图标的菜单原地弹出，全程不会移动你的鼠标。
- **右键**：弹出操作菜单（打开菜单 / 激活应用 / 退出应用 / 不再显示此图标）。「退出」对图标看不见的后台应用尤其有用。
- **实时状态**：电量、功耗、温度这类以数字开头的状态文字（例如功耗计的「12.3 W」）会直接显示在图标旁边，其余信息悬停查看。

几点说明：

- 第三方应用被吞掉后，系统会把它的图标窗口清零，所以这里显示的是应用图标而不是菜单栏里的原样图标，不影响点击。
- 应用自身的右键菜单无法转发：被吞的图标在系统里没有有效屏幕位置，辅助功能层也只暴露「按下」这一个动作。
- 扫描在后台并发进行（每个进程 250ms 超时），实测几十个应用约 1 秒完成，期间显示「正在扫描菜单栏…」。

</details>

<details>
<summary><b>功耗监测</b></summary>

功耗部分整合自 MIT 协议的 [JuiceFlow](https://github.com/imadhy/juice-flow)（中文版见 [JuiceFlow-Chinese](https://github.com/2922178532/JuiceFlow-Chinese)），去掉了自更新和独立菜单栏入口。

- **悬停刘海**：岛下沿显示当前系统功耗（读取 SMC 的 `PSTR` / `PPBR` 传感器，无需任何权限）和暂存的文件数。
- **仪表盘**：点岛上的功耗徽章打开，包含电量环、剩余续航估计、能耗影响排名、24 小时历史、今日耗电排行。
- **精确模式**：可在仪表盘里开启 Apple 官方 `powermetrics` 测量（真实瓦数、GPU、系统进程）。首次开启需输入一次管理员密码，创建一条**仅限 powermetrics** 的 sudo 规则，之后不再询问；设置里可以随时移除该规则。
- **告警**：用电池时某个应用持续异常耗电会收到通知，灵敏度在「功耗监测设置…」里调。
- 电池读数每 3 秒一次（IOKit，开销极小）；进程采样在仪表盘关闭后自动降为 30 秒一档。

</details>

## 数据与隐私

NotchIsland **完全离线运行**，没有任何网络请求、遥测或更新检查。所有数据只存在你自己的机器上：

```
~/Library/Application Support/NotchIsland/
├── index.json          # 暂存内容的元数据
└── Items/<UUID>/<原文件名>

~/Library/Application Support/JuiceFlow/
└── history.sqlite      # 功耗历史
```

拖入的文件会被**复制**一份到这里，所以原文件后续被移动或删除都不影响刘海岛里的副本。相应地，刘海岛里的内容会占用磁盘空间，默认 7 天后自动清理。菜单里的「打开暂存文件夹」可以直接查看。

如果开了[自动收存剪贴板](#剪贴板)，你复制的内容也会写进同一个目录。程序会遵守 macOS 的 `ConcealedType` / `TransientType` 约定跳过密码管理器的内容，但请注意，**未被来源应用正确标记的敏感文本仍会以明文落盘**——如果你经常复制密码、密钥或令牌，建议让这个开关保持关闭（默认就是关的）。

## 已知限制

- 预编译包只有 Apple Silicon 版本，Intel 机型需自行编译，且未经充分测试。
- ad-hoc 签名会触发 Gatekeeper 提示，且每次重建后需要重新授予辅助功能权限。
- 没有自动更新，新版本需要手动下载。
- 目前是预览版本，尚未建立自动化测试。遇到问题欢迎提 [Issue](https://github.com/2922178532/NotchIsland/issues)。

<details>
<summary><b>排查</b></summary>

查看程序识别到的刘海参数是否正确：

```bash
"/Applications/刘海岛.app/Contents/MacOS/NotchIsland" --diagnose
```

会打印每块屏幕的尺寸、安全区域，以及计算出的岛依附矩形。

想在不移动鼠标的情况下看展开效果，或确认快捷键是否注册成功：

```bash
NOTCHISLAND_AUTOEXPAND=1 NOTCHISLAND_DEBUG=1 "/Applications/刘海岛.app/Contents/MacOS/NotchIsland"
```

状态栏图标识别不对时，用这两个诊断脚本查看系统的真实状态（需要在有辅助功能权限的终端里运行）：

```bash
swift scripts/menubar-diagnose.swift   # 窗口层面：哪些状态栏窗口不在屏幕上
swift scripts/ax-diagnose.swift        # 辅助功能层面：各应用状态栏项的位置
```

改了 `scripts/make-icon.swift` 之后重新生成应用图标：

```bash
swift scripts/make-icon.swift
```

</details>

<details>
<summary><b>代码结构</b></summary>

纯 Swift 实现，零第三方依赖，用 Swift Package Manager 构建。

```
Sources/NotchIsland/
├── App/            程序入口、菜单栏、全局快捷键、定时清理
├── Core/
│   ├── ScreenGeometry.swift    刘海位置与尺寸的识别
│   ├── NotchModel.swift        岛的状态、尺寸与窗口几何
│   ├── Preferences.swift       偏好设置
│   └── HotKeyManager.swift     全局快捷键
├── Window/
│   ├── NotchPanel.swift            无边框浮动面板
│   ├── NotchWindowController.swift 鼠标跟踪、状态切换、全屏让位
│   └── DropContainerView.swift     接收拖入的内容
├── Shelf/
│   ├── ShelfStore.swift         暂存文件的存储、元数据与过期清理
│   ├── PasteboardImporter.swift 粘贴板内容解析（拖入与快捷键共用）
│   └── ClipboardWatcher.swift   剪贴板自动收存
├── MenuBar/
│   ├── MenuBarItemMonitor.swift    扫描被刘海吞掉的状态栏图标
│   └── MenuBarPermissions.swift    辅助功能 / 屏幕录制权限
├── Power/
│   └── PowerCenter.swift   功耗服务容器与仪表盘窗口
├── JuiceFlow/      整合自 JuiceFlow 的功耗监测（SMC、进程采样、历史、告警、界面）
└── UI/             SwiftUI 界面
```

两个关键设计：

1. **窗口尺寸跟随状态变化。** 收起时窗口只覆盖物理刘海，那块区域本来就点不到，不会干扰任何操作；只有展开时窗口才变大。切换过程中窗口会先扩到变化前后的并集，避免动画被窗口边界裁掉。
2. **岛比刘海大的时候，鼠标一离开就让事件穿透**，这样展开状态下的面板不会挡住菜单栏的点击。收起态则始终接收事件，否则感知不到拖进来的文件。

</details>

## 计划中

- 快捷键组合支持在界面里自定义
- 剪贴板历史
- 暂存项手动排序与分组

## 致谢

功耗监测部分移植自 [Imad El Hitti](https://github.com/imadhy) 的 [JuiceFlow](https://github.com/imadhy/juice-flow)，
该项目以 MIT 协议发布，版权归原作者所有。`Sources/NotchIsland/JuiceFlow/` 下的代码即来源于此。

## 许可证

NotchIsland 本身以 [MIT](LICENSE) 协议发布。项目包含的第三方代码及其原始许可证见
[THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md)。
