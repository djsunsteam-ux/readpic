# Readpic

A fast, lightweight image viewer for macOS. **Free and open source.**

> Great macOS image viewers are almost always paid. Readpic combines the best of them into a truly free, ready-to-use alternative.

English | [简体中文](README.zh-CN.md)

## Features

- **30+ formats**: JPEG, PNG, HEIC, WebP, GIF, TIFF, BMP, AVIF, PSD, 17 RAW formats, ZIP/CBZ
- **Fast browsing**: Natural sort, keyboard navigation, thumbnail grid
- **Zoom & pan**: Fit window, fit width, actual size, cursor-anchored zoom, mouse drag pan
- **GIF animation**: Frame-by-frame playback, pause, frame strip
- **Cropping**: Free & preset aspect ratios, interactive drag handles
- **Info panel**: EXIF, IPTC, XMP metadata, histogram, color picker
- **Batch operations**: Convert, rename, export
- **Fullscreen**: Auto-hiding toolbar, slideshow mode
- **Localization**: English, 简体中文

## Why Readpic

| Feature | Readpic | macOS Preview | qView | XnView MP | Pixea |
|---|:---:|:---:|:---:|:---:|:---:|
| **Price** | Free (MIT) | Free | Free (GPL) | Personal free | Free |
| **Native Apple Silicon** | ✅ | ✅ | ❌ | ❌ | ✅ |
| **Zero network access** | ✅ | ✅ | ✅ | ❌ | ✅ |
| **Formats** | 30+ | ~15 | ~20 | 500+ | ~20 |
| **RAW (17 types)** | ✅ | Limited | ❌ | ✅ | ❌ |
| **PSD / PSB** | ✅ | ❌ | ❌ | ✅ | ❌ |
| **ZIP / CBZ** | ✅ | ❌ | ❌ | ✅ | ❌ |
| **Thumbnail grid** | ✅ | ❌ | ❌ | ✅ | ❌ |
| **Subfolder grouping** | ✅ | ❌ | ❌ | ✅ | ❌ |
| **EXIF + Histogram + Color picker** | ✅ | Partial | ❌ | ✅ | ❌ |
| **Crop** | ✅ | ✅ | ❌ | ✅ | ❌ |
| **Batch convert & rename** | ✅ | ❌ | ❌ | ✅ | ❌ |
| **Slideshow** | ✅ | ✅ | ❌ | ✅ | ❌ |
| **Set as wallpaper** | ✅ | ❌ | ❌ | ✅ | ❌ |
| **UI design** | Clean, native | Clean, minimal | Minimal | Complex, dated | Clean |

macOS image viewers are almost always paid — Pixave ($9.99), PicView ($9.99), Lynx ($16.99), ApolloOne ($14.99), Photo Mechanic ($139). Readpic delivers the same (or better) capability set **for free**.

Readpic sits in the sweet spot between macOS Preview and heavyweight tools like XnView — **more capable than any free native viewer, lighter and faster than any cross-platform alternative**.

### App size comparison

| Readpic | PicView | Pixave | qView | ApolloOne | Pixea | XnView MP |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **4 MB** | ~6 MB | ~7 MB | ~44 MB | ~32 MB | ~194 MB | ~103 MB |

Highlights:

- **Polished, intuitive UI** — clean and minimal interface built with SwiftUI, following macOS design conventions; XnView MP offers more features but its interface feels cluttered and dated with a Windows-era layout
- **Free + open source + full-featured** — the only macOS image viewer that combines MIT license, 30+ formats, batch operations, and a pro-level info panel at zero cost
- **Zero network, total privacy** — no telemetry, no update checks, no data collection; everything runs locally
- **M-chip only optimization** — built exclusively for Apple Silicon, no Intel compatibility overhead; faster startup, lower memory, smoother scrolling
- **ZIP / CBZ browsing** — open comic archives directly without extraction
- **Pro tools built in** — histogram, color picker, EXIF/IPTC/XMP metadata, batch convert, batch rename — all in one free package
- **Subfolder recursive scanning** — open a parent folder and browse all nested images, auto-grouped by subfolder

## Requirements

- macOS 15.6+
- Apple Silicon (M1 or later). Intel Macs are not supported.

## Installation

1. Download `Readpic.dmg` from [Releases](https://github.com/djsunsteam-ux/readpic/releases)
2. Open the DMG
3. Drag **Readpic** to **Applications**
4. Launch from Applications or Spotlight

## First Launch

Readpic is not notarized with Apple. On first launch:

1. Right-click **Readpic.app** → select **Open**
2. Click **Open** in the dialog
3. The app will open normally from then on

Alternatively:

1. Double-click to attempt opening
2. Go to **System Settings → Privacy & Security**
3. Click **Open Anyway** next to "Readpic was blocked"

## Privacy & Security

Readpic does not include any networking features and does not request network access. It does not collect, upload, or analyze any personal data, image files, or image contents. All image decoding, browsing, metadata reading, and editing happen locally on your Mac.

## Keyboard Shortcuts

<table>
<tr>
<td>

### Navigation

| Key | Action |
|---|---|
| `←` `→` | Previous / Next image |
| `↑` `↓` | Grid: select up / down |
| `Space` | Pause / Resume GIF |
| `G` | Toggle grid view |
| `Esc` | Close panel / exit fullscreen / stop slideshow |

### Zoom

| Key | Action |
|---|---|
| `⌘=` `⌘-` | Zoom in / out |
| `⌘0` | Reset zoom (fit window) |
| `+` `-` `0` | Same (no modifier) |
| Double-click | Toggle fit / 100% |
| Pinch | Zoom toward cursor |
| Scroll + `⌥` | Zoom toward cursor |

### Edit

| Key | Action |
|---|---|
| `C` | Toggle crop mode |
| `P` | Color picker |
| `⌘⇧S` | Export image |
| `⌘[` `⌘]` | Rotate left / right |
| `⌘⇧H` | Flip horizontal |
| `⌘D` | Toggle favorite |

</td>
<td>

### File

| Key | Action |
|---|---|
| `⌘O` | Open image |
| `⌘⇧O` | Open folder |
| `⌘C` | Copy image |
| `⌘⇧C` | Copy file |
| `⌘⌥C` | Copy file path |
| `⌘⌫` | Move to trash |
| `⌘E` | Open externally |
| `⌘⌥E` | Reveal in Finder |

### View

| Key | Action |
|---|---|
| `I` | Toggle info panel |
| `T` | Toggle thumbnail strip |
| `S` | Toggle frame strip |
| `F` | Toggle fullscreen |
| `⌘⌥F` | Start slideshow |
| `?` | Keyboard shortcuts |

### Slideshow

| Key | Action |
|---|---|
| `←` `→` | Previous / Next slide |
| `Space` | Pause / Resume |
| Swipe left/right | Previous / Next slide |
| `Esc` | Stop slideshow |

### Grid Selection

| Key | Action |
|---|---|
| `⌘A` | Select all |
| `⌘⇧A` | Invert selection |

</td>
</tr>
</table>

## Supported Formats

| Category | Formats |
|---|---|
| Common | JPEG, PNG, GIF, BMP, TIFF, ICO |
| Apple | HEIC, HEIF |
| Web | WebP, AVIF |
| RAW | CR2, CR3, NEF, ARW, DNG, ORF, RW2, RAF, SRW, PEF, SRF, SR2, 3FR, FFF, X3F, MEF, MOS |
| Professional | PSD, PSB |
| Archive | ZIP, CBZ |

## Building from Source

### Requirements

- macOS 15.6+
- Xcode 26.5+

### Build

```bash
# Release (signed)
Scripts/build.sh

# Package DMG
Scripts/package_dmg.sh
```

## Support

Readpic is completely free and open source. It is also a vibe coding project that started from a simple frustration: most good macOS image viewers are paid, so I wanted to make a genuinely free one.

If you are willing and have a little room to spare, you can choose to support the project. Donation or not, every feature stays exactly the same. Thank you for using Readpic either way.

- [Sponsor on GitHub](https://github.com/sponsors/djsunsteam-ux)
- [Support on Ko-fi](https://ko-fi.com/djsunsteam)

For users in China:

| WeChat Pay | Alipay |
|---|---|
| <img src=".github/assets/donate-wechat.png" width="180" alt="WeChat Pay donation QR code"> | <img src=".github/assets/donate-alipay.jpg" width="180" alt="Alipay donation QR code"> |

Crypto:

- USDT TRC20: `TShU1sP4vaDNQhZuV1JDjpZyqVxn7fESy9`

## License

MIT
