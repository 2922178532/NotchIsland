# 第三方代码许可

NotchIsland 本身以 MIT 协议发布，许可证见 [LICENSE](LICENSE)。

本项目还包含以下第三方开源代码，其原始版权归各自作者所有，
下面完整收录它们的许可证文本。

---

## JuiceFlow

- 项目地址：https://github.com/imadhy/juice-flow
- 作者：Imad El Hitti
- 协议：MIT
- 使用范围：`Sources/NotchIsland/JuiceFlow/` 目录下的全部代码，即功耗监测功能的
  电池读数、进程采样、powermetrics 集成、历史记录、异常耗电告警与仪表盘界面。
- 修改说明：移植到 NotchIsland 时移除了自动更新与独立菜单栏入口，
  调整了窗口生命周期以适配刘海岛的展开收起，界面文案改为中文。

```
MIT License

Copyright (c) 2026 Imad El Hitti

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
