import AppKit
import Foundation
import SwiftUI

// MARK: - Localization helpers (SPM + Xcode cross-build)
extension Bundle {
    /// The bundle containing localized strings. SPM uses .module; Xcode uses .main.
    static let loc: Bundle = {
        #if SWIFT_PACKAGE
        return .module
        #else
        // Xcode builds: the .lproj are copied by the Resources build phase
        return .main
        #endif
    }()
}

extension String {
    /// Returns the localized version from the correct bundle.
    var localized: String {
        NSLocalizedString(self, bundle: .loc, comment: "")
    }
}

extension Text {
    /// Creates a localized Text using the correct bundle.
    /// Replace `Text("key")` with `Text.loc("key")`.
    static func loc(_ key: String) -> Text {
        Text(LocalizedStringKey(key), bundle: .loc)
    }
}

enum ScrollBehavior: String, CaseIterable, Sendable {
    case scrollPan
    case browse
    case zoom
}

enum DefaultZoomMode: String, CaseIterable, Sendable {
    case fitWindow
    case fitWidth
    case actualSize
}

enum ThemeMode: String, CaseIterable, Sendable {
    case system
    case light
    case dark
}

enum LanguageMode: String, CaseIterable, Sendable {
    case system = "System"
    case english = "English"
    case chinese = "简体中文"
}

enum BackgroundColor: String, CaseIterable, Sendable {
    case theme
    case black
    case darkGray
    case lightGray
    case white
    case custom

    var color: SwiftUI.Color {
        switch self {
        case .theme: Color(nsColor: .windowBackgroundColor)
        case .black: .black
        case .darkGray: Color(nsColor: .darkGray)
        case .lightGray: Color(nsColor: .lightGray)
        case .white: .white
        case .custom: Color(nsColor: AppSettings.readCustomBackgroundColor())
        }
    }

    var displayName: String {
        switch self {
        case .theme: String(localized: "Follow Theme")
        case .black: String(localized: "Black")
        case .darkGray: String(localized: "Dark Gray")
        case .lightGray: String(localized: "Light Gray")
        case .white: String(localized: "White")
        case .custom: String(localized: "Custom")
        }
    }
}

@Observable
final class AppSettings {
    nonisolated(unsafe) static let shared = AppSettings()

    var scrollBehavior: ScrollBehavior {
        didSet { UserDefaults.standard.set(scrollBehavior.rawValue, forKey: Self.scrollBehaviorKey) }
    }

    var defaultZoomMode: DefaultZoomMode {
        didSet { UserDefaults.standard.set(defaultZoomMode.rawValue, forKey: Self.defaultZoomModeKey) }
    }

    var showStatusBar: Bool {
        didSet { UserDefaults.standard.set(showStatusBar, forKey: Self.showStatusBarKey) }
    }

    var theme: ThemeMode {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey) }
    }

    var backgroundColor: BackgroundColor {
        didSet { UserDefaults.standard.set(backgroundColor.rawValue, forKey: Self.bgColorKey) }
    }

    var customBackgroundColor: Color {
        get { Color(nsColor: Self.readCustomBackgroundColor()) }
        set {
            let nsColor = NSColor(newValue)
            let data = try? NSKeyedArchiver.archivedData(withRootObject: nsColor, requiringSecureCoding: true)
            UserDefaults.standard.set(data, forKey: Self.customBgColorKey)
        }
    }

    var sortMode: SortMode {
        didSet { UserDefaults.standard.set(sortMode.rawValue, forKey: Self.sortModeKey) }
    }

    var rememberLastFolder: Bool {
        didSet {
            UserDefaults.standard.set(rememberLastFolder, forKey: Self.rememberFolderKey)
            if !rememberLastFolder {
                lastFolderURL = nil
            }
        }
    }

    var loadSubfolders: Bool {
        didSet { UserDefaults.standard.set(loadSubfolders, forKey: Self.loadSubfoldersKey) }
    }

    var language: LanguageMode {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.languageKey) }
    }

    var lastFolderURL: URL? {
        get {
            UserDefaults.standard.data(forKey: Self.lastFolderURLKey)
                .flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSURL.self, from: $0) } as URL?
        }
        set {
            if let url = newValue {
                let data = try? NSKeyedArchiver.archivedData(withRootObject: url as NSURL, requiringSecureCoding: true)
                UserDefaults.standard.set(data, forKey: Self.lastFolderURLKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.lastFolderURLKey)
            }
        }
    }

    /// Recent folder paths stored as path strings for reliable cross-launch persistence.
    var recentFolderPaths: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.recentFoldersKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Self.recentFoldersKey) }
    }

    var recentFolders: [URL] {
        let valid = recentFolderPaths.compactMap { path -> URL? in
            let url = URL(fileURLWithPath: path)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
            return url
        }
        // Prune stale entries from storage so displayed count matches stored count
        let validPaths = Set(valid.map(\.path))
        if recentFolderPaths.count != validPaths.count {
            recentFolderPaths = recentFolderPaths.filter { validPaths.contains($0) }
        }
        return valid
    }

    func addRecentFolder(_ url: URL) {
        var paths = recentFolderPaths
        let path = url.path
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        if paths.count > 10 { paths = Array(paths.prefix(10)) }
        recentFolderPaths = paths
        lastFolderURL = url
    }

    func clearRecentFolders() {
        recentFolderPaths = []
    }

    private init() {
        scrollBehavior = Self.read(key: Self.scrollBehaviorKey, fallback: ScrollBehavior.zoom)
        defaultZoomMode = Self.read(key: Self.defaultZoomModeKey, fallback: DefaultZoomMode.fitWindow)
        showStatusBar = UserDefaults.standard.object(forKey: Self.showStatusBarKey).flatMap { $0 as? Bool } ?? true
        theme = Self.read(key: Self.themeKey, fallback: ThemeMode.dark)
        backgroundColor = Self.read(key: Self.bgColorKey, fallback: BackgroundColor.black)
        sortMode = Self.read(key: Self.sortModeKey, fallback: SortMode.name)
        rememberLastFolder = UserDefaults.standard.object(forKey: Self.rememberFolderKey) as? Bool ?? false
        loadSubfolders = UserDefaults.standard.object(forKey: Self.loadSubfoldersKey) as? Bool ?? false
        language = Self.read(key: Self.languageKey, fallback: LanguageMode.system)
    }

    private static func read<T: RawRepresentable>(key: String, fallback: T) -> T where T.RawValue == String {
        UserDefaults.standard.string(forKey: key).flatMap { T(rawValue: $0) } ?? fallback
    }

    static func readCustomBackgroundColor() -> NSColor {
        guard let data = UserDefaults.standard.data(forKey: Self.customBgColorKey),
              let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) else {
            return .windowBackgroundColor
        }
        return color
    }

    private static let scrollBehaviorKey = "scrollBehavior"
    private static let defaultZoomModeKey = "defaultZoomMode"
    private static let showStatusBarKey = "showStatusBar"
    private static let themeKey = "theme"
    private static let bgColorKey = "backgroundColor"
    private static let customBgColorKey = "customBackgroundColor"
    private static let rememberFolderKey = "rememberLastFolder"
    private static let lastFolderURLKey = "lastFolderURL"
    private static let recentFoldersKey = "recentFolders"
    private static let sortModeKey = "sortMode"
    private static let languageKey = "LanguageMode"
    private static let loadSubfoldersKey = "loadSubfolders"

}
