import SwiftUI

@main
struct ReadpicApp: App {
    @State private var model = ViewerModel()

    var body: some Scene {
        WindowGroup {
            ViewerView(model: model)
                .frame(minWidth: 720, minHeight: 480)
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
                .disabled(!model.hasAnimatedFrames)

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

                Divider()

                Button("Show Status Bar") { model.settings.showStatusBar.toggle() }

                Divider()

                Button("Fullscreen") { model.toggleFullScreen() }
                    .keyboardShortcut("f")
            }

            // MARK: - Image
            CommandMenu("Image") {
                Button("Rotate Left") { model.rotateLeft() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(model.currentFile == nil)

                Button("Rotate Right") { model.rotateRight() }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(model.currentFile == nil)

                Button("Flip Horizontal") { model.flipHorizontal() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                    .disabled(model.currentFile == nil)
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
