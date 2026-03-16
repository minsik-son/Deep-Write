import Foundation

final class TranslationCache {
    static let shared = TranslationCache()

    private var cache: [String: CacheEntry] = [:]
    private var accessOrder: [String] = []
    private let maxItems = AppConstants.Limits.cacheMaxItems

    private struct CacheEntry {
        let translatedText: String
        let timestamp: Date
    }

    private init() {}

    private func cacheKey(text: String, source: String, target: String) -> String {
        return "\(source)_\(target)_\(text)"
    }

    func get(text: String, source: String, target: String) -> String? {
        let key = cacheKey(text: text, source: source, target: target)
        guard let entry = cache[key] else { return nil }

        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
            accessOrder.append(key)
        }

        return entry.translatedText
    }

    func set(text: String, source: String, target: String, translatedText: String) {
        let key = cacheKey(text: text, source: source, target: target)

        if cache[key] != nil {
            if let index = accessOrder.firstIndex(of: key) {
                accessOrder.remove(at: index)
            }
        }

        cache[key] = CacheEntry(translatedText: translatedText, timestamp: Date())
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

    #if DEBUG
    /// 현재 캐시 상태 (디버그 전용)
    var debugCacheInfo: String {
        let count = cache.count
        let totalChars = cache.values.reduce(0) { $0 + $1.translatedText.count }
        let estimatedKB = (totalChars * 2) / 1024  // UTF-16 기준
        return "entries=\(count)/\(maxItems), ~\(estimatedKB)KB"
    }
    #endif
}
