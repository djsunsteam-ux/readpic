import AppKit
import SwiftUI

struct ViewerView: View {
    @Bindable var model: ViewerModel
    @State private var keyMonitor: Any?

    private var barsHidden: Bool {
        model.isFullScreen && !model.cursorNearTop && !model.cursorNearBottom
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ViewerToolbar(model: model)
                    .opacity(barsHidden ? 0 : 1)
                    .frame(height: barsHidden ? 0 : 40)
                    .clipped()
                    .animation(.easeInOut(duration: 0.15), value: barsHidden)

                ZStack(alignment: .bottom) {
                    model.isFullScreen ? Color.black : model.settings.backgroundColor.color

                    if model.currentFile == nil {
                        EmptyStateView(model: model)
                    } else if model.isGridView {
                        GridView(
                            files: model.files,
                            currentIndex: model.currentIndex,
                            selectedIndex: nil,
                            select: { _ in },
                            open: { model.openFromGrid(at: $0) }
                        )
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

                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
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
                        .padding(.bottom, 16)
                    }

                    if model.showShortcutsHelp {
                        ShortcutsHelpView()
                    }
                }
                .frame(maxHeight: .infinity)

                if model.files.count > 1 && model.showThumbnailStrip && !model.isGridView {
                    ThumbnailStripView(
                        files: model.files,
                        currentIndex: model.currentIndex,
                        select: { model.selectFile(at: $0) }
                    )
                    .transition(.move(edge: .bottom))
                }
                if model.settings.showStatusBar && !model.statusText.isEmpty {
                    Text(model.statusText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .frame(height: barsHidden ? 0 : 26)
                        .clipped()
                        .opacity(barsHidden ? 0 : 1)
                        .animation(.easeInOut(duration: 0.15), value: barsHidden)
                }
            }
            .background(Color.black)

            if model.isInfoPanelVisible {
                InfoPanelView(model: model)
                    .transition(.move(edge: .trailing))
            }
        }
        .background {
            WindowAccessor { window in
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
                    if event.keyCode == 53 { model.isGridView = false; return nil }
                }
                if chars == "?" { model.toggleShortcutsHelp(); return nil }
                if event.keyCode == 53 {
                    if model.showShortcutsHelp { model.showShortcutsHelp = false; return nil }
                    if model.isInfoPanelVisible { model.isInfoPanelVisible = false; return nil }
                    if model.isGridView { model.isGridView = false; return nil }
                    model.closeWindow(); return nil
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = keyMonitor as? NSObjectProtocol {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

private struct ViewerToolbar: View {
    let model: ViewerModel

    var body: some View {
        HStack(spacing: 8) {
            ToolbarButton(title: "Open", systemImage: "doc", action: model.showOpenPanel)

            Divider()
                .frame(height: 18)

            ToolbarButton(title: "Grid", systemImage: "square.grid.3x3", action: model.toggleGridView)
                .disabled(model.currentFile == nil && !model.isGridView)
            ToolbarButton(title: "Fit", systemImage: "arrow.up.left.and.arrow.down.right", action: model.setFitMode)
                .disabled(model.currentFile == nil)
            Button("100%") {
                model.setActualSizeMode()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 13, weight: .medium))
            .disabled(model.currentFile == nil)

            Divider()
                .frame(height: 18)

            ToolbarButton(title: "Rotate Left", systemImage: "rotate.left", action: model.rotateLeft)
                .disabled(model.currentFile == nil)
            ToolbarButton(title: "Rotate Right", systemImage: "rotate.right", action: model.rotateRight)
                .disabled(model.currentFile == nil)

            Divider()
                .frame(height: 18)

                    ToolbarButton(title: "Thumbnails", systemImage: "rectangle.3.group") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            model.toggleThumbnailStrip()
                        }
                    }
                .disabled(model.currentFile == nil)

            ToolbarButton(title: "Info", systemImage: "info.circle", action: model.toggleInfoPanel)

            ToolbarButton(title: "Finder", systemImage: "folder", action: model.revealInFinder)
                .disabled(model.currentFile == nil)

            Spacer()
        }
        .padding(.horizontal, 10)
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

            Text("Supports JPEG, PNG, HEIC, WebP, GIF, TIFF, BMP")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .padding(32)
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
                    shortcutRow("\u{2190} / \u{2192}", "Previous / Next image")
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
                    shortcutRow("\u{2303}\u{2318}F", "Toggle fullscreen")
                    shortcutRow("\u{2318}[ / \u{2318}]", "Rotate left / right")
                    shortcutRow("\u{2318}\u{21E7}H", "Flip horizontal")
                    shortcutRow("T", "Toggle thumbnail strip")
                }
            }
            .padding(24)
            .frame(width: 380)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14))
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
