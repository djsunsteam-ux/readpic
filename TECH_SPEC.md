# Readpic for Mac — 技术规格 TECH_SPEC

> **版本:** v0.1  
> **日期:** 2026-05-14  
> **目标平台:** macOS 15.6+  
> **开发环境:** Xcode 26.5  
> **关联文档:** `PRD.md`, `ROADMAP.md`

---

## 1. 技术选型

| 层面 | 方案 |
|---|---|
| 语言 | Swift |
| UI | SwiftUI + AppKit 混合 |
| 构建 | Xcode 26.5 / Swift Package Manager |
| 图片解码 | ImageIO 优先 |
| 渲染 | AppKit `NSView` + CALayer |
| 状态 | Observation / `@Observable`，高频交互显式刷新 |
| 缓存 | 内存缓存（多因子 key，`ThumbnailCacheKey`），磁盘缓存 Phase 2+ |
| 持久化 | UserDefaults，后续 SQLite |
| 分发 | GitHub Release + DMG |

---

## 2. UI 架构

### 2.1 框架划分原则

高频交互、手势密集、性能敏感的区域使用 AppKit；表单、工具栏、设置等低频 UI 使用 SwiftUI。

| 模块 | 框架 | 原因 |
|---|---|---|
| 核心图片查看器 | AppKit `NSView` | 缩放、平移、滚动、CALayer 渲染更可控 |
| 缩略图网格 | SwiftUI `LazyVGrid` | 声明式网格，虚拟滚动由 SwiftUI 提供 |
| 裁剪 overlay | AppKit | hit testing 和拖拽控制更精确 |
| 工具栏 | SwiftUI | 状态简单，声明式布局方便 |
| 信息面板 | SwiftUI | 低频展示型 UI |
| 设置窗口 | SwiftUI | 表单场景适合 SwiftUI |
| 右键菜单 | AppKit `NSMenu` | 复杂菜单稳定性更好 |
| 拖拽 | AppKit | 文件拖拽兼容性更好 |

### 2.2 AppKit 与 SwiftUI 桥接

- SwiftUI 作为窗口和整体布局容器。
- 图片查看器通过 `NSViewRepresentable` 嵌入。
- `ViewerNSView` 持有或接收 `ViewerModel`，关键交互显式调用刷新。
- 高频状态如缩放、平移不依赖 Observation 自动刷新。
- 低频状态如当前图片切换、工具栏显隐、主题变化可使用 Observation 或显式事件。

### 2.3 工具栏布局变更说明

v1 工具栏按钮（从左到右）：Grid | Fit | Zoom Out | Zoom In | Rotate Left | Rotate Right | Mirror | Thumbnails | Info。

> **工具栏与菜单栏分工：** 工具栏保留高频视觉操作（网格、缩放、变换、面板开关）；低频/配置型功能（打开、原始尺寸、Finder 中显示等）移入菜单栏。所有功能在菜单栏中均有对应入口。

### 2.3 菜单栏架构

菜单栏使用 SwiftUI `.commands` 构建，划分 6 个标准菜单组：

| 菜单 | 职责 | SwiftUI 实现方式 |
|---|---|---|
| Readpic (App) | 应用级：关于、偏好设置、退出 | 系统自动 + `CommandGroup(replacing: .appInfo)` |
| File | 文件级：打开、关闭、删除、外部操作 | `CommandGroup(replacing: .newItem)` + `CommandGroup(after: .newItem)` |
| Edit | 剪贴板：复制图片/文件/路径 | `CommandGroup(replacing: .pasteboard)` |
| View | 显示：网格、缩放、面板开关、排序、全屏 | `CommandMenu("View")` |
| Image | 图片变换：旋转、翻转 | `CommandMenu("Image")` |
| Help | 帮助：快捷键参考 | `CommandMenu("Help")` |

菜单项通过 `@State private var model` 直接访问 `ViewerModel`，统一使用 `.keyboardShortcut()` 声明快捷键，`.disabled()` 跟随 Model 状态自动切换。

> **Phase 2 扩展：** 新增 Feature 模块需同步在对应菜单组添加入口。保持「功能-菜单」一一映射原则。

### 2.4 Observation 使用原则

`@Observable` 可用于 ViewModel，但不把它作为 AppKit 高频渲染的唯一同步机制。

Phase 1a 需要验证：

1. SwiftUI 容器驱动更新的成本。
2. AppKit NSView 显式刷新方案。
3. `withObservationTracking` 在低频状态变化中的可靠性。
4. 缩放/平移 60fps 场景下绕过 Observation 的收益。

---

## 3. 模块划分

```text
Readpic/
├── App/
│   └── ReadpicApp.swift
├── Core/
│   ├── ImageLoading/
│   │   ├── ImageDecoder.swift
│   │   ├── ImageCache.swift
│   │   ├── ImageWriter.swift
│   │   └── ThumbnailLoader.swift
│   ├── FileSystem/
│   │   ├── FolderScanner.swift
│   │   ├── FileItem.swift
│   │   └── FileSorter.swift
│   ├── Metadata/
│   │   └── MetadataReader.swift
│   ├── Favorites/
│   │   └── FavoritesManager.swift
│   ├── Settings/
│   │   └── AppSettings.swift
│   └── WindowAccessor.swift
├── ViewModels/
│   └── ViewerModel.swift
├── Features/
│   ├── Export/
│   │   └── ExportView.swift
│   ├── Viewer/
│   │   ├── ViewerView.swift
│   │   ├── ViewerNSView.swift
│   │   ├── ViewerRepresentable.swift
│   │   ├── CropOverlayView.swift
│   │   ├── NativeHScroll.swift
│   │   ├── ThumbnailStripView.swift
│   │   └── GridView.swift
│   ├── InfoPanel/
│   │   └── InfoPanelView.swift
│   └── Settings/
│       └── SettingsView.swift
├── Services/
│   ├── FileOperationService.swift
│   ├── ClipboardService.swift
│   ├── ExternalOpenService.swift
│   └── FinderService.swift
└── Resources/
    └── Assets.xcassets
```

---

## 4. 图片解码策略

### 4.1 v1 格式支持

v1 优先使用 ImageIO 支持的系统格式：

- JPEG / JPG
- PNG
- HEIC / HEIF
- WebP
- GIF
- TIFF
- BMP
- ICO 可作为 P1

### 4.2 解码流程

1. 根据文件 URL 创建 `CGImageSource`。
2. 读取基础元数据和像素尺寸。
3. 根据显示目标决定是否降采样。
4. 使用 `CGImageSourceCreateThumbnailAtIndex` 生成显示代理图。
5. 缩放到超过代理图有效分辨率时，再按需加载更高分辨率版本。

### 4.3 降采样策略

| 场景 | 策略 |
|---|---|
| 普通图片 | 长边 2048px 代理图 |
| 超大图片 | 长边 1024px 起步，必要时显示加载状态 |
| 用户放大 | 按需解码更高分辨率（每次翻倍，无上限），通过 `ViewerNSView` 检测缩放超出阈值后触发重解码 |
| 低内存模式 | 降为 1024px 代理图 |
| 缩略图 | 统一生成 160px 缩略图（低内存模式降为 128px） |

解码选项原则：

- 避免不必要的全尺寸位图解码。
- 对大图使用 `kCGImageSourceShouldCache = false` 降低峰值内存。
- 缩略图使用 `kCGImageSourceCreateThumbnailFromImageAlways`，优先利用内嵌缩略图。
- 用户缩放超过代理图分辨率 1.2x 时触发按需升级解码。

### 4.4 GIF / 动画图片

v1 支持基础动画播放：

- 尊重原始帧延迟，但受最低帧间隔限制（1/30s，即最高 30fps）。
- 帧数上限 100 帧，超出部分略过。
- 处理 disposal method：`do not dispose` 合成到前一帧、`restore to background` 使用干净底布、`restore to previous` 保留前帧。
- 帧降采样：每帧解码后按 `maxPixelSize` 等比例缩小。
- 自动动画循环，`Space` 暂停/恢复。
- 动画 WebP 依赖系统 ImageIO 支持。

---

## 5. 文件扫描与排序

### 5.1 扫描原则

- 默认只扫描当前文件夹。
- 不递归。
- 文件扫描在后台队列执行。
- 扫描结果增量更新 UI。
- 大文件夹优先返回文件名和基础信息，缩略图稍后填充。

### 5.2 排序

v1 支持：

- 文件名自然排序。
- 修改时间排序。

自然排序示例：

```text
img_2.jpg < img_10.jpg
```

### 5.3 iCloud / 网络盘 / 外接盘

对慢速或不可立即访问文件：

- 显示占位状态。
- 不阻塞主线程。
- 超过阈值显示加载提示。
- iCloud 未下载文件显示明确状态；自动下载行为需在 Phase 1a 验证系统 API 后确定。

---

## 6. 缩略图缓存

### 6.1 Phase 1 实现

Phase 1 使用内存缓存（上限 200 条目），不支持磁盘缓存。缓存使用多因子 key（`ThumbnailCacheKey`，基于 `url + fileSize + modificationDate`），确保文件变化后自动失效。

### 6.2 磁盘缓存（Phase 2+）

缓存位置：

```text
~/Library/Caches/Readpic/thumbnails/
```

### 6.3 缓存 key

v1 使用多因子 key，结合文件属性和路径：

```swift
struct ThumbnailCacheKey: Hashable, Sendable {
    let url: URL
    let fileSize: Int64
    let modificationDate: TimeInterval
}
```

- 基于 `{url}_{fileSize}_{modificationDate}` 的组合 key 确保文件被修改或替换后缓存自动失效。
- 未来磁盘缓存阶段可扩展为 `{volume_id}_{inode}_{file_size}_{file_mtime}`。

### 6.4 淘汰策略

- 基于 Dictionary 实现，超过上限时执行 FIFO 淘汰。
- 默认上限 200 条目（约 200 个缩略图）。
- 低内存模式下上限减半至 100。
- 缓存被清空后自动重建，不弹错误。

### 6.5 缩略图生成队列

v1 使用三级队列（`ThumbnailQueueManager`）：

| 队列 | 并发 | QoS | 用途 |
|---|---:|---:|---|
| VisibleThumbnailQueue | 4 | userInitiated | 当前可见区域 |
| BackgroundThumbnailQueue | 2 | utility | 非可见区域预生成 |
| PreloadQueue | 2 | userInitiated | 当前图片前后预加载 |

- `ThumbnailLoader.load(url:priority:)` 根据优先级调度到对应队列。
- GridView / ThumbnailStripView 使用 `.visible` 优先级（默认）。
- `cancelAll()` / `cancelBackground()` 支持快速翻页时取消过期任务。

---

## 7. 预加载与取消

### 7.1 预加载范围

默认预加载当前图片前后各 1 张。实测内存允许时可调整为前后各 2-3 张。

### 7.2 快速翻页取消策略

- 用户切换图片时，取消不在当前窗口附近的预加载任务。
- 解码前检查取消状态。
- 当前图片加载优先级高于缩略图生成。

---

## 8. 内存策略

### 8.1 目标

| 场景 | 目标 |
|---|---:|
| 单窗口常规浏览 | < 300MB |
| 单窗口硬上限 | < 512MB |
| 多窗口 | 每窗口独立预算，缓存共享 |

### 8.2 低内存模式

触发条件：

- 系统内存 ≤ 8GB（`ProcessInfo.physicalMemory`，启动时自动检测）。
- 或运行时收到系统内存压力信号（`DispatchSourceMemoryPressure` 的 `.warning` / `.critical`）。
- 或 Instruments 实测常规路径超过目标预算。

进入低内存模式（`handleMemoryWarning()`）：

- 设置全局 `isLowMemoryMode = true`。
- 后续所有新解码使用 1024px 代理图，128px 缩略图。
- `ThumbnailCache` 上限减半（200 → 100）。
- 清理 `ImageCache` 和 `ThumbnailCache`。
- 用户放大时，`requestHigherResolution()` 上限为 4096px（而非无上限）。

退出低内存模式（`handleMemoryRestore()`）：

- 收到 `DispatchSourceMemoryPressure` 的 `.normal` 事件时自动触发（仅限 >8GB 设备，≤8GB 设备持续保持低内存模式）。
- `isLowMemoryMode` 恢复为 `false`。
- `ThumbnailCache` 容量恢复为 200。

### 8.3 Phase 1a 必测项

- 空应用基线内存。
- 打开单张 2048px 代理图后的内存。
- 预加载 1/2/3 张的增量。
- 1000 / 10000 张文件夹缩略图浏览内存。
- 双窗口内存。
- 长图、超大 TIFF 的峰值内存。

---

## 9. 文件操作

### 9.1 删除

- v1 默认只支持移到废纸篓。
- 使用系统废纸篓能力。
- 删除后显示 Toast，并允许撤销。
- 永久删除不提供默认快捷键。

### 9.2 重命名

v1 可延后。实现时必须遵守：

- 修改扩展名默认只重命名，不自动转换格式。
- 如果用户希望转换格式，必须走「Export Image…」格式转换导出流程。

### 9.3 旋转 / 翻转保存

- v1 默认先做显示层变换。
- 保存到文件必须显式确认。
- 覆盖原图前创建备份或使用 Export Image… 导出副本。

---

## 10. 元数据

v1 读取：

- 文件名、路径、大小、创建/修改时间。
- 像素尺寸。
- 色彩空间。
- 基础 EXIF。

延后：

- 完整 XMP。
- IPTC。
- GPS 地图。
- 直方图。

---

## 11. 设置持久化

v1 使用 UserDefaults 存储：

- 窗口位置和大小。
- 上次打开文件夹。
- 最近打开文件夹列表。
- 主题设置。
- 背景色。
- 默认缩放模式。
- 滚轮行为。
- 排序模式（Name / Date）。
- 自定义背景色。

后续收藏、评分、标签进入 SQLite，不进入 v1 必做。

---

## 12. 收藏与 SQLite 设计预案

收藏功能进入后续阶段时，不建议使用 inode 作为唯一主键。

推荐表结构方向：

```sql
CREATE TABLE assets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  volume_id TEXT,
  inode INTEGER,
  file_path TEXT NOT NULL,
  file_name TEXT NOT NULL,
  file_size INTEGER NOT NULL,
  file_mtime REAL NOT NULL,
  content_fingerprint TEXT,
  is_favorite INTEGER DEFAULT 0,
  rating INTEGER DEFAULT 0,
  color_tag TEXT,
  created_at REAL NOT NULL,
  updated_at REAL NOT NULL
);

CREATE INDEX idx_assets_path ON assets(file_path);
CREATE INDEX idx_assets_inode ON assets(volume_id, inode);
CREATE INDEX idx_assets_favorite ON assets(is_favorite) WHERE is_favorite = 1;
```

匹配优先级：

1. `file_path + file_size + file_mtime`
2. `volume_id + inode`
3. `content_fingerprint + file_size`
4. 用户手动确认

---

## 13. 格式转换导出 (Export / ImageWriter)

### 13.1 功能定位

替代传统的「另存为」，将旋转/翻转后的图片导出为新文件，同时提供格式转换和尺寸调整能力。

### 13.2 入口

File > **Export Image…** (⌘⇧S)，打开 SwiftUI Sheet 面板。

### 13.3 导出面板 (`ExportView.swift`)

| 分区 | 功能 |
|---|---|
| **Format** | 格式选择 (JPEG/PNG/TIFF/BMP/HEIC)，JPEG/HEIC 带质量滑块 |
| **Resize** | 自定义宽高 (px)，锁定比例自动联动，解锁后显示 8 种预设比例 (1:1~21:9) |
| **Output** | 自定义文件名，选择输出文件夹 |

### 13.4 图像变换 (`ImageWriter.swift`)

- `applyTransform(to:rotation:isFlipped:)` — 将旋转/翻转烘焙到像素数据中
- `write(_:to:format:compressionQuality:)` — 通过 `CGImageDestination` 编码写入文件
- `resize(_:to:targetHeight:)` — 高质量重采样缩放
- CATransform3D 与 CGContext 的坐标系一致 (Y 轴向上)，旋转方向无需取反

### 13.5 Save Changes

Image > **Save Changes**，将旋转/翻转结果直接写回原文件（弹出确认警告）。写回后自动清除 ImageCache + ThumbnailCache，强制重新解码和缩略图更新。

---

## 14. 签名与分发

### 13.1 v1 分发前提

项目采用 GitHub 开源分发，暂不申请 Apple Developer Program，不做 Developer ID notarization。

### 13.2 目标体验

- GitHub Release 提供 DMG。
- 用户将 App 拖入 Applications。
- 首次打开使用右键「打开」。
- README 明确说明未公证、首次打开方式和故障排除方式。

### 13.3 签名策略

v1 使用本地/临时签名方式满足构建和运行需要。Release 构建是否启用 Hardened Runtime 需要 Phase 1a 实测验证。

需要验证：

- ad-hoc 签名下启用 Hardened Runtime 的实际行为。
- 第三方动态库是否触发 library validation 问题。
- 未 notarized DMG 在干净 macOS 15.6 机器上的首次打开流程。

### 13.4 非沙盒策略

v1 不启用 App Sandbox。

因此：

- 不依赖 sandbox file entitlements 获取文件访问。
- 不使用 Security-Scoped Bookmarks。
- 文件访问来自用户显式打开、拖拽、Finder 打开方式或普通文件系统权限。

如果未来发布 Mac App Store 或启用 Sandbox，需要重构为 Security-Scoped Bookmarks，并通过 `FileAccessService` 隔离改动。

### 13.5 README 必须说明

- Readpic 是开源项目。
- v1 未经过 Apple notarization。
- 首次打开需要右键「打开」。
- 如果仍无法打开，可在系统设置「隐私与安全性」中允许。
- 命令行 `xattr -cr /Applications/Readpic.app` 作为高级故障排除方案。

不建议在文档中鼓励用户关闭 Gatekeeper。

---

## 14. 本地化

Phase 1 不做本地化，所有 UI 文本使用英文。

### Phase 2+ 计划

- 简体中文
- English

使用 String Catalog：

```text
Localizable.xcstrings
```

所有用户可见文本必须本地化。

RTL 语言不进入 v1 支持范围。

---

## 15. 测试策略

### 15.1 单元测试（Phase 2+）

Phase 1 通过手动测试覆盖，单元测试延后到 Phase 2。需测试模块：

- ImageDecoder
- FolderScanner
- ThumbnailLoader
- MetadataReader

### 15.2 集成测试

- 打开文件 → 显示 → 翻页 → 关闭。
- 打开文件夹 → 扫描 → 网格缩略图 → 单图查看。
- 删除到废纸篓 → 撤销。
- 复制图片 / 文件路径。

### 15.3 性能测试

- 冷启动。
- 1080p JPEG/PNG 打开时间。
- 1000 / 10000 张文件夹扫描。
- 缩略图生成速度。
- 网格滚动帧率。
- 单窗口内存峰值。

### 15.4 手动测试场景

- Retina / 非 Retina 外接显示器。
- 多显示器全屏。
- 触控板捏合、滚动、双击。
- 外接鼠标滚轮。
- iCloud 未下载文件。
- SMB/NFS 网络目录。
- USB 外接硬盘。
- 损坏图片、0 字节文件、超大图片。

---

## 16. 后续技术预研

以下不进入 v1 必做，但需要在对应阶段开始前预研：

| 能力 | 预研点 |
|---|---|
| RAW | ImageIO 支持矩阵、内嵌 JPEG 预览、libraw 许可与体积 |
| AVIF | libavif SPM 可用性、动态库签名问题 |
| JPEG XL | libjxl 体积、性能、分发复杂度 |
| SVG | SVGKit vs WebKit 渲染稳定性 |
| ZIP/CBZ | ZIPFoundation / libarchive / minizip-ng 选型 |
| 自动更新 | Sparkle 与未公证应用的体验 |
