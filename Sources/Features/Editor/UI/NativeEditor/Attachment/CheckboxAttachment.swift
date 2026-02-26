//
//  CheckboxAttachment.swift
//  MiNoteMac
//
//  交互式复选框附件 - 用于渲染可点击的复选框
//

import AppKit

// MARK: - 交互式复选框附件

/// 交互式复选框附件 - 用于渲染可点击的复选框
/// 实现 Apple Notes 风格的复选框，支持深色/浅色模式适配
final class InteractiveCheckboxAttachment: ListMarkerAttachment, InteractiveAttachment {

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

    /// 复选框大小
    var checkboxSize: CGFloat = 16

    /// 附件总宽度（确保符号右侧与文字间距统一）
    var attachmentWidth: CGFloat = 21

    /// 重写基类 isDarkMode 以支持缓存失效
    override var isDarkMode: Bool {
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

        image.isTemplate = false

        return image
    }

    /// 绘制未选中的复选框
    private func drawUncheckedCheckbox(in rect: CGRect) {
        let borderColor: NSColor
        let fillColor: NSColor

        if isDarkMode {
            borderColor = NSColor.white.withAlphaComponent(0.5)
            fillColor = NSColor.white.withAlphaComponent(0.08)
        } else {
            borderColor = NSColor.black.withAlphaComponent(0.4)
            fillColor = NSColor.black.withAlphaComponent(0.03)
        }

        let boxRect = rect.insetBy(dx: 1.5, dy: 1.5)
        let boxPath = NSBezierPath(roundedRect: boxRect, xRadius: 3, yRadius: 3)

        fillColor.setFill()
        boxPath.fill()

        borderColor.setStroke()
        boxPath.lineWidth = 1.5
        boxPath.stroke()
    }

    /// 绘制选中的复选框
    private func drawCheckedCheckbox(in rect: CGRect) {
        let checkboxColor = NSColor.systemBlue
        let checkmarkColor = NSColor.white

        let boxRect = rect.insetBy(dx: 1.5, dy: 1.5)
        let boxPath = NSBezierPath(roundedRect: boxRect, xRadius: 3, yRadius: 3)

        checkboxColor.setFill()
        boxPath.fill()

        let checkPath = NSBezierPath()

        let inset: CGFloat = 3.5
        let leftX = inset
        let middleX = rect.width * 0.38
        let rightX = rect.width - inset
        let topY = rect.height - inset - 1
        let middleY = inset + 1
        let bottomY = rect.height * 0.45

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
