import AppKit
import Foundation
import SwiftUI

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

    var nsColor: NSColor {
        switch self {
        case .theme: .windowBackgroundColor
        case .black: .black
        case .darkGray: .darkGray
        case .lightGray: .lightGray
        case .white: .white
        case .custom: AppSettings.readCustomBackgroundColor()
        }
    }

    var displayName: String {
        switch self {
        case .theme: "Follow Theme"
        case .black: "Black"
        case .darkGray: "Dark Gray"
        case .lightGray: "Light Gray"
        case .white: "White"
        case .custom: "Custom"
        }
    }
}

@Observable
final class AppSettings {
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

    var recentFolders: [URL] {
        get { Self.readRecentFolders() }
        set {
            let data = try? NSKeyedArchiver.archivedData(withRootObject: newValue as NSArray, requiringSecureCoding: true)
            UserDefaults.standard.set(data, forKey: Self.recentFoldersKey)
        }
    }

    func addRecentFolder(_ url: URL) {
        var list = recentFolders
        list.removeAll { $0 == url }
        list.insert(url, at: 0)
        if list.count > 10 { list = Array(list.prefix(10)) }
        recentFolders = list
        lastFolderURL = url
    }

    func clearRecentFolders() {
        recentFolders = []
    }

    init() {
        scrollBehavior = Self.read(key: Self.scrollBehaviorKey, fallback: ScrollBehavior.zoom)
        defaultZoomMode = Self.read(key: Self.defaultZoomModeKey, fallback: DefaultZoomMode.fitWindow)
        showStatusBar = UserDefaults.standard.object(forKey: Self.showStatusBarKey).flatMap { $0 as? Bool } ?? true
        theme = Self.read(key: Self.themeKey, fallback: ThemeMode.dark)
        backgroundColor = Self.read(key: Self.bgColorKey, fallback: BackgroundColor.black)
        sortMode = Self.read(key: Self.sortModeKey, fallback: SortMode.name)
        rememberLastFolder = UserDefaults.standard.object(forKey: Self.rememberFolderKey) as? Bool ?? false
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

    private static func readRecentFolders() -> [URL] {
        guard let data = UserDefaults.standard.data(forKey: Self.recentFoldersKey),
              let array = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSArray.self, from: data) as? [URL]
        else { return [] }
        // Filter out folders that no longer exist
        return array.filter { path in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: path.path, isDirectory: &isDir) && isDir.boolValue
        }
    }
}
