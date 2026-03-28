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
    case calculator
    case chatReplyGenerator
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

        // settings is now user-customizable like any other item

        return items
    }

    static func save(_ items: [ToolbarItemType]) {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        let rawArray = items.map { $0.rawValue }
        defaults?.set(rawArray, forKey: userDefaultsKey)
        defaults?.synchronize()
    }
}
