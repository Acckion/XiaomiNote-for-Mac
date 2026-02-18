import Foundation

/// 主窗口状态，包含全屏状态、分割视图宽度、侧边栏隐藏状态及各子视图状态
public final class MainWindowState: NSObject, NSSecureCoding {

    // MARK: - Properties

    public let isFullScreen: Bool
    public let splitViewWidths: [Int]
    public let isSidebarHidden: Bool
    public let sidebarWindowState: SidebarWindowState?
    public let notesListWindowState: NotesListWindowState?
    public let noteDetailWindowState: NoteDetailWindowState?

    // MARK: - Initialization

    public init(
        isFullScreen: Bool,
        splitViewWidths: [Int],
        isSidebarHidden: Bool,
        sidebarWindowState: SidebarWindowState?,
        notesListWindowState: NotesListWindowState?,
        noteDetailWindowState: NoteDetailWindowState?
    ) {
        self.isFullScreen = isFullScreen
        self.splitViewWidths = splitViewWidths
        self.isSidebarHidden = isSidebarHidden
        self.sidebarWindowState = sidebarWindowState
        self.notesListWindowState = notesListWindowState
        self.noteDetailWindowState = noteDetailWindowState
        super.init()
    }

    // MARK: - NSSecureCoding

    public static let supportsSecureCoding = true

    private enum CodingKeys: String {
        case isFullScreen
        case splitViewWidths
        case isSidebarHidden
        case sidebarWindowState
        case notesListWindowState
        case noteDetailWindowState
    }

    public required init?(coder: NSCoder) {
        self.isFullScreen = coder.decodeBool(forKey: CodingKeys.isFullScreen.rawValue)

        if let widths = coder.decodeObject(of: [NSArray.self, NSNumber.self], forKey: CodingKeys.splitViewWidths.rawValue) as? [Int] {
            self.splitViewWidths = widths
        } else {
            self.splitViewWidths = []
        }

        self.isSidebarHidden = coder.decodeBool(forKey: CodingKeys.isSidebarHidden.rawValue)
        self.sidebarWindowState = coder.decodeObject(of: SidebarWindowState.self, forKey: CodingKeys.sidebarWindowState.rawValue)
        self.notesListWindowState = coder.decodeObject(of: NotesListWindowState.self, forKey: CodingKeys.notesListWindowState.rawValue)
        self.noteDetailWindowState = coder.decodeObject(of: NoteDetailWindowState.self, forKey: CodingKeys.noteDetailWindowState.rawValue)
    }

    public func encode(with coder: NSCoder) {
        coder.encode(isFullScreen, forKey: CodingKeys.isFullScreen.rawValue)
        coder.encode(splitViewWidths, forKey: CodingKeys.splitViewWidths.rawValue)
        coder.encode(isSidebarHidden, forKey: CodingKeys.isSidebarHidden.rawValue)
        coder.encode(sidebarWindowState, forKey: CodingKeys.sidebarWindowState.rawValue)
        coder.encode(notesListWindowState, forKey: CodingKeys.notesListWindowState.rawValue)
        coder.encode(noteDetailWindowState, forKey: CodingKeys.noteDetailWindowState.rawValue)
    }

    // MARK: - Convenience Methods

    /// 创建默认的主窗口状态
    public static func defaultState() -> MainWindowState {
        MainWindowState(
            isFullScreen: false,
            splitViewWidths: [200, 300, 600], // 默认宽度：侧边栏200，笔记列表300，笔记详情600
            isSidebarHidden: false,
            sidebarWindowState: nil,
            notesListWindowState: nil,
            noteDetailWindowState: nil
        )
    }

    /// 创建空的主窗口状态
    public static func emptyState() -> MainWindowState {
        MainWindowState(
            isFullScreen: false,
            splitViewWidths: [],
            isSidebarHidden: false,
            sidebarWindowState: nil,
            notesListWindowState: nil,
            noteDetailWindowState: nil
        )
    }
}
