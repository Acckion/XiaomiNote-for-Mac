import Foundation
import AppKit

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

    // MARK: - Public Methods
    func uploadImage(_ image: NSImage, noteId: String) async throws -> String {
        guard let imageData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: imageData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            throw ImageError.invalidImage
        }

        // 创建 multipart/form-data 请求
        let boundary = UUID().uuidString
        var body = Data()

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"noteId\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(noteId)\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(pngData)
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

    func downloadImage(url: String) async throws -> NSImage {
        // 检查缓存
        if let cachedData: Data = try? await cacheService.get(key: url) {
            if let image = NSImage(data: cachedData) {
                return image
            }
        }

        // 下载图片
        guard let imageUrl = URL(string: url) else {
            throw ImageError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: imageUrl)

        guard let image = NSImage(data: data) else {
            throw ImageError.invalidImage
        }

        // 缓存图片
        try? await cacheService.set(key: url, value: data, policy: .default)

        return image
    }

    func deleteImage(url: String, noteId: String) async throws {
        let parameters: [String: Any] = [
            "url": url,
            "noteId": noteId
        ]

        try await networkClient.request(
            "/images/delete",
            method: .post,
            parameters: parameters
        ) as EmptyResponse

        // 清除缓存
        try? await cacheService.remove(key: url)
    }

    func compressImage(_ image: NSImage, quality: Double) async throws -> NSImage {
        guard let imageData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: imageData) else {
            throw ImageError.invalidImage
        }

        let compressionFactor = max(0.0, min(1.0, quality))

        guard let compressedData = bitmapImage.representation(
            using: .jpeg,
            properties: [.compressionFactor: compressionFactor]
        ) else {
            throw ImageError.compressionFailed
        }

        guard let compressedImage = NSImage(data: compressedData) else {
            throw ImageError.invalidImage
        }

        return compressedImage
    }

    func resizeImage(_ image: NSImage, maxSize: CGSize) async throws -> NSImage {
        let originalSize = image.size
        let widthRatio = maxSize.width / originalSize.width
        let heightRatio = maxSize.height / originalSize.height
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
}

// MARK: - Supporting Types
private struct UploadResponse: Decodable {
    let imageUrl: String
}

private struct EmptyResponse: Decodable {}

enum ImageError: Error {
    case invalidImage
    case invalidURL
    case compressionFailed
}
