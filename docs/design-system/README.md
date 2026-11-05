# JamReader 设计系统

JamReader 当前界面的信息架构、视觉 token、组件规范、页面稿与实现取舍。书库首页汇总继续阅读、集合页快捷筛选已接入；iPhone Duo 的窗口适配已接入，阅读器折痕几何等限制见 [实现取舍与能力边界](05-batches.md)。

## 与其它文档的分工

| 文档 | 负责 |
| --- | --- |
| [design-requirements.md](../design-requirements.md) | 业务需求、数据边界、删除后果、必须保留的阅读器行为（做什么、不能改什么） |
| 本目录 | 界面规则：信息架构、入口安排、视觉 token、组件与页面；实现与静态稿的差异及原因 |
| [ui-guidelines.md](../ui-guidelines.md) | 长期有效的通用 UI 要求与检查清单 |

数据边界、删除后果和阅读器行为契约由 `design-requirements.md` 负责；页面结构、入口位置、视觉数值由本目录负责。文档与代码冲突时核对实现并修正文档，不把静态稿中的控件当作已有能力。

## 目录

| 文件 | 内容 |
| --- | --- |
| [00-foundations.md](00-foundations.md) | 视觉与文案基础：颜色、字体、间距、形状、动效、状态、图标（SF Symbols 对照）、固定用词、无障碍 |
| [01-requirements.md](01-requirements.md) | 设计决策的依据与负责文档 |
| [02-architecture.md](02-architecture.md) | 信息架构、当前入口安排与页面复用 |
| [03-reader.md](03-reader.md) | 阅读器：保护范围、工具布局、显示面板控件可见性 |
| [04-implementation.md](04-implementation.md) | 落地到代码：token → Swift、组件 → 文件 |
| [05-batches.md](05-batches.md) | 实现取舍与能力边界：与静态稿的差异、原因、尚未接入的环境适配 |
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

- 预览是 HTML 静态示意，用来对照布局、层级、文案和状态；以组件 README 与实现边界为准。静态稿仍含未接入的能力，不是 App 截图，不要逐像素复刻网页。
- 预览中的图标是网页手绘替身，实际使用 `00-foundations.md` 图标表里的 SF Symbols。
- 封面图是占位色块，书名为虚构示例。
- 黄色虚线框标出的“原样保留”是受保护组件，只按代码数值示意，不是新设计。

## 维护

- 界面行为或入口变更时，同步更新负责文档和代码。
- 改 `tokens.json` 后运行 `python3 docs/design-system/build_tokens_css.py` 重新生成 `tokens.css`。
- 系统控件或数据能力导致实现与页面稿不同时，在组件规则中链接到 [实现取舍与能力边界](05-batches.md)，不追加批次流水。
