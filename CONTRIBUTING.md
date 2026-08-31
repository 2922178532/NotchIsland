# 参与 NotchIsland 开发

欢迎提 Issue 和 Pull Request。这个项目目前由一个人维护，所以流程尽量简单。

## 提 Issue

**报告问题**前请附上这些信息，能省掉一轮来回：

- macOS 版本与机型（是否有物理刘海、是否接了外接显示器）
- NotchIsland 版本（菜单栏图标 → 关于，或用的哪个 Release）
- 复现步骤

如果问题和岛的位置、大小有关，请附上诊断输出：

```bash
"/Applications/刘海岛.app/Contents/MacOS/NotchIsland" --diagnose
```

如果是菜单栏图标识别不对，在已授予「辅助功能」权限的终端里跑：

```bash
swift scripts/menubar-diagnose.swift
swift scripts/ax-diagnose.swift
```

**提功能建议**时说清使用场景，比说清具体实现更有用。

## 开发环境

macOS 14+，Swift 5.9 或更新的工具链（Xcode 或 Command Line Tools 均可，不需要完整 Xcode）。

```bash
git clone https://github.com/2922178532/NotchIsland.git
cd NotchIsland
swift build          # 编译
swift test           # 跑单元测试
./build.sh           # 打包成 dist/刘海岛.app（仅本机架构）
./build.sh debug     # 打包调试版本
NOTCHISLAND_UNIVERSAL=1 ./build.sh   # 通用二进制，发版用；会校验产物确实是双架构
```

不改动鼠标就想看展开效果：

```bash
NOTCHISLAND_AUTOEXPAND=1 NOTCHISLAND_DEBUG=1 .build/debug/NotchIsland
```

## 提 Pull Request

1. 从 `main` 切分支，一个 PR 只做一件事。
2. `swift build` 和 `swift test` 都要通过 —— CI 会在 PR 上跑这两条，外加打包校验。
3. 涉及纯逻辑的改动请补测试。`Tests/NotchIslandTests/` 下已有的四个文件是参考：
   几何计算、粘贴板解析、暂存存储、powermetrics 输出解析。
4. 改了用户可见的行为，顺手更新 `README.md` 和 `README.en.md` 两份。

### 代码风格

没有强制的 formatter，跟着现有代码走即可：

- 缩进 4 空格，行宽控制在 100 列上下。
- 注释写**为什么**，不写**做了什么**；用中文。现有代码里像
  「用左右两块可用区域的宽度反推刘海宽度，避免依赖辅助区域矩形的坐标原点约定」
  这种解释性注释是希望保持的风格。
- 类型和函数用英文命名，面向用户的文案用中文。
- 零第三方依赖是这个项目的硬约束。需要引入依赖的 PR 请先开 Issue 讨论。

### 涉及权限的改动

辅助功能、屏幕录制、`powermetrics` 的 sudo 规则都是敏感面。这类改动请在 PR 里说明：
新增了什么权限需求、能不能做成可选、不给权限时的降级行为是什么。

### 第三方代码

`Sources/NotchIsland/JuiceFlow/` 来自 [JuiceFlow](https://github.com/imadhy/juice-flow)（MIT）。
往这个目录里提改动没问题，但请注意保留原作者版权声明；引入任何新的第三方代码都要同步更新
[THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md)。

## 许可

提交 PR 即表示同意你的贡献以 [MIT](LICENSE) 协议发布。
