import AppKit
import Foundation

// MARK: - Cache Keys

/// 字体缓存键
/// 用于唯一标识一个字体对象
struct FontCacheKey: Hashable {
    /// 字体名称
    let name: String

    /// 字体大小
    let size: CGFloat
}

/// 段落样式缓存键
/// 用于唯一标识一个段落样式对象
struct ParagraphStyleCacheKey: Hashable {
    /// 行间距
    let lineSpacing: CGFloat

    /// 段落间距
    let paragraphSpacing: CGFloat

    /// 对齐方式
    let alignment: NSTextAlignment

    /// 首行缩进
    let firstLineHeadIndent: CGFloat

    /// 头部缩进
    let headIndent: CGFloat

    /// 尾部缩进
    let tailIndent: CGFloat

    /// 最小行高
    let minimumLineHeight: CGFloat

    /// 最大行高
    let maximumLineHeight: CGFloat

    init(
        lineSpacing: CGFloat = 0,
        paragraphSpacing: CGFloat = 0,
        alignment: NSTextAlignment = .left,
        firstLineHeadIndent: CGFloat = 0,
        headIndent: CGFloat = 0,
        tailIndent: CGFloat = 0,
        minimumLineHeight: CGFloat = 0,
        maximumLineHeight: CGFloat = 0
    ) {
        self.lineSpacing = lineSpacing
        self.paragraphSpacing = paragraphSpacing
        self.alignment = alignment
        self.firstLineHeadIndent = firstLineHeadIndent
        self.headIndent = headIndent
        self.tailIndent = tailIndent
        self.minimumLineHeight = minimumLineHeight
        self.maximumLineHeight = maximumLineHeight
    }

    /// 从 NSParagraphStyle 创建缓存键
    init(from style: NSParagraphStyle) {
        self.lineSpacing = style.lineSpacing
        self.paragraphSpacing = style.paragraphSpacing
        self.alignment = style.alignment
        self.firstLineHeadIndent = style.firstLineHeadIndent
        self.headIndent = style.headIndent
        self.tailIndent = style.tailIndent
        self.minimumLineHeight = style.minimumLineHeight
        self.maximumLineHeight = style.maximumLineHeight
    }
}

/// 颜色缓存键
/// 用于唯一标识一个颜色对象
struct ColorCacheKey: Hashable {
    /// 十六进制颜色值（如 "#FF0000"）
    let hex: String

    init(hex: String) {
        self.hex = hex.uppercased()
    }

    /// 从 NSColor 创建缓存键
    init?(from color: NSColor) {
        guard let rgbColor = color.usingColorSpace(.deviceRGB) else {
            return nil
        }

        let red = Int(rgbColor.redComponent * 255)
        let green = Int(rgbColor.greenComponent * 255)
        let blue = Int(rgbColor.blueComponent * 255)

        self.hex = String(format: "#%02X%02X%02X", red, green, blue)
    }
}

// MARK: - Cache Statistics

/// 缓存统计信息
struct CacheStatistics {
    /// 字体缓存命中次数
    var fontCacheHits = 0

    /// 字体缓存未命中次数
    var fontCacheMisses = 0

    /// 段落样式缓存命中次数
    var paragraphStyleCacheHits = 0

    /// 段落样式缓存未命中次数
    var paragraphStyleCacheMisses = 0

    /// 颜色缓存命中次数
    var colorCacheHits = 0

    /// 颜色缓存未命中次数
    var colorCacheMisses = 0

    /// 字体缓存命中率
    var fontCacheHitRate: Double {
        let total = fontCacheHits + fontCacheMisses
        return total > 0 ? Double(fontCacheHits) / Double(total) : 0
    }

    /// 段落样式缓存命中率
    var paragraphStyleCacheHitRate: Double {
        let total = paragraphStyleCacheHits + paragraphStyleCacheMisses
        return total > 0 ? Double(paragraphStyleCacheHits) / Double(total) : 0
    }

    /// 颜色缓存命中率
    var colorCacheHitRate: Double {
        let total = colorCacheHits + colorCacheMisses
        return total > 0 ? Double(colorCacheHits) / Double(total) : 0
    }

    /// 总体缓存命中率
    var overallCacheHitRate: Double {
        let totalHits = fontCacheHits + paragraphStyleCacheHits + colorCacheHits
        let totalMisses = fontCacheMisses + paragraphStyleCacheMisses + colorCacheMisses
        let total = totalHits + totalMisses
        return total > 0 ? Double(totalHits) / Double(total) : 0
    }
}

// MARK: - Performance Cache

/// 性能缓存
/// 缓存常用的属性对象（字体、段落样式、颜色）以提高性能
public class PerformanceCache {
    /// 字体缓存
    private var fontCache: [FontCacheKey: NSFont] = [:]

    /// 段落样式缓存
    private var paragraphStyleCache: [ParagraphStyleCacheKey: NSParagraphStyle] = [:]

    /// 颜色缓存
    private var colorCache: [ColorCacheKey: NSColor] = [:]

    /// 缓存大小限制
    private let maxCacheSize = 100

    /// 缓存统计信息
    private(set) var statistics = CacheStatistics()

    /// LRU 访问顺序跟踪（字体）
    private var fontAccessOrder: [FontCacheKey] = []

    /// LRU 访问顺序跟踪（段落样式）
    private var paragraphStyleAccessOrder: [ParagraphStyleCacheKey] = []

    /// LRU 访问顺序跟踪（颜色）
    private var colorAccessOrder: [ColorCacheKey] = []

    /// 线程安全锁
    private let lock = NSLock()

    init() {}

    // MARK: - Font Cache

    /// 获取或创建字体
    /// - Parameters:
    ///   - name: 字体名称
    ///   - size: 字体大小
    /// - Returns: 字体对象
    func font(name: String, size: CGFloat) -> NSFont {
        let key = FontCacheKey(name: name, size: size)

        lock.lock()
        defer { lock.unlock() }

        // 查询缓存
        if let cachedFont = fontCache[key] {
            statistics.fontCacheHits += 1
            updateAccessOrder(for: key, in: &fontAccessOrder)
            return cachedFont
        }

        // 缓存未命中，创建新字体
        statistics.fontCacheMisses += 1
        let font = NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)

        // 加入缓存
        fontCache[key] = font
        fontAccessOrder.append(key)

        // 检查缓存大小
        if fontCache.count > maxCacheSize {
            evictLRUFont()
        }

        return font
    }

    // MARK: - Paragraph Style Cache

    /// 获取或创建段落样式
    /// - Parameter key: 段落样式缓存键
    /// - Returns: 段落样式对象
    func paragraphStyle(key: ParagraphStyleCacheKey) -> NSParagraphStyle {
        lock.lock()
        defer { lock.unlock() }

        // 查询缓存
        if let cachedStyle = paragraphStyleCache[key] {
            statistics.paragraphStyleCacheHits += 1
            updateAccessOrder(for: key, in: &paragraphStyleAccessOrder)
            return cachedStyle
        }

        // 缓存未命中，创建新样式
        statistics.paragraphStyleCacheMisses += 1
        let style = createParagraphStyle(from: key)

        // 加入缓存
        paragraphStyleCache[key] = style
        paragraphStyleAccessOrder.append(key)

        // 检查缓存大小
        if paragraphStyleCache.count > maxCacheSize {
            evictLRUParagraphStyle()
        }

        return style
    }

    /// 从缓存键创建段落样式
    private func createParagraphStyle(from key: ParagraphStyleCacheKey) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = key.lineSpacing
        style.paragraphSpacing = key.paragraphSpacing
        style.alignment = key.alignment
        style.firstLineHeadIndent = key.firstLineHeadIndent
        style.headIndent = key.headIndent
        style.tailIndent = key.tailIndent
        style.minimumLineHeight = key.minimumLineHeight
        style.maximumLineHeight = key.maximumLineHeight
        return style.copy() as! NSParagraphStyle
    }

    // MARK: - Color Cache

    /// 获取或创建颜色
    /// - Parameter hex: 十六进制颜色值（如 "#FF0000" 或 "FF0000"）
    /// - Returns: 颜色对象
    func color(hex: String) -> NSColor {
        let key = ColorCacheKey(hex: hex)

        lock.lock()
        defer { lock.unlock() }

        // 查询缓存
        if let cachedColor = colorCache[key] {
            statistics.colorCacheHits += 1
            updateAccessOrder(for: key, in: &colorAccessOrder)
            return cachedColor
        }

        // 缓存未命中，创建新颜色
        statistics.colorCacheMisses += 1
        let color = createColor(from: hex)

        // 加入缓存
        colorCache[key] = color
        colorAccessOrder.append(key)

        // 检查缓存大小
        if colorCache.count > maxCacheSize {
            evictLRUColor()
        }

        return color
    }

    /// 从十六进制字符串创建颜色
    private func createColor(from hex: String) -> NSColor {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0

        return NSColor(red: red, green: green, blue: blue, alpha: 1.0)
    }

    // MARK: - LRU Eviction

    /// 清理最少使用的字体
    private func evictLRUFont() {
        guard let oldestKey = fontAccessOrder.first else { return }
        fontCache.removeValue(forKey: oldestKey)
        fontAccessOrder.removeFirst()
    }

    /// 清理最少使用的段落样式
    private func evictLRUParagraphStyle() {
        guard let oldestKey = paragraphStyleAccessOrder.first else { return }
        paragraphStyleCache.removeValue(forKey: oldestKey)
        paragraphStyleAccessOrder.removeFirst()
    }

    /// 清理最少使用的颜色
    private func evictLRUColor() {
        guard let oldestKey = colorAccessOrder.first else { return }
        colorCache.removeValue(forKey: oldestKey)
        colorAccessOrder.removeFirst()
    }

    /// 更新访问顺序
    private func updateAccessOrder<T: Hashable>(for key: T, in order: inout [T]) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
            order.append(key)
        }
    }

    // MARK: - Cache Management

    /// 清理所有缓存
    func clearCache() {
        lock.lock()
        defer { lock.unlock() }

        fontCache.removeAll()
        paragraphStyleCache.removeAll()
        colorCache.removeAll()

        fontAccessOrder.removeAll()
        paragraphStyleAccessOrder.removeAll()
        colorAccessOrder.removeAll()

        statistics = CacheStatistics()
    }

    /// 获取缓存统计信息
    /// - Returns: 缓存统计信息
    func cacheStatistics() -> CacheStatistics {
        lock.lock()
        defer { lock.unlock() }

        return statistics
    }

    /// 重置统计信息
    func resetStatistics() {
        lock.lock()
        defer { lock.unlock() }

        statistics = CacheStatistics()
    }
}

// MARK: - CustomStringConvertible

extension CacheStatistics: CustomStringConvertible {
    var description: String {
        """
        缓存统计信息:
        - 字体缓存: \(fontCacheHits) 命中 / \(fontCacheMisses) 未命中 (命中率: \(String(format: "%.2f%%", fontCacheHitRate * 100)))
        - 段落样式缓存: \(paragraphStyleCacheHits) 命中 / \(paragraphStyleCacheMisses) 未命中 (命中率: \(String(
            format: "%.2f%%",
            paragraphStyleCacheHitRate * 100
        )))
        - 颜色缓存: \(colorCacheHits) 命中 / \(colorCacheMisses) 未命中 (命中率: \(String(format: "%.2f%%", colorCacheHitRate * 100)))
        - 总体命中率: \(String(format: "%.2f%%", overallCacheHitRate * 100))
        """
    }
}
