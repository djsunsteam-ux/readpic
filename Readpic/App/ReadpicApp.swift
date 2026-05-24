import SwiftUI

@main
struct ReadpicApp: App {
    @State private var model = ViewerModel()

    init() {
        let lang = UserDefaults.standard.string(forKey: "LanguageMode")
        let langs: [String]
        switch lang {
        case "English":     langs = ["en"]
        case "简体中文":    langs = ["zh-Hans"]
        default:            langs = []
        }
        UserDefaults.standard.set(langs, forKey: "AppleLanguages")
        // Copy .lproj from module bundle to main bundle so Text("key") resolves
        let fm = FileManager.default
        if let mainRes = Bundle.main.resourcePath ?? Bundle.main.bundlePath as String?,
           let moduleRes = Bundle.module.resourcePath {
            for locale in ["en", "zh-Hans"] {
                let src = moduleRes + "/" + locale + ".lproj"
                let dst = mainRes + "/" + locale + ".lproj"
                if fm.fileExists(atPath: src) && !fm.fileExists(atPath: dst) {
                    try? fm.copyItem(atPath: src, toPath: dst)
                }
            }
        }
    }

    var currentLocale: Locale {
        switch model.settings.language {
        case .english: Locale(identifier: "en")
        case .chinese: Locale(identifier: "zh-Hans")
        case .system:  .current
        }
    }

    var body: some Scene {
        WindowGroup {
            ViewerView(model: model)
                .frame(minWidth: 720, minHeight: 480)
                .environment(\.locale, currentLocale)
                .onChange(of: model.settings.language) { _, newValue in
                    let langs: [String]
                    switch newValue {
                    case .english: langs = ["en"]
                    case .chinese: langs = ["zh-Hans"]
                    case .system:  langs = []
                    }
                    UserDefaults.standard.set(langs, forKey: "AppleLanguages")
                }
                .preferredColorScheme(model.settings.theme == .dark ? .dark : model.settings.theme == .light ? .light : nil)
                .onOpenURL { url in
                    model.open(url)
                }
        }
        .commands {
            // MARK: - File
            CommandGroup(replacing: .newItem) {
                Button("Open Image\u{2026}") { model.showOpenPanel() }
                    .keyboardShortcut("o", modifiers: .command)

                Button("Open Folder\u{2026}") { model.showOpenFolderPanel() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            CommandGroup(after: .newItem) {
                Menu("Open Recent") {
                    let recents = model.settings.recentFolders
                    if recents.isEmpty {
                        Text.loc("No Recent Folders")
                    }
                    ForEach(recents, id: \.self) { url in
                        Button(url.lastPathComponent) { model.openFolder(url) }
                    }
                    if !recents.isEmpty {
                        Divider()
                        Button("Clear Recent") { model.settings.clearRecentFolders() }
                    }
                }

                Button("Export / Convert\u{2026}") { model.showExport() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(model.currentFile == nil || model.selectedGridIndices.count >= 2)

                Divider()

                Button("Move to Trash") { model.moveCurrentFileToTrash() }
                    .keyboardShortcut(.delete, modifiers: .command)

                Divider()

                Button("Reveal in Finder") { model.revealInFinder() }
                    .keyboardShortcut("e", modifiers: [.command, .option])
                    .disabled(model.currentFile == nil)

                Button("Open Externally") { model.openExternally() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(model.currentFile == nil)

                Divider()

                Button("Batch Convert / Export\u{2026}") { model.showBatchExport() }
                    .disabled(!model.isGridView || model.selectedGridIndices.count < 2)

                Button("Batch Rename\u{2026}") { model.showBatchRename() }
                    .disabled(!model.isGridView || model.selectedGridIndices.count < 2)
            }

            // MARK: - App Info
            CommandGroup(replacing: .appInfo) {
                Button("About Readpic") { NSApp.orderFrontStandardAboutPanel(nil) }
            }

            // MARK: - Edit
            CommandGroup(replacing: .pasteboard) {
                Button("Copy Image") { model.copyImage() }
                    .keyboardShortcut("c", modifiers: .command)
                    .disabled(model.decodedImage == nil)

                Button("Copy File") { model.copyFile() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(model.currentFile == nil)

                Button("Copy File Path") { model.copyFilePath() }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                    .disabled(model.currentFile == nil)

                Divider()

                Button("Select All") { model.selectAllGrid() }
                    .keyboardShortcut("a", modifiers: .command)
                    .disabled(!model.isGridView || model.files.isEmpty)

                Button("Invert Selection") { model.invertGridSelection() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(!model.isGridView || model.files.isEmpty)

                Divider()

                Button("Copy Metadata") { model.copyMetadata() }
                    .disabled(model.metadata == nil)
            }

            // MARK: - View
            CommandMenu("View") {
                Button("Grid View") { model.toggleGridView() }
                    .keyboardShortcut("g")
                    .disabled(model.currentFile == nil && !model.isGridView)

                Divider()

                Button("Fit Window") { model.setFitMode() }
                    .disabled(model.currentFile == nil)

                Button("Fit Width") { model.setFitWidthMode() }
                    .disabled(model.currentFile == nil)

                Button("Actual Size") { model.setActualSizeMode() }
                    .disabled(model.currentFile == nil)

                Divider()

                Button("Zoom In") { model.zoomIn() }
                    .keyboardShortcut("=", modifiers: .command)
                    .disabled(model.currentFile == nil)

                Button("Zoom Out") { model.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(model.currentFile == nil)

                Button("Reset Zoom") { model.resetZoom() }
                    .keyboardShortcut("0", modifiers: .command)
                    .disabled(model.currentFile == nil)

                Divider()

                Button("Thumbnail Strip") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        model.toggleThumbnailStrip()
                    }
                }
                .disabled(model.currentFile == nil)

                Button("Frame Strip") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        model.toggleFrameStrip()
                    }
                }
                .keyboardShortcut("s")
                .disabled(!model.hasAnimatedFrames || model.isGridView)

                Button("Info Panel") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        model.toggleInfoPanel()
                    }
                }
                .keyboardShortcut("i")

                Divider()

                Menu("Sort By") {
                    Button("Name") { model.setSortMode(.name) }
                    Button("Date") { model.setSortMode(.date) }
                }

                if model.isGridView {
                    Menu("Filter By") {
                        Menu("Format") {
                            ForEach(ViewerModel.FileFormatFilter.allCases, id: \.rawValue) { fmt in
                                Button(fmt.rawValue) { model.formatFilter = fmt }
                            }
                        }
                        Menu("Date") {
                            ForEach(ViewerModel.DateFilter.allCases, id: \.rawValue) { d in
                                Button(d.rawValue) { model.dateFilter = d }
                            }
                        }
                    }

                }

                Divider()

                Button("Show Status Bar") { model.settings.showStatusBar.toggle() }

                Divider()

                Button("Fullscreen") { model.toggleFullScreen() }
                    .keyboardShortcut("f")

                Divider()

                Button("Start Slideshow") { model.toggleSlideshow() }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                    .disabled(model.activeFile == nil || (model.activeFile?.url.pathExtension.lowercased() == "gif"))
            }

            // MARK: - Image
            CommandMenu("Image") {
                Button("Crop\u{2026}") { model.enterCropMode() }
                    .disabled(!model.isGridView && model.currentFile == nil)

                Button("Rotate Left") { model.rotateLeft() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(model.currentFile == nil)

                Button("Rotate Right") { model.rotateRight() }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(model.currentFile == nil)

                Button("Flip Horizontal") { model.flipHorizontal() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                    .disabled(model.currentFile == nil)

                Divider()

                Menu("Rate") {
                    Button("None") { model.rateCurrentFile(0) }
                    Divider()
                    ForEach(1...5, id: \.self) { rating in
                        Button(String(repeating: "★", count: rating)) {
                            model.rateCurrentFile(rating)
                        }
                    }
                }
                .disabled(model.currentFile == nil)

                Button("Toggle Favorite") { model.toggleFavorite() }
                    .keyboardShortcut("d", modifiers: .command)
                    .disabled(model.currentFile == nil)

                Divider()

                Button("Save Changes") { model.saveChanges() }
                    .disabled(model.currentFile == nil || (model.rotation == 0 && !model.isFlippedHorizontally))

                Divider()

                Button("Batch Convert / Export\u{2026}") { model.showBatchExport() }
                    .disabled(!model.isGridView || model.selectedGridIndices.count < 2)

                Button("Batch Rename\u{2026}") { model.showBatchRename() }
                    .disabled(!model.isGridView || model.selectedGridIndices.count < 2)
            }

            // MARK: - Help
            CommandMenu("Help") {
                Button("Keyboard Shortcuts") { model.toggleShortcutsHelp() }
                    .keyboardShortcut("?", modifiers: [])
            }
        }

        Settings {
            SettingsView(settings: model.settings)
        }
    }
}
