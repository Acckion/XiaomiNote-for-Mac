//
//  BulletAttachment.swift
//  MiNoteMac
//
//  项目符号附件 - 用于渲染无序列表的项目符号
//

import AppKit

// MARK: - 项目符号附件

/// 项目符号附件 - 用于渲染无序列表的项目符号
final class BulletAttachment: ListMarkerAttachment {

    // MARK: - Properties

    /// 重写基类 indent 以支持缓存失效
    override var indent: Int {
        didSet {
            cachedImage = nil
        }
    }

    /// 项目符号大小
    var bulletSize: CGFloat = 6

    /// 附件总宽度（优化后减小以使列表标记与正文左边缘对齐）
    var attachmentWidth: CGFloat = 16

    /// 重写基类 isDarkMode 以支持缓存失效
    override var isDarkMode: Bool {
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

        if let cached = cachedImage {
            return cached
        }

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
        let indentOffset = CGFloat(indent - 1) * 20
        return CGRect(x: indentOffset, y: 2, width: attachmentWidth, height: bulletSize + 4)
    }

    // MARK: - Private Methods

    /// 创建项目符号图像
    private func createBulletImage() -> NSImage {
        let size = NSSize(width: attachmentWidth, height: bulletSize + 4)

        return NSImage(size: size, flipped: false) { [weak self] rect in
            guard let self else { return false }

            let bulletColor = isDarkMode
                ? NSColor.white.withAlphaComponent(0.8)
                : NSColor.black.withAlphaComponent(0.7)

            let bulletStyle = getBulletStyle(for: indent)

            let bulletX: CGFloat = 2
            let bulletY = (rect.height - bulletSize) / 2
            let bulletRect = CGRect(x: bulletX, y: bulletY, width: bulletSize, height: bulletSize)

            bulletColor.setFill()
            bulletColor.setStroke()

            switch bulletStyle {
            case .filled:
                let path = NSBezierPath(ovalIn: bulletRect)
                path.fill()

            case .hollow:
                let path = NSBezierPath(ovalIn: bulletRect.insetBy(dx: 0.5, dy: 0.5))
                path.lineWidth = 1
                path.stroke()

            case .square:
                let path = NSBezierPath(rect: bulletRect)
                path.fill()

            case .dash:
                let dashRect = CGRect(x: bulletX, y: rect.height / 2 - 1, width: bulletSize, height: 2)
                let path = NSBezierPath(rect: dashRect)
                path.fill()
            }

            return true
        }
    }

    /// 项目符号样式
    private enum BulletStyle {
        case filled
        case hollow
        case square
        case dash
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
