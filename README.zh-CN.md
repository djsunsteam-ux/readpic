# Readpic

快速、轻量的 macOS 图片查看器。**完全免费，开源。**

> macOS 上优秀的图片查看器几乎都要付费。Readpic 吸取了它们的优点，为 macOS 用户提供一个真正免费、开箱即用的选择。

[English](README.md) | 简体中文

## 功能特性

- **30+ 格式支持**：JPEG、PNG、HEIC、WebP、GIF、TIFF、BMP、AVIF、PSD、17 种 RAW 格式、ZIP/CBZ
- **快速浏览**：自然排序、键盘导航、缩略图网格
- **缩放与平移**：适应窗口、适应宽度、实际大小、光标锚点缩放、鼠标拖拽平移
- **GIF 动画**：逐帧播放、暂停、帧条
- **裁剪**：自由比例与预设比例、交互式拖拽手柄
- **信息面板**：EXIF、IPTC、XMP 元数据、直方图、取色器
- **批量操作**：格式转换、批量重命名、导出
- **全屏模式**：自动隐藏工具栏、幻灯片放映
- **界面语言**：English、简体中文

## 系统要求

- macOS 15.6+
- Apple Silicon（M1 及更新机型），不支持 Intel Mac

## 安装

1. 从 [Releases](https://github.com/djsunsteam-ux/readpic/releases) 下载 `Readpic.dmg`
2. 打开 DMG 文件
3. 将 **Readpic** 拖入 **Applications** 文件夹
4. 从启动台或 Spotlight 启动

## 首次启动

Readpic 未经 Apple 公证。首次启动时：

1. 右键点击 **Readpic.app** → 选择 **打开**
2. 在弹窗中点击 **打开**
3. 此后可正常启动

或者：

1. 双击尝试打开
2. 前往 **系统设置 → 隐私与安全性**
3. 在 "Readpic 已被阻止" 旁点击 **仍要打开**

## 隐私与安全

Readpic 不包含任何联网功能，也不会请求网络访问。它不会收集、上传或分析任何个人数据、图片文件或图片内容。所有图片解码、浏览、元数据读取和编辑操作都在你的 Mac 本地完成，请放心使用。

## 快捷键

### 导航

| 按键 | 功能 |
|---|---|
| `←` `→` | 上一张 / 下一张 |
| `↑` `↓` | 网格：上移 / 下移 |
| `Space` | 暂停 / 继续 GIF 动画 |
| `G` | 切换缩略图网格 |
| `Esc` | 关闭面板 / 退出全屏 / 停止幻灯片 |

### 缩放

| 按键 | 功能 |
|---|---|
| `⌘=` `⌘-` | 放大 / 缩小 |
| `⌘0` | 重置缩放（适应窗口） |
| `+` `-` `0` | 同上（无修饰键） |
| 双击 | 切换适应窗口 / 100% |
| 触控板捏合 | 向光标位置缩放 |
| 滚动 + `⌥` | 向光标位置缩放 |

### 文件

| 按键 | 功能 |
|---|---|
| `⌘O` | 打开图片 |
| `⌘⇧O` | 打开文件夹 |
| `⌘C` | 复制图片 |
| `⌘⇧C` | 复制文件 |
| `⌘⌥C` | 复制文件路径 |
| `⌘⌫` | 移到废纸篓 |
| `⌘E` | 用外部应用打开 |
| `⌘⌥E` | 在 Finder 中显示 |

### 视图

| 按键 | 功能 |
|---|---|
| `I` | 切换信息面板 |
| `T` | 切换缩略图条 |
| `S` | 切换帧条 |
| `F` | 切换全屏 |
| `⌘⌥F` | 开始幻灯片放映 |
| `?` | 快捷键帮助 |

### 编辑

| 按键 | 功能 |
|---|---|
| `K` | 裁剪 |
| `P` | 取色器 |
| `⌘⇧S` | 导出图片 |
| `⌘[` `⌘]` | 左旋 / 右旋 |
| `⌘⇧H` | 水平翻转 |
| `⌘D` | 切换收藏 |
| `⌘A` | 全选（网格） |
| `⌘⇧A` | 反选（网格） |

## 支持格式

| 分类 | 格式 |
|---|---|
| 常用 | JPEG、PNG、GIF、BMP、TIFF、ICO |
| Apple | HEIC、HEIF |
| Web | WebP、AVIF |
| RAW | CR2、CR3、NEF、ARW、DNG、ORF、RW2、RAF、SRW、PEF、SRF、SR2、3FR、FFF、X3F、MEF、MOS |
| 专业 | PSD、PSB |
| 归档 | ZIP、CBZ |

## 从源码构建

### 环境要求

- macOS 15.6+
- Xcode 26.5+

### 构建

```bash
# Release 构建（签名）
Scripts/build.sh

# 打包 DMG
Scripts/package_dmg.sh
```

## 支持项目

Readpic 完全免费、开源。它也是一个 vibe coding 产品，最初的想法很简单：macOS 上好用的看图软件几乎都要收费，所以我想做一个真正免费的看图软件。

不过，如果你愿意且手头宽裕的话，也可以选择支持一下。无论是否捐赠，功能完全一样，也感谢你的使用。

- [GitHub Sponsors](https://github.com/sponsors/djsunsteam-ux)
- [Ko-fi](https://ko-fi.com/djsunsteam)

国内用户也可以用微信或支付宝：

| 微信支付 | 支付宝 |
|---|---|
| <img src=".github/assets/donate-wechat.png" width="180" alt="微信支付捐赠二维码"> | <img src=".github/assets/donate-alipay.jpg" width="180" alt="支付宝捐赠二维码"> |

也支持区块链捐赠：

- USDT TRC20：`TShU1sP4vaDNQhZuV1JDjpZyqVxn7fESy9`

## 许可证

MIT
