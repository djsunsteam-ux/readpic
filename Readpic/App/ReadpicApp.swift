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
            CommandGroup(replacing: .newItem) {
                Button("Open Image…") {
                    model.showOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Open Folder…") {
                    model.showOpenFolderPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .appInfo) {
                Button("About Readpic") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }

            CommandGroup(replacing: .pasteboard) {
                Button("Copy Image") {
                    model.copyImage()
                }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(model.decodedImage == nil)
            }

            CommandMenu("Image") {
                Button("Copy Image") {
                    model.copyImage()
                }
                .disabled(model.decodedImage == nil)

                Button("Copy File") {
                    model.copyFile()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("Copy File Path") {
                    model.copyFilePath()
                }
                .keyboardShortcut("c", modifiers: [.command, .option])

                Button("Reveal in Finder") {
                    model.revealInFinder()
                }
                .keyboardShortcut("e", modifiers: [.command, .option])

                Button("Open Externally") {
                    model.openExternally()
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("Move to Trash") {
                    model.moveCurrentFileToTrash()
                }
                .keyboardShortcut(.delete, modifiers: .command)

                Divider()

                Button("Rotate Left") {
                    model.rotateLeft()
                }
                .keyboardShortcut("[", modifiers: .command)

                Button("Rotate Right") {
                    model.rotateRight()
                }
                .keyboardShortcut("]", modifiers: .command)

                Button("Flip Horizontal") {
                    model.flipHorizontal()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Divider()

                Menu("Sort By") {
                    Button("Name") {
                        model.setSortMode(.name)
                    }
                    .disabled(model.currentFile == nil)

                    Button("Date") {
                        model.setSortMode(.date)
                    }
                    .disabled(model.currentFile == nil)
                }

                Divider()

                Button("Toggle Thumbnail Strip") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        model.toggleThumbnailStrip()
                    }
                }

                Button("Toggle Info Panel") {
                    model.toggleInfoPanel()
                }
                .keyboardShortcut("i")

                Divider()

                Button("Toggle Fullscreen") {
                    model.toggleFullScreen()
                }
                .keyboardShortcut("f", modifiers: [.command, .control])
            }
        }

        Settings {
            SettingsView(settings: model.settings)
        }
    }
}
