import AppKit
import SwiftUI

/// 笔记详情窗口视图（用于在新窗口打开笔记）
///
/// **已废弃**: 此视图已被新的多窗口架构替代。
/// 现在应该使用 `AppDelegate.createNewWindow(withNote:)` 来创建新窗口。
///
/// 保留此文件仅用于向后兼容，但不应在新代码中使用。
/// 将在 Task 16 中删除。
@available(*, deprecated, message: "使用 AppDelegate.createNewWindow(withNote:) 替代")
public struct NoteDetailWindowView: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView(
            "此视图已废弃",
            systemImage: "exclamationmark.triangle",
            description: Text("请使用新窗口架构")
        )
        .frame(minWidth: 600, minHeight: 400)
    }
}
