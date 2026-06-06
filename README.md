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

### Edit

| Key | Action |
|---|---|
| `K` | Crop |
| `P` | Color picker |
| `⌘⇧S` | Export image |
| `⌘[` `⌘]` | Rotate left / right |
| `⌘⇧H` | Flip horizontal |
| `⌘D` | Toggle favorite |
| `⌘A` | Select all (grid) |
| `⌘⇧A` | Invert selection (grid) |

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

### Run Tests

Open `Readpic.xcodeproj` in Xcode and press `⌘U`.

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
