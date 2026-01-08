//
//  ImageAttachment.swift
//  MiNoteMac
//
//  图片附件 - 用于在原生编辑器中显示和管理图片
//  需求: 10.1, 10.2, 10.3, 10.4, 10.5
//

import AppKit
import SwiftUI

// MARK: - 图片附件

/// 图片附件 - 用于在 NSTextView 中显示图片
/// 支持 minote:// URL 方案加载本地图片
final class ImageAttachment: NSTextAttachment, ThemeAwareAttachment {
    
    // MARK: - Properties
    
    /// 图片文件 ID（用于本地存储）
    var fileId: String?
    
    /// 图片源 URL（minote:// 或 http(s)://）
    var src: String?
    
    /// 文件夹 ID（用于本地存储路径）
    var folderId: String?
    
    /// 原始图片尺寸
    var originalSize: NSSize = .zero
    
    /// 显示尺寸
    var displaySize: NSSize = NSSize(width: 300, height: 200)
    
    /// 最大显示宽度
    var maxWidth: CGFloat = 500
    
    /// 是否正在加载
    var isLoading: Bool = false
    
    /// 加载失败
    var loadFailed: Bool = false
    
    /// 是否为深色模式
    var isDarkMode: Bool = false {
        didSet {
            if oldValue != isDarkMode {
                invalidateCache()
            }
        }
    }
    
    /// 缓存的图像
    private var cachedImage: NSImage?
    
    /// 占位符图像
    private var placeholderImage: NSImage?
    
    /// 加载完成回调
    var onLoadComplete: ((Bool) -> Void)?
    
    // MARK: - Initialization
    
    override init(data contentData: Data?, ofType uti: String?) {
        super.init(data: contentData, ofType: uti)
        setupAttachment()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupAttachment()
    }
    
    /// 便捷初始化方法 - 从图片数据创建
    convenience init(imageData: Data, fileId: String, folderId: String? = nil) {
        self.init(data: imageData, ofType: "public.image")
        self.fileId = fileId
        self.folderId = folderId
        
        if let image = NSImage(data: imageData) {
            self.image = image
            self.originalSize = image.size
            calculateDisplaySize()
        }
    }
    
    /// 便捷初始化方法 - 从 NSImage 创建
    convenience init(image: NSImage, fileId: String? = nil, folderId: String? = nil) {
        self.init(data: nil, ofType: nil)
        self.fileId = fileId
        self.folderId = folderId
        self.image = image
        self.originalSize = image.size
        calculateDisplaySize()
    }
    
    /// 便捷初始化方法 - 从 URL 创建（延迟加载）
    convenience init(src: String, fileId: String? = nil, folderId: String? = nil) {
        self.init(data: nil, ofType: nil)
        self.src = src
        self.fileId = fileId
        self.folderId = folderId
        self.isLoading = true
        setupPlaceholder()
    }
    
    private func setupAttachment() {
        updateTheme()
    }

    
    // MARK: - NSTextAttachment Override
    
    override func image(forBounds imageBounds: CGRect,
                       textContainer: NSTextContainer?,
                       characterIndex charIndex: Int) -> NSImage? {
        updateTheme()
        
        if let cached = cachedImage {
            return cached
        }
        
        if isLoading || loadFailed {
            return placeholderImage ?? createPlaceholderImage()
        }
        
        if let image = self.image {
            cachedImage = image
            return image
        }
        
        if let fileId = fileId, let folderId = folderId {
            loadImageFromLocalStorage(fileId: fileId, folderId: folderId)
        } else if let src = src {
            loadImageFromSource(src)
        }
        
        return placeholderImage ?? createPlaceholderImage()
    }
    
    override func attachmentBounds(for textContainer: NSTextContainer?,
                                  proposedLineFragment lineFrag: CGRect,
                                  glyphPosition position: CGPoint,
                                  characterIndex charIndex: Int) -> CGRect {
        if let container = textContainer {
            let containerWidth = container.size.width - container.lineFragmentPadding * 2
            if containerWidth > 0 && displaySize.width > containerWidth {
                let ratio = containerWidth / displaySize.width
                displaySize = NSSize(
                    width: containerWidth,
                    height: displaySize.height * ratio
                )
            }
        }
        
        return CGRect(origin: .zero, size: displaySize)
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
    
    // MARK: - Image Loading
    
    private func loadImageFromLocalStorage(fileId: String, folderId: String) {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let imageData = LocalStorageService.shared.getImage(imageId: fileId, folderId: folderId)
            
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let data = imageData, let image = NSImage(data: data) {
                    self.image = image
                    self.originalSize = image.size
                    self.calculateDisplaySize()
                    self.cachedImage = image
                    self.isLoading = false
                    self.loadFailed = false
                    self.onLoadComplete?(true)
                } else {
                    self.isLoading = false
                    self.loadFailed = true
                    self.onLoadComplete?(false)
                }
            }
        }
    }
    
    private func loadImageFromSource(_ src: String) {
        isLoading = true
        
        if src.hasPrefix("minote://") {
            loadFromMinoteURL(src)
        } else if src.hasPrefix("http://") || src.hasPrefix("https://") {
            loadFromRemoteURL(src)
        } else {
            loadFromLocalPath(src)
        }
    }
    
    private func loadFromMinoteURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            loadFailed = true
            isLoading = false
            return
        }
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        if pathComponents.count >= 3 && pathComponents[0] == "images" {
            let folderId = pathComponents[1]
            let fileName = pathComponents[2]
            let fileId = (fileName as NSString).deletingPathExtension
            
            self.folderId = folderId
            self.fileId = fileId
            
            loadImageFromLocalStorage(fileId: fileId, folderId: folderId)
        } else if let host = url.host {
            self.fileId = host
            
            if let folderId = self.folderId {
                loadImageFromLocalStorage(fileId: host, folderId: folderId)
            } else {
                loadFailed = true
                isLoading = false
            }
        } else {
            loadFailed = true
            isLoading = false
        }
    }
    
    private func loadFromRemoteURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            loadFailed = true
            isLoading = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let data = data, let image = NSImage(data: data) {
                    self.image = image
                    self.originalSize = image.size
                    self.calculateDisplaySize()
                    self.cachedImage = image
                    self.isLoading = false
                    self.loadFailed = false
                    self.onLoadComplete?(true)
                } else {
                    self.isLoading = false
                    self.loadFailed = true
                    self.onLoadComplete?(false)
                }
            }
        }.resume()
    }
    
    private func loadFromLocalPath(_ path: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = NSImage(contentsOfFile: path)
            
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let image = image {
                    self.image = image
                    self.originalSize = image.size
                    self.calculateDisplaySize()
                    self.cachedImage = image
                    self.isLoading = false
                    self.loadFailed = false
                    self.onLoadComplete?(true)
                } else {
                    self.isLoading = false
                    self.loadFailed = true
                    self.onLoadComplete?(false)
                }
            }
        }
    }

    
    // MARK: - Size Calculation
    
    private func calculateDisplaySize() {
        guard originalSize.width > 0 && originalSize.height > 0 else {
            displaySize = NSSize(width: 300, height: 200)
            return
        }
        
        if originalSize.width <= maxWidth {
            displaySize = originalSize
        } else {
            let ratio = maxWidth / originalSize.width
            displaySize = NSSize(
                width: maxWidth,
                height: originalSize.height * ratio
            )
        }
        
        self.bounds = CGRect(origin: .zero, size: displaySize)
    }
    
    func setMaxWidth(_ width: CGFloat) {
        maxWidth = width
        calculateDisplaySize()
        invalidateCache()
    }
    
    // MARK: - Placeholder
    
    private func setupPlaceholder() {
        placeholderImage = createPlaceholderImage()
        displaySize = NSSize(width: 200, height: 150)
        self.bounds = CGRect(origin: .zero, size: displaySize)
    }
    
    private func createPlaceholderImage() -> NSImage {
        let size = NSSize(width: 200, height: 150)
        
        let image = NSImage(size: size, flipped: false) { [weak self] rect in
            guard let self = self else { return false }
            
            let backgroundColor: NSColor
            let borderColor: NSColor
            let iconColor: NSColor
            let textColor: NSColor
            
            if self.isDarkMode {
                backgroundColor = NSColor.white.withAlphaComponent(0.05)
                borderColor = NSColor.white.withAlphaComponent(0.1)
                iconColor = NSColor.white.withAlphaComponent(0.3)
                textColor = NSColor.white.withAlphaComponent(0.5)
            } else {
                backgroundColor = NSColor.black.withAlphaComponent(0.03)
                borderColor = NSColor.black.withAlphaComponent(0.1)
                iconColor = NSColor.black.withAlphaComponent(0.2)
                textColor = NSColor.black.withAlphaComponent(0.4)
            }
            
            let backgroundPath = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
            backgroundColor.setFill()
            backgroundPath.fill()
            
            borderColor.setStroke()
            backgroundPath.lineWidth = 1
            backgroundPath.stroke()
            
            let iconSize: CGFloat = 40
            let iconRect = CGRect(
                x: (rect.width - iconSize) / 2,
                y: (rect.height - iconSize) / 2 + 10,
                width: iconSize,
                height: iconSize
            )
            
            if self.loadFailed {
                self.drawErrorIcon(in: iconRect, color: iconColor)
            } else if self.isLoading {
                self.drawLoadingIcon(in: iconRect, color: iconColor)
            } else {
                self.drawImageIcon(in: iconRect, color: iconColor)
            }
            
            let text: String
            if self.loadFailed {
                text = "图片加载失败"
            } else if self.isLoading {
                text = "加载中..."
            } else {
                text = "图片"
            }
            
            let font = NSFont.systemFont(ofSize: 12)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor
            ]
            
            let textSize = (text as NSString).size(withAttributes: attributes)
            let textPoint = NSPoint(
                x: (rect.width - textSize.width) / 2,
                y: (rect.height - iconSize) / 2 - textSize.height - 5
            )
            
            (text as NSString).draw(at: textPoint, withAttributes: attributes)
            
            return true
        }
        
        return image
    }
    
    private func drawImageIcon(in rect: CGRect, color: NSColor) {
        color.setStroke()
        color.setFill()
        
        let framePath = NSBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 4), xRadius: 4, yRadius: 4)
        framePath.lineWidth = 2
        framePath.stroke()
        
        let mountainPath = NSBezierPath()
        let baseY = rect.minY + rect.height * 0.35
        let peakY = rect.minY + rect.height * 0.7
        
        mountainPath.move(to: NSPoint(x: rect.minX + 8, y: baseY))
        mountainPath.line(to: NSPoint(x: rect.midX - 4, y: peakY))
        mountainPath.line(to: NSPoint(x: rect.midX + 4, y: baseY + 8))
        mountainPath.line(to: NSPoint(x: rect.maxX - 8, y: peakY - 8))
        mountainPath.line(to: NSPoint(x: rect.maxX - 8, y: baseY))
        mountainPath.close()
        mountainPath.fill()
        
        let sunRect = CGRect(x: rect.maxX - 18, y: rect.maxY - 18, width: 10, height: 10)
        let sunPath = NSBezierPath(ovalIn: sunRect)
        sunPath.fill()
    }
    
    private func drawLoadingIcon(in rect: CGRect, color: NSColor) {
        color.setStroke()
        
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius: CGFloat = 15
        
        let circlePath = NSBezierPath()
        circlePath.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 0,
            endAngle: 270,
            clockwise: false
        )
        circlePath.lineWidth = 3
        circlePath.lineCapStyle = .round
        circlePath.stroke()
    }
    
    private func drawErrorIcon(in rect: CGRect, color: NSColor) {
        let errorColor = NSColor.systemRed.withAlphaComponent(0.6)
        errorColor.setStroke()
        errorColor.setFill()
        
        let xPath = NSBezierPath()
        let inset: CGFloat = 12
        
        xPath.move(to: NSPoint(x: rect.minX + inset, y: rect.minY + inset))
        xPath.line(to: NSPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        
        xPath.move(to: NSPoint(x: rect.maxX - inset, y: rect.minY + inset))
        xPath.line(to: NSPoint(x: rect.minX + inset, y: rect.maxY - inset))
        
        xPath.lineWidth = 3
        xPath.lineCapStyle = .round
        xPath.stroke()
    }
    
    // MARK: - Cache Management
    
    func invalidateCache() {
        cachedImage = nil
        placeholderImage = nil
    }
    
    func reload() {
        invalidateCache()
        loadFailed = false
        isLoading = true
        
        if let fileId = fileId, let folderId = folderId {
            loadImageFromLocalStorage(fileId: fileId, folderId: folderId)
        } else if let src = src {
            loadImageFromSource(src)
        }
    }
}
