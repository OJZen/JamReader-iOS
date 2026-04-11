# JamReader iOS Design Handoff Index

更新时间：2026-04-09

## 0. 当前底座约束

当前 iOS 实现已经切到 App 自管的本地资料库模型，设计和交付时请默认以下前提成立：

- 本地资料库状态统一写入 `AppLibraryV2.sqlite` 与本地资产目录。
- 外部目录只作为漫画内容源，不再兼容桌面 `library.ydb` / `.jamreaderlibrary`。
- 页面语言只表达 `Linked Folder`、`App Managed`、`Read Only` 这类产品语义，不再引入镜像模式或桌面兼容提示。
- `docs/ios-migration-plan.md` 现在是历史归档，不能再作为当前交互与实现口径。

## 1. 推荐阅读顺序

### 1.1 先理解产品和方向

1. `docs/jamreader-ios-product-engineering-spec.md`
2. `docs/ui-design-requirements.md`
3. `docs/jamreader-ios-ui-redesign-blueprint.md`

### 1.2 再开始搭 Figma

4. `docs/jamreader-ios-figma-screen-spec.md`
5. `docs/jamreader-ios-priority-screen-content-spec.md`
6. `docs/jamreader-ios-priority-frame-recipes.md`

## 2. 每份文档负责什么

### `jamreader-ios-product-engineering-spec.md`

负责真实产品行为、模块关系、页面职责和交互边界，也是当前本地资料库架构的产品口径来源。

### `ui-design-requirements.md`

负责更偏设计需求侧的目标和约束。

### `jamreader-ios-ui-redesign-blueprint.md`

负责视觉方向、组件语言、页面原则和 Figma 组织策略。

### `jamreader-ios-figma-screen-spec.md`

负责参考画板、尺寸、组件规格、页面清单和低保真线框。

### `jamreader-ios-priority-screen-content-spec.md`

负责核心页面文案、section 命名、按钮名、badge 文案和示例数据。

### `jamreader-ios-priority-frame-recipes.md`

负责高保真出图时的 frame 结构、组件摆法、状态和页面配方。

## 3. 当前已覆盖页面

- Library Home
- Library Browser Root
- Browse Home
- Remote Browser
- Saved Folders
- Offline Shelf
- Reader
- Remote Opening Loading
- Settings Home
- Remote Cache Settings
- Remote Server Detail
- Remote Server Editor

## 4. 当前已覆盖的输出层级

- 方向层
- 视觉系统层
- Figma 结构层
- 页面内容层
- 高保真 frame 配方层

## 5. 如果下一步要继续

设计方向：

- 直接按 `jamreader-ios-priority-frame-recipes.md` 开始画高保真稿

实现方向：

- 先挑 `Library Home`、`Browse Home` 或 `Remote Browser` 任一页落 SwiftUI 原型

协作方向：

- 把这份索引发给设计师，让对方按顺序读取，避免只看单篇文档造成理解偏差
