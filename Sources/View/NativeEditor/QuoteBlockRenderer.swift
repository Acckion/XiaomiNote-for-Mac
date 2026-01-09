//
//  QuoteBlockRenderer.swift
//  MiNoteMac
//
//  引用块渲染器 - 使用自定义 NSLayoutManager 实现引用块的背景和边框绘制
//

import AppKit
import SwiftUI

// MARK: - 引用块属性键

/// 自定义属性键，用于标记引用块范围
extension NSAttributedString.Key {
    /// 引用块标记属性
    static let quoteBlock = NSAttributedString.Key("MiNote.quoteBlock")
    
    /// 引用块缩进级别
    static let quoteIndent = NSAttributedString.Key("MiNote.quoteIndent")
    
    /// 引用块 ID（用于标识同一个引用块的多行）
    static let quoteBlockId = NSAttributedString.Key("MiNote.quoteBlockId")
}

// MARK: - 引用块样式配置

/// 引用块样式配置
struct QuoteBlockStyle {
    /// 左侧边框宽度
    var borderWidth: CGFloat = 3
    
    /// 左侧边框颜色（浅色模式）
    var borderColorLight: NSColor = NSColor.systemBlue.withAlphaComponent(0.6)
    
    /// 左侧边框颜色（深色模式）
    var borderColorDark: NSColor = NSColor.systemBlue.withAlphaComponent(0.7)
    
    /// 背景颜色（浅色模式）
    var backgroundColorLight: NSColor = NSColor.systemBlue.withAlphaComponent(0.05)
    
    /// 背景颜色（深色模式）
    var backgroundColorDark: NSColor = NSColor.systemBlue.withAlphaComponent(0.1)
    
    /// 左侧内边距（边框到文本的距离）
    var leftPadding: CGFloat = 12
    
    /// 右侧内边距
    var rightPadding: CGFloat = 8
    
    /// 顶部内边距
    var topPadding: CGFloat = 4
    
    /// 底部内边距
    var bottomPadding: CGFloat = 4
    
    /// 圆角半径
    var cornerRadius: CGFloat = 4
    
    /// 获取当前主题的边框颜色
    func borderColor(isDarkMode: Bool) -> NSColor {
        return isDarkMode ? borderColorDark : borderColorLight
    }
    
    /// 获取当前主题的背景颜色
    func backgroundColor(isDarkMode: Bool) -> NSColor {
        return isDarkMode ? backgroundColorDark : backgroundColorLight
    }
}

// MARK: - 引用块布局管理器

/// 自定义 NSLayoutManager 子类，用于绘制引用块的背景和边框
class QuoteBlockLayoutManager: NSLayoutManager {
    
    // MARK: - Properties
    
    /// 引用块样式
    var quoteStyle: QuoteBlockStyle = QuoteBlockStyle()
    
    /// 是否为深色模式
    var isDarkMode: Bool = false {
        didSet {
            if oldValue != isDarkMode {
                // 需要重新绘制
                invalidateDisplay(forCharacterRange: NSRange(location: 0, length: textStorage?.length ?? 0))
            }
        }
    }
    
    /// 缓存的引用块范围
    private var cachedQuoteRanges: [NSRange] = []
    
    /// 是否需要更新缓存
    private var needsUpdateCache: Bool = true
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupLayoutManager()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayoutManager()
    }
    
    private func setupLayoutManager() {
        // 启用背景布局
        allowsNonContiguousLayout = true
    }
    
    // MARK: - NSLayoutManager Override
    
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        // 先调用父类方法绘制默认背景
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        
        // 更新主题
        updateTheme()
        
        // 绘制引用块背景
        drawQuoteBlockBackgrounds(forGlyphRange: glyphsToShow, at: origin)
    }
    
    override func processEditing(for textStorage: NSTextStorage,
                                edited editMask: NSTextStorageEditActions,
                                range newCharRange: NSRange,
                                changeInLength delta: Int,
                                invalidatedRange invalidatedCharRange: NSRange) {
        super.processEditing(for: textStorage, edited: editMask, range: newCharRange, changeInLength: delta, invalidatedRange: invalidatedCharRange)
        
        // 标记需要更新缓存
        needsUpdateCache = true
    }
    
    // MARK: - Quote Block Drawing
    
    /// 绘制引用块背景
    private func drawQuoteBlockBackgrounds(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let textStorage = textStorage,
              let textContainer = textContainers.first else {
            return
        }
        
        // 更新引用块范围缓存
        if needsUpdateCache {
            updateQuoteRangesCache()
        }
        
        // 获取要显示的字符范围
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        
        // 遍历所有引用块范围
        for quoteRange in cachedQuoteRanges {
            // 检查引用块是否与显示范围重叠
            let intersection = NSIntersectionRange(quoteRange, charRange)
            guard intersection.length > 0 else { continue }
            
            // 绘制该引用块
            drawQuoteBlock(for: quoteRange, in: textContainer, at: origin)
        }
    }
    
    /// 绘制单个引用块
    private func drawQuoteBlock(for charRange: NSRange, in textContainer: NSTextContainer, at origin: NSPoint) {
        // 获取引用块的字形范围
        let glyphRange = glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        
        // 收集所有行的矩形
        var lineRects: [CGRect] = []
        
        enumerateLineFragments(forGlyphRange: glyphRange) { [weak self] (rect, usedRect, container, range, stop) in
            guard let self = self else { return }
            
            // 计算该行在引用块中的实际范围
            let lineCharRange = self.characterRange(forGlyphRange: range, actualGlyphRange: nil)
            let intersection = NSIntersectionRange(lineCharRange, charRange)
            
            if intersection.length > 0 {
                // 调整矩形位置
                var adjustedRect = usedRect
                adjustedRect.origin.x += origin.x
                adjustedRect.origin.y += origin.y
                
                // 扩展矩形以包含内边距
                adjustedRect.origin.x -= self.quoteStyle.leftPadding
                adjustedRect.size.width += self.quoteStyle.leftPadding + self.quoteStyle.rightPadding
                
                lineRects.append(adjustedRect)
            }
        }
        
        guard !lineRects.isEmpty else { return }
        
        // 合并相邻的行矩形
        let mergedRect = mergeLineRects(lineRects)
        
        // 绘制背景
        drawQuoteBackground(in: mergedRect)
        
        // 绘制左侧边框
        drawQuoteBorder(in: mergedRect)
    }
    
    /// 合并行矩形
    private func mergeLineRects(_ rects: [CGRect]) -> CGRect {
        guard let first = rects.first else {
            return .zero
        }
        
        var minX = first.minX
        var minY = first.minY
        var maxX = first.maxX
        var maxY = first.maxY
        
        for rect in rects.dropFirst() {
            minX = min(minX, rect.minX)
            minY = min(minY, rect.minY)
            maxX = max(maxX, rect.maxX)
            maxY = max(maxY, rect.maxY)
        }
        
        // 添加顶部和底部内边距
        minY -= quoteStyle.topPadding
        maxY += quoteStyle.bottomPadding
        
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    /// 绘制引用块背景
    private func drawQuoteBackground(in rect: CGRect) {
        let backgroundColor = quoteStyle.backgroundColor(isDarkMode: isDarkMode)
        
        // 创建圆角矩形路径
        let backgroundPath = NSBezierPath(roundedRect: rect, xRadius: quoteStyle.cornerRadius, yRadius: quoteStyle.cornerRadius)
        
        backgroundColor.setFill()
        backgroundPath.fill()
    }
    
    /// 绘制引用块左侧边框
    private func drawQuoteBorder(in rect: CGRect) {
        let borderColor = quoteStyle.borderColor(isDarkMode: isDarkMode)
        
        // 创建左侧边框路径
        let borderRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: quoteStyle.borderWidth,
            height: rect.height
        )
        
        // 使用圆角矩形绘制边框
        let borderPath = NSBezierPath(roundedRect: borderRect, xRadius: quoteStyle.borderWidth / 2, yRadius: quoteStyle.borderWidth / 2)
        
        borderColor.setFill()
        borderPath.fill()
    }
    
    // MARK: - Cache Management
    
    /// 更新引用块范围缓存
    private func updateQuoteRangesCache() {
        cachedQuoteRanges.removeAll()
        
        guard let textStorage = textStorage else {
            needsUpdateCache = false
            return
        }
        
        let fullRange = NSRange(location: 0, length: textStorage.length)
        
        // 遍历文本存储，查找所有引用块标记
        textStorage.enumerateAttribute(.quoteBlock, in: fullRange, options: []) { [weak self] value, range, _ in
            guard let self = self, value != nil else { return }
            
            // 检查是否可以与上一个范围合并
            if let lastRange = self.cachedQuoteRanges.last,
               lastRange.upperBound == range.location {
                // 合并相邻的引用块范围
                self.cachedQuoteRanges[self.cachedQuoteRanges.count - 1] = NSRange(
                    location: lastRange.location,
                    length: lastRange.length + range.length
                )
            } else {
                self.cachedQuoteRanges.append(range)
            }
        }
        
        needsUpdateCache = false
    }
    
    /// 使缓存失效
    func invalidateQuoteCache() {
        needsUpdateCache = true
    }
    
    // MARK: - Theme
    
    /// 更新主题
    private func updateTheme() {
        guard let currentAppearance = NSApp?.effectiveAppearance else {
            return
        }
        let newIsDarkMode = currentAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        
        if isDarkMode != newIsDarkMode {
            isDarkMode = newIsDarkMode
        }
    }
}

// MARK: - 引用块文本存储扩展

extension NSMutableAttributedString {
    
    /// 将指定范围标记为引用块
    /// - Parameters:
    ///   - range: 要标记的范围
    ///   - indent: 缩进级别
    ///   - blockId: 引用块 ID（可选，用于标识同一个引用块的多行）
    func markAsQuoteBlock(range: NSRange, indent: Int = 1, blockId: String? = nil) {
        addAttribute(.quoteBlock, value: true, range: range)
        addAttribute(.quoteIndent, value: indent, range: range)
        
        if let blockId = blockId {
            addAttribute(.quoteBlockId, value: blockId, range: range)
        }
    }
    
    /// 移除指定范围的引用块标记
    /// - Parameter range: 要移除标记的范围
    func removeQuoteBlockMark(range: NSRange) {
        removeAttribute(.quoteBlock, range: range)
        removeAttribute(.quoteIndent, range: range)
        removeAttribute(.quoteBlockId, range: range)
    }
    
    /// 检查指定位置是否在引用块内
    /// - Parameter location: 要检查的位置
    /// - Returns: 是否在引用块内
    func isInQuoteBlock(at location: Int) -> Bool {
        guard location >= 0 && location < length else {
            return false
        }
        
        let value = attribute(.quoteBlock, at: location, effectiveRange: nil)
        return value != nil
    }
    
    /// 获取包含指定位置的引用块范围
    /// - Parameter location: 位置
    /// - Returns: 引用块范围，如果不在引用块内则返回 nil
    func quoteBlockRange(at location: Int) -> NSRange? {
        guard location >= 0 && location < length else {
            return nil
        }
        
        var effectiveRange = NSRange(location: 0, length: 0)
        let value = attribute(.quoteBlock, at: location, effectiveRange: &effectiveRange)
        
        if value != nil {
            return effectiveRange
        }
        
        return nil
    }
}

// MARK: - 引用块附件（可选实现）

/// 引用块附件 - 用于在文本中标记引用块的开始
/// 注意：这是一个可选的实现方式，主要的引用块渲染通过 QuoteBlockLayoutManager 完成
final class QuoteBlockAttachment: NSTextAttachment, ThemeAwareAttachment {
    
    // MARK: - Properties
    
    /// 缩进级别
    var indent: Int = 1
    
    /// 是否为深色模式
    var isDarkMode: Bool = false {
        didSet {
            if oldValue != isDarkMode {
                cachedImage = nil
            }
        }
    }
    
    /// 引用块样式
    var style: QuoteBlockStyle = QuoteBlockStyle()
    
    /// 缓存的图像
    private var cachedImage: NSImage?
    
    // MARK: - Initialization
    
    override init(data contentData: Data?, ofType uti: String?) {
        super.init(data: contentData, ofType: uti)
        setupAttachment()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupAttachment()
    }
    
    /// 便捷初始化方法
    convenience init(indent: Int = 1) {
        self.init(data: nil, ofType: nil)
        self.indent = indent
    }
    
    private func setupAttachment() {
        // 设置附件边界（仅用于左侧边框指示器）
        self.bounds = CGRect(x: 0, y: 0, width: style.borderWidth + style.leftPadding, height: 16)
    }
    
    // MARK: - NSTextAttachment Override
    
    override func image(forBounds imageBounds: CGRect,
                       textContainer: NSTextContainer?,
                       characterIndex charIndex: Int) -> NSImage? {
        // 检查主题变化
        updateTheme()
        
        // 如果有缓存的图像，直接返回
        if let cached = cachedImage {
            return cached
        }
        
        // 创建新图像
        let image = createQuoteIndicatorImage()
        cachedImage = image
        return image
    }
    
    override func attachmentBounds(for textContainer: NSTextContainer?,
                                  proposedLineFragment lineFrag: CGRect,
                                  glyphPosition position: CGPoint,
                                  characterIndex charIndex: Int) -> CGRect {
        return CGRect(x: 0, y: 0, width: style.borderWidth + style.leftPadding, height: lineFrag.height)
    }
    
    // MARK: - ThemeAwareAttachment
    
    func updateTheme() {
        guard let currentAppearance = NSApp?.effectiveAppearance else {
            return
        }
        let newIsDarkMode = currentAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        
        if isDarkMode != newIsDarkMode {
            isDarkMode = newIsDarkMode
        }
    }
    
    // MARK: - Private Methods
    
    /// 创建引用块指示器图像
    private func createQuoteIndicatorImage() -> NSImage {
        let width = style.borderWidth + style.leftPadding
        let height: CGFloat = 16
        let size = NSSize(width: width, height: height)
        
        let image = NSImage(size: size, flipped: false) { [weak self] rect in
            guard let self = self else { return false }
            
            // 绘制左侧边框
            let borderColor = self.style.borderColor(isDarkMode: self.isDarkMode)
            let borderRect = CGRect(x: 0, y: 0, width: self.style.borderWidth, height: rect.height)
            
            borderColor.setFill()
            NSBezierPath(roundedRect: borderRect, xRadius: self.style.borderWidth / 2, yRadius: self.style.borderWidth / 2).fill()
            
            return true
        }
        
        return image
    }
}
