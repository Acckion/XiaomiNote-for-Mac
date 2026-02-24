import AppKit
import Foundation

/// 图片存储管理器 - 负责图片的本地存储和加载
@MainActor
class ImageStorageManager {

    // MARK: - Properties

    private let localStorage: LocalStorageService
    private let fileAPI: FileAPI
    private var imageCache: [String: NSImage] = [:]
    private let maxCacheSize = 50

    // MARK: - Initialization

    init(localStorage: LocalStorageService, fileAPI: FileAPI) {
        self.localStorage = localStorage
        self.fileAPI = fileAPI
    }

    // MARK: - Public Methods

    /// 保存图片到本地存储（统一使用 images/{imageId}.jpg 格式）
    func saveImage(_ image: NSImage) -> (fileId: String, url: URL)? {
        let fileId = generateFileId()

        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            return nil
        }

        do {
            try localStorage.saveImage(imageData: imageData, fileId: fileId, fileType: "jpg")
            let url = localStorage.getImageURL(fileId: fileId, fileType: "jpg")!
            addToCache(image, forKey: fileId)
            return (fileId, url)
        } catch {
            LogService.shared.error(.editor, "保存图片失败: \(error)")
            return nil
        }
    }

    func saveImage(_ image: NSImage, folderId _: String) -> (fileId: String, url: URL)? {
        saveImage(image)
    }

    func saveImageData(_ imageData: Data) -> (fileId: String, url: URL)? {
        let fileId = generateFileId()

        do {
            try localStorage.saveImage(imageData: imageData, fileId: fileId, fileType: "jpg")
            let url = localStorage.getImageURL(fileId: fileId, fileType: "jpg")!
            if let image = NSImage(data: imageData) {
                addToCache(image, forKey: fileId)
            }
            return (fileId, url)
        } catch {
            LogService.shared.error(.editor, "保存图片数据失败: \(error)")
            return nil
        }
    }

    func saveImageData(_ imageData: Data, folderId _: String) -> (fileId: String, url: URL)? {
        saveImageData(imageData)
    }

    /// 从本地存储加载图片（仅使用 images/{userId}.{fileId}.{format} 格式）
    func loadImage(fileId: String) -> NSImage? {
        if let cached = imageCache[fileId] {
            return cached
        }

        if let (imageData, _) = localStorage.loadImageWithFullFormatAllFormats(fullFileId: fileId),
           let image = NSImage(data: imageData)
        {
            addToCache(image, forKey: fileId)
            return image
        }

        return nil
    }

    func loadImage(fileId: String, folderId _: String) -> NSImage? {
        loadImage(fileId: fileId)
    }

    func loadImageAsync(fileId: String, completion: @escaping @Sendable (NSImage?) -> Void) {
        if let cached = imageCache[fileId] {
            completion(cached)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let localStorage = self?.localStorage else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            var image: NSImage?
            if let (imageData, _) = localStorage.loadImageWithFullFormatAllFormats(fullFileId: fileId),
               let loadedImage = NSImage(data: imageData)
            {
                image = loadedImage
            }

            DispatchQueue.main.async {
                if let image {
                    self?.addToCache(image, forKey: fileId)
                }
                completion(image)
            }
        }
    }

    func loadImageAsync(fileId: String, folderId _: String, completion: @escaping @Sendable (NSImage?) -> Void) {
        loadImageAsync(fileId: fileId, completion: completion)
    }

    func imageExists(fileId: String) -> Bool {
        let imageFormats = ["jpg", "jpeg", "png", "gif"]
        for format in imageFormats {
            if localStorage.imageExists(fileId: fileId, fileType: format) {
                return true
            }
        }
        return false
    }

    func imageExists(fileId: String, folderId _: String) -> Bool {
        imageExists(fileId: fileId)
    }

    func generateMinoteURL(fileId: String) -> String {
        "minote://image/\(fileId)"
    }

    func generateMinoteURL(fileId: String, folderId _: String) -> String {
        generateMinoteURL(fileId: fileId)
    }

    func parseMinoteURL(_ urlString: String) -> String? {
        guard urlString.hasPrefix("minote://") else {
            return nil
        }

        guard let url = URL(string: urlString) else {
            return nil
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }

        if pathComponents.count >= 2, pathComponents[0] == "image" {
            return pathComponents[1]
        }

        if pathComponents.count >= 3, pathComponents[0] == "images" {
            let fileName = pathComponents[2]
            return (fileName as NSString).deletingPathExtension
        }

        if let host = url.host {
            return host
        }

        return nil
    }

    // MARK: - Cache Management

    func clearCache() {
        imageCache.removeAll()
    }

    func removeFromCache(fileId: String, folderId: String) {
        let cacheKey = "\(folderId)/\(fileId)"
        imageCache.removeValue(forKey: cacheKey)
    }

    func getCacheStats() -> (count: Int, maxSize: Int) {
        (imageCache.count, maxCacheSize)
    }

    // MARK: - 按需下载

    func loadImageWithFallback(fileId: String) async -> NSImage {
        if let image = loadImage(fileId: fileId) {
            return image
        }

        if let image = await downloadImageOnDemand(fileId: fileId) {
            return image
        }

        return createPlaceholderImage()
    }

    private func downloadImageOnDemand(fileId: String) async -> NSImage? {
        do {
            let components = fileId.split(separator: ".")
            guard components.count >= 2 else {
                return nil
            }

            let actualFileId = components.dropFirst().joined(separator: ".")
            let imageData = try await fileAPI.downloadFile(fileId: actualFileId, type: "note_img")

            try localStorage.saveImage(imageData: imageData, fileId: fileId, fileType: "jpg")

            if let image = NSImage(data: imageData) {
                addToCache(image, forKey: fileId)
                return image
            }

            return nil
        } catch {
            LogService.shared.error(.editor, "按需下载图片失败: \(fileId), 错误: \(error)")
            return nil
        }
    }

    private func createPlaceholderImage() -> NSImage {
        let size = NSSize(width: 200, height: 150)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor.lightGray.setFill()
        NSRect(origin: .zero, size: size).fill()

        let text = "无法加载图片"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.darkGray,
        ]
        let textSize = text.size(withAttributes: attributes)
        let textRect = NSRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
        image.unlockFocus()

        return image
    }

    // MARK: - Private Methods

    private func generateFileId() -> String {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let random = Int.random(in: 1000 ... 9999)
        return "img_\(timestamp)_\(random)"
    }

    private func addToCache(_ image: NSImage, forKey key: String) {
        if imageCache.count >= maxCacheSize {
            if let firstKey = imageCache.keys.first {
                imageCache.removeValue(forKey: firstKey)
            }
        }
        imageCache[key] = image
    }
}

// MARK: - NSImage Extension

extension NSImage {
    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }

    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return bitmapRep.representation(using: .png, properties: [:])
    }

    func resized(to newSize: NSSize) -> NSImage {
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()
        return newImage
    }

    func resizedToMaxWidth(_ maxWidth: CGFloat) -> NSImage {
        guard size.width > maxWidth else {
            return self
        }
        let ratio = maxWidth / size.width
        let newSize = NSSize(width: maxWidth, height: size.height * ratio)
        return resized(to: newSize)
    }
}
