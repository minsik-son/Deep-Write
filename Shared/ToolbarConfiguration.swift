import Foundation

// MARK: - Toolbar Item Type

enum ToolbarItemType: String, CaseIterable, Equatable {
    case settings
    case emoji
    case clipboard
    case savedPhrases
    case quickNote
    case correction
    case translation
}

// MARK: - Toolbar Configuration

struct ToolbarConfiguration {

    static let defaultItems: [ToolbarItemType] = [
        .settings, .emoji, .clipboard, .savedPhrases,
        .quickNote, .correction, .translation
    ]

    private static let userDefaultsKey = AppConstants.UserDefaultsKeys.toolbarItems

    static func load() -> [ToolbarItemType] {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)

        guard let rawArray = defaults?.stringArray(forKey: userDefaultsKey) else {
            return defaultItems
        }

        var items = rawArray.compactMap { ToolbarItemType(rawValue: $0) }

        if items.isEmpty {
            return defaultItems
        }

        // Merge new items from future app versions
        let existing = Set(items)
        let newItems = ToolbarItemType.allCases.filter { !existing.contains($0) }
        if !newItems.isEmpty {
            items.append(contentsOf: newItems)
            save(items)
        }

        // settings always first
        items.removeAll { $0 == .settings }
        items.insert(.settings, at: 0)

        return items
    }

    static func save(_ items: [ToolbarItemType]) {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        let rawArray = items.map { $0.rawValue }
        defaults?.set(rawArray, forKey: userDefaultsKey)
        defaults?.synchronize()
    }
}
