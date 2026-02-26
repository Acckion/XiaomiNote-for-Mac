//
//  HorizontalRuleAttachment.swift
//  MiNoteMac
//
//  水平分割线附件 - 用于渲染分割线
//

import AppKit

// MARK: - 水平分割线附件

/// 水平分割线附件 - 用于渲染分割线
/// 实现 Apple Notes 风格的分割线，支持深色/浅色模式适配
final class HorizontalRuleAttachment: NSTextAttachment, ThemeAwareAttachment {

    // MARK: - Properties

    /// 分割线高度
    var lineHeight: CGFloat = 1

    /// 分割线宽度（相对于容器宽度的比例，0-1）
    var widthRatio: CGFloat = 1.0

    /// 垂直边距
    var verticalPadding: CGFloat = 12

    /// 水平边距
    var horizontalPadding: CGFloat = 0

    /// 是否为深色模式
    var isDarkMode = false {
        didSet {
            if oldValue != isDarkMode {
                invalidateCache()
            }
        }
    }

    /// 分割线样式
    var lineStyle: LineStyle = .solid

    /// 缓存的图像
    private var cachedImage: NSImage?

    /// 当前容器宽度
    private var currentWidth: CGFloat = 300

    /// 上次渲染时的宽度（用于检测宽度变化）
    private var lastRenderedWidth: CGFloat = 0

    // MARK: - Line Style

    /// 分割线样式枚举
    enum LineStyle {
        case solid
        case dashed
        case dotted
        case gradient
    }

    // MARK: - Initialization

    override nonisolated init(data contentData: Data?, ofType uti: String?) {
        super.init(data: contentData, ofType: uti)
        setupAttachment()
    }

    required nonisolated init?(coder: NSCoder) {
        super.init(coder: coder)
        setupAttachment()
    }

    /// 便捷初始化方法
    convenience init(width: CGFloat = 300, style: LineStyle = .solid) {
        self.init(data: nil, ofType: nil)
        self.currentWidth = width
        self.lineStyle = style
    }

    private func setupAttachment() {
        updateBounds()
        image = createHorizontalRuleImage()
    }

    private func updateBounds() {
        let totalHeight = lineHeight + verticalPadding * 2
        bounds = CGRect(x: 0, y: 0, width: currentWidth, height: totalHeight)
    }

    // MARK: - NSTextAttachment Override

    override nonisolated func image(
        forBounds _: CGRect,
        textContainer: NSTextContainer?,
        characterIndex _: Int
    ) -> NSImage? {
        updateTheme()

        if let container = textContainer {
            let containerWidth = container.size.width - container.lineFragmentPadding * 2 - horizontalPadding * 2
            if containerWidth > 0, abs(containerWidth - currentWidth) > 1 {
                currentWidth = containerWidth
                invalidateCache()
                updateBounds()
            }
        }

        if abs(currentWidth - lastRenderedWidth) > 1 {
            invalidateCache()
        }

        if let cached = cachedImage {
            return cached
        }

        let image = createHorizontalRuleImage()
        cachedImage = image
        lastRenderedWidth = currentWidth
        return image
    }

    override nonisolated func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment _: CGRect,
        glyphPosition _: CGPoint,
        characterIndex _: Int
    ) -> CGRect {
        if let container = textContainer {
            let containerWidth = container.size.width - container.lineFragmentPadding * 2 - horizontalPadding * 2
            if containerWidth > 0 {
                currentWidth = containerWidth
            }
        }

        let totalHeight = lineHeight + verticalPadding * 2
        let lineWidth = currentWidth * widthRatio
        let xOffset = (currentWidth - lineWidth) / 2

        return CGRect(x: xOffset, y: 0, width: lineWidth, height: totalHeight)
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

    // MARK: - Cache Management

    /// 清除缓存的图像
    func invalidateCache() {
        cachedImage = nil
    }

    // MARK: - Private Methods

    /// 创建分割线图像
    private func createHorizontalRuleImage() -> NSImage {
        let totalHeight = lineHeight + verticalPadding * 2
        let lineWidth = currentWidth * widthRatio
        let size = NSSize(width: lineWidth, height: totalHeight)

        let image = NSImage(size: size)
        image.lockFocus()

        let lineColor = if isDarkMode {
            NSColor.white.withAlphaComponent(0.3)
        } else {
            NSColor.black.withAlphaComponent(0.25)
        }

        let lineY = (totalHeight - lineHeight) / 2
        let lineRect = CGRect(x: 0, y: lineY, width: lineWidth, height: lineHeight)
        lineColor.setFill()
        NSBezierPath(rect: lineRect).fill()

        image.unlockFocus()

        return image
    }

    /// 绘制实线
    private func drawSolidLine(in rect: CGRect, at y: CGFloat, color: NSColor) {
        let linePath = NSBezierPath()
        linePath.move(to: NSPoint(x: 0, y: y))
        linePath.line(to: NSPoint(x: rect.width, y: y))

        color.setStroke()
        linePath.lineWidth = lineHeight
        linePath.stroke()
    }

    /// 绘制虚线
    private func drawDashedLine(in rect: CGRect, at y: CGFloat, color: NSColor) {
        let linePath = NSBezierPath()
        linePath.move(to: NSPoint(x: 0, y: y))
        linePath.line(to: NSPoint(x: rect.width, y: y))

        color.setStroke()
        linePath.lineWidth = lineHeight
        linePath.setLineDash([6, 4], count: 2, phase: 0)
        linePath.stroke()
    }

    /// 绘制点线
    private func drawDottedLine(in rect: CGRect, at y: CGFloat, color: NSColor) {
        let linePath = NSBezierPath()
        linePath.move(to: NSPoint(x: 0, y: y))
        linePath.line(to: NSPoint(x: rect.width, y: y))

        color.setStroke()
        linePath.lineWidth = lineHeight
        linePath.setLineDash([2, 3], count: 2, phase: 0)
        linePath.lineCapStyle = .round
        linePath.stroke()
    }

    /// 绘制渐变线
    private func drawGradientLine(in rect: CGRect, at y: CGFloat) {
        let centerColor: NSColor
        let edgeColor: NSColor

        if isDarkMode {
            centerColor = NSColor.white.withAlphaComponent(0.5)
            edgeColor = NSColor.white.withAlphaComponent(0.0)
        } else {
            centerColor = NSColor.black.withAlphaComponent(0.35)
            edgeColor = NSColor.black.withAlphaComponent(0.0)
        }

        guard let gradient = NSGradient(
            colors: [edgeColor, centerColor, edgeColor],
            atLocations: [0.0, 0.5, 1.0],
            colorSpace: .deviceRGB
        ) else {
            drawSolidLine(in: rect, at: y, color: centerColor)
            return
        }

        let lineRect = CGRect(x: 0, y: y - lineHeight / 2, width: rect.width, height: lineHeight)
        gradient.draw(in: lineRect, angle: 0)
    }
}
