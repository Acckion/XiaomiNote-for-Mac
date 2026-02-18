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
        ///
        /// 注意: 这是一个简化的 Coordinator,仅用于 Preview
        public func createPreviewCoordinator() -> AppCoordinator {
            AppCoordinator()
            // 可以添加一些测试数据
        }

        /// 创建用于 Preview 的 NotesViewModelAdapter
        ///
        /// 这是推荐的方式,因为它使用新架构
        public func createPreviewViewModel() -> NotesViewModelAdapter {
            let coordinator = createPreviewCoordinator()
            return NotesViewModelAdapter(coordinator: coordinator)
        }

        /// 创建用于 Preview 的 NotesViewModel (向后兼容)
        ///
        /// 注意: 这个方法保留用于向后兼容,新代码应该使用 createPreviewViewModel()
        @available(*, deprecated, message: "使用 createPreviewViewModel() 代替")
        public func createLegacyPreviewViewModel() -> NotesViewModel {
            NotesViewModel()
        }
    }
#endif
