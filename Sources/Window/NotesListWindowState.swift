import Foundation

/// 笔记列表窗口状态，包含选中的笔记、滚动位置等
public final class NotesListWindowState: NSObject, NSSecureCoding {
    
    // MARK: - Properties
    
    public let selectedNoteId: String?
    public let scrollPosition: Double
    
    // MARK: - Initialization
    
    public init(selectedNoteId: String?, scrollPosition: Double) {
        self.selectedNoteId = selectedNoteId
        self.scrollPosition = scrollPosition
        super.init()
    }
    
    // MARK: - NSSecureCoding
    
    public static let supportsSecureCoding = true
    
    private enum CodingKeys: String {
        case selectedNoteId
        case scrollPosition
    }
    
    public required init?(coder: NSCoder) {
        self.selectedNoteId = coder.decodeObject(of: NSString.self, forKey: CodingKeys.selectedNoteId.rawValue) as String?
        self.scrollPosition = coder.decodeDouble(forKey: CodingKeys.scrollPosition.rawValue)
    }
    
    public func encode(with coder: NSCoder) {
        coder.encode(selectedNoteId, forKey: CodingKeys.selectedNoteId.rawValue)
        coder.encode(scrollPosition, forKey: CodingKeys.scrollPosition.rawValue)
    }
    
    // MARK: - Convenience Methods
    
    /// 创建空的笔记列表窗口状态
    public static func emptyState() -> NotesListWindowState {
        return NotesListWindowState(
            selectedNoteId: nil,
            scrollPosition: 0.0
        )
    }
}
