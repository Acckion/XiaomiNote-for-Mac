#if DEBUG
    import Foundation
    import MiNoteLibrary

    /// Preview 辅助工具
    ///
    /// 为 SwiftUI Preview 提供测试用的 ViewModel 和数据
    @MainActor
    public class PreviewHelper {
        /// 单例
        public static let shared = PreviewHelper()

        private init() {}

        /// 创建用于 Preview 的 AppCoordinator
        public func createPreviewCoordinator() -> AppCoordinator {
            AppCoordinator()
        }

        /// 创建用于 Preview 的 NotesViewModel（向后兼容，供尚未迁移的视图使用）
        public func createPreviewViewModel() -> NotesViewModel {
            let coordinator = createPreviewCoordinator()
            return coordinator.notesViewModel
        }
    }
#endif
