import Foundation

public enum SortMode: String, CaseIterable, Sendable {
    case name
    case date

    public var displayName: String {
        switch self {
        case .name: "Sort by Name"
        case .date: "Sort by Date"
        }
    }
}

public struct FileSorter {
    public static func sortByName(_ items: [FileItem]) -> [FileItem] {
        items.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public static func sortByDate(_ items: [FileItem]) -> [FileItem] {
        items.sorted {
            switch ($0.modificationDate, $1.modificationDate) {
            case (.some(let a), .some(let b)):
                a > b
            case (.some, .none):
                true
            case (.none, .some):
                false
            case (.none, .none):
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }

    public static func sort(_ items: [FileItem], by mode: SortMode) -> [FileItem] {
        switch mode {
        case .name: sortByName(items)
        case .date: sortByDate(items)
        }
    }
}
