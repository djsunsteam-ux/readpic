# Readpic

A fast, lightweight image viewer for macOS.

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

### Homebrew (recommended)

```bash
brew install --cask readpic
```

### Manual

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

## Keyboard Shortcuts

### Navigation

| Key | Action |
|---|---|
| `←` `→` | Previous / Next image |
| `Space` | Pause / Resume GIF |
| `G` | Toggle grid view |

### Zoom

| Key | Action |
|---|---|
| `+` `-` | Zoom in / out |
| `0` | Reset zoom (fit window) |
| Double-click | Toggle fit / 100% |

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
| `⌘I` | Toggle info panel |
| `⌘T` | Toggle thumbnail strip |
| `⌘F` | Toggle fullscreen |
| `?` | Keyboard shortcuts |

### Edit

| Key | Action |
|---|---|
| `K` | Crop |
| `P` | Color picker |
| `⌘⇧S` | Export image |
| `⌘S` | Save changes (rotate/flip) |

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

## License

MIT
