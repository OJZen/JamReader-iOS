# JamReader 设计系统（UI/UX 改版）

JamReader iPhone / iPad（含 iPhone Duo）的改版方案：需求整理、信息架构、视觉 token、组件规范、页面稿，以及给实现者的分批实施计划。2026-10-14 定稿；其中两项功能变化（书库首页汇总继续阅读、集合页快捷筛选）已由产品负责人确认。

## 与其它文档的分工

| 文档 | 负责 |
| --- | --- |
| [design-requirements.md](../design-requirements.md) | 业务需求、数据边界、删除后果、必须保留的阅读器行为（做什么、不能改什么） |
| 本目录 | 改版后的界面方案：信息架构、入口安排、视觉 token、组件与页面（怎么做） |
| [ui-guidelines.md](../ui-guidelines.md) | 长期有效的通用 UI 要求与检查清单 |

冲突时：数据边界、删除后果和阅读器行为契约以 `design-requirements.md` 为准；页面结构、入口位置、视觉数值以本目录为准。

## 目录

| 文件 | 内容 |
| --- | --- |
| [00-foundations.md](00-foundations.md) | 视觉与文案基础：颜色、字体、间距、形状、动效、状态、图标（SF Symbols 对照）、固定用词、无障碍 |
| [01-requirements.md](01-requirements.md) | 需求整理：现状问题、已确认的改版决定、二次审查调整、必须画出的状态 |
| [02-architecture.md](02-architecture.md) | 信息架构、入口合并（之前 → 之后）、关键流程、删除 / 移除 / 清理的后果 |
| [03-reader.md](03-reader.md) | 阅读器：受保护组件、可重设计部分、行为契约、显示面板控件可见性 |
| [04-implementation.md](04-implementation.md) | 落地到代码：token → Swift、组件 → 文件 |
| [05-batches.md](05-batches.md) | **分批实施计划**：6 批任务清单、对照卡片、验收标准 |
| [06-iphone-duo.md](06-iphone-duo.md) | iPhone Duo 适配：外屏 / 内屏 / 半折时的布局规则、阅读器与受保护组件的环境适配 |
| `tokens.json` | 唯一的数值来源（颜色含浅 / 深色、字号、间距、圆角、阴影、尺寸） |
| `tokens.css` | 由 `tokens.json` 生成，只供预览页使用，不要手改 |
| `components/<名称>/README.md` | 组件或页面的规则：何时用、需要什么数据、Do / Don't |
| `components/<名称>/preview.html` | 静态示意（`Screen*` 为页面稿，`InformationArchitecture` 为信息架构图） |
| `components/bundle.css` | 预览页的样式，不是 App 代码 |
| `index.html` | 预览总览 |
| `assets/` | 设计示意图片（示意封面、漫画页、App 图标候选）与生成提示词；只用于设计稿，不进 App |

## 查看预览

在浏览器中打开 `index.html`（Safari / Chrome 直接打开本地文件即可），左侧选卡片，右上角切换浅色 / 深色。单独打开某个 `preview.html` 时，可在地址后加 `?theme=dark` 查看深色。

- 预览是 HTML 静态示意，用来对照布局、层级、文案和状态；实现以 SwiftUI / UIKit 系统控件为准，不要逐像素复刻网页。
- 预览中的图标是网页手绘替身，实际使用 `00-foundations.md` 图标表里的 SF Symbols。
- 封面图是占位色块，书名为虚构示例。
- 黄色虚线框标出的“原样保留”是受保护组件，只按代码数值示意，不是新设计。

## 维护

- 设计变更先改本目录，再改代码；不要只改代码。
- 改 `tokens.json` 后运行 `python3 docs/design-system/build_tokens_css.py` 重新生成 `tokens.css`。
- 实施某一批后，如果行为与本目录描述不同（因能力限制保留了现有行为），在对应章节更新说明，避免文档与实现脱节。
