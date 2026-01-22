import Foundation

/// 默认缓存服务实现
final class DefaultCacheService: CacheServiceProtocol {
    // MARK: - Properties
    private let cache = NSCache<NSString, CacheEntry>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let lock = NSLock()

    // MARK: - Initialization
    init() {
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = cachesDirectory.appendingPathComponent("com.minote.cache")

        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
    }

    // MARK: - Public Methods
    func get<T: Codable>(key: String) async throws -> T {
        lock.lock()
        defer { lock.unlock() }

        // 检查内存缓存
        if let entry = cache.object(forKey: key as NSString) {
            if !entry.isExpired {
                if let value = entry.value as? T {
                    return value
                }
            } else {
                cache.removeObject(forKey: key as NSString)
            }
        }

        // 检查磁盘缓存
        let fileURL = cacheDirectory.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw CacheError.notFound
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        let entry = try decoder.decode(CacheEntry.self, from: data)

        if entry.isExpired {
            try? fileManager.removeItem(at: fileURL)
            throw CacheError.expired
        }

        guard let value = entry.value as? T else {
            throw CacheError.typeMismatch
        }

        // 更新内存缓存
        cache.setObject(entry, forKey: key as NSString)

        return value
    }

    func set<T: Codable>(key: String, value: T, policy: CachePolicy) async throws {
        lock.lock()
        defer { lock.unlock() }

        let expirationDate: Date
        switch policy {
        case .default:
            expirationDate = Date().addingTimeInterval(3600) // 1 hour
        case .short:
            expirationDate = Date().addingTimeInterval(300) // 5 minutes
        case .long:
            expirationDate = Date().addingTimeInterval(86400) // 24 hours
        case .permanent:
            expirationDate = Date.distantFuture
        }

        let entry = CacheEntry(value: value, expirationDate: expirationDate)

        // 更新内存缓存
        cache.setObject(entry, forKey: key as NSString)

        // 更新磁盘缓存
        let fileURL = cacheDirectory.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)

        let encoder = JSONEncoder()
        let data = try encoder.encode(entry)
        try data.write(to: fileURL)
    }

    func remove(key: String) async throws {
        lock.lock()
        defer { lock.unlock() }

        cache.removeObject(forKey: key as NSString)

        let fileURL = cacheDirectory.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)
        try? fileManager.removeItem(at: fileURL)
    }

    func clear() async throws {
        lock.lock()
        defer { lock.unlock() }

        cache.removeAllObjects()

        let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        for fileURL in contents {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    func clearExpired() async throws {
        lock.lock()
        defer { lock.unlock() }

        let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)

        for fileURL in contents {
            guard let data = try? Data(contentsOf: fileURL),
                  let entry = try? JSONDecoder().decode(CacheEntry.self, from: data) else {
                continue
            }

            if entry.isExpired {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }
}

// MARK: - Supporting Types
private class CacheEntry: NSObject, Codable {
    let value: Any
    let expirationDate: Date

    var isExpired: Bool {
        Date() > expirationDate
    }

    init(value: Any, expirationDate: Date) {
        self.value = value
        self.expirationDate = expirationDate
    }

    enum CodingKeys: String, CodingKey {
        case value
        case expirationDate
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.value = try container.decode(AnyCodable.self, forKey: .value).value
        self.expirationDate = try container.decode(Date.self, forKey: .expirationDate)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(AnyCodable(value), forKey: .value)
        try container.encode(expirationDate, forKey: .expirationDate)
    }
}

private struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
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
