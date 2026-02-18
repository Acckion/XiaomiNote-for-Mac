import Foundation

/// 默认缓存服务实现
final class DefaultCacheService: CacheServiceProtocol, @unchecked Sendable {
    // MARK: - Properties

    private let cache = NSCache<NSString, CacheEntryWrapper>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let queue = DispatchQueue(label: "com.minote.cache", attributes: .concurrent)

    // MARK: - Initialization

    init() {
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = cachesDirectory.appendingPathComponent("com.minote.cache")

        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
    }

    // MARK: - Public Methods

    func get<T: Codable>(key: String) async throws -> T? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }

                // 检查内存缓存
                if let wrapper = cache.object(forKey: key as NSString) {
                    if !wrapper.isExpired {
                        if let value = wrapper.value as? T {
                            continuation.resume(returning: value)
                            return
                        }
                    } else {
                        cache.removeObject(forKey: key as NSString)
                    }
                }

                // 检查磁盘缓存
                let fileURL = cacheDirectory.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)

                guard fileManager.fileExists(atPath: fileURL.path) else {
                    continuation.resume(returning: nil)
                    return
                }

                do {
                    let data = try Data(contentsOf: fileURL)
                    let decoder = JSONDecoder()
                    let wrapper = try decoder.decode(CacheEntryWrapper.self, from: data)

                    if wrapper.isExpired {
                        try? fileManager.removeItem(at: fileURL)
                        continuation.resume(returning: nil)
                        return
                    }

                    guard let value = wrapper.value as? T else {
                        continuation.resume(returning: nil)
                        return
                    }

                    // 更新内存缓存
                    cache.setObject(wrapper, forKey: key as NSString)
                    continuation.resume(returning: value)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func set(key: String, value: some Codable, policy: CachePolicy) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async(flags: .barrier) { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                let expirationDate = switch policy {
                case .default:
                    Date().addingTimeInterval(3600) // 1 hour
                case .never:
                    Date.distantFuture
                case let .expiration(interval):
                    Date().addingTimeInterval(interval)
                default:
                    Date().addingTimeInterval(3600) // 默认 1 小时
                }

                let wrapper = CacheEntryWrapper(value: value, expirationDate: expirationDate)

                // 更新内存缓存
                cache.setObject(wrapper, forKey: key as NSString)

                // 更新磁盘缓存
                let fileURL = cacheDirectory.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)

                do {
                    let encoder = JSONEncoder()
                    let data = try encoder.encode(wrapper)
                    try data.write(to: fileURL)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func remove(key: String) async throws {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                cache.removeObject(forKey: key as NSString)

                let fileURL = cacheDirectory.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)
                try? fileManager.removeItem(at: fileURL)

                continuation.resume()
            }
        }
    }

    func exists(key: String) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: false)
                    return
                }

                if cache.object(forKey: key as NSString) != nil {
                    continuation.resume(returning: true)
                    return
                }

                let fileURL = cacheDirectory.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)
                continuation.resume(returning: fileManager.fileExists(atPath: fileURL.path))
            }
        }
    }

    func getMultiple<T: Codable>(keys: [String]) async throws -> [String: T] {
        var result: [String: T] = [:]
        for key in keys {
            if let value: T = try await get(key: key) {
                result[key] = value
            }
        }
        return result
    }

    func setMultiple(values: [String: some Codable], policy: CachePolicy) async throws {
        for (key, value) in values {
            try await set(key: key, value: value, policy: policy)
        }
    }

    func removeMultiple(keys: [String]) async throws {
        for key in keys {
            try await remove(key: key)
        }
    }

    func clear() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async(flags: .barrier) { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                cache.removeAllObjects()

                do {
                    let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
                    for fileURL in contents {
                        try? fileManager.removeItem(at: fileURL)
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func clearExpired() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async(flags: .barrier) { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                do {
                    let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)

                    for fileURL in contents {
                        guard let data = try? Data(contentsOf: fileURL),
                              let wrapper = try? JSONDecoder().decode(CacheEntryWrapper.self, from: data)
                        else {
                            continue
                        }

                        if wrapper.isExpired {
                            try? fileManager.removeItem(at: fileURL)
                        }
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func getCacheSize() async -> Int64 {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: 0)
                    return
                }

                var totalSize: Int64 = 0

                guard let contents = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
                    continuation.resume(returning: 0)
                    return
                }

                for fileURL in contents {
                    if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                       let fileSize = attributes[.size] as? Int64
                    {
                        totalSize += fileSize
                    }
                }

                continuation.resume(returning: totalSize)
            }
        }
    }

    func getCacheCount() async -> Int {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: 0)
                    return
                }

                guard let contents = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
                    continuation.resume(returning: 0)
                    return
                }
                continuation.resume(returning: contents.count)
            }
        }
    }

    func setMaxCacheSize(_ size: Int64) async {
        cache.totalCostLimit = Int(size)
    }

    func setMaxCacheCount(_ count: Int) async {
        cache.countLimit = count
    }

    func setDefaultExpiration(_: TimeInterval) async {
        // 存储默认过期时间（可以添加一个属性来保存）
    }
}

// MARK: - Supporting Types

private class CacheEntryWrapper: NSObject, Codable {
    let value: AnyCodableValue
    let expirationDate: Date

    var isExpired: Bool {
        Date() > expirationDate
    }

    init(value: some Codable, expirationDate: Date) {
        self.value = AnyCodableValue(value)
        self.expirationDate = expirationDate
    }

    enum CodingKeys: String, CodingKey {
        case value
        case expirationDate
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode(AnyCodableValue.self, forKey: .value)
        expirationDate = try container.decode(Date.self, forKey: .expirationDate)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(expirationDate, forKey: .expirationDate)
    }
}

private struct AnyCodableValue: Codable {
    let value: Any

    init(_ value: some Codable) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let dataValue = try? container.decode(Data.self) {
            value = dataValue
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let dataValue as Data:
            try container.encode(dataValue)
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "Unsupported type"))
        }
    }
}

enum CacheError: Error {
    case notFound
    case expired
    case typeMismatch
}
