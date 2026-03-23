import Foundation

struct ComposeHistoryItem: Codable {
    static let currentSchemaVersion = 1
    let schemaVersion: Int
    let id: String
    let prompt: String
    let replyContext: String?
    let tone: String
    let length: String
    let result: String
    let timestamp: Date
    var isFavorite: Bool

    init(id: String = UUID().uuidString,
         prompt: String,
         replyContext: String? = nil,
         tone: String,
         length: String,
         result: String,
         timestamp: Date = Date(),
         isFavorite: Bool = false) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.prompt = prompt
        self.replyContext = replyContext
        self.tone = tone
        self.length = length
        self.result = result
        self.timestamp = timestamp
        self.isFavorite = isFavorite
    }

    // [v2-C1] Custom decoder for backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.id = try container.decode(String.self, forKey: .id)
        self.prompt = try container.decode(String.self, forKey: .prompt)
        self.replyContext = try container.decodeIfPresent(String.self, forKey: .replyContext)
        self.tone = try container.decode(String.self, forKey: .tone)
        self.length = try container.decodeIfPresent(String.self, forKey: .length) ?? "medium"
        self.result = try container.decode(String.self, forKey: .result)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }
}

// [v3-C2] SECURITY NOTE: UserDefaults.standard stores data as plaintext plist on disk.
// User prompts and AI-generated results are stored unencrypted.
// Mitigation (current): isEnabled toggle + clearAll() give users control.
// TODO Phase 3: Migrate to encrypted storage (Keychain or CryptoKit-based encryption)
// for sensitive compose history data.
final class ComposeHistoryManager {
    static let shared = ComposeHistoryManager()
    private let defaults = UserDefaults.standard
    private let historyKey = "compose_history_v1"
    private let historyEnabledKey = "compose_history_enabled"
    private let maxItems = 100

    private init() {}

    var isEnabled: Bool {
        get { defaults.object(forKey: historyEnabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: historyEnabledKey) }
    }

    var items: [ComposeHistoryItem] {
        guard let data = defaults.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([ComposeHistoryItem].self, from: data)
        else { return [] }
        return decoded
    }

    var favorites: [ComposeHistoryItem] {
        return items.filter { $0.isFavorite }
    }

    func addItem(_ item: ComposeHistoryItem) {
        guard isEnabled else { return }
        var list = items
        list.insert(item, at: 0)
        if list.count > maxItems {
            let favs = list.filter { $0.isFavorite }
            let nonFavs = list.filter { !$0.isFavorite }
            list = favs + Array(nonFavs.prefix(max(0, maxItems - favs.count)))
        }
        save(list)
    }

    func toggleFavorite(id: String) {
        var list = items
        if let idx = list.firstIndex(where: { $0.id == id }) {
            list[idx].isFavorite.toggle()
            save(list)
        }
    }

    func deleteItem(id: String) {
        var list = items
        list.removeAll { $0.id == id }
        save(list)
    }

    func clearAll() {
        save([])
    }

    private func save(_ list: [ComposeHistoryItem]) {
        do {
            let data = try JSONEncoder().encode(list)
            defaults.set(data, forKey: historyKey)
        } catch {
            print("[ComposeHistoryManager] Failed to encode history: \(error.localizedDescription)")
        }
    }
}
