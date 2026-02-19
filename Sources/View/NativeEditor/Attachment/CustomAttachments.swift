//
//  CustomAttachments.swift
//  MiNoteMac
//
//  自定义 NSTextAttachment 子类 - 用于渲染复选框、分割线、项目符号等特殊元素
//

import AppKit
import SwiftUI

// MARK: - 基础协议

/// 可交互附件协议
protocol InteractiveAttachment: AnyObject {
    /// 处理点击事件
    /// - Parameters:
    ///   - point: 点击位置
    ///   - textContainer: 文本容器
    ///   - characterIndex: 字符索引
    /// - Returns: 是否处理了点击
    func handleClick(at point: NSPoint, in textContainer: NSTextContainer?, characterIndex: Int) -> Bool
}

/// 主题感知附件协议
protocol ThemeAwareAttachment: AnyObject {
    /// 当前是否为深色模式
    var isDarkMode: Bool { get set }

    /// 更新主题
    func updateTheme()
}

// MARK: - 交互式复选框附件

/// 交互式复选框附件 - 用于渲染可点击的复选框
/// 实现 Apple Notes 风格的复选框，支持深色/浅色模式适配
final class InteractiveCheckboxAttachment: NSTextAttachment, InteractiveAttachment, ThemeAwareAttachment {

    // MARK: - Properties

    /// 复选框是否选中
    /// 此属性会被保存到 XML 中（checked="true"）
    var isChecked = false {
        didSet {
            // 清除缓存的图像，强制重新渲染
            cachedImage = nil
            cachedCheckedImage = nil
            cachedUncheckedImage = nil
            // 更新附件的 image 属性
            image = createCheckboxImage(checked: isChecked)
        }
    }

    /// 缩进级别（对应 XML 中的 level 属性）
    var level = 3

    /// 缩进值（对应 XML 中的 indent 属性）
    var indent = 1

    /// 复选框大小
    var checkboxSize: CGFloat = 16

    /// 附件总宽度（确保符号右侧与文字间距统一）
    var attachmentWidth: CGFloat = 21

    /// 是否为深色模式
    var isDarkMode = false {
        didSet {
            if oldValue != isDarkMode {
                invalidateCache()
                // 更新附件的 image 属性
                image = createCheckboxImage(checked: isChecked)
            }
        }
    }

    /// 状态切换回调
    var onToggle: ((Bool) -> Void)?

    /// 字符索引（用于定位）
    var characterIndex = 0

    /// 缓存的图像
    private var cachedImage: NSImage?

    /// 缓存的选中状态图像
    private var cachedCheckedImage: NSImage?

    /// 缓存的未选中状态图像
    private var cachedUncheckedImage: NSImage?

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
    convenience init(checked: Bool = false, level: Int = 3, indent: Int = 1) {
        self.init(data: nil, ofType: nil)
        self.isChecked = checked
        self.level = level
        self.indent = indent
    }

    private func setupAttachment() {
        // 设置附件边界，使用 attachmentWidth 确保与其他列表类型间距一致
        bounds = CGRect(x: 0, y: -3, width: attachmentWidth, height: checkboxSize)

        // 预先创建图像，确保附件有默认图像
        // 这对于某些 NSTextView 配置是必要的
        image = createCheckboxImage(checked: isChecked)
    }

    // MARK: - NSTextAttachment Override

    override nonisolated func image(
        forBounds _: CGRect,
        textContainer _: NSTextContainer?,
        characterIndex charIndex: Int
    ) -> NSImage? {
        // 保存字符索引
        characterIndex = charIndex

        // 检查主题变化
        updateTheme()

        // 使用状态特定的缓存
        if isChecked {
            if let cached = cachedCheckedImage {
                return cached
            }
            let image = createCheckboxImage(checked: true)
            cachedCheckedImage = image
            return image
        } else {
            if let cached = cachedUncheckedImage {
                return cached
            }
            let image = createCheckboxImage(checked: false)
            cachedUncheckedImage = image
            return image
        }
    }

    override nonisolated func attachmentBounds(
        for _: NSTextContainer?,
        proposedLineFragment _: CGRect,
        glyphPosition _: CGPoint,
        characterIndex _: Int
    ) -> CGRect {
        // 返回复选框的边界，使用 attachmentWidth 确保与其他列表类型间距一致
        CGRect(x: 0, y: -3, width: attachmentWidth, height: checkboxSize)
    }

    // MARK: - InteractiveAttachment

    func handleClick(at point: NSPoint, in _: NSTextContainer?, characterIndex _: Int) -> Bool {
        // 检查点击是否在复选框区域内
        let bounds = CGRect(x: 0, y: 0, width: checkboxSize, height: checkboxSize)
        guard bounds.contains(point) else {
            return false
        }

        // 切换选中状态
        isChecked.toggle()

        // 触发回调
        onToggle?(isChecked)

        return true
    }

    /// 检查点是否在复选框的可点击区域内
    /// - Parameter point: 相对于附件的点击位置
    /// - Returns: 是否在可点击区域内
    func isPointInClickableArea(_ point: NSPoint) -> Bool {
        let clickableRect = CGRect(x: 0, y: 0, width: checkboxSize, height: checkboxSize)
        return clickableRect.contains(point)
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

    /// 清除所有缓存的图像
    func invalidateCache() {
        cachedImage = nil
        cachedCheckedImage = nil
        cachedUncheckedImage = nil
    }

    // MARK: - Private Methods

    /// 创建复选框图像
    /// - Parameter checked: 是否为选中状态
    /// - Returns: 复选框图像
    private func createCheckboxImage(checked: Bool) -> NSImage {
        // 图像使用 attachmentWidth 宽度，但 checkbox 只绘制在左侧 checkboxSize 区域
        let size = NSSize(width: attachmentWidth, height: checkboxSize)
        let image = NSImage(size: size, flipped: false) { [weak self] _ in
            guard let self else { return false }

            // 只在左侧 checkboxSize 区域绘制 checkbox，右侧留白作为间距
            let checkboxRect = CGRect(x: 0, y: 0, width: checkboxSize, height: checkboxSize)

            if checked {
                drawCheckedCheckbox(in: checkboxRect)
            } else {
                drawUncheckedCheckbox(in: checkboxRect)
            }

            return true
        }

        // 设置图像为模板图像以支持自动颜色适配
        image.isTemplate = false

        return image
    }

    /// 绘制未选中的复选框
    private func drawUncheckedCheckbox(in rect: CGRect) {
        // 获取颜色 - Apple Notes 风格
        let borderColor: NSColor
        let fillColor: NSColor

        if isDarkMode {
            borderColor = NSColor.white.withAlphaComponent(0.5)
            fillColor = NSColor.white.withAlphaComponent(0.08)
        } else {
            borderColor = NSColor.black.withAlphaComponent(0.4)
            fillColor = NSColor.black.withAlphaComponent(0.03)
        }

        // 绘制复选框背景
        let boxRect = rect.insetBy(dx: 1.5, dy: 1.5)
        let boxPath = NSBezierPath(roundedRect: boxRect, xRadius: 3, yRadius: 3)

        // 填充背景
        fillColor.setFill()
        boxPath.fill()

        // 绘制边框
        borderColor.setStroke()
        boxPath.lineWidth = 1.5
        boxPath.stroke()
    }

    /// 绘制选中的复选框
    private func drawCheckedCheckbox(in rect: CGRect) {
        // 获取颜色 - Apple Notes 风格（选中时使用系统蓝色）
        let checkboxColor = NSColor.systemBlue
        let checkmarkColor = NSColor.white

        // 绘制填充的圆角矩形背景
        let boxRect = rect.insetBy(dx: 1.5, dy: 1.5)
        let boxPath = NSBezierPath(roundedRect: boxRect, xRadius: 3, yRadius: 3)

        checkboxColor.setFill()
        boxPath.fill()

        // 绘制勾选标记
        let checkPath = NSBezierPath()

        // 计算勾选标记的点位置（Apple Notes 风格的勾选）
        let inset: CGFloat = 3.5
        let leftX = inset
        let middleX = rect.width * 0.38
        let rightX = rect.width - inset
        let topY = rect.height - inset - 1
        let middleY = inset + 1
        let bottomY = rect.height * 0.45

        // 绘制勾选标记路径
        checkPath.move(to: NSPoint(x: leftX, y: bottomY))
        checkPath.line(to: NSPoint(x: middleX, y: middleY))
        checkPath.line(to: NSPoint(x: rightX, y: topY))

        checkmarkColor.setStroke()
        checkPath.lineWidth = 2
        checkPath.lineCapStyle = .round
        checkPath.lineJoinStyle = .round
        checkPath.stroke()
    }
}

// MARK: - 水平分割线附件

/// 水平分割线附件 - 用于渲染分割线
/// 实现 Apple Notes 风格的分割线，支持深色/浅色模式适配
final class HorizontalRuleAttachment: NSTextAttachment, ThemeAwareAttachment {

    // MARK: - Properties

    /// 分割线高度（1pt 适中，既清晰可见又不会太粗）
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
        case solid // 实线
        case dashed // 虚线
        case dotted // 点线
        case gradient // 渐变线（Apple Notes 风格）
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
        // 预先创建图像，确保附件有默认图像
        // 这对于某些 NSTextView 配置是必要的
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
        // 检查主题变化
        updateTheme()

        // 更新宽度
        if let container = textContainer {
            let containerWidth = container.size.width - container.lineFragmentPadding * 2 - horizontalPadding * 2
            if containerWidth > 0, abs(containerWidth - currentWidth) > 1 {
                currentWidth = containerWidth
                invalidateCache()
                updateBounds()
            }
        }

        // 检查是否需要重新渲染
        if abs(currentWidth - lastRenderedWidth) > 1 {
            invalidateCache()
        }

        // 如果有缓存的图像，直接返回
        if let cached = cachedImage {
            return cached
        }

        // 创建新图像
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
        // 根据容器宽度调整分割线宽度
        if let container = textContainer {
            let containerWidth = container.size.width - container.lineFragmentPadding * 2 - horizontalPadding * 2
            if containerWidth > 0 {
                currentWidth = containerWidth
            }
        }

        let totalHeight = lineHeight + verticalPadding * 2
        let lineWidth = currentWidth * widthRatio

        // 居中显示分割线
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

        // 使用 lockFocus 方式创建图像（更可靠）
        let image = NSImage(size: size)
        image.lockFocus()

        // 获取分割线颜色（使用适中的透明度）
        let lineColor = if isDarkMode {
            // 深色模式使用浅色分割线，透明度 0.3 适中
            NSColor.white.withAlphaComponent(0.3)
        } else {
            // 浅色模式使用深色分割线，透明度 0.25 适中
            NSColor.black.withAlphaComponent(0.25)
        }

        // 计算分割线位置（垂直居中）
        let lineY = (totalHeight - lineHeight) / 2

        // 使用填充矩形绘制分割线
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

    /// 绘制渐变线（Apple Notes 风格）
    private func drawGradientLine(in rect: CGRect, at y: CGFloat) {
        // 创建渐变颜色
        let centerColor: NSColor
        let edgeColor: NSColor

        if isDarkMode {
            // 深色模式渐变线中心使用更高对比度
            centerColor = NSColor.white.withAlphaComponent(0.5)
            edgeColor = NSColor.white.withAlphaComponent(0.0)
        } else {
            // 浅色模式渐变线中心使用更高对比度
            centerColor = NSColor.black.withAlphaComponent(0.35)
            edgeColor = NSColor.black.withAlphaComponent(0.0)
        }

        // 创建渐变
        guard let gradient = NSGradient(
            colors: [edgeColor, centerColor, edgeColor],
            atLocations: [0.0, 0.5, 1.0],
            colorSpace: .deviceRGB
        ) else {
            // 回退到实线
            drawSolidLine(in: rect, at: y, color: centerColor)
            return
        }

        // 绘制渐变线
        let lineRect = CGRect(x: 0, y: y - lineHeight / 2, width: rect.width, height: lineHeight)
        gradient.draw(in: lineRect, angle: 0)
    }
}

// MARK: - 项目符号附件

/// 项目符号附件 - 用于渲染无序列表的项目符号
final class BulletAttachment: NSTextAttachment, ThemeAwareAttachment {

    // MARK: - Properties

    /// 缩进级别
    var indent = 1 {
        didSet {
            cachedImage = nil
        }
    }

    /// 项目符号大小
    var bulletSize: CGFloat = 6

    /// 附件总宽度（优化后减小以使列表标记与正文左边缘对齐）
    var attachmentWidth: CGFloat = 16

    /// 是否为深色模式
    var isDarkMode = false {
        didSet {
            if oldValue != isDarkMode {
                cachedImage = nil
            }
        }
    }

    /// 缓存的图像
    private var cachedImage: NSImage?

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
    convenience init(indent: Int = 1) {
        self.init(data: nil, ofType: nil)
        self.indent = indent
    }

    private func setupAttachment() {
        bounds = CGRect(x: 0, y: 0, width: attachmentWidth, height: bulletSize + 4)
        // 预先创建图像，确保附件有默认图像
        // 这对于某些 NSTextView 配置是必要的
        image = createBulletImage()
    }

    // MARK: - NSTextAttachment Override

    override nonisolated func image(
        forBounds _: CGRect,
        textContainer _: NSTextContainer?,
        characterIndex _: Int
    ) -> NSImage? {
        // 检查主题变化
        updateTheme()

        // 如果有缓存的图像，直接返回
        if let cached = cachedImage {
            return cached
        }

        // 创建新图像
        let image = createBulletImage()
        cachedImage = image
        return image
    }

    override nonisolated func attachmentBounds(
        for _: NSTextContainer?,
        proposedLineFragment _: CGRect,
        glyphPosition _: CGPoint,
        characterIndex _: Int
    ) -> CGRect {
        // 根据缩进级别调整位置
        // 缩进级别 1 时 x = 0（与正文左边缘对齐）
        // 缩进级别 > 1 时按 20pt 递增
        let indentOffset = CGFloat(indent - 1) * 20
        return CGRect(x: indentOffset, y: 2, width: attachmentWidth, height: bulletSize + 4)
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

    /// 创建项目符号图像
    private func createBulletImage() -> NSImage {
        let size = NSSize(width: attachmentWidth, height: bulletSize + 4)

        return NSImage(size: size, flipped: false) { [weak self] rect in
            guard let self else { return false }

            // 获取项目符号颜色
            let bulletColor = isDarkMode
                ? NSColor.white.withAlphaComponent(0.8)
                : NSColor.black.withAlphaComponent(0.7)

            // 根据缩进级别选择不同的符号样式
            let bulletStyle = getBulletStyle(for: indent)

            // 计算项目符号位置（左对齐，x = 2 提供最小边距）
            let bulletX: CGFloat = 2
            let bulletY = (rect.height - bulletSize) / 2
            let bulletRect = CGRect(x: bulletX, y: bulletY, width: bulletSize, height: bulletSize)

            bulletColor.setFill()
            bulletColor.setStroke()

            switch bulletStyle {
            case .filled:
                // 实心圆点
                let path = NSBezierPath(ovalIn: bulletRect)
                path.fill()

            case .hollow:
                // 空心圆点
                let path = NSBezierPath(ovalIn: bulletRect.insetBy(dx: 0.5, dy: 0.5))
                path.lineWidth = 1
                path.stroke()

            case .square:
                // 实心方块
                let path = NSBezierPath(rect: bulletRect)
                path.fill()

            case .dash:
                // 短横线
                let dashRect = CGRect(x: bulletX, y: rect.height / 2 - 1, width: bulletSize, height: 2)
                let path = NSBezierPath(rect: dashRect)
                path.fill()
            }

            return true
        }
    }

    /// 项目符号样式
    private enum BulletStyle {
        case filled // 实心圆点
        case hollow // 空心圆点
        case square // 实心方块
        case dash // 短横线
    }

    /// 根据缩进级别获取项目符号样式
    private func getBulletStyle(for indent: Int) -> BulletStyle {
        switch indent % 4 {
        case 1: .filled
        case 2: .hollow
        case 3: .square
        case 0: .dash
        default: .filled
        }
    }
}

// MARK: - 有序列表附件

/// 有序列表附件 - 用于渲染有序列表的编号
final class OrderAttachment: NSTextAttachment, ThemeAwareAttachment {

    // MARK: - Properties

    /// 列表编号
    nonisolated(unsafe) var number = 1 {
        didSet {
            cachedImage = nil
        }
    }

    /// 输入编号（对应 XML 中的 inputNumber 属性）
    nonisolated(unsafe) var inputNumber = 0

    /// 缩进级别
    nonisolated(unsafe) var indent = 1 {
        didSet {
            cachedImage = nil
        }
    }

    /// 附件宽度（优化后减小以使列表标记与正文左边缘对齐）
    nonisolated(unsafe) var attachmentWidth: CGFloat = 20

    /// 附件高度
    nonisolated(unsafe) var attachmentHeight: CGFloat = 16

    /// 是否为深色模式
    nonisolated(unsafe) var isDarkMode = false {
        didSet {
            if oldValue != isDarkMode {
                cachedImage = nil
            }
        }
    }

    /// 缓存的图像
    private nonisolated(unsafe) var cachedImage: NSImage?

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
    convenience init(number: Int = 1, inputNumber: Int = 0, indent: Int = 1) {
        self.init(data: nil, ofType: nil)
        self.number = number
        self.inputNumber = inputNumber
        self.indent = indent
    }

    private func setupAttachment() {
        bounds = CGRect(x: 0, y: -2, width: attachmentWidth, height: attachmentHeight)
        // 预先创建图像，确保附件有默认图像
        // 这对于某些 NSTextView 配置是必要的
        image = createOrderImage()
    }

    // MARK: - NSTextAttachment Override

    override nonisolated func image(
        forBounds _: CGRect,
        textContainer _: NSTextContainer?,
        characterIndex _: Int
    ) -> NSImage? {
        // 检查主题变化
        updateTheme()

        // 如果有缓存的图像，直接返回
        if let cached = cachedImage {
            return cached
        }

        // 创建新图像
        let image = createOrderImage()
        cachedImage = image
        return image
    }

    override nonisolated func attachmentBounds(
        for _: NSTextContainer?,
        proposedLineFragment _: CGRect,
        glyphPosition _: CGPoint,
        characterIndex _: Int
    ) -> CGRect {
        // 根据缩进级别调整位置
        // 缩进级别 1 时 x = 0（与正文左边缘对齐）
        // 缩进级别 > 1 时按 20pt 递增
        let indentOffset = CGFloat(indent - 1) * 20
        return CGRect(x: indentOffset, y: -2, width: attachmentWidth, height: attachmentHeight)
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

    /// 创建编号图像
    private func createOrderImage() -> NSImage {
        let size = NSSize(width: attachmentWidth, height: attachmentHeight)

        return NSImage(size: size, flipped: false) { [weak self] rect in
            guard let self else { return false }

            // 获取文本颜色
            let textColor = isDarkMode
                ? NSColor.white.withAlphaComponent(0.8)
                : NSColor.black.withAlphaComponent(0.7)

            // 创建编号文本
            let numberText = "\(number)."
            let font = NSFont.systemFont(ofSize: 13)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
            ]

            let attributedString = NSAttributedString(string: numberText, attributes: attributes)
            let textSize = attributedString.size()

            // 计算文本位置（左对齐，x = 2 提供最小边距）
            let textX: CGFloat = 2
            let textY = (rect.height - textSize.height) / 2

            attributedString.draw(at: NSPoint(x: textX, y: textY))

            return true
        }
    }
}

// MARK: - 图片附件

// 注意：ImageAttachment 类已移至单独的文件 ImageAttachment.swift
// 请使用 Sources/View/NativeEditor/ImageAttachment.swift 中的定义
