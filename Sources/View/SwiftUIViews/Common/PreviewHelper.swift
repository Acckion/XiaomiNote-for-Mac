#if DEBUG
    import Foundation
    import MiNoteLibrary

    /// Preview 辅助工具
    ///
    /// 为 SwiftUI Preview 提供测试用的 Coordinator 和数据
    @MainActor
    public class PreviewHelper {

        public init() {}

        /// 创建用于 Preview 的 AppCoordinator
        public func createPreviewCoordinator() -> AppCoordinator {
            AppCoordinator()
        }
    }
#endif
