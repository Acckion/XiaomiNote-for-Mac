//
//  ImageAttachment.swift
//  MiNoteMac
//
//  图片附件 - 用于在原生编辑器中显示和管理图片

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
    
    /// 图片描述（从 XML 解析得到，用户可编辑的说明信息）
    var imageDescription: String?
    
    /// 图片显示属性（小米笔记固有属性，必须保持原值）
    /// "0" 或 "1"，客户端不使用但需要保持与云端一致
    var imgshow: String?
    
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
    convenience init(imageData: Data, fileId: String, folderId: String? = nil, imageDescription: String? = nil, imgshow: String? = nil) {
        self.init(data: imageData, ofType: "public.image")
        self.fileId = fileId
        self.folderId = folderId
        self.imageDescription = imageDescription
        self.imgshow = imgshow
        
        if let image = NSImage(data: imageData) {
            self.image = image
            self.originalSize = image.size
            calculateDisplaySize()
        }
    }
    
    /// 便捷初始化方法 - 从 NSImage 创建
    convenience init(image: NSImage, fileId: String? = nil, folderId: String? = nil, imageDescription: String? = nil, imgshow: String? = nil) {
        self.init(data: nil, ofType: nil)
        self.fileId = fileId
        self.folderId = folderId
        self.imageDescription = imageDescription
        self.imgshow = imgshow
        self.image = image
        self.originalSize = image.size
        calculateDisplaySize()
    }
    
    /// 便捷初始化方法 - 从 URL 创建（立即加载）
    convenience init(src: String, fileId: String? = nil, folderId: String? = nil, imageDescription: String? = nil, imgshow: String? = nil) {
        self.init(data: nil, ofType: nil)
        self.src = src
        self.fileId = fileId
        self.folderId = folderId
        self.imageDescription = imageDescription
        self.imgshow = imgshow
        self.isLoading = true
        print("[ImageAttachment] 🖼️ 初始化（立即加载）")
        print("[ImageAttachment]   - src: '\(src)'")
        print("[ImageAttachment]   - fileId: '\(fileId ?? "nil")'")
        print("[ImageAttachment]   - folderId: '\(folderId ?? "nil")'")
        print("[ImageAttachment]   - imageDescription: '\(imageDescription ?? "nil")'")
        print("[ImageAttachment]   - imgshow: '\(imgshow ?? "nil")'")
        print("[ImageAttachment]   - 附件对象地址: \(Unmanaged.passUnretained(self).toOpaque())")
        setupPlaceholder()
        
        // 立即开始加载图片，不等待 image(forBounds:) 被调用
        startLoadingImage()
    }
    
    /// 开始加载图片
    private func startLoadingImage() {
        print("[ImageAttachment] 🖼️ startLoadingImage 被调用")
        
        if let fileId = fileId {
            print("[ImageAttachment] 🖼️ 使用 fileId 加载: \(fileId)")
            loadImageFromLocalStorage(fileId: fileId, folderId: folderId ?? "0")
        } else if let src = src {
            print("[ImageAttachment] 🖼️ 使用 src 加载: \(src)")
            loadImageFromSource(src)
        } else {
            print("[ImageAttachment] ❌ 无法加载：没有 fileId 也没有 src")
            isLoading = false
            loadFailed = true
        }
    }
    
    private func setupAttachment() {
        updateTheme()
    }

    
    // MARK: - NSTextAttachment Override
    
    /// 是否已记录过调用日志（避免重复日志）
    private var hasLoggedCall: Bool = false
    
    override func image(forBounds imageBounds: CGRect,
                       textContainer: NSTextContainer?,
                       characterIndex charIndex: Int) -> NSImage? {
        // 只在第一次调用时打印详细日志
        if !hasLoggedCall {
            print("[ImageAttachment] 🖼️ image(forBounds:) 首次调用")
            print("[ImageAttachment]   - 附件对象地址: \(Unmanaged.passUnretained(self).toOpaque())")
            print("[ImageAttachment]   - imageBounds: \(imageBounds)")
            print("[ImageAttachment]   - characterIndex: \(charIndex)")
            print("[ImageAttachment]   - fileId: '\(fileId ?? "nil")'")
            print("[ImageAttachment]   - src: '\(src ?? "nil")'")
            hasLoggedCall = true
        }
        
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
        
        // 只在需要加载时打印日志
        print("[ImageAttachment] 🖼️ image(forBounds:) - 开始加载图片")
        print("[ImageAttachment]   - fileId: '\(fileId ?? "nil")'")
        print("[ImageAttachment]   - folderId: '\(folderId ?? "nil")'")
        print("[ImageAttachment]   - src: '\(src ?? "nil")'")
        
        if let fileId = fileId, let folderId = folderId {
            print("[ImageAttachment] 🖼️ 使用 fileId + folderId 加载")
            loadImageFromLocalStorage(fileId: fileId, folderId: folderId)
        } else if let src = src {
            print("[ImageAttachment] 🖼️ 使用 src 加载: \(src)")
            loadImageFromSource(src)
        } else {
            print("[ImageAttachment] ❌ 无法加载：没有 fileId/folderId 也没有 src")
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
    
    /// 从本地存储加载图片
    /// 仅使用 images/{userId}.{fileId}.{format} 格式
    private func loadImageFromLocalStorage(fileId: String, folderId: String) {
        isLoading = true
        print("[ImageAttachment] 🖼️ loadImageFromLocalStorage 开始")
        print("[ImageAttachment]   - fileId: \(fileId)")
        print("[ImageAttachment]   - folderId: \(folderId)（已废弃，不再使用）")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let localStorage = LocalStorageService.shared
            
            // 仅使用统一的 images/{userId}.{fileId}.{format} 格式加载
            let result = localStorage.loadImageWithFullFormatAllFormats(fullFileId: fileId)
            
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let (data, format) = result, let loadedImage = NSImage(data: data) {
                    print("[ImageAttachment] ✅ 图片加载成功: \(fileId).\(format), 尺寸: \(loadedImage.size)")
                    self.originalSize = loadedImage.size
                    self.calculateDisplaySize()
                    self.cachedImage = loadedImage
                    self.isLoading = false
                    self.loadFailed = false
                    
                    // 关键：更新 self.image 以便 NSTextView 显示
                    self.image = loadedImage
                    print("[ImageAttachment] ✅ 已更新 self.image")
                    
                    // 通知需要刷新显示
                    self.onLoadComplete?(true)
                    
                    // 发送通知让 NSTextView 刷新
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ImageAttachmentDidLoad"),
                        object: self
                    )
                } else {
                    print("[ImageAttachment] ❌ 无法加载图片: \(fileId)")
                    print("[ImageAttachment] ❌ 仅尝试 images/\(fileId).{format} 格式，未找到图片文件")
                    self.isLoading = false
                    self.loadFailed = true
                    
                    // 更新占位符为错误状态
                    self.placeholderImage = self.createPlaceholderImage()
                    self.image = self.placeholderImage
                    
                    self.onLoadComplete?(false)
                }
            }
        }
    }
    
    private func loadImageFromSource(_ src: String) {
        isLoading = true
        print("[ImageAttachment] 🖼️ loadImageFromSource: \(src)")
        
        if src.hasPrefix("minote://") {
            print("[ImageAttachment] 🖼️ 检测到 minote:// URL，调用 loadFromMinoteURL")
            loadFromMinoteURL(src)
        } else if src.hasPrefix("http://") || src.hasPrefix("https://") {
            print("[ImageAttachment] 🖼️ 检测到 http(s):// URL，调用 loadFromRemoteURL")
            loadFromRemoteURL(src)
        } else {
            print("[ImageAttachment] 🖼️ 检测到本地路径，调用 loadFromLocalPath")
            loadFromLocalPath(src)
        }
    }
    
    private func loadFromMinoteURL(_ urlString: String) {
        print("[ImageAttachment] 🖼️ loadFromMinoteURL: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            print("[ImageAttachment] ❌ 无效的 URL: \(urlString)")
            loadFailed = true
            isLoading = false
            return
        }
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        print("[ImageAttachment] 🖼️ URL 路径组件: \(pathComponents)")
        print("[ImageAttachment] 🖼️ URL host: \(url.host ?? "nil")")
        
        // 格式1: minote://images/{folderId}/{fileName}
        if pathComponents.count >= 3 && pathComponents[0] == "images" {
            let folderId = pathComponents[1]
            let fileName = pathComponents[2]
            let fileId = (fileName as NSString).deletingPathExtension
            
            print("[ImageAttachment] 🖼️ 格式1: minote://images/{folderId}/{fileName}")
            print("[ImageAttachment]   - folderId: \(folderId)")
            print("[ImageAttachment]   - fileId: \(fileId)")
            
            self.folderId = folderId
            self.fileId = fileId
            
            loadImageFromLocalStorage(fileId: fileId, folderId: folderId)
        }
        // 格式2: minote://image/{fileId} (Web 端生成的格式，没有 folderId)
        else if pathComponents.count >= 2 && pathComponents[0] == "image" {
            let fileId = pathComponents[1]
            self.fileId = fileId
            
            // 使用已有的 folderId（可能是 "0" 代表未分类），或者使用 "0" 作为默认值
            let effectiveFolderId = self.folderId ?? "0"
            
            print("[ImageAttachment] 🖼️ 格式2: minote://image/{fileId}")
            print("[ImageAttachment]   - fileId: \(fileId)")
            print("[ImageAttachment]   - effectiveFolderId: \(effectiveFolderId)")
            
            loadImageFromLocalStorage(fileId: fileId, folderId: effectiveFolderId)
        }
        // 格式3: minote://{fileId} (host 格式)
        else if let host = url.host {
            self.fileId = host
            
            // 使用已有的 folderId，或者使用 "0" 作为默认值
            let effectiveFolderId = self.folderId ?? "0"
            
            print("[ImageAttachment] 🖼️ 格式3: minote://{fileId} (host)")
            print("[ImageAttachment]   - fileId: \(host)")
            print("[ImageAttachment]   - effectiveFolderId: \(effectiveFolderId)")
            
            loadImageFromLocalStorage(fileId: host, folderId: effectiveFolderId)
        } else {
            print("[ImageAttachment] ❌ 无法解析 minote URL: \(urlString)")
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
        // 设置 self.image 为占位符，这样 NSTextView 才能显示它
        // 注意：设置 self.image 后，image(forBounds:) 不会被调用
        // 所以我们需要在图片加载完成后更新 self.image
        self.image = placeholderImage
        print("[ImageAttachment] 🖼️ setupPlaceholder - 设置占位符图片")
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
