import Foundation

// MARK: - 操作数据协议

/// 操作数据协议
///
/// 为每种操作类型提供类型安全的数据编解码，
/// 替代手动 JSONSerialization 构建 Data 的方式。
public protocol OperationData: Codable, Sendable {
    func encoded() -> Data
    static func decoded(from data: Data) throws -> Self
}

public extension OperationData {
    func encoded() -> Data {
        // swiftlint:disable:next force_try
        try! JSONEncoder().encode(self)
    }

    static func decoded(from data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }
}

// MARK: - NoteCreateData

/// 笔记创建操作数据
///
/// noteCreate 不需要额外数据，笔记内容从本地数据库读取
public struct NoteCreateData: OperationData {}

// MARK: - CloudUploadData

/// 云端上传操作数据
public struct CloudUploadData: OperationData {
    public let title: String
    public let content: String
    public let folderId: String

    public init(title: String, content: String, folderId: String) {
        self.title = title
        self.content = content
        self.folderId = folderId
    }
}

// MARK: - CloudDeleteData

/// 云端删除操作数据
public struct CloudDeleteData: OperationData {
    public let tag: String

    public init(tag: String) {
        self.tag = tag
    }
}

// MARK: - FolderCreateData

/// 文件夹创建操作数据
public struct FolderCreateData: OperationData {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

// MARK: - FolderRenameData

/// 文件夹重命名操作数据
public struct FolderRenameData: OperationData {
    public let name: String
    public let tag: String

    public init(name: String, tag: String) {
        self.name = name
        self.tag = tag
    }
}

// MARK: - FolderDeleteData

/// 文件夹删除操作数据
public struct FolderDeleteData: OperationData {
    public let tag: String

    public init(tag: String) {
        self.tag = tag
    }
}
