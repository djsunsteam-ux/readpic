# 简化图片加载机制：全分辨率解码 + 滑动窗口缓存

## Context

当前项目采用渐进式分辨率升级（2048px proxy → 4096 → 8192...），配合低内存模式（≤8GB 设备降采样、缩窄预加载窗口）。用户希望统一改为：所有图片（含 GIF 帧）直接全分辨率解码，仅预加载 ±2 张，切换图片后清理窗口外缓存。

## Task 1: 精简 `Downsample.swift`

- **保留** `readOrientation()` — ImageDecoder 读取 EXIF 方向
- **保留** `targetDimensions()` — Histogram.swift 内部使用
- **删除** `createImage(source:maxPixelSize:)` (30行) — 不再被调用

## Task 2: 重构 `ImageDecoder.swift`

- `decode(url:maxPixelSize:)` 签名不变，行为改变：
  - `maxPixelSize == nil`（默认）→ `CGImageSourceCreateImageAtIndex` 全分辨率
  - `maxPixelSize` 非 nil（仅 selectInGrid 的 512px 直方图预览）→ 内联简短降采样
- `decodeFrames` 移除 `maxPixelSize` 参数，动画帧全分辨率
- **删除** `downsampleIfNeeded()` — 不再需要

## Task 3: 精简 `ThumbnailLoader.swift`

- **删除** 全局 `isLowMemoryMode`（`_isLowMemoryMode` 锁 + 计算属性）
- `maxSize` 固定为 `160`（移除 `isLowMemoryMode ? 128 : 160` 条件）
- **删除** `ThumbnailCache.halveCapacity()` 和 `restoreCapacity()`

## Task 4: 扩展 `ImageCache.swift`

新增窗口化清理方法：
```swift
func evictOutside(window: Set<URL>) {
    entries.removeAll { !window.contains($0.url) }
}
```

## Task 5: 大幅简化 `ViewerModel.swift`

**5a 移除低内存模式 + 内存监控：**
- 删除 `memorySource` 属性、init 中的 `DispatchSource` 创建、≤8GB 检测
- 删除 `handleMemoryWarning()`、`handleMemoryRestore()`、deinit 中的 cancel

**5b 移除分辨率升级：**
- 删除 `preloadTask`、`currentProxyMaxPixelSize` 属性
- 删除 `requestHigherResolution()`、`preloadHigherResolutions()` 方法
- 清理 `open()`/`openFolder()`/`openArchive()`/`loadCurrentImage()` 中相关赋值和调用

**5c 扩展预加载到 ±2：**
```swift
let adjPositions = (-2...2).compactMap { offset -> Int? in
    guard offset != 0 else { return nil }
    let p = pos + offset
    return nav.indices.contains(p) ? p : nil
}
```

**5d 添加缓存窗口清理：**
在 `loadCurrentImage()` 两条路径中 `preloadAdjacent()` 之后调用 `evictOutside(window:)`

## Task 6: 简化 `ViewerNSView.swift`

- **删除** `onRequestHigherRes`、`hasRequestedHigherRes`、`proxyStretchLimit`
- `setImage()` 移除 `hasRequestedHigherRes = false`
- `upgradeImage()` → 重命名为 `updateImage()`，移除 `hasRequestedHigherRes` 相关
- `layoutImageLayer()` 中删除 proxy cap 块（~35行），替换为：
  ```swift
  let ds = zoom.displaySize
  let boundsSize = (zoom.rotation % 180 == 0) ? ds : CGSize(width: ds.height, height: ds.width)
  ```
- 删除 `onRequestHigherRes` 触发块

## Task 7: 更新 `ViewerRepresentable.swift`

- 删除 `view.onRequestHigherRes` 赋值
- `nsView.upgradeImage(...)` → `nsView.updateImage(...)`

## Task 8: 更新记忆

清理已废弃的记忆条目（渐进式加载、低内存模式、proxyStretchLimit）

## 验证

1. `xcodebuild` 编译通过
2. Grep 确认以下符号零引用：`isLowMemoryMode`、`requestHigherResolution`、`currentProxyMaxPixelSize`、`preloadHigherResolutions`、`hasRequestedHigherRes`、`proxyStretchLimit`、`halveCapacity`、`restoreCapacity`、`memorySource`、`handleMemoryWarning`、`handleMemoryRestore`