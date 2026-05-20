import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ViewerView: View {
    @Bindable var model: ViewerModel
    @State private var keyMonitor: Any?

    private var barsHidden: Bool {
        model.isFullScreen && !model.cursorNearTop && !model.cursorNearBottom
    }

    private var gridTopInset: CGFloat {
        barsHidden ? 0 : 40
    }

    private var gridBottomInset: CGFloat {
        guard !barsHidden else { return 0 }
        var height: CGFloat = 0
        if model.showFrameStrip && model.hasAnimatedFrames { height += 80 }
        if model.settings.showStatusBar && !model.statusText.isEmpty { height += 26 }
        return height
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Canvas fills the entire ZStack
            ZStack(alignment: .bottom) {
                model.isFullScreen ? Color.black : model.settings.backgroundColor.color

                if model.currentFile == nil {
                    EmptyStateView(model: model)
                } else if model.isGridView {
                    GridView(
                        files: model.files,
                        currentIndex: model.currentIndex,
                        selectedIndices: model.selectedGridIndices,
                        handleClick: { index, isCmd, isShift in
                            if isCmd {
                                model.toggleGridSelection(at: index)
                            } else if isShift {
                                model.selectGridRange(from: model.lastGridClickedIndex, to: index)
                            } else {
                                model.selectInGrid(at: index)
                            }
                        },
                        open: { model.openFromGrid(at: $0) },
                        topInset: gridTopInset,
                        bottomInset: gridBottomInset,
                        infoPanelVisible: model.isInfoPanelVisible
                    )
                    .id(model.fileListVersion)
                    .padding(.trailing, model.isInfoPanelVisible ? 300 : 0)
                } else {
                    ViewerRepresentable(model: model)
                }

                if model.isDragTargeted {
                    DragHoverOverlay()
                }

                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .frame(maxHeight: .infinity, alignment: .center)
                }

                if let toastMessage = model.toastMessage {
                    HStack(spacing: 12) {
                        Text(toastMessage)
                            .font(.system(size: 13))

                        if let actionTitle = model.toastActionTitle {
                            Button(actionTitle) {
                                model.performToastAction()
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 13, weight: .medium))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .frame(maxHeight: .infinity, alignment: .center)
                }

                if model.showShortcutsHelp {
                    ShortcutsHelpView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async {
                        var isDirectory: ObjCBool = false
                        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                            model.openFolder(url)
                        } else {
                            model.open(url)
                        }
                    }
                }
                return true
            }

            // ── Info Panel floats over the canvas, right-aligned ──
            if model.isInfoPanelVisible {
                HStack(spacing: 0) {
                    Spacer()
                    InfoPanelView(model: model)
                        .transition(.move(edge: .trailing))
                }
            }

            // ── Toolbar overlaid at top ──
            ViewerToolbar(model: model)
                .frame(height: barsHidden ? 0 : 40)
                .background(.ultraThinMaterial)
                .opacity(barsHidden ? 0 : 1)
                .animation(.easeInOut(duration: 0.15), value: barsHidden)
                .clipped()
                .zIndex(2)

            // ── Bottom bars overlaid at bottom ──
            VStack(spacing: 0) {
                Spacer()

                if model.showFrameStrip, model.hasAnimatedFrames, let frames = model.decodedImage?.animatedFrames {
                    FrameStripView(
                        frames: frames.map(\.image),
                        totalFrameCount: model.decodedImage?.frameCount ?? frames.count,
                        currentIndex: model.currentFrameIndex,
                        isPlaying: model.isAnimating && !model.isAnimationPaused,
                        onSelect: { model.selectFrame(at: $0) },
                        onTogglePlay: { model.toggleAnimationPause() }
                    )
                    .transition(.move(edge: .bottom))
                }

                if model.files.count > 1 && model.showThumbnailStrip && !model.isGridView {
                    ThumbnailStripView(
                        files: model.files,
                        currentIndex: model.currentIndex,
                        select: { model.selectFile(at: $0) }
                    )
                    .id(model.fileListVersion)
                    .transition(.move(edge: .bottom))
                }

                if model.settings.showStatusBar && !model.statusText.isEmpty {
                    HStack(spacing: 6) {
                        if model.isLoading {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.6)
                        }
                        Text(model.statusText)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: barsHidden ? 0 : 26)
                    .background(.ultraThinMaterial)
                    .clipped()
                    .opacity(barsHidden ? 0 : 1)
                    .animation(.easeInOut(duration: 0.15), value: barsHidden)
                }
            }
            .zIndex(2)
        }
        .background(Color.black)
        .background {
            WindowAccessor { window in
                model.window = window
                // Keep the title bar opaque — prevents ScrollView content from extending
                // behind it (which triggers the system's title-bar vibrancy in GridView).
                window.styleMask.remove(.fullSizeContentView)
                if !window.setFrameUsingName("mainWindow") {
                    window.setFrame(NSRect(x: 0, y: 0, width: 1280, height: 800), display: false)
                    window.center()
                }
                window.setFrameAutosaveName("mainWindow")
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak model] event in
                guard let model else { return event }
                let chars = event.characters

                if model.isGridView {
                    if chars == "g" { model.toggleGridView(); return nil }
                    switch event.keyCode {
                    case 123: model.gridSelectPrevious(); return nil
                    case 124: model.gridSelectNext(); return nil
                    case 125:
                        let infoWidth: CGFloat = model.isInfoPanelVisible ? 300 : 0
                        if let window = NSApp.keyWindow, let content = window.contentView {
                            let available = content.frame.width - 32 - infoWidth
                            let columns = max(1, Int(available / 162))
                            model.gridSelectDown(columns: columns)
                        }
                        return nil
                    case 126:
                        let infoWidth: CGFloat = model.isInfoPanelVisible ? 300 : 0
                        if let window = NSApp.keyWindow, let content = window.contentView {
                            let available = content.frame.width - 32 - infoWidth
                            let columns = max(1, Int(available / 162))
                            model.gridSelectUp(columns: columns)
                        }
                        return nil
                    default: break
                    }
                }
                if chars?.lowercased() == "g" {
                    let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    if mods.isEmpty || mods == .shift || mods == .capsLock {
                        model.toggleGridView()
                        return nil
                    }
                }
                if chars?.lowercased() == "i" {
                    let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    if mods.isEmpty || mods == .shift || mods == .capsLock {
                        withAnimation(.easeInOut(duration: 0.2)) { model.toggleInfoPanel() }
                        return nil
                    }
                }
                if chars?.lowercased() == "t" {
                    let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    if mods.isEmpty || mods == .shift || mods == .capsLock {
                        withAnimation(.easeInOut(duration: 0.2)) { model.toggleThumbnailStrip() }
                        return nil
                    }
                }
                if chars?.lowercased() == "s" {
                    let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    if mods.isEmpty || mods == .shift || mods == .capsLock {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            model.toggleFrameStrip()
                        }
                        return nil
                    }
                }
                if chars == "?" { model.toggleShortcutsHelp(); return nil }
                if chars?.lowercased() == "f" {
                    let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    if mods.isEmpty || mods == .shift || mods == .capsLock {
                        model.toggleFullScreen()
                        return nil
                    }
                }
                if event.keyCode == 53 {
                    if model.showShortcutsHelp {
                        withAnimation(.easeInOut(duration: 0.15)) { model.showShortcutsHelp = false }
                        return nil
                    }
                    if model.isInfoPanelVisible {
                        withAnimation(.easeInOut(duration: 0.2)) { model.isInfoPanelVisible = false }
                        return nil
                    }
                    if model.isFullScreen { model.toggleFullScreen(); return nil }
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = keyMonitor as? NSObjectProtocol {
                NSEvent.removeMonitor(monitor)
            }
        }
        .sheet(isPresented: $model.showExportPanel) {
            if let url = model.exportFileURL {
                ExportView(
                    fileURL: url,
                    sourceWidth: Int(model.metadata?.pixelSize.width ?? 0),
                    sourceHeight: Int(model.metadata?.pixelSize.height ?? 0),
                    rotation: model.rotation,
                    isFlipped: model.isFlippedHorizontally,
                    onComplete: { model.showExportPanel = false }
                )
            }
        }
        .sheet(isPresented: $model.showBatchExportPanel) {
            BatchConvertView(
                files: Array(model.selectedFiles),
                onComplete: { model.showBatchExportPanel = false }
            )
        }
    }
}

private struct ViewerToolbar: View {
    let model: ViewerModel

    private var disabled: Bool {
        model.currentFile == nil || model.isGridView
    }

    var body: some View {
        HStack(spacing: 8) {
            ToolbarButton(title: model.isGridView ? "Viewer" : "Grid", systemImage: model.isGridView ? "photo" : "square.grid.3x3", action: model.toggleGridView)
                .disabled(model.currentFile == nil)

            Divider()
                .frame(height: 18)

            ToolbarButton(title: "Zoom Out", systemImage: "minus.magnifyingglass", action: model.zoomOut)
                .disabled(disabled)
            ToolbarButton(title: "Fit", systemImage: "1.magnifyingglass", action: model.setFitMode)
                .disabled(disabled)
            ToolbarButton(title: "Zoom In", systemImage: "plus.magnifyingglass", action: model.zoomIn)
                .disabled(disabled)

            Divider()
                .frame(height: 18)

            ToolbarButton(title: "Rotate Left", systemImage: "rotate.left", action: model.rotateLeft)
                .disabled(disabled)
            ToolbarButton(title: "Rotate Right", systemImage: "rotate.right", action: model.rotateRight)
                .disabled(disabled)
            ToolbarButton(title: "Mirror", systemImage: "flip.horizontal", action: model.flipHorizontal)
                .disabled(disabled)

            Divider()
                .frame(height: 18)

            ToolbarButton(title: "Thumbnails", systemImage: "rectangle.split.3x1") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    model.toggleThumbnailStrip()
                }
            }
            .disabled(disabled)

            ToolbarButton(title: "Info", systemImage: "info.circle") {
                withAnimation(.easeInOut(duration: 0.2)) { model.toggleInfoPanel() }
            }
            .disabled(!model.isGridView && model.currentFile == nil)

            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

private struct ToolbarButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .help(title)
    }
}

private struct DragHoverOverlay: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .stroke(Color.accentColor, lineWidth: 2)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                Text("Release to open")
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(18)
    }
}

private struct EmptyStateView: View {
    let model: ViewerModel

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                Image(systemName: "photo")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.secondary)

                VStack(spacing: 6) {
                    Text("Readpic")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Drop images or folders here")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button("Open Image") {
                        model.showOpenPanel()
                    }
                    .keyboardShortcut("o", modifiers: .command)

                    Button("Open Folder") {
                        model.showOpenFolderPanel()
                    }
                }

                if model.settings.rememberLastFolder, let lastURL = model.settings.lastFolderURL {
                    Button {
                        model.openFolder(lastURL)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text("Open Recent Folder")
                        }
                        .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(lastURL.path)
                }

                Text("Supports JPEG, PNG, HEIC, WebP, GIF, TIFF, BMP, ICO")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 10) {
                Spacer()

                Divider()
                    .frame(width: 200)

                Text("Keyboard Shortcuts")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 40) {
                    VStack(alignment: .leading, spacing: 5) {
                        shortcutItem("\u{2190} / \u{2192}", "Previous / Next")
                        shortcutItem("G", "Grid view")
                        shortcutItem("I", "Info panel")
                        shortcutItem("Space", "Play / Pause")
                        shortcutItem("Esc", "Close overlay")
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        shortcutItem("\u{2318}O", "Open file")
                        shortcutItem("\u{2318}\u{232B}", "Move to Trash")
                        shortcutItem("\u{2318}C", "Copy image")
                        shortcutItem("+ / -", "Zoom in/out")
                        shortcutItem("?", "Help")
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .padding(32)
    }

    private func shortcutItem(_ key: String, _ description: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(minWidth: 50, alignment: .leading)
            Text(description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ShortcutsHelpView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Text("Keyboard Shortcuts")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.bottom, 16)

                shortcutsGroup("Navigation") {
                    shortcutRow("\u{2190} / \u{2192} / \u{2191} / \u{2193}", "Navigate images / grid")
                    shortcutRow("Space", "Play / Pause animation")
                    shortcutRow("G", "Toggle Grid view")
                    shortcutRow("I", "Toggle Info panel")
                    shortcutRow("Esc", "Close overlay / panel / window")
                }

                shortcutsGroup("Zoom") {
                    shortcutRow("+ / -", "Zoom in / out")
                    shortcutRow("0", "Reset zoom")
                    shortcutRow("Double-click", "Fit window / 100%")
                }

                shortcutsGroup("File") {
                    shortcutRow("\u{2318}O", "Open file")
                    shortcutRow("\u{2318}\u{21E7}O", "Open folder")
                    shortcutRow("\u{2318}C", "Copy image")
                    shortcutRow("\u{2318}\u{21E7}C", "Copy file")
                    shortcutRow("\u{2318}\u{2325}C", "Copy path")
                    shortcutRow("\u{2318}\u{2325}E", "Reveal in Finder")
                    shortcutRow("\u{2318}E", "Open externally")
                    shortcutRow("\u{2318}\u{232B}", "Move to Trash")
                }

                shortcutsGroup("View") {
                    shortcutRow("F", "Toggle fullscreen")
                    shortcutRow("\u{2318}[ / \u{2318}]", "Rotate left / right")
                    shortcutRow("\u{2318}\u{21E7}H", "Flip horizontal")
                    shortcutRow("T", "Toggle thumbnail strip")
                    shortcutRow("S", "Toggle frame strip")
                }
            }
            .padding(24)
            .frame(width: 380)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14))
            .offset(y: -20)
        }
    }

    @ViewBuilder
    private func shortcutsGroup(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            content()
        }
    }

    @ViewBuilder
    private func shortcutRow(_ key: String, _ description: String) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(minWidth: 80, alignment: .leading)
            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
