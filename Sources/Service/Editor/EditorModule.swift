import Foundation

/// 编辑器层模块工厂
///
/// 集中构建编辑器层的完整依赖图。
/// 在 AppDelegate 中创建，通过 AppCoordinator 传递。
@MainActor
public struct EditorModule: Sendable {
    // 第 1 层：无依赖类
    public let performanceCache: PerformanceCache
    public let fontSizeManager: FontSizeManager
    public let editorConfigurationManager: EditorConfigurationManager
    public let xmlNormalizer: XMLNormalizer
    let performanceMonitor: PerformanceMonitor
    public let typingOptimizer: TypingOptimizer
    public let pasteboardManager: PasteboardManager

    // 第 2 层：依赖第 1 层
    let formatConverter: XiaoMiFormatConverter
    let customRenderer: CustomRenderer
    public let specialElementFormatHandler: SpecialElementFormatHandler
    public let unifiedFormatManager: UnifiedFormatManager

    // 第 3 层：依赖第 2 层
    let safeRenderer: SafeRenderer
    let editorInitializer: NativeEditorInitializer
    let editorRecoveryManager: EditorRecoveryManager
    let imageStorageManager: ImageStorageManager

    // 第 4 层：附件管理
    let attachmentSelectionManager: AttachmentSelectionManager
    public let attachmentKeyboardHandler: AttachmentKeyboardHandler

    // 第 5 层：Bridge 层
    public let formatStateManager: FormatStateManager
    public let cursorFormatManager: CursorFormatManager

    public init(syncModule: SyncModule, networkModule: NetworkModule) {
        // 第 1 层
        let cache = PerformanceCache()
        self.performanceCache = cache

        let fontManager = FontSizeManager()
        self.fontSizeManager = fontManager

        let configManager = EditorConfigurationManager()
        self.editorConfigurationManager = configManager

        let normalizer = XMLNormalizer()
        self.xmlNormalizer = normalizer

        let perfMonitor = PerformanceMonitor()
        self.performanceMonitor = perfMonitor

        let optimizer = TypingOptimizer()
        self.typingOptimizer = optimizer

        let pasteboard = PasteboardManager()
        self.pasteboardManager = pasteboard

        // 第 2 层
        let converter = XiaoMiFormatConverter(xmlNormalizer: normalizer)
        self.formatConverter = converter

        let renderer = CustomRenderer()
        renderer.localStorage = syncModule.localStorage
        self.customRenderer = renderer

        let specialHandler = SpecialElementFormatHandler()
        self.specialElementFormatHandler = specialHandler

        let formatManager = UnifiedFormatManager()
        self.unifiedFormatManager = formatManager

        // 第 3 层
        let safe = SafeRenderer(customRenderer: renderer)
        self.safeRenderer = safe

        let initializer = NativeEditorInitializer(
            customRenderer: renderer,
            formatConverter: converter
        )
        self.editorInitializer = initializer

        let recovery = EditorRecoveryManager()
        self.editorRecoveryManager = recovery

        let imageStorage = ImageStorageManager(
            localStorage: syncModule.localStorage,
            fileAPI: networkModule.fileAPI
        )
        self.imageStorageManager = imageStorage

        // 第 4 层
        let selectionManager = AttachmentSelectionManager()
        self.attachmentSelectionManager = selectionManager

        let keyboardHandler = AttachmentKeyboardHandler(
            selectionManager: selectionManager
        )
        self.attachmentKeyboardHandler = keyboardHandler

        // 第 5 层
        let stateManager = FormatStateManager()
        self.formatStateManager = stateManager

        let cursorManager = CursorFormatManager(
            unifiedFormatManager: formatManager,
            fontSizeManager: fontManager
        )
        self.cursorFormatManager = cursorManager
    }

    /// Preview 和测试用的便利构造器
    public init() {
        let nm = NetworkModule()
        let sm = SyncModule(networkModule: nm)
        self.init(syncModule: sm, networkModule: nm)
    }
}
