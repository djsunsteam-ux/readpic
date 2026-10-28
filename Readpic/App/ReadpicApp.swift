import SwiftUI

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var model: ViewerModel?
    private var pendingURLs: [URL] = []

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// AppKit-supplied menu titles are resolved once at launch, so they don't
    /// follow runtime language switches. Each known title (in either language)
    /// maps to its localization key so the whole bar can be patched in place.
    private static let menuTitleKeys: [String: String] = [
        // App menu
        "About Readpic": "About Readpic", "关于 Readpic": "About Readpic",
        "Settings…": "Settings…", "设置…": "Settings…",
        "Services": "Services", "服务": "Services",
        "Hide Readpic": "Hide Readpic", "隐藏Readpic": "Hide Readpic",
        "Hide Others": "Hide Others", "隐藏其他": "Hide Others",
        "Show All": "Show All", "全部显示": "Show All",
        "Quit Readpic": "Quit Readpic", "退出Readpic": "Quit Readpic",
        // File
        "File": "File", "文件": "File",
        "Open Image…": "Open Image…", "打开图片…": "Open Image…",
        "Open Folder…": "Open Folder…", "打开文件夹…": "Open Folder…",
        "Open Recent": "Open Recent", "最近打开": "Open Recent",
        "Clear Recent": "Clear Recent", "清除最近": "Clear Recent",
        "Export / Convert…": "Export / Convert…", "导出 / 转换…": "Export / Convert…",
        "Move to Trash": "Move to Trash", "移到废纸篓": "Move to Trash",
        "Reveal in Finder": "Reveal in Finder", "在 Finder 中显示": "Reveal in Finder",
        "Open Externally": "Open Externally", "用外部应用打开": "Open Externally",
        "Batch Convert / Export…": "Batch Convert / Export…", "批量转换 / 导出…": "Batch Convert / Export…",
        "Batch Rename…": "Batch Rename…", "批量重命名…": "Batch Rename…",
        "Close": "Close", "关闭": "Close",
        "Close All": "Close All", "全部关闭": "Close All",
        // Edit
        "Edit": "Edit", "编辑": "Edit",
        "Undo": "Undo", "撤销": "Undo",
        "Redo": "Redo", "重做": "Redo",
        "Copy Image": "Copy Image", "复制图片": "Copy Image",
        "Copy File": "Copy File", "复制文件": "Copy File",
        "Copy File Path": "Copy File Path", "复制文件路径": "Copy File Path",
        "Select All": "Select All", "全选": "Select All",
        "Invert Selection": "Invert Selection", "反选": "Invert Selection",
        "Copy Metadata": "Copy Metadata", "复制元数据": "Copy Metadata",
        "AutoFill": "AutoFill", "自动填充": "AutoFill",
        "Contact…": "Contact…", "通讯录…": "Contact…",
        "Passwords…": "Passwords…", "密码…": "Passwords…",
        "Credit Card…": "Credit Card…", "信用卡…": "Credit Card…",
        "Start Dictation…": "Start Dictation…", "开始听写…": "Start Dictation…",
        "Emoji & Symbols": "Emoji & Symbols", "表情与符号": "Emoji & Symbols",
        // Navigate
        "Navigate": "Navigate", "导航": "Navigate",
        "Grid View": "Grid View", "网格视图": "Grid View",
        "Fit Window": "Fit Window", "适应窗口": "Fit Window",
        "Fit Width": "Fit Width", "适应宽度": "Fit Width",
        "Actual Size": "Actual Size", "实际大小": "Actual Size",
        "Zoom In": "Zoom In", "放大": "Zoom In",
        "Zoom Out": "Zoom Out", "缩小": "Zoom Out",
        "Reset Zoom": "Reset Zoom", "重置缩放": "Reset Zoom",
        "Thumbnail Strip": "Thumbnail Strip", "缩略图条": "Thumbnail Strip",
        "Frame Strip": "Frame Strip", "帧条": "Frame Strip",
        "Info Panel": "Info Panel", "信息面板": "Info Panel",
        "Sort By": "Sort By", "排序方式": "Sort By",
        "Filter By": "Filter By", "过滤": "Filter By",
        "Format": "Format", "格式": "Format",
        "Name": "Name", "名称": "Name",
        "Date": "Date", "日期": "Date",
        "All": "All", "全部": "All",
        "Today": "Today", "今天": "Today",
        "This Week": "This Week", "本周": "This Week",
        "This Month": "This Month", "本月": "This Month",
        "This Year": "This Year", "今年": "This Year",
        "Show Status Bar": "Show Status Bar", "显示状态栏": "Show Status Bar",
        "Fullscreen": "Fullscreen", "全屏": "Fullscreen",
        "Start Slideshow": "Start Slideshow", "开始幻灯片": "Start Slideshow",
        // Image
        "Image": "Image", "图片": "Image",
        "Crop…": "Crop…", "裁剪…": "Crop…",
        "Rotate Left": "Rotate Left", "向左旋转": "Rotate Left",
        "Rotate Right": "Rotate Right", "向右旋转": "Rotate Right",
        "Flip Horizontal": "Flip Horizontal", "水平翻转": "Flip Horizontal",
        "Color Picker": "Color Picker", "取色器": "Color Picker",
        "Rate": "Rate", "评分": "Rate",
        "None": "None", "无": "None",
        "Toggle Favorite": "Toggle Favorite", "切换收藏": "Toggle Favorite",
        "Save Changes": "Save Changes", "保存修改": "Save Changes",
        "Set as Desktop Wallpaper": "Set as Desktop Wallpaper", "设为桌面壁纸": "Set as Desktop Wallpaper",
        // Help / View / Window
        "Help": "Help", "帮助": "Help",
        "Keyboard Shortcuts": "Keyboard Shortcuts", "键盘快捷键": "Keyboard Shortcuts",
        "View": "View", "显示": "View",
        "Window": "Window", "窗口": "Window",
        "Minimize": "Minimize", "最小化": "Minimize",
        "Zoom": "Zoom", "缩放": "Zoom",
        "Bring All to Front": "Bring All to Front", "前置全部窗口": "Bring All to Front",
        "Readpic Help": "Readpic Help", "Readpic帮助": "Readpic Help",
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .readpicLanguageDidChange,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(menuDidBeginTracking(_:)),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )

        // AppKit localizes the menu bar from `AppleLanguages` before the
        // runtime language is resolved, which can leave stale titles at launch.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            self.relocalizeMenuBar()
        }
    }

    @objc private func languageDidChange(_ notification: Notification) {
        relocalizeMenuBar()
        // SwiftUI rebuilds its own commands asynchronously; patch them again
        // once the rebuild has settled.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            self.relocalizeMenuBar()
        }
    }

    @objc private func menuDidBeginTracking(_ notification: Notification) {
        relocalizeMenuBar()
    }

    private func relocalizeMenuBar() {
        guard let menu = NSApp.mainMenu else { return }
        Self.relocalize(menu)
    }

    private static func relocalize(_ menu: NSMenu) {
        for item in menu.items {
            if let key = menuTitleKeys[item.title] {
                let title = L(key)
                if item.title != title { item.title = title }
            }
            if let submenu = item.submenu { relocalize(submenu) }
        }
    }

    /// Called once the scene's model exists; replays URLs delivered at launch.
    func attach(_ model: ViewerModel) {
        Self.model = model
        guard !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs.removeAll()
        model.open(urls: urls)
        activateApp()
    }

    private func deliver(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard let model = Self.model else {
            pendingURLs.append(contentsOf: urls)
            return
        }
        model.open(urls: urls)
        activateApp()
    }

    /// Brings the app and its viewer window forward after a document open.
    /// A launch driven by an open event can leave the scene's window created
    /// but never ordered front (`isVisible == false`, and such a window even
    /// reports `canBecomeMain == false`), so activation alone doesn't show it.
    /// Retried because the window appears asynchronously.
    private func activateApp() {
        for delay in [0, 200, 600, 1200] {
            Task { @MainActor in
                if delay > 0 { try? await Task.sleep(for: .milliseconds(delay)) }
                NSApp.unhide(nil)
                NSApp.activate()
                NSRunningApplication.current.activate(options: [.activateAllWindows])
                guard let window = self.largestWindow() else { return }
                if window.isMiniaturized { window.deminiaturize(nil) }
                if !window.isVisible || !window.isKeyWindow {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
    }

    /// The viewer is the largest window; menu bar strips, Settings and panels
    /// are smaller, so this avoids raising them over the image being opened.
    private func largestWindow() -> NSWindow? {
        NSApp.windows
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            activateApp()
        }
        return true
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
            CommandGroup(replacing: .help) {
                Button(L("Keyboard Shortcuts")) { model.toggleShortcutsHelp() }
                    .keyboardShortcut("?", modifiers: [])
            }
        }

        Settings {
            SettingsView(settings: model.settings)
        }
    }
}
