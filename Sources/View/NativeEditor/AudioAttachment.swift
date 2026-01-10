//
//  AudioAttachment.swift
//  MiNoteMac
//
//  语音文件附件 - 用于在原生编辑器中显示语音文件占位符
//  需求: 2.1, 2.2, 2.4
//

import AppKit
import SwiftUI

// MARK: - 语音文件附件

/// 语音文件附件 - 用于在 NSTextView 中显示语音文件占位符
/// 由于小米笔记浏览器端不支持播放录音，本附件仅显示占位符标识
final class AudioAttachment: NSTextAttachment, ThemeAwareAttachment {
    
    // MARK: - Properties
    
    /// 语音文件 ID（对应 XML 中的 fileid 属性）
    var fileId: String?
    
    /// 文件摘要（digest）
    var digest: String?
    
    /// MIME 类型
    var mimeType: String?
    
    /// 是否为深色模式
    var isDarkMode: Bool = false {
        didSet {
            if oldValue != isDarkMode {
                invalidateCache()
            }
        }
    }
    
    /// 占位符尺寸
    var placeholderSize: NSSize = NSSize(width: 160, height: 44)
    
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
    /// - Parameters:
    ///   - fileId: 语音文件 ID
    ///   - digest: 文件摘要（可选）
    ///   - mimeType: MIME 类型（可选）
    convenience init(fileId: String, digest: String? = nil, mimeType: String? = nil) {
        self.init(data: nil, ofType: nil)
        self.fileId = fileId
        self.digest = digest
        self.mimeType = mimeType
        print("[AudioAttachment] 🎤 初始化语音附件")
        print("[AudioAttachment]   - fileId: '\(fileId)'")
        print("[AudioAttachment]   - digest: '\(digest ?? "nil")'")
        print("[AudioAttachment]   - mimeType: '\(mimeType ?? "nil")'")
    }
    
    private func setupAttachment() {
        updateTheme()
        self.bounds = CGRect(origin: .zero, size: placeholderSize)
        // 预先创建占位符图像
        self.image = createPlaceholderImage()
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
        let image = createPlaceholderImage()
        cachedImage = image
        return image
    }
    
    override func attachmentBounds(for textContainer: NSTextContainer?,
                                  proposedLineFragment lineFrag: CGRect,
                                  glyphPosition position: CGPoint,
                                  characterIndex charIndex: Int) -> CGRect {
        // 检查容器宽度，确保不超出
        if let container = textContainer {
            let containerWidth = container.size.width - container.lineFragmentPadding * 2
            if containerWidth > 0 && placeholderSize.width > containerWidth {
                // 如果占位符宽度超过容器宽度，调整尺寸
                let ratio = containerWidth / placeholderSize.width
                return CGRect(
                    origin: .zero,
                    size: NSSize(
                        width: containerWidth,
                        height: placeholderSize.height * ratio
                    )
                )
            }
        }
        
        return CGRect(origin: .zero, size: placeholderSize)
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
        // 重新创建图像
        self.image = createPlaceholderImage()
    }

    
    // MARK: - Placeholder Image Creation
    
    /// 创建占位符图像
    /// - Returns: 语音文件占位符图像
    private func createPlaceholderImage() -> NSImage {
        let size = placeholderSize
        
        let image = NSImage(size: size, flipped: false) { [weak self] rect in
            guard let self = self else { return false }
            
            // 获取主题相关颜色
            let backgroundColor: NSColor
            let borderColor: NSColor
            let iconColor: NSColor
            let textColor: NSColor
            
            if self.isDarkMode {
                backgroundColor = NSColor.white.withAlphaComponent(0.08)
                borderColor = NSColor.white.withAlphaComponent(0.15)
                iconColor = NSColor.systemOrange.withAlphaComponent(0.8)
                textColor = NSColor.white.withAlphaComponent(0.7)
            } else {
                backgroundColor = NSColor.black.withAlphaComponent(0.04)
                borderColor = NSColor.black.withAlphaComponent(0.12)
                iconColor = NSColor.systemOrange
                textColor = NSColor.black.withAlphaComponent(0.6)
            }
            
            // 绘制圆角矩形背景
            let backgroundPath = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
            backgroundColor.setFill()
            backgroundPath.fill()
            
            // 绘制边框
            borderColor.setStroke()
            backgroundPath.lineWidth = 1
            backgroundPath.stroke()
            
            // 绘制音频图标（麦克风图标）
            let iconSize: CGFloat = 20
            let iconRect = CGRect(
                x: 12,
                y: (rect.height - iconSize) / 2,
                width: iconSize,
                height: iconSize
            )
            self.drawAudioIcon(in: iconRect, color: iconColor)
            
            // 绘制"语音录音"文字标签
            let text = "语音录音"
            let font = NSFont.systemFont(ofSize: 13, weight: .medium)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor
            ]
            
            let textSize = (text as NSString).size(withAttributes: attributes)
            let textPoint = NSPoint(
                x: iconRect.maxX + 10,
                y: (rect.height - textSize.height) / 2
            )
            
            (text as NSString).draw(at: textPoint, withAttributes: attributes)
            
            return true
        }
        
        return image
    }
    
    /// 绘制音频图标（麦克风样式）
    /// - Parameters:
    ///   - rect: 绘制区域
    ///   - color: 图标颜色
    private func drawAudioIcon(in rect: CGRect, color: NSColor) {
        color.setStroke()
        color.setFill()
        
        let centerX = rect.midX
        let centerY = rect.midY
        
        // 绘制麦克风主体（椭圆形）
        let micWidth: CGFloat = 8
        let micHeight: CGFloat = 12
        let micRect = CGRect(
            x: centerX - micWidth / 2,
            y: centerY - 2,
            width: micWidth,
            height: micHeight
        )
        let micPath = NSBezierPath(roundedRect: micRect, xRadius: micWidth / 2, yRadius: micWidth / 2)
        micPath.fill()
        
        // 绘制麦克风支架（U 形）
        let standPath = NSBezierPath()
        let standWidth: CGFloat = 12
        let standHeight: CGFloat = 8
        let standY = centerY - 4
        
        standPath.move(to: NSPoint(x: centerX - standWidth / 2, y: standY))
        standPath.appendArc(
            withCenter: NSPoint(x: centerX, y: standY),
            radius: standWidth / 2,
            startAngle: 180,
            endAngle: 0,
            clockwise: true
        )
        
        standPath.lineWidth = 2
        standPath.lineCapStyle = .round
        standPath.stroke()
        
        // 绘制麦克风底座（竖线 + 横线）
        let basePath = NSBezierPath()
        let baseY = standY - standHeight
        
        // 竖线
        basePath.move(to: NSPoint(x: centerX, y: standY - standWidth / 2))
        basePath.line(to: NSPoint(x: centerX, y: baseY))
        
        // 横线
        let baseWidth: CGFloat = 8
        basePath.move(to: NSPoint(x: centerX - baseWidth / 2, y: baseY))
        basePath.line(to: NSPoint(x: centerX + baseWidth / 2, y: baseY))
        
        basePath.lineWidth = 2
        basePath.lineCapStyle = .round
        basePath.stroke()
    }
}
