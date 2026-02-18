import Foundation

/// 侧边栏窗口状态，包含选中的文件夹、展开状态等
public final class SidebarWindowState: NSObject, NSSecureCoding {

    // MARK: - Properties

    public let selectedFolderId: String?
    public let expandedFolderIds: [String]

    // MARK: - Initialization

    public init(selectedFolderId: String?, expandedFolderIds: [String]) {
        self.selectedFolderId = selectedFolderId
        self.expandedFolderIds = expandedFolderIds
        super.init()
    }

    // MARK: - NSSecureCoding

    public static let supportsSecureCoding = true

    private enum CodingKeys: String {
        case selectedFolderId
        case expandedFolderIds
    }

    public required init?(coder: NSCoder) {
        selectedFolderId = coder.decodeObject(of: NSString.self, forKey: CodingKeys.selectedFolderId.rawValue) as String?

        if let expandedIds = coder.decodeObject(of: [NSArray.self, NSString.self], forKey: CodingKeys.expandedFolderIds.rawValue) as? [String] {
            expandedFolderIds = expandedIds
        } else {
            expandedFolderIds = []
        }
    }

    public func encode(with coder: NSCoder) {
        coder.encode(selectedFolderId, forKey: CodingKeys.selectedFolderId.rawValue)
        coder.encode(expandedFolderIds, forKey: CodingKeys.expandedFolderIds.rawValue)
    }

    // MARK: - Convenience Methods

    /// 创建空的侧边栏窗口状态
    public static func emptyState() -> SidebarWindowState {
        SidebarWindowState(
            selectedFolderId: nil,
            expandedFolderIds: []
        )
    }
}
