import Foundation

public enum SortMode: String, CaseIterable, Sendable {
    case name
    case date
}

public struct FileSorter {
    public static func sort(_ items: [FileItem], by mode: SortMode) -> [FileItem] {
        switch mode {
        case .name:
            items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .date:
            items.sorted {
                switch ($0.modificationDate, $1.modificationDate) {
                case (.some(let a), .some(let b)): a > b
                case (.some, .none): true
                case (.none, .some): false
                case (.none, .none): $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            }
        }
    }

    /// Sort items first by `relativeFolder` (group), then within each group by `mode`.
    public static func sortGrouped(_ items: [FileItem], by mode: SortMode) -> [FileItem] {
        // Primary key: relativeFolder (ascending, localized)
        // Secondary key: sort mode (name or date)
        items.sorted { a, b in
            let cmp = a.relativeFolder.localizedStandardCompare(b.relativeFolder)
            if cmp != .orderedSame { return cmp == .orderedAscending }
            // Same folder group — apply mode sort
            switch mode {
            case .name:
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .date:
                switch (a.modificationDate, b.modificationDate) {
                case (.some(let da), .some(let db)): return da > db
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return a.name.localizedStandardCompare(b.name) == .orderedAscending
                }
            }
        }
    }
}
