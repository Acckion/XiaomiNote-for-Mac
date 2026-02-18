import AppKit
import Foundation

/// 默认图片服务实现
final class DefaultImageService: ImageServiceProtocol {
    // MARK: - Properties

    private let networkClient: NetworkClient
    private let cacheService: CacheServiceProtocol

    // MARK: - Initialization

    init(networkClient: NetworkClient, cacheService: CacheServiceProtocol) {
        self.networkClient = networkClient
        self.cacheService = cacheService
    }

    // MARK: - Upload Methods

    func uploadImage(_ image: NSImage) async throws -> String {
        guard let imageData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: imageData),
              let pngData = bitmapImage.representation(using: .png, properties: [:])
        else {
            throw ImageError.invalidImage
        }

        return try await uploadImageData(pngData, filename: "image.png")
    }

    func uploadImageData(_ data: Data, filename: String) async throws -> String {
        // 创建 multipart/form-data 请求
        let boundary = UUID().uuidString
        var body = Data()

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let headers = ["Content-Type": "multipart/form-data; boundary=\(boundary)"]

        let response: UploadResponse = try await networkClient.request(
            "/images/upload",
            method: .post,
            headers: headers
        )

        return response.imageUrl
    }

    // MARK: - Download Methods

    func downloadImage(from url: String) async throws -> NSImage {
        let data = try await downloadImageData(from: url)

        guard let image = NSImage(data: data) else {
            throw ImageError.invalidImage
        }

        return image
    }

    func downloadImageData(from url: String) async throws -> Data {
        // 检查缓存
        if let cachedData: Data = try? await cacheService.get(key: url) {
            return cachedData
        }

        // 下载图片
        guard let imageUrl = URL(string: url) else {
            throw ImageError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: imageUrl)

        // 缓存图片
        try? await cacheService.set(key: url, value: data, policy: .default)

        return data
    }

    // MARK: - Cache Methods

    func getCachedImage(for _: String) -> NSImage? {
        // 同步方法，暂时返回 nil
        // 实际应用中可以使用同步缓存
        nil
    }

    func cacheImage(_: NSImage, for _: String) {
        // 同步方法，暂时不实现
        // 实际应用中可以使用同步缓存
    }

    func clearImageCache() {
        // 异步清理,不等待结果
        // 实际应用中可以使用后台队列
    }

    // MARK: - Image Processing Methods

    func compressImage(_ image: NSImage, quality: Double) -> Data? {
        guard let imageData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: imageData)
        else {
            return nil
        }

        let compressionFactor = max(0.0, min(1.0, quality))

        return bitmapImage.representation(
            using: .jpeg,
            properties: [.compressionFactor: compressionFactor]
        )
    }

    func resizeImage(_ image: NSImage, to size: CGSize) -> NSImage? {
        let originalSize = image.size
        let widthRatio = size.width / originalSize.width
        let heightRatio = size.height / originalSize.height
        let ratio = min(widthRatio, heightRatio)

        let newSize = CGSize(
            width: originalSize.width * ratio,
            height: originalSize.height * ratio
        )

        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        resizedImage.unlockFocus()

        return resizedImage
    }

    func generateThumbnail(from image: NSImage, size: CGSize) -> NSImage? {
        resizeImage(image, to: size)
    }
}

// MARK: - Supporting Types

private struct UploadResponse: Decodable {
    let imageUrl: String
}

enum ImageError: Error {
    case invalidImage
    case invalidURL
    case compressionFailed
}
