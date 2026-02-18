import Foundation

/// 笔记详情窗口状态，包含编辑器状态、滚动位置等
public final class NoteDetailWindowState: NSObject, NSSecureCoding {

    // MARK: - Properties

    public let editorContent: String?
    public let scrollPosition: Double
    public let cursorPosition: Int

    // MARK: - Initialization

    public init(editorContent: String?, scrollPosition: Double, cursorPosition: Int) {
        self.editorContent = editorContent
        self.scrollPosition = scrollPosition
        self.cursorPosition = cursorPosition
        super.init()
    }

    // MARK: - NSSecureCoding

    public static let supportsSecureCoding = true

    private enum CodingKeys: String {
        case editorContent
        case scrollPosition
        case cursorPosition
    }

    public required init?(coder: NSCoder) {
        self.editorContent = coder.decodeObject(of: NSString.self, forKey: CodingKeys.editorContent.rawValue) as String?
        self.scrollPosition = coder.decodeDouble(forKey: CodingKeys.scrollPosition.rawValue)
        self.cursorPosition = coder.decodeInteger(forKey: CodingKeys.cursorPosition.rawValue)
    }

    public func encode(with coder: NSCoder) {
        coder.encode(editorContent, forKey: CodingKeys.editorContent.rawValue)
        coder.encode(scrollPosition, forKey: CodingKeys.scrollPosition.rawValue)
        coder.encode(cursorPosition, forKey: CodingKeys.cursorPosition.rawValue)
    }

    // MARK: - Convenience Methods

    /// 创建空的笔记详情窗口状态
    public static func emptyState() -> NoteDetailWindowState {
        NoteDetailWindowState(
            editorContent: nil,
            scrollPosition: 0.0,
            cursorPosition: 0
        )
    }
}
