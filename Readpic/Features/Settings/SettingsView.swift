import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        TabView {
            // ---------- General ----------
            Form {
                Section("Navigation") {
                    Picker("Scroll Wheel", selection: $settings.scrollBehavior) {
                        Text.loc("Zoom").tag(ScrollBehavior.zoom)
                        Text.loc("Pan").tag(ScrollBehavior.scrollPan)
                        Text.loc("Browse").tag(ScrollBehavior.browse)
                    }
                    .pickerStyle(.radioGroup)
                }

                Section("Viewing") {
                    Picker("Default Zoom", selection: $settings.defaultZoomMode) {
                        Text.loc("Fit Window").tag(DefaultZoomMode.fitWindow)
                        Text.loc("Fit Width").tag(DefaultZoomMode.fitWidth)
                        Text("100%").tag(DefaultZoomMode.actualSize)
                    }

                    Toggle("Show Status Bar", isOn: $settings.showStatusBar)
                }

                Section {
                    Toggle("Remember Last Folder", isOn: $settings.rememberLastFolder)
                    Toggle("Load Subfolders", isOn: $settings.loadSubfolders)
                    Text.loc("Recursively scan subfolders up to 10 levels deep.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(20)
            .tabItem { Label("General", systemImage: "gearshape") }

            // ---------- Appearance ----------
            Form {
                Section("Theme") {
                    Picker(selection: $settings.theme) {
                        Text.loc("System").tag(ThemeMode.system)
                        Text.loc("Light").tag(ThemeMode.light)
                        Text.loc("Dark").tag(ThemeMode.dark)
                    } label: { }
                    .pickerStyle(.radioGroup)

                    Picker("Background", selection: $settings.backgroundColor) {
                        ForEach(BackgroundColor.allCases, id: \.self) { bg in
                            Text(bg.displayName).tag(bg)
                        }
                    }

                    if settings.backgroundColor == .custom {
                        ColorPicker("Custom Color", selection: $settings.customBackgroundColor)
                    }
                }
            }
            .padding(20)
            .tabItem { Label("Appearance", systemImage: "paintbrush") }

            // ---------- Language ----------
            Form {
                Section {
                    Picker("Language", selection: $settings.language) {
                        Text.loc("System").tag(LanguageMode.system)
                        Text.loc("English").tag(LanguageMode.english)
                        Text("简体中文").tag(LanguageMode.chinese)
                    }
                    .pickerStyle(.radioGroup)

                    Text.loc("Changes will take effect after restarting the app.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(20)
            .tabItem { Label("Language", systemImage: "globe") }
        }
        .frame(width: 460, height: 340)
    }
}
