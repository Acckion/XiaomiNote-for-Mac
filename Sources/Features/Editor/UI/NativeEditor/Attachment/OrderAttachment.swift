//
//  OrderAttachment.swift
//  MiNoteMac
//
//  有序列表附件 - 用于渲染有序列表的编号
//

import AppKit

// MARK: - 有序列表附件

/// 有序列表附件 - 用于渲染有序列表的编号
final class OrderAttachment: ListMarkerAttachment {

    // MARK: - Properties

    /// 列表编号
    nonisolated(unsafe) var number = 1 {
        didSet {
            cachedImage = nil
        }
    }

    /// 输入编号（对应 XML 中的 inputNumber 属性）
    nonisolated(unsafe) var inputNumber = 0

    /// 重写基类 indent 以支持缓存失效
    override var indent: Int {
        didSet {
            cachedImage = nil
        }
    }

    /// 附件宽度（优化后减小以使列表标记与正文左边缘对齐）
    nonisolated(unsafe) var attachmentWidth: CGFloat = 20

    /// 附件高度
    nonisolated(unsafe) var attachmentHeight: CGFloat = 16

    /// 重写基类 isDarkMode 以支持缓存失效
    override var isDarkMode: Bool {
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

        if let cached = cachedImage {
            return cached
        }

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
        let indentOffset = CGFloat(indent - 1) * 20
        return CGRect(x: indentOffset, y: -2, width: attachmentWidth, height: attachmentHeight)
    }

    // MARK: - Private Methods

    /// 创建编号图像
    private func createOrderImage() -> NSImage {
        let size = NSSize(width: attachmentWidth, height: attachmentHeight)

        return NSImage(size: size, flipped: false) { [weak self] rect in
            guard let self else { return false }

            let textColor = isDarkMode
                ? NSColor.white.withAlphaComponent(0.8)
                : NSColor.black.withAlphaComponent(0.7)

            let numberText = "\(number)."
            let font = NSFont.systemFont(ofSize: 13)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
            ]

            let attributedString = NSAttributedString(string: numberText, attributes: attributes)
            let textSize = attributedString.size()

            let textX: CGFloat = 2
            let textY = (rect.height - textSize.height) / 2

            attributedString.draw(at: NSPoint(x: textX, y: textY))

            return true
        }
    }
}
