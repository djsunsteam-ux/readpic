import Foundation
import Observation

/// Manages favorite status and ratings for image files.
///
/// Uses `@Observable` so SwiftUI views that read its state in their body
/// automatically re-render on changes. Currently persists via UserDefaults
/// (JSON-encoded); the data model is designed for future SQLite migration.
///
/// Thread safety: all methods must be called from the MainActor.
@Observable
@MainActor
public final class FavoritesManager {
    public static let shared = FavoritesManager()

    // MARK: - Entry model

    private struct FavoriteEntry: Codable, Equatable {
        var isFavorite: Bool
        var rating: Int  // 0 = not rated, 1-5 = star rating

        static let empty = FavoriteEntry(isFavorite: false, rating: 0)
    }

    // MARK: - Private state

    /// Keyed by file path (URL.path) — unique on a single machine.
    private var entries: [String: FavoriteEntry] = [:]
    private let storageKey = "ReadpicFavorites_v1"

    private init() {
        load()
    }

    // MARK: - Public API

    /// Returns `true` if the file at `url` is marked as a favorite.
    public func isFavorite(_ url: URL) -> Bool {
        entries[url.path]?.isFavorite ?? false
    }

    /// Toggle the favorite status for the file at `url`.
    public func toggleFavorite(_ url: URL) {
        let path = url.path
        if var entry = entries[path] {
            entry.isFavorite.toggle()
            entries[path] = (entry.isFavorite || entry.rating > 0) ? entry : nil
        } else {
            entries[path] = FavoriteEntry(isFavorite: true, rating: 0)
        }
        save()
    }

    /// Returns the rating (0-5) for the file at `url`.
    public func rating(for url: URL) -> Int {
        entries[url.path]?.rating ?? 0
    }

    /// Set the rating (0-5) for the file at `url`.
    /// - Parameter rating: 0 = clear rating, 1-5 = star count.
    public func setRating(_ rating: Int, for url: URL) {
        let r = max(0, min(5, rating))
        let path = url.path
        if var entry = entries[path] {
            entry.rating = r
            entries[path] = (entry.isFavorite || r > 0) ? entry : nil
        } else if r > 0 {
            entries[path] = FavoriteEntry(isFavorite: false, rating: r)
        }
        save()
    }

    /// All URLs currently marked as favorite.
    public var allFavorites: [URL] {
        entries.compactMap { path, entry in
            entry.isFavorite ? URL(fileURLWithPath: path) : nil
        }
    }

    /// All rated entries (rating > 0).
    public var allRated: [(url: URL, rating: Int)] {
        entries.compactMap { path, entry in
            entry.rating > 0 ? (URL(fileURLWithPath: path), entry.rating) : nil
        }
    }

    /// Remove all favorites and ratings.
    public func clear() {
        entries.removeAll()
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let dict = try? JSONDecoder().decode(
                [String: FavoriteEntry].self, from: data
              ) else {
            entries = [:]
            return
        }
        entries = dict
    }
}
