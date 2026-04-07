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
    case dictation
    // Productivity editing tools
    case cursorLeft
    case cursorRight
    case deleteWord
    case undo
    case redo
    case selectAll
    case copy
    case paste
    case cut
    case caseTransform
    // New features
    case dateTimeInsert
    case dismissKeyboard
    case unitConverter
}

// MARK: - Toolbar Configuration

struct ToolbarConfiguration {

    static let defaultItems: [ToolbarItemType] = [
        .settings, .emoji, .clipboard, .savedPhrases,
        .quickNote, .correction, .translation
    ]

    /// Host text에서 iOS API 제약상 동작 불가능한 항목
    static let unsupportedHostTextItems: Set<ToolbarItemType> = [
        .undo, .redo, .selectAll, .copy, .cut
    ]

    private static let userDefaultsKey = AppConstants.UserDefaultsKeys.toolbarItems

    static func load() -> [ToolbarItemType] {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)

        guard let rawArray = defaults?.stringArray(forKey: userDefaultsKey) else {
            return defaultItems
        }

        let items = rawArray.compactMap { ToolbarItemType(rawValue: $0) }

        if items.isEmpty {
            return defaultItems
        }

        // Sanitize: remove unsupported host text items (legacy migration)
        let sanitized = items.filter { !unsupportedHostTextItems.contains($0) }

        if sanitized.isEmpty {
            return defaultItems
        }

        // Migrate: save back if unsupported items were removed
        if sanitized.count != items.count {
            save(sanitized)
        }

        return sanitized
    }

    static func save(_ items: [ToolbarItemType]) {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        let rawArray = items.map { $0.rawValue }
        defaults?.set(rawArray, forKey: userDefaultsKey)
        defaults?.synchronize()
    }
}
