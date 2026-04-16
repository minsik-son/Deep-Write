import Foundation

extension Notification.Name {
    static let historyDidChange = Notification.Name("historyDidChange")
    static let savedPhrasesDidChange = Notification.Name("savedPhrasesDidChange")
}

final class HistoryManager {
    static let shared = HistoryManager()

    private let defaults: UserDefaults?
    private let historyKey = "history_items"
    private var maxItems: Int { FeatureGate.shared.maxHistoryItems }

    private init() {
        defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
    }

    func addItem(type: HistoryType, original: String, result: String?, metadata: String?) {
        var items = loadItems()
        let item = HistoryItem(
            id: UUID(),
            type: type,
            originalText: original,
            resultText: result,
            metadata: metadata,
            createdAt: Date()
        )
        items.insert(item, at: 0)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        saveItems(items)
    }

    func loadItems() -> [HistoryItem] {
        guard let data = defaults?.data(forKey: historyKey) else { return [] }
        return (try? JSONDecoder().decode([HistoryItem].self, from: data)) ?? []
    }

    func loadItems(ofType type: HistoryType) -> [HistoryItem] {
        return loadItems().filter { $0.type == type }
    }

    func deleteItem(id: UUID) {
        var items = loadItems()
        items.removeAll { $0.id == id }
        saveItems(items)
    }

    func clearAll() {
        saveItems([])
    }

    func deleteAllItems(ofType type: HistoryType) {
        var items = loadItems()
        items.removeAll { $0.type == type }
        saveItems(items)
    }

    /// 기존 ClipboardHistoryManager 데이터를 HistoryManager로 마이그레이션 (1회성)
    func migrateClipboardHistoryIfNeeded() {
        #if DEBUG
        let _hmStart = CFAbsoluteTimeGetCurrent()
        #endif
        let migrationKey = "clipboard_migration_done"
        guard defaults?.bool(forKey: migrationKey) != true else {
            #if DEBUG
            NSLog("[HistoryMigration] skipped alreadyDone=true duration=%.2fms", (CFAbsoluteTimeGetCurrent() - _hmStart) * 1000)
            #endif
            return
        }

        guard let data = defaults?.data(forKey: AppConstants.UserDefaultsKeys.clipboardHistory),
              let oldItems = try? JSONDecoder().decode([ClipboardItem].self, from: data) else {
            defaults?.set(true, forKey: migrationKey)
            #if DEBUG
            NSLog("[HistoryMigration] skipped empty-data duration=%.2fms", (CFAbsoluteTimeGetCurrent() - _hmStart) * 1000)
            #endif
            return
        }

        let existingTexts = Set(loadItems(ofType: .clipboard).map { $0.originalText })
        var currentItems = loadItems()
        #if DEBUG
        let _oldCount = oldItems.count
        let _existingCount = existingTexts.count
        #endif

        for oldItem in oldItems where !existingTexts.contains(oldItem.text) {
            let historyItem = HistoryItem(
                id: oldItem.id,
                type: .clipboard,
                originalText: oldItem.text,
                resultText: nil,
                metadata: nil,
                createdAt: oldItem.copiedAt
            )
            currentItems.append(historyItem)
        }

        currentItems.sort { $0.createdAt > $1.createdAt }
        saveItems(currentItems)

        defaults?.set(true, forKey: migrationKey)
        #if DEBUG
        NSLog("[HistoryMigration] migrated old=%d existing=%d total=%.2fms", _oldCount, _existingCount, (CFAbsoluteTimeGetCurrent() - _hmStart) * 1000)
        #endif
    }

    /// 특정 타입의 전체 아이템 수 (주간 제한 없이)
    func totalCount(ofType type: HistoryType) -> Int {
        return loadItems().filter { $0.type == type }.count
    }

    func weeklyCount(ofType type: HistoryType) -> Int {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        guard let monday = calendar.date(from: components) else { return 0 }
        return loadItems().filter { $0.type == type && $0.createdAt >= monday }.count
    }

    func lastWeekCount(ofType type: HistoryType) -> Int {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        guard let thisMonday = calendar.date(from: components),
              let lastMonday = calendar.date(byAdding: .weekOfYear, value: -1, to: thisMonday) else { return 0 }
        return loadItems().filter { $0.type == type && $0.createdAt >= lastMonday && $0.createdAt < thisMonday }.count
    }

    private func saveItems(_ items: [HistoryItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults?.set(data, forKey: historyKey)
        // 메인앱에서만 노티 발송 (키보드 익스텐션에서는 옵저버가 없으므로 불필요)
        if Bundle.main.bundlePath.hasSuffix(".app") {
            NotificationCenter.default.post(name: .historyDidChange, object: nil)
        }
    }
}
