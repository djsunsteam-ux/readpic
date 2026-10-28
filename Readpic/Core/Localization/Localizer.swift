import Foundation
import Observation
import SwiftUI

/// Resolves the effective app language and loads the matching `.lproj` bundle
/// on demand, so switching language takes effect without restarting the app.
@Observable
final class Localizer {
    nonisolated(unsafe) static let shared = Localizer()

    static let supportedCodes = ["en", "zh-Hans"]

    /// Language code currently in effect. Reading this inside a SwiftUI view
    /// body registers an observation, which makes the UI update live.
    private(set) var code: String = "en"

    @ObservationIgnored private var bundles: [String: Bundle] = [:]

    private init() {
        for code in Self.supportedCodes {
            bundles[code] = Self.loadBundle(for: code)
        }
        code = Self.detectSystemCode()
    }

    var locale: Locale { Locale(identifier: code) }

    func string(_ key: String) -> String {
        bundle(for: code).localizedString(forKey: key, value: key, table: nil)
    }

    /// Applies the selected mode: updates the effective language immediately
    /// and keeps the persisted `AppleLanguages` default aligned for next launch.
    func apply(mode: LanguageMode) {
        switch mode {
        case .english:
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        case .chinese:
            UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        case .system:
            // Remove the app-level override so the system preference applies.
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }

        let newCode: String
        switch mode {
        case .english: newCode = "en"
        case .chinese: newCode = "zh-Hans"
        case .system:  newCode = Self.detectSystemCode()
        }
        if code != newCode {
            code = newCode
            // AppKit-owned menu titles (File, Edit, Window, …) are fixed at
            // launch; the delegate listens for this to relocalize them.
            NotificationCenter.default.post(name: .readpicLanguageDidChange, object: nil)
        }
    }

    private func bundle(for code: String) -> Bundle {
        if let bundle = bundles[code] { return bundle }
        let loaded = Self.loadBundle(for: code)
        // Not observed: safe to populate during a view body evaluation.
        bundles[code] = loaded
        return loaded
    }

    private static func loadBundle(for code: String) -> Bundle {
        guard let path = Bundle.loc.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .loc
        }
        return bundle
    }

    /// Highest-priority system language the app supports.
    /// Reads the system-level preference so an app-level override set by a
    /// previous explicit selection doesn't leak in.
    static func detectSystemCode() -> String {
        let preferred =
            (UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String])
            ?? Locale.preferredLanguages

        for identifier in preferred {
            let code = identifier.lowercased()
            if code.hasPrefix("zh") { return "zh-Hans" }
            if code.hasPrefix("en") { return "en" }
        }
        return "en"
    }
}

/// Localized string lookup backed by the runtime-switchable `Localizer`.
func L(_ key: String) -> String {
    Localizer.shared.string(key)
}

/// Localized format string lookup with arguments.
func Lf(_ key: String, _ args: CVarArg...) -> String {
    String(format: Localizer.shared.string(key), locale: Localizer.shared.locale, arguments: args)
}

extension Notification.Name {
    /// Posted when the app language changes at runtime.
    static let readpicLanguageDidChange = Notification.Name("ReadpicLanguageDidChange")
}

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
    /// Returns the localized version for the currently selected language.
    var localized: String {
        Localizer.shared.string(self)
    }
}

extension Text {
    /// Creates a localized Text using the currently selected language.
    static func loc(_ key: String) -> Text {
        Text(Localizer.shared.string(key))
    }
}
