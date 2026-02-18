import Foundation

/// 内存缓存节点（用于LRU链表）
private class CacheNode {
    let noteId: String
    var note: Note
    var previous: CacheNode?
    var next: CacheNode?
    var lastAccessTime: Date

    init(noteId: String, note: Note) {
        self.noteId = noteId
        self.note = note
        lastAccessTime = Date()
    }
}

/// 内存缓存管理器
///
/// 使用LRU（最近最少使用）算法管理笔记缓存
/// - 最多缓存10条最近访问的笔记
/// - 线程安全（使用actor）
/// - 自动清理过期缓存
public actor MemoryCacheManager {
    static let shared = MemoryCacheManager()

    /// 缓存大小限制
    private let maxCacheSize = 10

    // LRU链表：head是最新访问的，tail是最久未访问的
    private var head: CacheNode?
    private var tail: CacheNode?

    /// 快速查找字典
    private var cache: [String: CacheNode] = [:]

    private init() {
        Swift.print("[MemoryCache] 初始化内存缓存管理器，最大缓存数: \(maxCacheSize)")
    }

    // MARK: - 公共接口

    /// 获取笔记（优先从缓存）
    ///
    /// - Parameter noteId: 笔记ID
    /// - Returns: 笔记对象，如果缓存未命中则返回nil
    func getNote(noteId: String) -> Note? {
        guard let node = cache[noteId] else {
            Swift.print("[MemoryCache] 缓存未命中 - ID: \(noteId.prefix(8))...")
            return nil
        }

        // 更新访问时间
        node.lastAccessTime = Date()

        // 移动到链表头部（标记为最近访问）
        moveToHead(node)

        Swift.print("[MemoryCache] 缓存命中 - ID: \(noteId.prefix(8))..., 标题: \(node.note.title)")
        return node.note
    }

    /// 缓存笔记
    ///
    /// - Parameter note: 笔记对象
    func cacheNote(_ note: Note) {
        let noteId = note.id

        if let existingNode = cache[noteId] {
            // 更新现有节点
            existingNode.note = note
            existingNode.lastAccessTime = Date()
            moveToHead(existingNode)
            Swift.print("[MemoryCache] 更新缓存 - ID: \(noteId.prefix(8))..., 标题: \(note.title)")
        } else {
            // 创建新节点
            let newNode = CacheNode(noteId: noteId, note: note)

            // 如果缓存已满，移除最久未访问的节点
            if cache.count >= maxCacheSize {
                evictLRU()
            }

            // 添加到链表头部
            addToHead(newNode)
            cache[noteId] = newNode

            Swift.print("[MemoryCache] 添加缓存 - ID: \(noteId.prefix(8))..., 标题: \(note.title), 当前缓存数: \(cache.count)")
        }
    }

    /// 更新缓存中的笔记
    ///
    /// - Parameter note: 更新后的笔记对象
    func updateCachedNote(_ note: Note) {
        cacheNote(note) // 复用cacheNote逻辑
    }

    /// 清除缓存
    func clearCache() {
        cache.removeAll()
        head = nil
        tail = nil
        Swift.print("[MemoryCache] 清除所有缓存")
    }

    /// 移除指定笔记的缓存
    ///
    /// - Parameter noteId: 笔记ID
    func removeNote(noteId: String) {
        guard let node = cache[noteId] else {
            return
        }

        removeNode(node)
        cache.removeValue(forKey: noteId)
        Swift.print("[MemoryCache] 移除缓存 - ID: \(noteId.prefix(8))...")
    }

    /// 预加载笔记列表
    ///
    /// - Parameter notes: 笔记数组
    func preloadNotes(_ notes: [Note]) {
        for note in notes.prefix(maxCacheSize) {
            if cache[note.id] == nil {
                let newNode = CacheNode(noteId: note.id, note: note)

                // 如果缓存已满，移除最久未访问的节点
                if cache.count >= maxCacheSize {
                    evictLRU()
                }

                addToHead(newNode)
                cache[note.id] = newNode
            }
        }

        Swift.print("[MemoryCache] 预加载完成 - 预加载 \(min(notes.count, maxCacheSize)) 条笔记，当前缓存数: \(cache.count)")
    }

    /// 获取缓存统计信息
    ///
    /// - Returns: 缓存统计信息字典
    func getCacheStats() -> [String: Any] {
        [
            "count": cache.count,
            "maxSize": maxCacheSize,
            "hitRate": "N/A", // 需要添加命中率统计
        ]
    }

    // MARK: - 私有方法（LRU操作）

    /// 将节点移动到链表头部
    private func moveToHead(_ node: CacheNode) {
        if node === head {
            return // 已经是头部
        }

        removeNode(node)
        addToHead(node)
    }

    /// 将节点添加到链表头部
    private func addToHead(_ node: CacheNode) {
        node.previous = nil
        node.next = head

        if let head {
            head.previous = node
        } else {
            tail = node // 如果链表为空，新节点也是尾部
        }

        head = node
    }

    /// 从链表中移除节点
    private func removeNode(_ node: CacheNode) {
        if let previous = node.previous {
            previous.next = node.next
        } else {
            head = node.next // 是头部节点
        }

        if let next = node.next {
            next.previous = node.previous
        } else {
            tail = node.previous // 是尾部节点
        }

        node.previous = nil
        node.next = nil
    }

    /// 移除最久未访问的节点（LRU）
    private func evictLRU() {
        guard let tailNode = tail else {
            return
        }

        removeNode(tailNode)
        cache.removeValue(forKey: tailNode.noteId)
        Swift.print("[MemoryCache] 移除LRU缓存 - ID: \(tailNode.noteId.prefix(8))..., 标题: \(tailNode.note.title)")
    }
}
