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

| 项目 | 状态 | 实测值 | 备注 |
|---|---|---|---|
| 空应用内存基线 | [x] 手动通过 | **36.4 MB** | Activity Monitor 实测 |
| 单张 2048px 代理图内存 | [x] 通过 | 进程 RSS **50.7 MB**（增量 14.3 MB）；像素缓冲区 **7.9 MB** | `testDecodeMemoryImpact_JPEG_1080p` + 手动确认 |
| 预加载前后各 1 张的内存增量 | [x] 手动通过 | **98–150 MB** 波动，LRU 管理正常有回落 | 49 张混合格式文件夹翻页测试 |
| 1000 张图片文件夹扫描耗时 | [x] 自测通过 | **9.6 ms** | `testFolderScanner_1000Images` |
| 1000 张缩略图生成内存峰值 | [x] 通过 | 自测: 100 张批量 **44 ms**（0.44 ms/张）；手动: 峰值 **118.3 MB** / 稳定 **117.7 MB** | `testThumbnailBatch_100Images` + 1000 张网格视图手动验证 |

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
- [x] ICO 可选。

### 3.2 导航与交互

- [x] 鼠标滚轮滚动。
- [x] 设置中支持滚轮行为切换：缩放 / 滚动平移 / 翻页。
- [x] 触控板双指滚动平移（magnify 手势）。
- [x] 触控板捏合缩放。
- [x] 双击切换适应窗口 / 100%。
- [x] 长图适应宽度模式。
- [x] `Esc` 按顺序关闭：快捷键帮助浮层 → Info 面板。
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
- [x] 缩略图磁盘缓存。（内存缓存 + 磁盘缓存已实现）
- [x] 虚拟滚动（LazyVGrid）。
- [x] 多选（⌘+点击 / Shift+点击）+ 全选/反选（⌘A / ⌘⇧A）。
- [x] 网格↔查看器平滑切换（opacity 保留滚动位置）。

### 4.2 预加载与缓存

- [x] 当前图片前后各 1 张预加载。
- [x] 快速翻页取消过期任务。
- [x] 基础 LRU 缓存（5 张）。
- [x] 缩略图缓存 LRU 清理。
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
- [x] 多显示器验证。

### 4.5 设置

- [x] 主题设置。
- [x] 背景色设置（含自定义颜色拾取器）。
- [x] 默认缩放模式设置。
- [x] 滚轮行为设置。
- [x] 是否显示状态栏。
- [x] 记住窗口位置和大小。
- [x] 记住上次打开文件夹。

### 4.6 测试与性能验收

| 项目 | 状态 | 实测值 | 目标 | 判定 |
|---|---|---|---|---|
| 1000 张文件夹扫描 UI 不假死 | [x] 自测通过 | 扫描 **9.6 ms** | < 500 ms | ✅ 远超 |
| 10000 张文件夹渐进浏览 | [x] 自测通过 | 扫描 **86 ms** | < 2 s | ✅ 远超 |
| 首屏 20 张缩略图 < 2s | [x] 自测通过 | **9.4 ms** | < 2 s | ✅ 远超 |
| 1080p JPEG 冷缓存打开 < 150ms | [x] 自测通过 | **7.2 ms** | < 150 ms | ✅ 远超 |
| 1080p PNG 冷缓存打开 < 150ms | [x] 自测通过 | **11.7 ms** | < 150 ms | ✅ 远超 |
| 热缓存打开 < 50ms | [x] 自测通过 | **~0 μs** | < 50 ms | ✅ 设计级满足 |
| 单窗口内存 < 300MB | [x] 手动通过 | 峰值 **118.3 MB / 稳定 117.7 MB** | < 300 MB | ✅ 远低于目标 |
| 单窗口硬上限 < 512MB | [x] 手动通过 | 同上 | < 512 MB | ✅ 远低于目标 |

全部自测通过项可通过 `swift test --filter ReadpicPerformanceTests` 重新运行。

**主观 UI 体验确认:** 缩放跟手、切换顺滑、滚动流畅、全屏工具栏/状态栏显隐正常、触控板手势灵敏 — 全部 ✅

> **Phase 1 验收结论:** 所有代码功能和性能验收指标均已达标，Phase 1 完成。

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

- [x] 完整 EXIF 面板（焦距、曝光补偿、闪光灯、测光模式、白平衡、曝光模式等）。
- [x] IPTC 基础字段（标题、说明、作者、版权、关键词、城市、国家）。
- [ ] XMP 基础读取（待 XML 解析方案）。
- [ ] 元数据复制。
- [ ] 元数据导出 JSON。

### 5.2 基础编辑

- [x] 裁剪（AppKit overlay 九宫格 + 自由/预设比例 + 拖拽缩放 + Save Changes 保存 _crop_N 文件）。
- [x] 格式转换导出（替代另存为）：支持 6 种格式 (JPEG/PNG/TIFF/BMP/HEIC)、质量滑块 (JPEG/HEIC)、自定义宽高、比例锁定与预设、输出文件夹选择。菜单栏 File > Export Image… (⌘⇧S)。
- [x] 旋转/翻转保存 + 旋转方向修正。
### 5.3 文件管理

- [x] 多选（⌘+click、Shift+click）+ 全选/反选（⌘A / ⌘⇧A）。
- [x] 批量重命名（Sequential 模式 + Find & Replace 模式，预设项快捷填充，实时预览冲突检测）。
- [x] 批量格式转换（多选 → Batch Convert / Export，与单图导出共享 ImageWriter）。
- [x] 搜索文件名。
- [x] 格式过滤。
- [x] 日期过滤。
- [x] 收藏 / 评分：心形收藏 + 1-5 星评分，信息面板/网格/缩略图条可见，UserDefaults 持久化。
### 5.4 体验增强

- [ ] 幻灯片。
- [x] 最近文件夹管理（最近 10 个，自动清理不存在的路径）。
- [x] **菜单栏重构**：按 macOS 惯例重组菜单栏结构，确保所有功能入口在菜单中可用。
  - File 菜单：Open Image…、Open Folder…、Close Window、Move to Trash、Reveal in Finder、Open Externally
  - Edit 菜单：Copy Image、Copy File、Copy File Path
  - View 菜单：Grid View、Fit Window / Fit Width / Actual Size、Zoom In / Out / Reset、Thumbnail Strip、Info Panel、Sort By、Show Status Bar、Fullscreen
  - Image 菜单：Rotate Left / Right、Flip Horizontal
  - Help 菜单：Keyboard Shortcuts
- [ ] **Phase 2+ 菜单扩展**：后续新增功能模块均需同时在菜单栏中提供入口，保持「功能-菜单」一一映射。
  - File：Export Image…、Batch Convert…、Batch Rename…、Open Recent ▸
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
- SQLite 元数据存储（当前 UserDefaults 方案已满足轻量需求，不做引入额外数据库依赖）。

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
