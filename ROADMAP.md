# Readpic for Mac — 开发路线图 ROADMAP

> **版本:** v0.1  
> **日期:** 2026-05-14  
> **目标平台:** macOS 15.6+  
> **开发环境:** Xcode 26.5  
> **关联文档:** `PRD.md`, `TECH_SPEC.md`

---

## 1. 路线图原则

1. **先做可日常使用的查看器，再扩展格式和编辑能力。**
2. **Phase 1 只解决核心浏览体验。**
3. **高风险格式、归档、批量能力全部延后。**
4. **所有性能数字先验证再承诺。**
5. **GitHub 开源分发是 v1 默认约束，不以 App Store / notarization 为前提设计。**

---

## 2. Phase 1a — 技术验证与最小原型

> **目标周期:** 1 周  
> **目标:** 验证关键技术风险，完成能打开 JPEG/PNG 并翻页的最小原型。

### 2.1 技术验证

- [x] 创建 Xcode 26.5 项目结构。
- [x] 验证 macOS 15.6 部署目标配置。
- [x] 验证 SwiftUI + AppKit `NSViewRepresentable` 桥接方式。
- [x] 验证 `@Observable` 与 AppKit 显式刷新策略。
- [x] 验证 ImageIO JPEG/PNG 解码与降采样。
- [x] 验证基础缩放和平移渲染性能。
- [x] 验证本地签名 / ad-hoc 签名构建运行流程。
- [x] 验证未 notarized App 在本机首次打开行为。

### 2.2 内存与性能基线

- [ ] 空应用内存基线。（需手动测量）
- [ ] 单张 2048px 代理图内存。（需手动测量）
- [ ] 预加载前后各 1 张的内存增量。（需手动测量）
- [ ] 1000 张图片文件夹扫描耗时。（需手动测量）
- [ ] 1000 张缩略图生成内存峰值。（需手动测量）

### 2.3 最小功能

- [x] 打开单张 JPEG。
- [x] 打开单张 PNG。
- [x] 自动扫描同目录图片。
- [x] `←` / `→` 翻页。
- [x] 适应窗口显示。
- [x] 100% 显示。
- [x] 深色背景。

### 2.4 里程碑

能打开 JPEG/PNG 文件夹，键盘翻页，基础缩放可用，主线程不卡顿，关键技术选型确认。

---

## 3. Phase 1b — 核心浏览体验

> **目标周期:** 2 周  
> **目标:** 完成日常单图浏览体验。

### 3.1 格式支持

- [x] HEIC / HEIF。
- [x] WebP。
- [x] GIF 基础动画播放。
- [x] TIFF。
- [x] BMP。
- [ ] ICO 可选。

### 3.2 导航与交互

- [x] 鼠标滚轮滚动。
- [x] 设置中支持滚轮行为切换：缩放 / 滚动平移 / 翻页。
- [x] 触控板双指滚动平移（magnify 手势）。
- [x] 触控板捏合缩放。
- [x] 双击切换适应窗口 / 100%。
- [x] 长图适应宽度模式。
- [x] `Esc` 按顺序关闭：快捷键帮助浮层 → Info 面板 → 网格视图 → 窗口。
- [x] `Space` 暂停/继续 GIF 动画。

### 3.3 文件操作

- [x] 拖拽图片打开。
- [x] 拖拽文件夹打开。
- [x] `⌘+C` 复制图片。
- [x] `⌘+Shift+C` 复制文件。
- [x] `⌘+⌥+C` 复制文件路径。
- [x] `⌘+⌥+E` 在 Finder 中显示。
- [x] `⌘+E` 用外部应用打开。
- [x] `⌘+Delete` 移到废纸篓。
- [x] 删除 Toast + 撤销。

### 3.4 UI

- [x] 顶部工具栏。
- [x] 底部状态栏。
- [x] 空状态页面。
- [x] 加载中状态。
- [x] 错误占位图：损坏文件、不支持格式、权限不足。

### 3.5 里程碑

可作为轻量图片查看器日常使用：打开、翻页、缩放、拖拽、复制、删除、外部打开体验完整。

---

## 4. Phase 1c — 缩略图、全屏与性能打磨

> **目标周期:** 2 周  
> **目标:** 完成大文件夹浏览和 v1 发布候选能力。

### 4.1 缩略图网格

- [x] `LazyVGrid` 网格视图（SwiftUI 替代 NSCollectionView）。
- [x] 可见区域优先生成缩略图。
- [x] 后台渐进式生成缩略图。
- [ ] 缩略图磁盘缓存。（内存缓存已实现）
- [x] 虚拟滚动（LazyVGrid）。
- [x] 单选（点击打开，可扩展多选）。
- [x] `G` 切换网格视图。

### 4.2 预加载与缓存

- [x] 当前图片前后各 1 张预加载。
- [x] 快速翻页取消过期任务。
- [x] 基础 LRU 缓存（5 张）。
- [ ] 缩略图缓存 LRU 清理。
- [x] 低内存模式（DispatchSource 内存压力监控）。

### 4.3 旋转与翻转

- [x] 左旋 / 右旋 90°。
- [x] 水平翻转。
- [x] 工具栏按钮 + 快捷键。
- [x] 旋转变换不影响原始文件。

### 4.4 全屏

- [x] 系统全屏。
- [x] 全屏下工具栏自动隐藏。
- [x] 鼠标移到顶部/底部显示工具栏/状态栏。
- [x] 底部轻量缩略图条。
- [x] 全屏下缩略图条与 chrome 同步隐藏。
- [x] 全屏背景为纯黑 #000000（不跟随设置背景色）。
- [ ] 多显示器验证。

### 4.5 设置

- [x] 主题设置。
- [x] 背景色设置（含自定义颜色拾取器）。
- [x] 默认缩放模式设置。
- [x] 滚轮行为设置。
- [x] 是否显示状态栏。
- [x] 记住窗口位置和大小。
- [x] 记住上次打开文件夹。

### 4.6 测试与性能验收

- [ ] 1000 张图片文件夹 UI 不假死。（需手动测试）
- [ ] 10000 张图片文件夹可渐进浏览。（需手动测试）
- [ ] 首屏 20 张缩略图 2 秒内完成。（需手动测试）
- [ ] 常见 1080p JPEG/PNG 热缓存打开 < 50ms。（需手动测试）
- [ ] 常见 1080p JPEG/PNG 冷缓存打开 < 150ms。（需手动测试）
- [ ] 单窗口常规浏览内存目标 < 300MB。（需手动测试）
- [ ] 单窗口硬上限 < 512MB。（需手动测试）

### 4.7 信息面板

- [x] 基础 EXIF：拍摄时间、相机型号、镜头、ISO、光圈、快门。
- [x] Bit Depth 显示。
- [x] 文件信息：名称、路径、大小、创建/修改时间。
- [x] 图片信息：尺寸、格式、色彩空间。

### 4.8 快捷键帮助

- [x] `?` 键显示快捷键帮助浮层。
- [x] 浮层按 Navigation / Zoom / File / View 分组。
- [x] `Esc` 或再次按 `?` 关闭。

### 4.9 里程碑

形成 Readpic v1.0 beta：核心浏览、缩略图、全屏、设置和基础性能达标。

---

## 5. Phase 2 — 信息、编辑与管理增强

> **目标周期:** 3-4 周  
> **目标:** 从轻量查看器升级为更完整的图片管理工具。

### 5.1 信息能力

- [ ] 完整 EXIF 面板。
- [ ] IPTC 基础字段。
- [ ] XMP 基础读取。
- [ ] 元数据复制。
- [ ] 元数据导出 JSON。

### 5.2 基础编辑

- [ ] 裁剪。
- [ ] Resize。
- [ ] 旋转/翻转保存。
- [ ] 另存为。
- [ ] 文件大小优化 / 重新压缩。

注意：JPEG 重新编码不能称为严格无损优化。

### 5.3 文件管理

- [ ] 多选（⌘+click、Shift+click）。
- [ ] 批量重命名。
- [ ] 批量格式转换。
- [ ] 搜索文件名。
- [ ] 格式过滤。
- [ ] 日期过滤。
- [ ] 收藏 / 评分 / 标签。
- [ ] SQLite 元数据存储。

### 5.4 体验增强

- [ ] 幻灯片。
- [ ] 快捷键自定义。
- [ ] 最近文件夹管理。
- [ ] **菜单栏重构**：按 macOS 惯例重组菜单栏结构，确保所有功能入口在菜单中可用。
  - File 菜单：Open Image…、Open Folder…、Close Window、Move to Trash、Reveal in Finder、Open Externally
  - Edit 菜单：Copy Image、Copy File、Copy File Path
  - View 菜单：Grid View、Fit Window / Fit Width / Actual Size、Zoom In / Out / Reset、Thumbnail Strip、Info Panel、Sort By、Show Status Bar、Fullscreen
  - Image 菜单：Rotate Left / Right、Flip Horizontal
  - Help 菜单：Keyboard Shortcuts
- [ ] **Phase 2+ 菜单扩展**：后续新增功能模块均需同时在菜单栏中提供入口，保持「功能-菜单」一一映射。
  - File：Export / Save As…、Batch Convert…、Batch Rename…、Open Recent ▸
  - Edit：Select All、Copy Metadata
  - View：Filter By ▸ (Format / Date)、Search Files…、Start Slideshow、Metadata Panel
  - Image：Crop…、Resize…、Save Changes…、Optimize File Size…、Rate ▸、Favorite / Tag…
- [ ] 本地化（Localizable.xcstrings，简体中文 + English）。

### 5.5 基础工程

- [ ] 单元测试：ImageDecoder、FolderScanner、ThumbnailLoader、MetadataReader。
- [ ] 缩略图磁盘缓存。

### 5.6 技术预研

- [ ] ZIP/CBZ 选型：ZIPFoundation / libarchive / minizip-ng。
- [ ] SVG 选型：SVGKit vs WebKit。
- [ ] RAW ImageIO 支持矩阵。

---

## 6. Phase 3 — 高级格式与专业功能

> **目标周期:** 4-6 周，视技术预研结果调整。

### 6.1 高级格式

- [ ] RAW 常见格式浏览。
- [ ] RAW 内嵌 JPEG 预览优先。
- [ ] AVIF。
- [ ] JPEG XL。
- [ ] SVG。
- [ ] PSD/PSB 合并图层预览。

### 6.2 专业查看

- [ ] 直方图。
- [ ] 颜色拾取器。
- [ ] 并排对比。
- [ ] 同步缩放。
- [ ] 打印尺寸信息。

### 6.3 归档与漫画

- [ ] ZIP / CBZ 浏览。
- [ ] 加密 ZIP 支持。
- [ ] 漫画阅读模式。
- [ ] TAR / GZIP 视需求评估。

### 6.4 系统集成

- [ ] 分享菜单。
- [ ] 设置桌面壁纸。
- [ ] 更完整的 Finder 集成。
- [ ] Homebrew Cask 可选。

---

## 7. Phase 4 — GitHub 发布准备

> **目标周期:** 3-5 天  
> **目标:** 完成开源发布所需的安装、说明和基础分发流程。

### 7.1 Release 构建

- [ ] Release scheme 配置。
- [ ] 构建脚本。
- [ ] 本地/临时签名流程验证。
- [ ] 是否启用 Hardened Runtime 的实测结论。
- [ ] 干净 macOS 15.6 环境首次打开验证。

### 7.2 DMG

- [ ] DMG 制作脚本。
- [ ] DMG 包含 Applications 快捷方式。
- [ ] 安装后首次打开流程验证。

### 7.3 文档

- [ ] README 安装说明。
- [ ] 首次右键「打开」说明。
- [ ] 未 notarized 说明。
- [ ] 常见问题。
- [ ] 快捷键表。
- [ ] 支持格式表。

### 7.4 里程碑

GitHub Release 可发布，用户可按 README 完成安装和首次启动。

---

## 8. Phase 5 — 分发体验升级（可选）

> **触发条件:** 项目有稳定用户后再决定。

可选事项：

- [ ] Apple Developer ID。
- [ ] Notarization。
- [ ] Sparkle 自动更新。
- [ ] Homebrew Cask 发布。
- [ ] 更完整的崩溃日志收集，但必须默认尊重隐私。
- [ ] 官方网站。

---

## 9. 暂不计划

以下方向短期不做：

- Mac App Store 沙盒版。
- 云同步。
- AI 图片识别。
- 图层编辑。
- 专业 RAW 调色。
- 视频播放器。
- DAM 数字资产管理系统。
- 团队协作功能。

---

## 10. 每阶段验收摘要

| 阶段 | 验收结果 |
|---|---|
| Phase 1a | JPEG/PNG 原型可翻页，技术风险完成验证 |
| Phase 1b | 单图浏览体验完整，可日常轻量使用 |
| Phase 1c | 缩略图条、全屏、EXIF、性能目标达成，形成 beta |
| Phase 2 | 信息、基础编辑、批量管理能力完成 |
| Phase 3 | 高级格式、归档、专业查看功能完成 |
| Phase 4 | GitHub Release 可发布，安装说明完整 |
| Phase 5 | 可选分发体验升级 |
