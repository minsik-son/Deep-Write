import Foundation

final class ChatReplyCache {
    static let shared = ChatReplyCache()

    private var cache: [String: CacheEntry] = [:]
    private var accessOrder: [String] = []
    private let maxItems: Int = 20

    private struct CacheEntry {
        let replies: [String]
        let timestamp: Date
    }

    private init() {}

    private func cacheKey(context: String, tone: String, direction: String) -> String {
        let trimmedContext = String(context.prefix(100))
        return "\(tone)_\(trimmedContext)_\(direction)"
    }

    func get(context: String, tone: String, direction: String) -> [String]? {
        let key = cacheKey(context: context, tone: tone, direction: direction)
        guard let entry = cache[key] else { return nil }

        if Date().timeIntervalSince(entry.timestamp) > 300 {
            cache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
            return nil
        }

        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
            accessOrder.append(key)
        }

        return entry.replies
    }

    func set(context: String, tone: String, direction: String, replies: [String]) {
        let key = cacheKey(context: context, tone: tone, direction: direction)

        if cache[key] != nil {
            if let index = accessOrder.firstIndex(of: key) {
                accessOrder.remove(at: index)
            }
        }

        cache[key] = CacheEntry(replies: replies, timestamp: Date())
        accessOrder.append(key)

        while cache.count > maxItems, let oldest = accessOrder.first {
            accessOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }

    func clear() {
        cache.removeAll()
        accessOrder.removeAll()
    }
}
