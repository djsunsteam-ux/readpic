import SwiftUI

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var model: ViewerModel?
    private var pendingURLs: [URL] = []

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Called once the scene's model exists; replays URLs delivered at launch.
    func attach(_ model: ViewerModel) {
        Self.model = model
        guard !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs.removeAll()
        model.open(urls: urls)
        NSApp.activate()
    }

    private func deliver(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard let model = Self.model else {
            pendingURLs.append(contentsOf: urls)
            return
        }
        model.open(urls: urls)
        NSApp.activate()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        deliver(urls)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        deliver(filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        deliver([URL(fileURLWithPath: filename)])
        return true
    }
}

@main
struct ReadpicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = ViewerModel()

    init() {
        // Suppress macOS 15 Shortcuts/Intents auto-registration warnings.
        // AppKit unconditionally tries to XPC into com.apple.linkd.autoShortcut
        // during launch. When linkd is unavailable it logs a benign Code 4097
        // error. Setting this default short-circuits the registration.
        UserDefaults.standard.register(defaults: [
            "NSApplicationSupportsSecureRestorableState": true
        ])

        #if SWIFT_PACKAGE
        // Copy .lproj from module bundle to main bundle so Text("key") resolves
        let fm = FileManager.default
        if let mainRes = Bundle.main.resourcePath ?? Bundle.main.bundlePath as String?,
           let moduleRes = Bundle.loc.resourcePath {
            for locale in ["en", "zh-Hans"] {
                let src = moduleRes + "/" + locale + ".lproj"
                let dst = mainRes + "/" + locale + ".lproj"
                if fm.fileExists(atPath: src) && !fm.fileExists(atPath: dst) {
                    try? fm.copyItem(atPath: src, toPath: dst)
                }
            }
        }
        #endif
    }

    private var currentLocale: Locale {
        Localizer.shared.locale
    }

    var body: some Scene {
        WindowGroup {
            ViewerView(model: model)
                .frame(minWidth: 720, minHeight: 480)
                .environment(\.locale, currentLocale)
                .preferredColorScheme(model.settings.theme == .dark ? .dark : model.settings.theme == .light ? .light : nil)
                .onAppear { appDelegate.attach(model) }
        }
        .commands {
            // MARK: - File
            CommandGroup(replacing: .newItem) {
                Button(L("Open Image\u{2026}")) { model.showOpenPanel() }
                    .keyboardShortcut("o", modifiers: .command)

                Button(L("Open Folder\u{2026}")) { model.showOpenFolderPanel() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            CommandGroup(after: .newItem) {
                Menu(L("Open Recent")) {
                    let recents = model.settings.recentFolders
                    if recents.isEmpty {
                        Text.loc("No Recent Folders")
                    }
                    ForEach(recents, id: \.self) { url in
                        Button(url.lastPathComponent) { model.openFolder(url) }
                    }
                    if !recents.isEmpty {
                        Divider()
                        Button(L("Clear Recent")) { model.settings.clearRecentFolders() }
                    }
                }

                Button(L("Export / Convert\u{2026}")) { model.showExport() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(model.currentFile == nil || (model.isGridView && model.selectedGridIndices.isEmpty))

                Divider()

                Button(L("Move to Trash")) { model.moveCurrentFileToTrash() }
                    .keyboardShortcut(.delete, modifiers: .command)

                Divider()

                Button(L("Reveal in Finder")) { model.revealInFinder() }
                    .keyboardShortcut("e", modifiers: [.command, .option])
                    .disabled(model.currentFile == nil)

                Button(L("Open Externally")) { model.openExternally() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(model.currentFile == nil)

                Divider()

                Button(L("Batch Convert / Export\u{2026}")) { model.showBatchExport() }
                    .disabled(!model.isGridView || model.selectedGridIndices.count < 2)

                Button(L("Batch Rename\u{2026}")) { model.showBatchRename() }
                    .disabled(!model.isGridView || model.selectedGridIndices.count < 2)
            }

            // MARK: - App Info
            CommandGroup(replacing: .appInfo) {
                Button(L("About Readpic")) { NSApp.orderFrontStandardAboutPanel(nil) }
            }

            // MARK: - Edit
            CommandGroup(replacing: .pasteboard) {
                Button(L("Copy Image")) { model.copyImage() }
                    .keyboardShortcut("c", modifiers: .command)
                    .disabled(model.decodedImage == nil)

                Button(L("Copy File")) { model.copyFile() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(model.currentFile == nil)

                Button(L("Copy File Path")) { model.copyFilePath() }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                    .disabled(model.currentFile == nil)

                Divider()

                Button(L("Select All")) { model.selectAllGrid() }
                    .keyboardShortcut("a", modifiers: .command)
                    .disabled(!model.isGridView || model.files.isEmpty)

                Button(L("Invert Selection")) { model.invertGridSelection() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(!model.isGridView || model.files.isEmpty)

                Divider()

                Button(L("Copy Metadata")) { model.copyMetadata() }
                    .disabled(model.metadata == nil)
            }

            // MARK: - View
            CommandMenu(L("Navigate")) {
                Button(L("Grid View")) { model.toggleGridView() }
                    .keyboardShortcut("g")
                    .disabled(model.currentFile == nil && !model.isGridView)

                Divider()

                Button(L("Fit Window")) { model.setFitMode() }
                    .disabled(model.currentFile == nil)

                Button(L("Fit Width")) { model.setFitWidthMode() }
                    .disabled(model.currentFile == nil)

                Button(L("Actual Size")) { model.setActualSizeMode() }
                    .disabled(model.currentFile == nil)

                Divider()

                Button(L("Zoom In")) { model.zoomIn() }
                    .keyboardShortcut("=", modifiers: .command)
                    .disabled(model.currentFile == nil)

                Button(L("Zoom Out")) { model.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(model.currentFile == nil)

                Button(L("Reset Zoom")) { model.resetZoom() }
                    .keyboardShortcut("0", modifiers: .command)
                    .disabled(model.currentFile == nil)

                Divider()

                Button(L("Thumbnail Strip")) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        model.toggleThumbnailStrip()
                    }
                }
                .disabled(model.currentFile == nil)

                Button(L("Frame Strip")) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        model.toggleFrameStrip()
                    }
                }
                .keyboardShortcut("s")
                .disabled(!model.hasAnimatedFrames || model.isGridView)

                Button(L("Info Panel")) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        model.toggleInfoPanel()
                    }
                }
                .keyboardShortcut("i")

                Divider()

                Menu(L("Sort By")) {
                    Button(L("Name")) { model.setSortMode(.name) }
                    Button(L("Date")) { model.setSortMode(.date) }
                }

                if model.isGridView {
                    Menu(L("Filter By")) {
                        Menu(L("Format")) {
                            ForEach(ViewerModel.FileFormatFilter.allCases, id: \.rawValue) { fmt in
                                Button(L(fmt.rawValue)) { model.formatFilter = fmt }
                            }
                        }
                        Menu(L("Date")) {
                            ForEach(ViewerModel.DateFilter.allCases, id: \.rawValue) { d in
                                Button(L(d.rawValue)) { model.dateFilter = d }
                            }
                        }
                    }

                }

                Divider()

                Button(L("Show Status Bar")) { model.settings.showStatusBar.toggle() }

                Divider()

                Button(L("Fullscreen")) { model.toggleFullScreen() }
                    .keyboardShortcut("f")

                Divider()

                Button(L("Start Slideshow")) { model.toggleSlideshow() }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                    .disabled(model.activeFile == nil || (model.activeFile?.url.pathExtension.lowercased() == "gif"))
            }

            // MARK: - Image
            CommandMenu(L("Image")) {
                Button(L("Crop\u{2026}")) { model.enterCropMode() }
                    .keyboardShortcut("k")
                    .disabled(!model.isGridView && model.currentFile == nil)

                Button(L("Rotate Left")) { model.rotateLeft() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(model.currentFile == nil)

                Button(L("Rotate Right")) { model.rotateRight() }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(model.currentFile == nil)

                Button(L("Flip Horizontal")) { model.flipHorizontal() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                    .disabled(model.currentFile == nil)

                Button(L("Color Picker")) { model.toggleColorPickerMode() }
                    .keyboardShortcut("p")
                    .disabled(model.currentFile == nil)

                Divider()

                Menu(L("Rate")) {
                    Button(L("None")) { model.rateCurrentFile(0) }
                    Divider()
                    ForEach(1...5, id: \.self) { rating in
                        Button(String(repeating: "★", count: rating)) {
                            model.rateCurrentFile(rating)
                        }
                    }
                }
                .disabled(model.currentFile == nil)

                Button(L("Toggle Favorite")) { model.toggleFavorite() }
                    .keyboardShortcut("d", modifiers: .command)
                    .disabled(model.currentFile == nil)

                Divider()

                Button(L("Save Changes")) { model.saveChanges() }
                    .disabled(model.currentFile == nil || (model.rotation == 0 && !model.isFlippedHorizontally))

                Divider()

                Button(L("Set as Desktop Wallpaper")) { model.setDesktopWallpaper() }
                    .disabled(model.currentFile == nil)

                Divider()

                Button(L("Batch Convert / Export\u{2026}")) { model.showBatchExport() }
                    .disabled(!model.isGridView || model.selectedGridIndices.count < 2)

                Button(L("Batch Rename\u{2026}")) { model.showBatchRename() }
                    .disabled(!model.isGridView || model.selectedGridIndices.count < 2)
            }

            // MARK: - Help
            CommandMenu(L("Help")) {
                Button(L("Keyboard Shortcuts")) { model.toggleShortcutsHelp() }
                    .keyboardShortcut("?", modifiers: [])
            }
        }

        Settings {
            SettingsView(settings: model.settings)
        }
    }
}
