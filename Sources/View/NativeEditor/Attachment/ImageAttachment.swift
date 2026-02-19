import AppKit
import SwiftUI

// MARK: - 图片附件

/// 图片附件 - 用于在 NSTextView 中显示图片
/// 支持 minote:// URL 方案加载本地图片
final class ImageAttachment: NSTextAttachment, ThemeAwareAttachment {

    // MARK: - Properties

    nonisolated(unsafe) var fileId: String?
    nonisolated(unsafe) var src: String?
    nonisolated(unsafe) var folderId: String?
    nonisolated(unsafe) var imageDescription: String?
    /// 小米笔记固有属性，必须保持原值与云端一致
    nonisolated(unsafe) var imgshow: String?
    nonisolated(unsafe) var originalSize: NSSize = .zero
    nonisolated(unsafe) var displaySize = NSSize(width: 300, height: 200)
    nonisolated(unsafe) var maxWidth: CGFloat = 500
    nonisolated(unsafe) var isLoading = false
    nonisolated(unsafe) var loadFailed = false
    nonisolated(unsafe) var isDarkMode = false {
        didSet {
            if oldValue != isDarkMode {
                invalidateCache()
            }
        }
    }

    private nonisolated(unsafe) var cachedImage: NSImage?
    private nonisolated(unsafe) var placeholderImage: NSImage?
    nonisolated(unsafe) var onLoadComplete: ((Bool) -> Void)?

    // MARK: - Initialization

    override nonisolated init(data contentData: Data?, ofType uti: String?) {
        super.init(data: contentData, ofType: uti)
        setupAttachment()
    }

    required nonisolated init?(coder: NSCoder) {
        super.init(coder: coder)
        setupAttachment()
    }

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

    convenience init(src: String, fileId: String? = nil, folderId: String? = nil, imageDescription: String? = nil, imgshow: String? = nil) {
        self.init(data: nil, ofType: nil)
        self.src = src
        self.fileId = fileId
        self.folderId = folderId
        self.imageDescription = imageDescription
        self.imgshow = imgshow
        self.isLoading = true

        setupPlaceholder()
        startLoadingImage()
    }

    private func startLoadingImage() {
        if let fileId {
            loadImageFromLocalStorage(fileId: fileId, folderId: folderId ?? "0")
        } else if let src {
            loadImageFromSource(src)
        } else {
            isLoading = false
            loadFailed = true
        }
    }

    private nonisolated func setupAttachment() {
        updateTheme()
    }

    // MARK: - NSTextAttachment Override

    private nonisolated(unsafe) var hasLoggedCall = false

    override nonisolated func image(
        forBounds _: CGRect,
        textContainer _: NSTextContainer?,
        characterIndex _: Int
    ) -> NSImage? {
        updateTheme()

        if let cached = cachedImage {
            return cached
        }

        if isLoading || loadFailed {
            return placeholderImage ?? createPlaceholderImage()
        }

        if let image {
            cachedImage = image
            return image
        }

        if let fileId, let folderId {
            loadImageFromLocalStorage(fileId: fileId, folderId: folderId)
        } else if let src {
            loadImageFromSource(src)
        }

        return placeholderImage ?? createPlaceholderImage()
    }

    override nonisolated func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment _: CGRect,
        glyphPosition _: CGPoint,
        characterIndex _: Int
    ) -> CGRect {
        if let container = textContainer {
            let containerWidth = container.size.width - container.lineFragmentPadding * 2
            if containerWidth > 0, displaySize.width > containerWidth {
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

    nonisolated func updateTheme() {
        guard let currentAppearance = NSApp?.effectiveAppearance else { return }
        let newIsDarkMode = currentAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDarkMode != newIsDarkMode {
            isDarkMode = newIsDarkMode
        }
    }

    // MARK: - Image Loading

    private nonisolated func loadImageFromLocalStorage(fileId: String, folderId: String) {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let localStorage = LocalStorageService.shared
            let result = localStorage.loadImageWithFullFormatAllFormats(fullFileId: fileId)

            DispatchQueue.main.async {
                guard let self else { return }

                if let (data, _) = result, let loadedImage = NSImage(data: data) {
                    self.originalSize = loadedImage.size
                    self.calculateDisplaySize()
                    self.cachedImage = loadedImage
                    self.isLoading = false
                    self.loadFailed = false
                    self.image = loadedImage
                    self.onLoadComplete?(true)
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ImageAttachmentDidLoad"),
                        object: self
                    )
                } else {
                    self.isLoading = false
                    self.loadFailed = true
                    self.placeholderImage = self.createPlaceholderImage()
                    self.image = self.placeholderImage
                    self.onLoadComplete?(false)
                }
            }
        }
    }

    private nonisolated func loadImageFromSource(_ src: String) {
        isLoading = true

        if src.hasPrefix("minote://") {
            loadFromMinoteURL(src)
        } else if src.hasPrefix("http://") || src.hasPrefix("https://") {
            loadFromRemoteURL(src)
        } else {
            loadFromLocalPath(src)
        }
    }

    private nonisolated func loadFromMinoteURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            loadFailed = true
            isLoading = false
            return
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }

        if pathComponents.count >= 3, pathComponents[0] == "images" {
            let folderId = pathComponents[1]
            let fileName = pathComponents[2]
            let fileId = (fileName as NSString).deletingPathExtension
            self.folderId = folderId
            self.fileId = fileId
            loadImageFromLocalStorage(fileId: fileId, folderId: folderId)
        } else if pathComponents.count >= 2, pathComponents[0] == "image" {
            let fileId = pathComponents[1]
            self.fileId = fileId
            let effectiveFolderId = folderId ?? "0"
            loadImageFromLocalStorage(fileId: fileId, folderId: effectiveFolderId)
        } else if let host = url.host {
            fileId = host
            let effectiveFolderId = folderId ?? "0"
            loadImageFromLocalStorage(fileId: host, folderId: effectiveFolderId)
        } else {
            loadFailed = true
            isLoading = false
        }
    }

    private nonisolated func loadFromRemoteURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            loadFailed = true
            isLoading = false
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if let data, let image = NSImage(data: data) {
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

    private nonisolated func loadFromLocalPath(_ path: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = NSImage(contentsOfFile: path)
            DispatchQueue.main.async {
                guard let self else { return }
                if let image {
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
        guard originalSize.width > 0, originalSize.height > 0 else {
            displaySize = NSSize(width: 300, height: 200)
            return
        }

        if originalSize.width <= maxWidth {
            displaySize = originalSize
        } else {
            let ratio = maxWidth / originalSize.width
            displaySize = NSSize(width: maxWidth, height: originalSize.height * ratio)
        }

        bounds = CGRect(origin: .zero, size: displaySize)
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
        bounds = CGRect(origin: .zero, size: displaySize)
        image = placeholderImage
    }

    private nonisolated func createPlaceholderImage() -> NSImage {
        let size = NSSize(width: 200, height: 150)

        return NSImage(size: size, flipped: false) { [weak self] rect in
            guard let self else { return false }

            let backgroundColor: NSColor
            let borderColor: NSColor
            let iconColor: NSColor
            let textColor: NSColor

            if isDarkMode {
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

            if loadFailed {
                drawErrorIcon(in: iconRect, color: iconColor)
            } else if isLoading {
                drawLoadingIcon(in: iconRect, color: iconColor)
            } else {
                drawImageIcon(in: iconRect, color: iconColor)
            }

            let text = if loadFailed {
                "图片加载失败"
            } else if isLoading {
                "加载中..."
            } else {
                "图片"
            }

            let font = NSFont.systemFont(ofSize: 12)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
            ]

            let textSize = (text as NSString).size(withAttributes: attributes)
            let textPoint = NSPoint(
                x: (rect.width - textSize.width) / 2,
                y: (rect.height - iconSize) / 2 - textSize.height - 5
            )

            (text as NSString).draw(at: textPoint, withAttributes: attributes)
            return true
        }
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
        NSBezierPath(ovalIn: sunRect).fill()
    }

    private func drawLoadingIcon(in rect: CGRect, color: NSColor) {
        color.setStroke()
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let circlePath = NSBezierPath()
        circlePath.appendArc(withCenter: center, radius: 15, startAngle: 0, endAngle: 270, clockwise: false)
        circlePath.lineWidth = 3
        circlePath.lineCapStyle = .round
        circlePath.stroke()
    }

    private func drawErrorIcon(in rect: CGRect, color _: NSColor) {
        let errorColor = NSColor.systemRed.withAlphaComponent(0.6)
        errorColor.setStroke()

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

    nonisolated func invalidateCache() {
        cachedImage = nil
        placeholderImage = nil
    }

    nonisolated func reload() {
        invalidateCache()
        loadFailed = false
        isLoading = true

        if let fileId, let folderId {
            loadImageFromLocalStorage(fileId: fileId, folderId: folderId)
        } else if let src {
            loadImageFromSource(src)
        }
    }
}
