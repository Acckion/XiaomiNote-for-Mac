import Foundation

/// 默认缓存服务实现
actor DefaultCacheService: CacheServiceProtocol {
    // MARK: - Properties

    private let cache = NSCache<NSString, CacheEntryWrapper>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    // MARK: - Initialization

    init() {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = cachesDirectory.appendingPathComponent("com.minote.cache")

        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
    }

    // MARK: - Public Methods

    func get<T: Codable & Sendable>(key: String) async throws -> T? {
        // 检查内存缓存
        if let wrapper = cache.object(forKey: key as NSString) {
            if !wrapper.isExpired {
                if let value = wrapper.value as? T {
                    return value
                }
            } else {
                cache.removeObject(forKey: key as NSString)
            }
        }

        // 检查磁盘缓存
        let fileURL = cacheDirectory.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        let wrapper = try decoder.decode(CacheEntryWrapper.self, from: data)

        if wrapper.isExpired {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }

        guard let value = wrapper.value as? T else {
            return nil
        }

        // 更新内存缓存
        cache.setObject(wrapper, forKey: key as NSString)
        return value
    }

    func set(key: String, value: some Codable & Sendable, policy: CachePolicy) async throws {
        let expirationDate = switch policy {
        case .default:
            Date().addingTimeInterval(3600)
        case .never:
            Date.distantFuture
        case let .expiration(interval):
            Date().addingTimeInterval(interval)
        default:
            Date().addingTimeInterval(3600)
        }

        let wrapper = CacheEntryWrapper(value: value, expirationDate: expirationDate)

        // 更新内存缓存
        cache.setObject(wrapper, forKey: key as NSString)

        // 更新磁盘缓存
        let fileURL = cacheDirectory.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)

        let encoder = JSONEncoder()
        let data = try encoder.encode(wrapper)
        try data.write(to: fileURL)
    }

    func remove(key: String) async throws {
        cache.removeObject(forKey: key as NSString)

        let fileURL = cacheDirectory.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)
        try? fileManager.removeItem(at: fileURL)
    }

    func exists(key: String) async -> Bool {
        if cache.object(forKey: key as NSString) != nil {
            return true
        }

        let fileURL = cacheDirectory.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)
        return fileManager.fileExists(atPath: fileURL.path)
    }

    func getMultiple<T: Codable & Sendable>(keys: [String]) async throws -> [String: T] {
        var result: [String: T] = [:]
        for key in keys {
            if let value: T = try await get(key: key) {
                result[key] = value
            }
        }
        return result
    }

    func setMultiple(values: [String: some Codable & Sendable], policy: CachePolicy) async throws {
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
        cache.removeAllObjects()

        let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        for fileURL in contents {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    func clearExpired() async throws {
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
    }

    func getCacheSize() async -> Int64 {
        var totalSize: Int64 = 0

        guard let contents = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        for fileURL in contents {
            if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
               let fileSize = attributes[.size] as? Int64
            {
                totalSize += fileSize
            }
        }

        return totalSize
    }

    func getCacheCount() async -> Int {
        guard let contents = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            return 0
        }
        return contents.count
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
        self.value = try container.decode(AnyCodableValue.self, forKey: .value)
        self.expirationDate = try container.decode(Date.self, forKey: .expirationDate)
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
            self.value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            self.value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            self.value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            self.value = boolValue
        } else if let dataValue = try? container.decode(Data.self) {
            self.value = dataValue
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
