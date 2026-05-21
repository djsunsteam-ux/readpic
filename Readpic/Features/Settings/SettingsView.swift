import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        TabView {
            Form {
                Section("Navigation") {
                    Picker("Scroll Wheel", selection: $settings.scrollBehavior) {
                        Text("Zoom").tag(ScrollBehavior.zoom)
                        Text("Pan").tag(ScrollBehavior.scrollPan)
                        Text("Browse").tag(ScrollBehavior.browse)
                    }
                    .pickerStyle(.radioGroup)
                }

                Section("Viewing") {
                    Picker("Default Zoom", selection: $settings.defaultZoomMode) {
                        Text("Fit Window").tag(DefaultZoomMode.fitWindow)
                        Text("Fit Width").tag(DefaultZoomMode.fitWidth)
                        Text("100%").tag(DefaultZoomMode.actualSize)
                    }

                    Toggle("Show Status Bar", isOn: $settings.showStatusBar)
                }

                Section("Appearance") {
                    Picker("Theme", selection: $settings.theme) {
                        Text("System").tag(ThemeMode.system)
                        Text("Light").tag(ThemeMode.light)
                        Text("Dark").tag(ThemeMode.dark)
                    }
                    .pickerStyle(.radioGroup)

                    Picker("Background", selection: $settings.backgroundColor) {
                        ForEach(BackgroundColor.allCases, id: \.self) { bg in
                            Text(bg.displayName).tag(bg)
                        }
                    }

                    if settings.backgroundColor == .custom {
                        ColorPicker("Custom Color", selection: $settings.customBackgroundColor)
                            .padding(.leading, 12)
                    }
                }

                Section("Language") {
                    Picker("Language", selection: $settings.language) {
                        Text("System").tag(LanguageMode.system)
                        Text("English").tag(LanguageMode.english)
                        Text("简体中文").tag(LanguageMode.chinese)
                    }
                    .pickerStyle(.radioGroup)
                }

                Section("Session") {
                    Toggle("Remember Last Folder", isOn: $settings.rememberLastFolder)
                }
            }
            .padding(20)
            .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 460, height: 400)
    }
}
