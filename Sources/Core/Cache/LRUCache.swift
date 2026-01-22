import Foundation

/// LRU 缓存实现
final class LRUCache<Key: Hashable, Value> {
    private struct CacheEntry {
        let key: Key
        let value: Value
        var accessTime: Date
    }

    private var cache: [Key: CacheEntry] = [:]
    private let maxSize: Int
    private let lock = NSLock()

    init(maxSize: Int = 100) {
        self.maxSize = maxSize
    }

    func get(_ key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }

        guard var entry = cache[key] else {
            return nil
        }

        entry.accessTime = Date()
        cache[key] = entry
        return entry.value
    }

    func set(_ key: Key, value: Value) {
        lock.lock()
        defer { lock.unlock() }

        if cache.count >= maxSize {
            evictLeastRecentlyUsed()
        }

        cache[key] = CacheEntry(
            key: key,
            value: value,
            accessTime: Date()
        )
    }

    func remove(_ key: Key) {
        lock.lock()
        defer { lock.unlock() }

        cache.removeValue(forKey: key)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }

        cache.removeAll()
    }

    private func evictLeastRecentlyUsed() {
        guard let lruEntry = cache.values.min(by: { $0.accessTime < $1.accessTime }) else {
            return
        }

        cache.removeValue(forKey: lruEntry.key)
    }
}
