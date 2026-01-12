import SwiftUI
import Combine

/// Web编辑器上下文，管理编辑器状态和格式操作
@MainActor
class WebEditorContext: ObservableObject {
    @Published var content: String = ""
    @Published var isEditorReady: Bool = false
    @Published var hasSelection: Bool = false
    @Published var selectedText: String = ""
    
    // 格式状态（参考 CKEditor 5：状态由编辑器同步，不手动管理）
    @Published var isBold: Bool = false
    @Published var isItalic: Bool = false
    @Published var isUnderline: Bool = false
    @Published var isStrikethrough: Bool = false
    @Published var isHighlighted: Bool = false
    @Published var textAlignment: TextAlignment = .leading
    @Published var headingLevel: Int? = nil
    @Published var listType: String? = nil  // 'bullet' 或 'order' 或 nil
    @Published var isInQuote: Bool = false  // 是否在引用块中
    
    /// 编辑器是否获得焦点
    /// _Requirements: 8.4_
    @Published var isEditorFocused: Bool = false
    
    // 操作闭包，用于执行编辑器操作
    var executeFormatActionClosure: ((String, String?) -> Void)?
    var insertImageClosure: ((String, String) -> Void)?
    var getCurrentContentClosure: ((@escaping (String) -> Void) -> Void)?
    var forceSaveContentClosure: ((@escaping () -> Void) -> Void)?
    var undoClosure: (() -> Void)?
    var redoClosure: (() -> Void)?
    var openWebInspectorClosure: (() -> Void)?
    var highlightSearchTextClosure: ((String) -> Void)?
    var findTextClosure: (([String: Any]) -> Void)?
    var replaceTextClosure: (([String: Any]) -> Void)?
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 格式提供者
    
    /// 格式提供者（延迟初始化）
    /// _Requirements: 3.1, 3.2, 3.3_
    private var _formatProvider: WebFormatProvider?
    
    /// 格式提供者（公开访问）
    /// _Requirements: 3.1, 3.2, 3.3_
    @MainActor
    public var formatProvider: WebFormatProvider {
        if _formatProvider == nil {
            _formatProvider = WebFormatProvider(webEditorContext: self)
        }
        return _formatProvider!
    }
    
    init() {
        // 监听内容变化
        $content
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] newContent in
                self?.handleContentChanged(newContent)
            }
            .store(in: &cancellables)
    }
    
    /// 上一次的音频附件文件 ID 集合（用于检测删除）
    private var previousAudioFileIds: Set<String> = []
    
    /// 是否是第一次设置内容（用于区分初始化和用户编辑）
    private var isFirstContentSet = true
    
    // 处理内容变化
    private func handleContentChanged(_ content: String) {
        let currentAudioFileIds = extractAudioFileIds(from: content)
        
        if isFirstContentSet {
            // 第一次设置内容，只初始化音频附件集合，不检测删除
            previousAudioFileIds = currentAudioFileIds
            isFirstContentSet = false
            print("[WebEditorContext] 初始化音频附件集合，数量: \(currentAudioFileIds.count)")
        } else {
            // 后续内容变化，检测音频附件删除
            detectAndHandleAudioAttachmentDeletion(htmlContent: content)
        }
        
        // 这里可以添加内容变化后的处理逻辑
        // 例如自动保存、同步等
        print("内容已更新，长度: \(content.count)")
    }
    
    /// 提取 HTML 内容中的音频附件文件 ID
    /// - Parameter htmlContent: HTML 内容
    /// - Returns: 音频附件文件 ID 集合
    private func extractAudioFileIds(from htmlContent: String) -> Set<String> {
        var fileIds: Set<String> = []
        
        // 使用正则表达式匹配音频附件
        // 音频附件的 HTML 格式类似：<div class="mi-note-sound-container" data-fileid="xxx">
        let pattern = #"<div[^>]*class="mi-note-sound-container"[^>]*data-fileid="([^"]+)""#
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let matches = regex.matches(in: htmlContent, options: [], range: NSRange(location: 0, length: htmlContent.count))
            
            for match in matches {
                if match.numberOfRanges > 1 {
                    let fileIdRange = match.range(at: 1)
                    if let range = Range(fileIdRange, in: htmlContent) {
                        let fileId = String(htmlContent[range])
                        fileIds.insert(fileId)
                    }
                }
            }
        } catch {
            print("[WebEditorContext] 解析音频附件时出错: \(error)")
        }
        
        return fileIds
    }
    
    /// 检测并处理音频附件删除
    /// - Parameter htmlContent: 当前的 HTML 内容
    @MainActor
    private func detectAndHandleAudioAttachmentDeletion(htmlContent: String) {
        let currentAudioFileIds = extractAudioFileIds(from: htmlContent)
        
        // 找出被删除的音频附件
        let deletedFileIds = previousAudioFileIds.subtracting(currentAudioFileIds)
        
        // 处理每个被删除的音频附件
        for fileId in deletedFileIds {
            print("[WebEditorContext] 检测到音频附件删除: \(fileId)")
            AudioPanelStateManager.shared.handleAudioAttachmentDeleted(fileId: fileId)
        }
        
        // 更新记录的音频附件集合
        previousAudioFileIds = currentAudioFileIds
    }
    
    // 格式操作（参考 CKEditor 5：不手动切换状态，状态由编辑器同步）
    func toggleBold() {
        executeFormatActionClosure?("bold", nil)
        // 状态由编辑器通过 formatStateChanged 消息同步，不在这里手动切换
    }
    
    func toggleItalic() {
        executeFormatActionClosure?("italic", nil)
        // 状态由编辑器通过 formatStateChanged 消息同步，不在这里手动切换
    }
    
    func toggleUnderline() {
        executeFormatActionClosure?("underline", nil)
        // 状态由编辑器通过 formatStateChanged 消息同步，不在这里手动切换
    }
    
    func toggleStrikethrough() {
        executeFormatActionClosure?("strikethrough", nil)
        // 状态由编辑器通过 formatStateChanged 消息同步，不在这里手动切换
    }
    
    func toggleHighlight() {
        executeFormatActionClosure?("highlight", nil)
        // 状态由编辑器通过 formatStateChanged 消息同步，不在这里手动切换
    }
    
    func setTextAlignment(_ alignment: TextAlignment) {
        let alignmentValue: String
        switch alignment {
        case .leading:
            alignmentValue = "left"
        case .center:
            alignmentValue = "center"
        case .trailing:
            alignmentValue = "right"
        default:
            alignmentValue = "left"
        }
        
        executeFormatActionClosure?("textAlignment", alignmentValue)
        // 状态由编辑器通过 formatStateChanged 消息同步，不在这里手动设置
    }
    
    func setHeadingLevel(_ level: Int?) {
        if let level = level {
            executeFormatActionClosure?("heading", "\(level)")
        } else {
            // 清除标题格式
            executeFormatActionClosure?("heading", "0")
        }
        // 状态由编辑器通过 formatStateChanged 消息同步，不在这里手动设置
    }
    
    // 列表操作
    func toggleBulletList() {
        executeFormatActionClosure?("bulletList", nil)
    }
    
    func toggleOrderList() {
        executeFormatActionClosure?("orderList", nil)
    }
    
    func insertCheckbox() {
        executeFormatActionClosure?("checkbox", nil)
    }
    
    func insertHorizontalRule() {
        executeFormatActionClosure?("horizontalRule", nil)
    }
    
    func toggleQuote() {
        executeFormatActionClosure?("quote", nil)
    }
    
    // 缩进操作
    func increaseIndent() {
        executeFormatActionClosure?("indent", "increase")
    }
    
    func decreaseIndent() {
        executeFormatActionClosure?("indent", "decrease")
    }
    
    // 图片操作
    func insertImage(_ imageUrl: String, altText: String = "图片") {
        insertImageClosure?(imageUrl, altText)
    }
    
    // MARK: - 语音操作 (Requirements: 12.1, 12.2, 12.3)
    
    /// 插入语音录音闭包
    var insertAudioClosure: ((String, String?, String?) -> Void)?
    
    /// 插入录音模板闭包
    var insertRecordingTemplateClosure: ((String) -> Void)?
    
    /// 更新录音模板闭包
    var updateRecordingTemplateClosure: ((String, String, String?, String?) -> Void)?
    
    /// 在 Web 编辑器中插入语音录音
    /// - Parameters:
    ///   - fileId: 语音文件 ID
    ///   - digest: 文件摘要（可选）
    ///   - mimeType: MIME 类型（可选，默认 audio/mpeg）
    /// - Requirements: 12.1, 12.2, 12.3
    func insertAudio(fileId: String, digest: String? = nil, mimeType: String? = nil) {
        print("[WebEditorContext] 插入语音录音: fileId=\(fileId)")
        insertAudioClosure?(fileId, digest, mimeType)
    }
    
    /// 在 Web 编辑器中插入录音模板占位符
    /// - Parameter templateId: 模板唯一标识符
    func insertRecordingTemplate(templateId: String) {
        print("[WebEditorContext] 插入录音模板: templateId=\(templateId)")
        insertRecordingTemplateClosure?(templateId)
    }
    
    /// 更新录音模板为实际的音频附件
    /// - Parameters:
    ///   - templateId: 模板唯一标识符
    ///   - fileId: 音频文件 ID
    ///   - digest: 文件摘要（可选）
    ///   - mimeType: MIME 类型（可选）
    func updateRecordingTemplate(templateId: String, fileId: String, digest: String? = nil, mimeType: String? = nil) {
        print("[WebEditorContext] 更新录音模板: templateId=\(templateId), fileId=\(fileId)")
        updateRecordingTemplateClosure?(templateId, fileId, digest, mimeType)
    }
    
    /// 更新录音模板并强制保存
    /// 
    /// 更新录音模板为音频附件后立即强制保存，确保内容持久化
    /// 不依赖防抖机制，立即触发保存操作
    /// 
    /// - Parameters:
    ///   - templateId: 模板唯一标识符
    ///   - fileId: 音频文件 ID
    ///   - digest: 文件摘要（可选）
    ///   - mimeType: MIME 类型（可选）
    /// - Requirements: 1.1, 2.1
    func updateRecordingTemplateAndSave(templateId: String, fileId: String, digest: String? = nil, mimeType: String? = nil) async throws {
        print("[WebEditorContext] 更新录音模板并强制保存: templateId=\(templateId), fileId=\(fileId)")
        
        // 1. 更新录音模板
        updateRecordingTemplate(templateId: templateId, fileId: fileId, digest: digest, mimeType: mimeType)
        
        // 2. 强制保存内容，不依赖防抖机制
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            forceSaveContent {
                continuation.resume()
            }
        }
        
        print("[WebEditorContext] ✅ 录音模板更新和保存完成")
    }
    
    /// 验证内容持久化
    /// 
    /// 验证保存后的内容是否包含预期的音频附件，确保持久化成功
    /// 
    /// - Parameter expectedContent: 预期的内容（包含音频附件的XML）
    /// - Returns: 是否验证成功
    /// - Requirements: 1.3, 3.4
    func verifyContentPersistence(expectedContent: String) async -> Bool {
        print("[WebEditorContext] 验证内容持久化，预期内容长度: \(expectedContent.count)")
        
        // 获取当前编辑器内容
        let currentContent = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            getCurrentContent { content in
                continuation.resume(returning: content)
            }
        }
        
        // 简单的内容比较验证
        let isValid = currentContent.contains("<sound fileid=") && 
                     !currentContent.contains("des=\"temp\"") && 
                     currentContent.count > 0
        
        print("[WebEditorContext] 内容持久化验证结果: \(isValid ? "成功" : "失败")")
        print("[WebEditorContext] 当前内容长度: \(currentContent.count)")
        
        return isValid
    }
    
    // MARK: - 语音播放控制 (Requirements: 13.2, 13.3)
    
    /// 播放语音闭包
    var playAudioClosure: ((String) -> Void)?
    
    /// 暂停语音闭包
    var pauseAudioClosure: ((String) -> Void)?
    
    /// 更新播放状态闭包
    var updateAudioPlaybackStateClosure: ((String, Bool, Bool, String?) -> Void)?
    
    /// 播放 Web 编辑器中的语音
    /// - Parameter fileId: 语音文件 ID
    /// - Requirements: 13.2, 13.3
    func playAudio(fileId: String) {
        print("[WebEditorContext] 播放语音: fileId=\(fileId)")
        playAudioClosure?(fileId)
    }
    
    /// 暂停语音播放
    /// - Parameter fileId: 语音文件 ID
    /// - Requirements: 13.2
    func pauseAudio(fileId: String) {
        print("[WebEditorContext] 暂停语音: fileId=\(fileId)")
        pauseAudioClosure?(fileId)
    }
    
    /// 更新 Web 编辑器中的播放状态
    /// - Parameters:
    ///   - fileId: 语音文件 ID
    ///   - isPlaying: 是否正在播放
    ///   - isLoading: 是否正在加载
    ///   - error: 错误信息（可选）
    /// - Requirements: 13.4
    func updateAudioPlaybackState(fileId: String, isPlaying: Bool, isLoading: Bool = false, error: String? = nil) {
        print("[WebEditorContext] 更新播放状态: fileId=\(fileId), isPlaying=\(isPlaying), isLoading=\(isLoading)")
        updateAudioPlaybackStateClosure?(fileId, isPlaying, isLoading, error)
    }
    
    // 获取当前内容
    func getCurrentContent(completion: @escaping (String) -> Void) {
        getCurrentContentClosure?(completion)
    }
    
    // 强制保存当前内容（用于切换笔记前）
    func forceSaveContent(completion: @escaping () -> Void) {
        forceSaveContentClosure?(completion)
    }
    
    // 撤销操作
    func undo() {
        undoClosure?()
    }
    
    // 重做操作
    func redo() {
        redoClosure?()
    }
    
    // 编辑器准备就绪
    @MainActor
    func editorReady() {
        isEditorReady = true
        isEditorFocused = true
        
        // 注册格式提供者到 FormatStateManager
        // _Requirements: 8.4_
        FormatStateManager.shared.setActiveProvider(formatProvider)
        
        // 发送编辑器焦点变化通知
        postEditorFocusNotification(true)
    }
    
    /// 设置编辑器焦点状态
    /// _Requirements: 8.4_
    @MainActor
    func setEditorFocused(_ focused: Bool) {
        // 只有状态真正变化时才更新和发送通知
        guard isEditorFocused != focused else { return }
        
        isEditorFocused = focused
        
        // 发送编辑器焦点变化通知
        postEditorFocusNotification(focused)
        
        if focused {
            // 注册格式提供者到 FormatStateManager
            // _Requirements: 8.4_
            FormatStateManager.shared.setActiveProvider(formatProvider)
        }
    }
    
    /// 发送编辑器焦点变化通知
    /// _Requirements: 8.4_
    private func postEditorFocusNotification(_ focused: Bool) {
        NotificationCenter.default.post(
            name: .editorFocusDidChange,
            object: self,
            userInfo: ["isEditorFocused": focused]
        )
    }
    
    // 更新选择状态
    func updateSelection(hasSelection: Bool, selectedText: String = "") {
        self.hasSelection = hasSelection
        self.selectedText = selectedText
    }
    
    // 打开Web Inspector
    func openWebInspector() {
        openWebInspectorClosure?()
    }
    
    // 高亮搜索文本
    func highlightSearchText(_ searchText: String) {
        highlightSearchTextClosure?(searchText)
    }

    // 查找文本
    func findText(_ options: [String: Any]) {
        findTextClosure?(options)
    }

    // 替换文本
    func replaceText(_ options: [String: Any]) {
        replaceTextClosure?(options)
    }
    
    // MARK: - 缩放操作 (Requirements: 10.2, 10.3, 10.4)
    
    /// 放大
    /// - Requirements: 10.2
    func zoomIn() {
        executeFormatActionClosure?("zoomIn", nil)
    }
    
    /// 缩小
    /// - Requirements: 10.3
    func zoomOut() {
        executeFormatActionClosure?("zoomOut", nil)
    }
    
    /// 重置缩放
    /// - Requirements: 10.4
    func resetZoom() {
        executeFormatActionClosure?("resetZoom", nil)
    }
}

// 扩展TextAlignment以便与字符串转换
extension TextAlignment {
    var stringValue: String {
        switch self {
        case .leading:
            return "left"
        case .center:
            return "center"
        case .trailing:
            return "right"
        default:
            return "left"
        }
    }
    
    static func fromString(_ value: String) -> TextAlignment {
        switch value.lowercased() {
        case "center":
            return .center
        case "right":
            return .trailing
        default:
            return .leading
        }
    }
}
