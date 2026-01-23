import SwiftUI
import AppKit
import Combine

/// 笔记详情视图
@available(macOS 14.0, *)
struct NoteDetailView: View {
    /// 应用协调器（共享数据层）
    let coordinator: AppCoordinator
    
    /// 窗口状态（窗口独立状态）
    @ObservedObject var windowState: WindowState
    
    /// 笔记视图模型（通过 coordinator 访问）
    private var viewModel: NotesViewModel {
        coordinator.notesViewModel
    }
    
    @State private var editedTitle: String = ""
    @State private var currentXMLContent: String = ""
    @State private var isSaving: Bool = false
    @State private var isUploading: Bool = false
    @State private var showSaveSuccess: Bool = false
    
    // 标题提取服务
    private let titleExtractionService = TitleExtractionService.shared
    
    // 保存流程协调器
    private let savePipelineCoordinator = SavePipelineCoordinator()
    
    // 保存状态
    /// 保存状态枚举
    /// 
    /// 用于显示当前笔记的保存状态
    /// 
    /// _Requirements: 6.1, 6.2, 6.3, 6.4_
    enum SaveStatus: Equatable {
        case saved        // 已保存（绿色）
        case saving       // 保存中（黄色）
        case unsaved      // 未保存（红色）
        case error(String) // 保存失败（红色，带错误信息）
        
        /// 实现 Equatable 协议
        static func == (lhs: SaveStatus, rhs: SaveStatus) -> Bool {
            switch (lhs, rhs) {
            case (.saved, .saved), (.saving, .saving), (.unsaved, .unsaved):
                return true
            case (.error(let lhsMessage), .error(let rhsMessage)):
                return lhsMessage == rhsMessage
            default:
                return false
            }
        }
    }
    @State private var saveStatus: SaveStatus = .saved
    
    // MARK: - 调试模式状态
    // _Requirements: 1.1, 1.2_
    
    /// 是否处于调试模式
    /// 
    /// 当为 true 时，显示 XML 调试编辑器；当为 false 时，显示普通编辑器
    @State private var isDebugMode: Bool = false
    
    /// 调试模式下的 XML 内容
    /// 
    /// 用于在调试模式下编辑的 XML 内容，切换模式时与 currentXMLContent 同步
    @State private var debugXMLContent: String = ""
    
    /// 调试模式下的保存状态
    @State private var debugSaveStatus: DebugSaveStatus = .saved
    @State private var showSaveErrorAlert: Bool = false
    @State private var saveErrorMessage: String = ""
    @State private var isEditable: Bool = true
    @State private var isInitializing: Bool = true
    @State private var originalTitle: String = ""
    @State private var originalXMLContent: String = ""
    @State private var currentEditingNoteId: String? = nil
    @State private var isSavingBeforeSwitch: Bool = false
    @State private var lastSavedXMLContent: String = ""
    @State private var isSavingLocally: Bool = false
    
    // 保存任务跟踪
    @State private var htmlSaveTask: Task<Void, Never>? = nil
    @State private var xmlSaveTask: Task<Void, Never>? = nil
    @State private var xmlSaveDebounceTask: Task<Void, Never>? = nil
    
    // XML保存防抖延迟（毫秒）
    private let xmlSaveDebounceDelay: UInt64 = 300_000_000 // 300ms
    
    // MARK: - 保存重试状态
    // _Requirements: 2.5, 9.1_ - 保存失败时的内容保护和重试
    
    /// 待重试保存的 XML 内容
    @State private var pendingRetryXMLContent: String? = nil
    
    /// 待重试保存的笔记对象
    @State private var pendingRetryNote: Note? = nil
    
    /// 是否显示重试保存确认对话框
    @State private var showRetrySaveAlert: Bool = false
    
    @State private var showImageInsertAlert: Bool = false
    @State private var imageInsertMessage: String = ""
    @State private var isInsertingImage: Bool = false
    @State private var imageInsertStatus: ImageInsertStatus = .idle
    
    enum ImageInsertStatus {
        case idle, uploading, success, failed
    }
    
    @State private var showingHistoryView: Bool = false
    
    // 使用共享的 NativeEditorContext（从 viewModel 获取）
    private var nativeEditorContext: NativeEditorContext {
        viewModel.nativeEditorContext
    }
    
    // 编辑器偏好设置服务 - 使用 @ObservedObject 因为是单例
    @ObservedObject private var editorPreferencesService = EditorPreferencesService.shared
    
    /// 当前是否使用原生编辑器（始终为 true）
    private var isUsingNativeEditor: Bool {
        editorPreferencesService.isNativeEditorAvailable
    }
    
    var body: some View {
        mainContentView
            .onChange(of: viewModel.selectedNote) { oldValue, newValue in
                handleSelectedNoteChange(oldValue: oldValue, newValue: newValue)
            }
            .onAppear {
                // 注册保存回调到 ViewStateCoordinator 
                // - 3.5: 用户在 Editor 中编辑笔记时切换到另一个文件夹，先保存当前编辑内容再切换
                // - 6.1: 切换文件夹且 Editor 有未保存内容时，先触发保存操作
                // - 6.2: 保存操作完成后继续执行文件夹切换
                registerSaveCallback()
            }
            .onDisappear {
                // 清除保存回调
                viewModel.stateCoordinator.saveContentCallback = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleDebugMode)) { _ in
                // 监听调试模式切换通知
                // _Requirements: 1.1, 1.2, 5.2, 6.1_
                toggleDebugMode()
            }
            // 监听原生编辑器保存状态变化通知
            // _Requirements: 6.1, 6.2, 6.3, 6.4_
            .onReceive(NotificationCenter.default.publisher(for: .nativeEditorSaveStatusDidChange)) { notification in
                handleNativeEditorSaveStatusChange(notification)
            }
            .navigationTitle("详情")
            .toolbar {
                toolbarContent
            }
    }
    
    /// 处理原生编辑器保存状态变化通知
    /// 
    /// 当原生编辑器的 needsSave 状态变化时,更新保存状态指示器
    /// 
    /// _Requirements: FR-1, FR-6_ - 使用版本号机制判断是否需要保存
    private func handleNativeEditorSaveStatusChange(_ notification: Notification) {
        // 只在使用原生编辑器时处理
        guard isUsingNativeEditor else { return }
        
        // 只在非调试模式下处理
        guard !isDebugMode else { return }
        
        // 获取 needsSave 状态
        guard let userInfo = notification.userInfo,
              let needsSave = userInfo["needsSave"] as? Bool else {
            return
        }
        
        // 更新保存状态
        // _Requirements: FR-1, FR-6_ - 内容未保存时显示"未保存"状态
        if needsSave {
            // 只有在当前状态不是 saving 时才更新为 unsaved
            // 避免在保存过程中被覆盖
            if case .saving = saveStatus {
                // 保持 saving 状态
            } else {
                saveStatus = .unsaved
                Swift.print("[保存状态] 📝 内容变化 - 设置为未保存")
            }
        }
        // 注意：saved 状态由保存完成后的回调设置,不在这里处理
    }
    
    /// 注册保存回调到 ViewStateCoordinator
    /// 
    /// 当文件夹切换时，ViewStateCoordinator 会调用此回调来保存当前编辑的内容
    /// 
    private func registerSaveCallback() {
        viewModel.stateCoordinator.saveContentCallback = { [self] in
            await self.saveCurrentContentForFolderSwitch()
        }
        Swift.print("[NoteDetailView] ✅ 已注册保存回调到 ViewStateCoordinator")
    }
    
    /// 为文件夹切换保存当前内容
    /// 
    /// 这个方法会被 ViewStateCoordinator 在文件夹切换前调用
    /// 后台异步保存，不阻塞界面切换
    /// 
    /// 
    /// - Returns: 是否保存成功（立即返回 true，保存在后台进行）
    @MainActor
    private func saveCurrentContentForFolderSwitch() async -> Bool {
        guard let note = viewModel.selectedNote, note.id == currentEditingNoteId else {
            Swift.print("[保存流程] ⏭️ 文件夹切换保存跳过 - 无当前编辑笔记")
            return true
        }
        
        // 关键修复：在切换前立即捕获当前编辑的标题和内容
        let capturedTitle = editedTitle
        let capturedOriginalTitle = originalTitle
        let capturedLastSavedXMLContent = lastSavedXMLContent
        let capturedNote = note
        
        // 关键修复：立即获取原生编辑器的内容（在切换前）
        var capturedContent: String = ""
        if isUsingNativeEditor {
            capturedContent = nativeEditorContext.exportToXML()
            Swift.print("[保存流程] 📝 立即捕获原生编辑器内容 - 长度: \(capturedContent.count)")
            
            // 如果导出为空，使用 currentXMLContent
            if capturedContent.isEmpty && !currentXMLContent.isEmpty {
                capturedContent = currentXMLContent
                Swift.print("[保存流程] 📝 使用 currentXMLContent - 长度: \(capturedContent.count)")
            }
        }
        
        Swift.print("[保存流程] 🔄 文件夹切换前保存 - 笔记ID: \(note.id.prefix(8))..., 标题: \(capturedTitle)")
        
        // 后台异步保存，不阻塞界面切换
        Task { @MainActor in
            // 1. 使用捕获的内容
            let content: String = capturedContent
            
            // 2. 检查内容是否变化
            let hasContentChange = content != capturedLastSavedXMLContent
            let hasTitleChange = capturedTitle != capturedOriginalTitle
            
            guard hasContentChange || hasTitleChange else {
                Swift.print("[保存流程] ⏭️ 文件夹切换保存跳过 - 内容无变化")
                return
            }
            
            Swift.print("[保存流程] 💾 后台保存 - 内容长度: \(content.count)")
            Swift.print("[保存流程]   - 内容变化: \(hasContentChange)")
            Swift.print("[保存流程]   - 标题变化: \(hasTitleChange)")
            
            // 3. 构建更新的笔记对象（保留所有字段）
            let updated = Note(
                id: capturedNote.id,
                title: capturedTitle,
                content: content,
                folderId: capturedNote.folderId,
                isStarred: capturedNote.isStarred,
                createdAt: capturedNote.createdAt,
                updatedAt: Date(),
                tags: capturedNote.tags,
                rawData: capturedNote.rawData,
                snippet: capturedNote.snippet,
                colorId: capturedNote.colorId,
                subject: capturedNote.subject,
                alertDate: capturedNote.alertDate,
                type: capturedNote.type,
                serverTag: capturedNote.serverTag,
                status: capturedNote.status,
                settingJson: capturedNote.settingJson,
                extraInfoJson: capturedNote.extraInfoJson
            )
            
            // 立即更新内存缓存（不阻塞）
            await MemoryCacheManager.shared.cacheNote(updated)
            
            // 更新视图模型中的笔记（不阻塞）
            if let index = self.viewModel.notes.firstIndex(where: { $0.id == updated.id }) {
                self.viewModel.notes[index] = updated
            }
            
            // 4. 后台异步保存到数据库
            DatabaseService.shared.saveNoteAsync(updated) { error in
                Task { @MainActor in
                    if let error = error {
                        Swift.print("[保存流程] ❌ 文件夹切换后台保存失败: \(error)")
                    } else {
                        Swift.print("[保存流程] ✅ 文件夹切换后台保存完成")
                        
                        // 调度云端同步（后台执行）
                        self.scheduleCloudUpload(for: updated, xmlContent: content)
                    }
                }
            }
        }
        
        // 立即返回 true，不阻塞界面切换
        return true
    }
    
    /// 主内容视图
    @ViewBuilder
    private var mainContentView: some View {
        // 检查是否是私密笔记文件夹且未解锁
        if let folder = viewModel.selectedFolder, folder.id == "2", !viewModel.isPrivateNotesUnlocked {
            // 显示验证界面
            PrivateNotesVerificationView(viewModel: viewModel)
        } else if let note = viewModel.selectedNote {
            noteEditorView(for: note)
        } else {
            emptyNoteView
        }
    }
    
    /// 工具栏内容
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            newNoteButton
        }
        ToolbarItemGroup(placement: .automatic) {
            undoButton
            redoButton
        }
        ToolbarItemGroup(placement: .automatic) {
            formatMenu
            checkboxButton
            horizontalRuleButton
            imageButton
        }
        ToolbarItemGroup(placement: .automatic) {
            indentButtons
            Spacer()
            // 调试模式切换按钮
            // _Requirements: 1.3, 1.5, 6.1_
            debugModeToggleButton
            if let note = viewModel.selectedNote {
                shareAndMoreButtons(for: note)
            }
        }
    }
    
    /// 调试模式切换按钮
    /// 
    /// _Requirements: 1.1, 1.2, 1.3, 1.5, 5.2, 6.1_
    private var debugModeToggleButton: some View {
        Button {
            toggleDebugMode()
        } label: {
            Label(
                isDebugMode ? "退出调试" : "调试模式",
                systemImage: isDebugMode ? "xmark.circle" : "chevron.left.forwardslash.chevron.right"
            )
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])
        .disabled(viewModel.selectedNote == nil)
        .help(isDebugMode ? "退出 XML 调试模式 (⌘⇧D)" : "进入 XML 调试模式 (⌘⇧D)")
    }
    
    @ViewBuilder
    private func noteEditorView(for note: Note) -> some View {
        ZStack {
            Color(nsColor: NSColor.textBackgroundColor).ignoresSafeArea()
            editorContentView(for: note)
            
            // 悬浮信息栏
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    FloatingInfoBar(
                        note: note,
                        currentXMLContent: currentXMLContent,
                        isDebugMode: isDebugMode,
                        saveStatus: isDebugMode ? .debug(debugSaveStatus) : .normal(saveStatus),
                        showSaveErrorAlert: $showSaveErrorAlert,
                        saveErrorMessage: $saveErrorMessage,
                        onRetrySave: { retrySave() }
                    )
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .onAppear {
            handleNoteAppear(note)
        }
        .onChange(of: note) { oldValue, newValue in
            if oldValue.id != newValue.id {
                Task { @MainActor in await handleNoteChange(newValue) }
            }
        }
        .onChange(of: editedTitle) { _, newValue in
            Task { @MainActor in await handleTitleChange(newValue) }
        }
        .sheet(isPresented: $showImageInsertAlert) {
            ImageInsertStatusView(isInserting: isInsertingImage, message: imageInsertMessage, status: imageInsertStatus, onDismiss: { imageInsertStatus = .idle })
        }
        .alert("保存失败", isPresented: $showSaveErrorAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
    }
    
    private func editorContentView(for note: Note) -> some View {
        bodyEditorView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .top) // 允许内容延伸到工具栏下方
    }
    
    // 标题编辑器已移除,标题将在后续任务中作为编辑器的第一个段落
    private func hasRealTitle() -> Bool {
        guard let note = viewModel.selectedNote else { return false }
        return !note.title.isEmpty && !note.title.hasPrefix("未命名笔记_")
    }
    
    private func metaInfoView(for note: Note) -> some View {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy年MM月dd日 HH:mm"
        let updateDateString = dateFormatter.string(from: note.updatedAt)
        let wordCount = calculateWordCount(from: currentXMLContent.isEmpty ? note.primaryXMLContent : currentXMLContent)
        
        return HStack(spacing: 8) {
            Text("\(updateDateString) · \(wordCount) 字")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            
            // 调试模式指示器
            if isDebugMode {
                debugModeIndicator
            }
            
            // 保存状态指示器（根据模式显示不同状态）
            if isDebugMode {
                debugSaveStatusIndicator
            } else {
                saveStatusIndicator
            }
        }
    }
    
    /// 调试模式指示器
    private var debugModeIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 8))
            Text("调试模式")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.15))
        .cornerRadius(4)
    }
    
    /// 调试模式保存状态指示器
    private var debugSaveStatusIndicator: some View {
        Group {
            switch debugSaveStatus {
            case .saved:
                Text("已保存")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
            case .saving:
                Text("保存中...")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            case .unsaved:
                Text("未保存")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            case .error(let message):
                Text("保存失败")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .onTapGesture {
                        saveErrorMessage = message
                        showSaveErrorAlert = true
                    }
            }
        }
    }
    
    /// 保存状态指示器
    /// 
    /// 显示当前保存状态：已保存（绿色）、保存中（黄色）、未保存（红色）、保存失败（红色，可点击查看详情和重试）
    /// 
    /// _Requirements: 6.1, 6.2, 6.3, 6.4, 2.5, 9.1_
    private var saveStatusIndicator: some View {
        Group {
            switch saveStatus {
            case .saved:
                // _Requirements: 6.3_ - 保存完成显示"已保存"状态（绿色）
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 8))
                    Text("已保存")
                        .font(.system(size: 10))
                }
                .foregroundColor(.green)
            case .saving:
                // _Requirements: 6.2_ - 保存中显示"保存中..."状态（黄色）
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 10, height: 10)
                    Text("保存中...")
                        .font(.system(size: 10))
                }
                .foregroundColor(.orange)
            case .unsaved:
                // _Requirements: 6.1_ - 内容未保存显示"未保存"状态（红色）
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 8))
                    Text("未保存")
                        .font(.system(size: 10))
                }
                .foregroundColor(.red)
            case .error(let message):
                // _Requirements: 6.4, 2.5, 9.1_ - 保存失败显示"保存失败"状态（红色，可点击查看详情和重试）
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 8))
                        Text("保存失败")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.red)
                    .onTapGesture {
                        // 点击显示错误详情
                        saveErrorMessage = message
                        showSaveErrorAlert = true
                    }
                    
                    // _Requirements: 9.1_ - 提供重试选项
                    if pendingRetryXMLContent != nil {
                        Button(action: {
                            retrySave()
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 8))
                                Text("重试")
                                    .font(.system(size: 10))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.1))
                .cornerRadius(4)
                .help("点击查看错误详情，或点击重试按钮重新保存")
            }
        }
    }
    
    private func calculateWordCount(from xmlContent: String) -> Int {
    guard !xmlContent.isEmpty else { return 0 }
    let textOnly = xmlContent
        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")  // 修复此处：转义双引号
        .replacingOccurrences(of: "&apos;", with: "'")   // 修复此处：转义单引号
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return textOnly.count
    }

    
    private var bodyEditorView: some View {
        Group {
            if isInitializing {
                // 占位符：显示加载状态
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("加载中...")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let note = viewModel.selectedNote {
                // 根据调试模式显示不同编辑器
                // _Requirements: 1.1, 1.2, 1.4, 6.2_
                if isDebugMode {
                    // 调试模式：显示 XML 调试编辑器
                    // _Requirements: 1.1, 2.1, 6.2_
                    XMLDebugEditorView(
                        xmlContent: $debugXMLContent,
                        isEditable: $isEditable,
                        saveStatus: $debugSaveStatus,
                        onSave: {
                            // 保存调试编辑器中的内容
                            Task { @MainActor in
                                await saveDebugContent()
                            }
                        },
                        onContentChange: { newContent in
                            // 调试模式下的内容变化处理
                            handleDebugContentChange(newContent)
                        }
                    )
                } else {
                    // 普通模式：使用原生编辑器包装器
                    // 任务 22.2 修复：使用 currentXMLContent（包含标题）而不是 note.primaryXMLContent
                    // 这确保标题能够正确显示在编辑器中
                    UnifiedEditorWrapper(
                        content: $currentXMLContent,
                        isEditable: $isEditable,
                        nativeEditorContext: nativeEditorContext,
                        xmlContent: currentXMLContent,
                        folderId: note.folderId,
                        onContentChange: { newXML, newHTML in
                            guard !isInitializing else { return }
                            
                            // 关键修复：始终使用当前的selectedNote，而不是捕获的note
                            // 这确保切换笔记后，内容变化不会应用到错误的笔记
                            guard let currentNote = viewModel.selectedNote,
                                  currentNote.id == currentEditingNoteId else {
                                Swift.print("[保存流程] ⚠️ 内容变化时笔记已切换，忽略此次保存")
                                return
                            }
                            
                            Task { @MainActor in
                                // 任务 4.1: 集成 TitleExtractionService 进行标题提取
                                // _需求: 1.1, 1.2, 4.2_ - 使用 TitleExtractionService 提取标题
                                
                                // 1. 优先从原生编辑器提取标题
                                var titleResult: TitleExtractionResult
                                let nsAttributedText = self.nativeEditorContext.nsAttributedText
                                if nsAttributedText.length > 0 {
                                    // 创建临时的 NSTextStorage 用于标题提取
                                    let textStorage = NSTextStorage(attributedString: nsAttributedText)
                                    titleResult = self.titleExtractionService.extractTitleFromEditor(textStorage)
                                    Swift.print("[保存流程] 📝 从原生编辑器提取标题: '\(titleResult.title)' (来源: \(titleResult.source.displayName))")
                                } else {
                                    // 2. 后备方案：从 XML 内容提取标题
                                    titleResult = self.titleExtractionService.extractTitleFromXML(newXML)
                                    Swift.print("[保存流程] 📝 从 XML 内容提取标题: '\(titleResult.title)' (来源: \(titleResult.source.displayName))")
                                }
                                
                                // 3. 验证提取的标题
                                let validation = self.titleExtractionService.validateTitle(titleResult.title)
                                if validation.isValid {
                                    // 更新 editedTitle 状态（保持 UI 同步）
                                    if !titleResult.title.isEmpty {
                                        self.editedTitle = titleResult.title
                                        Swift.print("[保存流程] ✅ 标题验证通过，已更新 editedTitle: '\(titleResult.title)'")
                                    }
                                } else {
                                    Swift.print("[保存流程] ⚠️ 标题验证失败: \(validation.error ?? "未知错误")")
                                    // 保持原有标题不变
                                }
                                
                                // 4. 更新当前内容状态
                                self.currentXMLContent = newXML
                                
                                // [Tier 0] 立即更新内存缓存（<1ms，无延迟）
                                await self.updateMemoryCache(xmlContent: newXML, htmlContent: newHTML, for: currentNote)
                                
                                // [Tier 1] 异步保存 HTML 缓存（后台，<10ms）
                                if let html = newHTML {
                                    self.flashSaveHTML(html, for: currentNote)
                                }
                                
                                // [Tier 2] 异步保存 XML（后台，<50ms，防抖300ms）
                                // 传递提取的标题结果，确保在保存前正确提取和设置标题
                                self.scheduleXMLSave(xmlContent: newXML, for: currentNote, extractedTitle: titleResult, immediate: false)
                                
                                // [Tier 3] 计划同步云端（延迟3秒）
                                self.scheduleCloudUpload(for: currentNote, xmlContent: newXML)
                            }
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - 调试模式方法
    
    /// 切换调试模式
    /// 
    /// _Requirements: 1.1, 1.2, 1.4_
    private func toggleDebugMode() {
        if isDebugMode {
            // 从调试模式切换到普通模式
            // _Requirements: 1.2, 1.4_
            // 保留调试模式下编辑的内容
            if debugXMLContent != currentXMLContent {
                currentXMLContent = debugXMLContent
                // 标记内容已修改，触发保存
                if let note = viewModel.selectedNote {
                    scheduleXMLSave(xmlContent: debugXMLContent, for: note, immediate: false)
                }
            }
            isDebugMode = false
            Swift.print("[调试模式] 🔄 退出调试模式")
        } else {
            // 从普通模式切换到调试模式
            // _Requirements: 1.1_
            // 同步当前内容到调试编辑器
            if let note = viewModel.selectedNote {
                // 优先使用当前编辑的内容，如果为空则使用笔记的原始内容
                debugXMLContent = currentXMLContent.isEmpty ? note.primaryXMLContent : currentXMLContent
            }
            debugSaveStatus = DebugSaveStatus.saved
            isDebugMode = true
            Swift.print("[调试模式] 🔄 进入调试模式 - 内容长度: \(debugXMLContent.count)")
        }
    }
    
    /// 处理调试模式下的内容变化
    /// 
    /// _Requirements: 3.1, 3.3_
    private func handleDebugContentChange(_ newContent: String) {
        guard !isInitializing else { return }
        
        // 标记为未保存
        if debugSaveStatus != .saving {
            debugSaveStatus = DebugSaveStatus.unsaved
        }
        
        Swift.print("[调试模式] 📝 内容变化 - 长度: \(newContent.count)")
    }
    
    /// 保存调试编辑器中的内容
    /// 
    /// 实现完整的保存流程：
    /// 1. 更新 Note.content 为编辑后的 XML 内容
    /// 2. 触发本地数据库保存
    /// 3. 调度云端同步
    /// 
    /// _Requirements: 4.1, 4.2, 4.3, 4.4_
    @MainActor
    private func saveDebugContent() async {
        guard let note = viewModel.selectedNote, note.id == currentEditingNoteId else {
            Swift.print("[调试模式] ⚠️ 保存失败 - 无当前编辑笔记")
            debugSaveStatus = .error("无法保存：未选择笔记")
            return
        }
        
        // 检查内容是否有变化
        let hasChanges = debugXMLContent != lastSavedXMLContent || editedTitle != originalTitle
        guard hasChanges else {
            Swift.print("[调试模式] ⏭️ 保存跳过 - 内容无变化")
            debugSaveStatus = .saved
            return
        }
        
        // _Requirements: 4.5_ - 显示 "保存中..." 状态
        debugSaveStatus = .saving
        
        // 同步内容到 currentXMLContent
        // _Requirements: 4.1, 4.2_ - 更新 Note.content
        currentXMLContent = debugXMLContent
        
        Swift.print("[调试模式] 💾 开始保存 - 笔记ID: \(note.id.prefix(8))..., 内容长度: \(debugXMLContent.count)")
        
        // 构建更新的笔记对象
        let updated = buildUpdatedNote(from: note, xmlContent: debugXMLContent)
        
        // _Requirements: 4.3_ - 触发本地数据库保存
        do {
            try await saveDebugContentToDatabase(updated)
            
            // _Requirements: 4.6_ - 显示 "已保存" 状态
            debugSaveStatus = .saved
            // 关键修复：确保 lastSavedXMLContent 与 debugXMLContent 同步
            // _需求: 2.2_
            lastSavedXMLContent = debugXMLContent
            Swift.print("[调试模式] 📝 保存成功，lastSavedXMLContent 已同步 - 长度: \(lastSavedXMLContent.count)")
            
            // 更新内存缓存
            await MemoryCacheManager.shared.cacheNote(updated)
            
            // 更新视图模型中的笔记
            if let index = viewModel.notes.firstIndex(where: { $0.id == updated.id }) {
                viewModel.notes[index] = updated
            }
            if viewModel.selectedNote?.id == updated.id {
                viewModel.selectedNote = updated
                viewModel.stateCoordinator.updateNoteContent(updated)
            }
            
            // 清除未保存内容标志
            viewModel.stateCoordinator.hasUnsavedContent = false
            
            Swift.print("[调试模式] ✅ 本地保存成功")
            
            // _Requirements: 4.4_ - 调度云端同步
            scheduleCloudUpload(for: updated, xmlContent: debugXMLContent)
            
        } catch {
            // _Requirements: 4.7_ - 显示错误信息并保留编辑内容
            let errorMessage = "保存失败: \(error.localizedDescription)"
            debugSaveStatus = .error(errorMessage)
            Swift.print("[调试模式] ❌ 保存失败: \(error)")
            // 不清空 debugXMLContent，保留用户编辑的内容
        }
    }
    
    /// 将调试内容保存到数据库
    /// 
    /// _Requirements: 4.3_
    @MainActor
    private func saveDebugContentToDatabase(_ note: Note) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DatabaseService.shared.saveNoteAsync(note) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    private var emptyNoteView: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text").font(.system(size: 48)).foregroundColor(.secondary)
            Text("选择笔记或创建新笔记").font(.title2).foregroundColor(.secondary)
            Button(action: { viewModel.createNewNote() }) { Label("新建笔记", systemImage: "plus") }.buttonStyle(.borderedProminent)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 工具栏按钮
    
    private var undoButton: some View {
        Button {
            if isUsingNativeEditor {
                // 原生编辑器撤销（通过 NSTextView 的 undoManager）
                NSApp.sendAction(#selector(UndoManager.undo), to: nil, from: nil)
            }
        } label: { Label("撤销", systemImage: "arrow.uturn.backward") }
    }
    
    private var redoButton: some View {
        Button {
            if isUsingNativeEditor {
                // 原生编辑器重做（通过 NSTextView 的 undoManager）
                NSApp.sendAction(#selector(UndoManager.redo), to: nil, from: nil)
            }
        } label: { Label("重做", systemImage: "arrow.uturn.forward") }
    }
    
    @State private var showFormatMenu: Bool = false
    private var formatMenu: some View {
        Button { showFormatMenu.toggle() } label: { Label("格式", systemImage: "textformat") }
        .popover(isPresented: $showFormatMenu, arrowEdge: .top) {
            FormatMenuPopoverContent(
                nativeEditorContext: nativeEditorContext,
                onDismiss: { showFormatMenu = false }
            )
        }
    }
    
    private var checkboxButton: some View {
        Button {
            if isUsingNativeEditor {
                nativeEditorContext.insertCheckbox()
            }
        } label: { Label("插入待办", systemImage: "checklist") }
    }
    
    private var horizontalRuleButton: some View {
        Button {
            if isUsingNativeEditor {
                nativeEditorContext.insertHorizontalRule()
            }
        } label: { Label("插入分割线", systemImage: "minus") }
    }
    
    private var imageButton: some View { Button { insertImage() } label: { Label("插入图片", systemImage: "paperclip") } }
    
    @ViewBuilder
    private var indentButtons: some View {
        Button {
            if isUsingNativeEditor {
                // 原生编辑器增加缩进
                nativeEditorContext.increaseIndent()
            }
        } label: { Label("增加缩进", systemImage: "increase.indent") }
        
        Button {
            if isUsingNativeEditor {
                // 原生编辑器减少缩进
                nativeEditorContext.decreaseIndent()
            }
        } label: { Label("减少缩进", systemImage: "decrease.indent") }
    }
    
    private func insertImage() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.image, .png, .jpeg, .gif]
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                Task { @MainActor in await self.insertImage(from: url) }
            }
        }
    }
    
    @MainActor
    private func insertImage(from url: URL) async {
        guard viewModel.selectedNote != nil else { return }
        isInsertingImage = true
        imageInsertStatus = .uploading
        imageInsertMessage = "正在上传图片..."
        showImageInsertAlert = true
        do {
            let fileId = try await viewModel.uploadImageAndInsertToNote(imageURL: url)
            
            // 使用原生编辑器插入图片
            if isUsingNativeEditor {
                nativeEditorContext.insertImage(fileId: fileId, src: "minote://image/\(fileId)")
            }
            
            imageInsertStatus = .success
            imageInsertMessage = "图片插入成功"
            isInsertingImage = false
            await performSaveImmediately()
        } catch {
            imageInsertStatus = .failed
            imageInsertMessage = "插入失败"
            isInsertingImage = false
        }
    }
    
    @ViewBuilder
    private func shareAndMoreButtons(for note: Note) -> some View {
        Button {
            let picker = NSSharingServicePicker(items: [note.content])
            if let window = NSApplication.shared.keyWindow, let view = window.contentView {
                picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
            }
        } label: { Label("分享", systemImage: "square.and.arrow.up") }
        
        Button { showingHistoryView = true } label: { Label("历史记录", systemImage: "clock.arrow.circlepath") }
        
        Menu {
            Button { viewModel.toggleStar(note) } label: { Label(note.isStarred ? "取消置顶" : "置顶", systemImage: "pin") }
            Divider()
            Button { viewModel.showTrashView = true } label: { Label("回收站", systemImage: "trash") }
            Button(role: .destructive) { viewModel.deleteNote(note) } label: { Label("删除", systemImage: "trash") }
        } label: { Label("更多", systemImage: "ellipsis.circle") }
        .sheet(isPresented: $showingHistoryView) { NoteHistoryView(viewModel: viewModel, noteId: note.id) }
    }
    
    private var newNoteButton: some View { Button { viewModel.createNewNote() } label: { Label("新建笔记", systemImage: "square.and.pencil") } }
    
    private func handleNoteAppear(_ note: Note) {
        let task = saveCurrentNoteBeforeSwitching(newNoteId: note.id)
        Task { @MainActor in
            if let t = task { await t.value }
            await quickSwitchToNote(note)
            
        }
    }
    
    /// 快速切换笔记（使用缓存）
    /// 
    /// 优先从内存缓存加载，实现无延迟切换
    /// 
    /// - Parameter note: 笔记对象
    @MainActor
    private func quickSwitchToNote(_ note: Note) async {
        // 关键修复：在最开始就更新 currentEditingNoteId，确保后续所有操作都针对正确的笔记
        currentEditingNoteId = note.id
        Swift.print("[快速切换] 🔄 开始切换到笔记 - ID: \(note.id.prefix(8))..., 标题: \(note.title)")
        
        // 1. 立即显示占位符（<1ms）
        isInitializing = true
        
        // 重置保存状态为已保存（新笔记加载时默认为已保存状态）
        // _Requirements: 6.3_
        saveStatus = .saved
        Swift.print("[保存状态] 🔄 笔记切换 - 重置为已保存")
        
        // 关键修复：立即更新标题，不要等待内容加载
        let title = note.title.isEmpty || note.title.hasPrefix("未命名笔记_") ? "" : note.title
        editedTitle = title
        originalTitle = title
        Swift.print("[快速切换] 📝 标题已更新: \(title)")
        
        // 取消之前的保存任务
        htmlSaveTask?.cancel()
        xmlSaveTask?.cancel()
        xmlSaveDebounceTask?.cancel()
        htmlSaveTask = nil
        xmlSaveTask = nil
        xmlSaveDebounceTask = nil
        
        // 关键修复：清空内容前先记录，避免在加载过程中被覆盖
        // _需求: 2.2_ - 确保 lastSavedXMLContent 与 currentXMLContent 同步
        currentXMLContent = ""
        lastSavedXMLContent = ""
        originalXMLContent = ""
        Swift.print("[快速切换] 📝 重置内容状态，lastSavedXMLContent 已清空")
        
        // 调试模式：处理笔记切换时的内容加载
        // _Requirements: 6.4_ - 切换笔记时加载新笔记的 XML 内容，保持调试模式状态
        // 优化：先尝试从新笔记获取内容，避免显示空内容占位符
        if isDebugMode {
            // 优先使用新笔记的 primaryXMLContent，如果为空则暂时保持空状态
            // 后续在 loadNoteContentFromCache 或 loadNoteContent 中会更新
            let newNoteContent = note.primaryXMLContent
            if !newNoteContent.isEmpty {
                debugXMLContent = newNoteContent
                Swift.print("[快速切换] 🔧 调试模式预加载内容 - 长度: \(debugXMLContent.count)")
            } else {
                debugXMLContent = ""
            }
            debugSaveStatus = DebugSaveStatus.saved
        } else {
            // 非调试模式：清空调试内容
            debugXMLContent = ""
            debugSaveStatus = DebugSaveStatus.saved
        }
        
        // 2. 尝试从内存缓存获取完整笔记
        let cachedNote = await MemoryCacheManager.shared.getNote(noteId: note.id)
        if let cachedNote = cachedNote {
            // 关键修复：验证缓存的笔记ID是否匹配
            if cachedNote.id == note.id {
                Swift.print("[快速切换] ✅ 内存缓存命中 - ID: \(note.id.prefix(8))...")
                await loadNoteContentFromCache(cachedNote)
                return
            } else {
                Swift.print("[快速切换] ⚠️ 缓存笔记ID不匹配，忽略缓存 - 缓存ID: \(cachedNote.id.prefix(8))..., 期望ID: \(note.id.prefix(8))...")
                // 继续使用数据库加载
            }
        }
        
        // 3. 从数据库加载完整内容
        Swift.print("[快速切换] 📂 从数据库加载 - ID: \(note.id.prefix(8))...")
        await loadNoteContent(note)
    }
    
    /// 从缓存加载笔记内容
    @MainActor
    private func loadNoteContentFromCache(_ note: Note) async {
        // 关键修复：确保笔记ID匹配
        guard note.id == currentEditingNoteId else {
            Swift.print("[快速切换] ⚠️ loadNoteContentFromCache: 笔记ID不匹配，取消加载 - 传入ID: \(note.id.prefix(8))..., 当前编辑ID: \(currentEditingNoteId?.prefix(8) ?? "nil")")
            return
        }
        
        // 加载标题（不要重置，因为在 quickSwitchToNote 中已经设置）
        let title = note.title.isEmpty || note.title.hasPrefix("未命名笔记_") ? "" : note.title
        if editedTitle != title {
            editedTitle = title
            originalTitle = title
            Swift.print("[快速切换] 📝 从缓存更新标题: \(title)")
        }
        
        // 加载内容
        var contentToLoad = note.primaryXMLContent
        
        // ✅ 关键修复：插入标题到 XML（与 loadNoteContent 保持一致）
        // 任务 22.2: 如果有标题，将标题插入到内容的开头
        // 标题将作为编辑器的第一个段落显示
        if !title.isEmpty {
            print("[快速切换] 📝 开始处理标题插入")
            print("[快速切换]   - 标题: '\(title)'")
            print("[快速切换]   - 原始内容长度: \(contentToLoad.count)")
            print("[快速切换]   - 原始内容前100字符: '\(String(contentToLoad.prefix(100)))'")
            
            // 检查 XML 中是否已经有 <title> 标签
            if !contentToLoad.contains("<title>") {
                print("[快速切换] 📝 XML 中没有 <title> 标签，准备插入")
                
                // 如果没有 <title> 标签，添加一个
                // 将标题插入到内容的最前面（在 <new-format/> 之后）
                let titleTag = "<title>\(encodeXMLEntities(title))</title>"
                print("[快速切换]   - 标题标签: '\(titleTag)'")
                
                if contentToLoad.hasPrefix("<new-format/>") {
                    print("[快速切换] 📝 内容以 <new-format/> 开头，在其后插入标题")
                    // 在 <new-format/> 后插入标题
                    let afterPrefix = String(contentToLoad.dropFirst("<new-format/>".count))
                    contentToLoad = "<new-format/>\(titleTag)\(afterPrefix)"
                } else {
                    print("[快速切换] 📝 内容不以 <new-format/> 开头，直接在开头插入标题")
                    // 直接在开头插入标题
                    contentToLoad = "\(titleTag)\(contentToLoad)"
                }
                
                print("[快速切换] ✅ 标题已插入到 XML 内容开头")
                print("[快速切换]   - 插入后内容长度: \(contentToLoad.count)")
                print("[快速切换]   - 插入后内容前150字符: '\(String(contentToLoad.prefix(150)))'")
            } else {
                print("[快速切换] 📝 XML 中已存在 <title> 标签，跳过插入")
            }
        } else {
            print("[快速切换] 📝 标题为空，不插入 <title> 标签")
        }
        
        currentXMLContent = contentToLoad
        // 关键修复：确保 lastSavedXMLContent 与 currentXMLContent 同步
        // _需求: 2.2_
        lastSavedXMLContent = currentXMLContent
        originalXMLContent = currentXMLContent
        Swift.print("[快速切换] 📝 从缓存加载内容（包含标题），lastSavedXMLContent 已同步 - 长度: \(lastSavedXMLContent.count)")
        Swift.print("[快速切换] 📝 currentXMLContent 前200字符: '\(String(currentXMLContent.prefix(200)))'")
        
        // 关键修复：立即调用 loadFromXML 确保编辑器内容同步
        // 这解决了笔记切换时内容丢失的问题
        if isUsingNativeEditor {
            Swift.print("[快速切换] 🔄 立即加载内容到原生编辑器")
            nativeEditorContext.loadFromXML(currentXMLContent)
            Swift.print("[快速切换] ✅ 原生编辑器内容已加载 - nsAttributedText.length: \(nativeEditorContext.nsAttributedText.length)")
        }
        
        // 调试模式：同步内容到调试编辑器
        // _Requirements: 6.4_
        if isDebugMode {
            debugXMLContent = currentXMLContent
            debugSaveStatus = DebugSaveStatus.saved
            Swift.print("[快速切换] 🔧 调试模式内容已同步 - 长度: \(debugXMLContent.count)")
        }
        
        Swift.print("[快速切换] ✅ 从缓存加载完成 - ID: \(note.id.prefix(8))..., 标题: \(title), 内容长度: \(currentXMLContent.count)")
        
        // 验证内容持久化 - 检查是否包含音频附件 
        await verifyAudioAttachmentPersistence(note: note)
        
        // 短暂延迟以确保编辑器正确初始化
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // 再次验证笔记ID（防止在延迟期间切换了笔记）
        guard note.id == currentEditingNoteId else {
            Swift.print("[快速切换] ⚠️ 延迟后笔记ID不匹配，取消显示 - 传入ID: \(note.id.prefix(8))..., 当前编辑ID: \(currentEditingNoteId?.prefix(8) ?? "nil")")
            return
        }
        
        isInitializing = false
    }
    
    /// 验证音频附件持久化
    /// 
    /// 检查加载的笔记内容是否包含预期的音频附件，确保持久化成功
    /// 
    /// - Parameter note: 要验证的笔记 
    @MainActor
    private func verifyAudioAttachmentPersistence(note: Note) async {
        Swift.print("[持久化验证] 🔍 开始验证音频附件 - 笔记ID: \(note.id.prefix(8))...")
        
        let contentToVerify = currentXMLContent.isEmpty ? note.primaryXMLContent : currentXMLContent
        
        // 检查是否包含音频附件
        let hasAudioAttachments = contentToVerify.contains("<sound fileid=")
        let hasTemporaryTemplates = contentToVerify.contains("des=\"temp\"")
        
        if hasAudioAttachments {
            if hasTemporaryTemplates {
                Swift.print("[持久化验证] ⚠️ 发现临时录音模板未更新 - 笔记ID: \(note.id.prefix(8))...")
                Swift.print("[持久化验证] 内容片段: \(String(contentToVerify.prefix(200)))...")
            } else {
                Swift.print("[持久化验证] ✅ 音频附件持久化正常 - 笔记ID: \(note.id.prefix(8))...")
            }
        } else {
            Swift.print("[持久化验证] ℹ️ 无音频附件 - 笔记ID: \(note.id.prefix(8))...")
        }
        
        // 如果使用原生编辑器，进行验证
        if isUsingNativeEditor {
            let isValid = await nativeEditorContext.verifyContentPersistence(expectedContent: contentToVerify)
            Swift.print("[持久化验证] 原生编辑器验证结果: \(isValid ? "通过" : "失败")")
        }
    }
    
    /// 使用HTML缓存快速加载笔记
    @MainActor
    private func loadNoteContentWithHTML(note: Note, htmlContent: String) async {
        // 重置状态
        currentXMLContent = ""
        lastSavedXMLContent = ""
        originalXMLContent = ""
        
        // 加载标题
        let title = note.title.isEmpty || note.title.hasPrefix("未命名笔记_") ? "" : note.title
        editedTitle = title
        originalTitle = title
        
        // 使用 XML 内容初始化编辑器
        // 暂时使用 primaryXMLContent，后台会加载完整内容
        currentXMLContent = note.primaryXMLContent
        // 关键修复：确保 lastSavedXMLContent 与 currentXMLContent 同步
        // _需求: 2.2_
        lastSavedXMLContent = currentXMLContent
        originalXMLContent = currentXMLContent
        Swift.print("[快速切换] 📝 从HTML缓存加载内容，lastSavedXMLContent 已同步 - 长度: \(lastSavedXMLContent.count)")
        
        Swift.print("[快速切换] ✅ 从HTML缓存加载完成 - ID: \(note.id.prefix(8))..., 标题: \(title)")
        
        // 短暂延迟以确保编辑器正确初始化
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        isInitializing = false
    }
    
    /// 异步加载完整内容
    @MainActor
    private func loadFullContentAsync(for note: Note) async {
        // 如果内容为空，确保获取完整内容
        if note.content.isEmpty {
            await viewModel.ensureNoteHasFullContent(note)
            if let updated = viewModel.selectedNote, updated.id == note.id {
                // 更新缓存
                await MemoryCacheManager.shared.cacheNote(updated)
                
                // 更新内容
                currentXMLContent = updated.primaryXMLContent
                // 关键修复：确保 lastSavedXMLContent 与 currentXMLContent 同步
                // _需求: 2.2_
                lastSavedXMLContent = currentXMLContent
                originalXMLContent = currentXMLContent
                Swift.print("[快速切换] 📝 异步加载完整内容，lastSavedXMLContent 已同步 - 长度: \(lastSavedXMLContent.count)")
                
                Swift.print("[快速切换] ✅ 完整内容加载完成 - ID: \(note.id.prefix(8))...")
            }
        } else {
            // 关键修复：确保 lastSavedXMLContent 与 currentXMLContent 同步
            // _需求: 2.2_
            Swift.print("[快速切换] 📝 内容已存在，lastSavedXMLContent 已同步 - 长度: \(lastSavedXMLContent.count)")
            // 更新缓存
            await MemoryCacheManager.shared.cacheNote(note)
        }
    }
    
    @MainActor
    private func loadNoteContent(_ note: Note) async {
        // 关键修复：确保笔记ID匹配
        guard note.id == currentEditingNoteId else {
            Swift.print("[笔记切换] ⚠️ loadNoteContent: 笔记ID不匹配，取消加载 - 传入ID: \(note.id.prefix(8))..., 当前编辑ID: \(currentEditingNoteId?.prefix(8) ?? "nil")")
            return
        }
        
        // 防止内容污染：在加载新笔记前，确保所有状态正确重置
        isInitializing = true
        
        // 0. 取消之前的保存任务（如果存在）
        htmlSaveTask?.cancel()
        xmlSaveTask?.cancel()
        xmlSaveDebounceTask?.cancel()
        htmlSaveTask = nil
        xmlSaveTask = nil
        xmlSaveDebounceTask = nil
        
        // 1. 加载标题（不要重置，因为在 quickSwitchToNote 中已经设置）
        let title = note.title.isEmpty || note.title.hasPrefix("未命名笔记_") ? "" : note.title
        if editedTitle != title {
            editedTitle = title
            originalTitle = title
            Swift.print("[笔记切换] 📝 更新标题: \(title)")
        }
        
        // 2. 加载内容
        // 任务 22.2: 构建包含标题的完整内容
        // 将标题作为第一个段落插入到编辑器中
        var contentToLoad = note.primaryXMLContent
        
        // 3. 如果内容为空，确保获取完整内容
        if note.content.isEmpty {
            Swift.print("[笔记切换] ⚠️ 笔记内容为空，需要获取完整内容")
            
            await viewModel.ensureNoteHasFullContent(note)
            
            // 再次验证笔记ID
            guard note.id == currentEditingNoteId else {
                Swift.print("[笔记切换] ⚠️ 获取完整内容后笔记ID不匹配，取消更新 - 传入ID: \(note.id.prefix(8))..., 当前编辑ID: \(currentEditingNoteId?.prefix(8) ?? "nil")")
                return
            }
            
            if let updated = viewModel.selectedNote, updated.id == note.id {
                Swift.print("[笔记切换] ✅ 获取完整内容后更新 - 内容长度: \(updated.content.count)")
                contentToLoad = updated.primaryXMLContent
                
                // 更新缓存
                await MemoryCacheManager.shared.cacheNote(updated)
            } else {
                Swift.print("[笔记切换] ⚠️ selectedNote 不匹配")
            }
        } else {
            // 更新缓存
            await MemoryCacheManager.shared.cacheNote(note)
        }
        
        // 任务 22.2: 如果有标题，将标题插入到内容的开头
        // 标题将作为编辑器的第一个段落显示
        if !title.isEmpty {
            print("[NoteDetailView] 📝 开始处理标题插入")
            print("[NoteDetailView]   - 标题: '\(title)'")
            print("[NoteDetailView]   - 原始内容长度: \(contentToLoad.count)")
            print("[NoteDetailView]   - 原始内容前100字符: '\(String(contentToLoad.prefix(100)))'")
            
            // 检查 XML 中是否已经有 <title> 标签
            if !contentToLoad.contains("<title>") {
                print("[NoteDetailView] 📝 XML 中没有 <title> 标签，准备插入")
                
                // 如果没有 <title> 标签，添加一个
                // 将标题插入到内容的最前面（在 <new-format/> 之后）
                let titleTag = "<title>\(encodeXMLEntities(title))</title>"
                print("[NoteDetailView]   - 标题标签: '\(titleTag)'")
                
                if contentToLoad.hasPrefix("<new-format/>") {
                    print("[NoteDetailView] 📝 内容以 <new-format/> 开头，在其后插入标题")
                    // 在 <new-format/> 后插入标题
                    let afterPrefix = String(contentToLoad.dropFirst("<new-format/>".count))
                    contentToLoad = "<new-format/>\(titleTag)\(afterPrefix)"
                } else {
                    print("[NoteDetailView] 📝 内容不以 <new-format/> 开头，直接在开头插入标题")
                    // 直接在开头插入标题
                    contentToLoad = "\(titleTag)\(contentToLoad)"
                }
                
                print("[NoteDetailView] ✅ 标题已插入到 XML 内容开头")
                print("[NoteDetailView]   - 插入后内容长度: \(contentToLoad.count)")
                print("[NoteDetailView]   - 插入后内容前150字符: '\(String(contentToLoad.prefix(150)))'")
            } else {
                print("[NoteDetailView] 📝 XML 中已存在 <title> 标签，跳过插入")
            }
        } else {
            print("[NoteDetailView] 📝 标题为空，不插入 <title> 标签")
        }
        
        currentXMLContent = contentToLoad
        // 关键修复：确保 lastSavedXMLContent 与 currentXMLContent 同步
        // _需求: 2.2_
        lastSavedXMLContent = currentXMLContent
        originalXMLContent = currentXMLContent
        Swift.print("[笔记切换] 📝 初始加载内容（包含标题），lastSavedXMLContent 已同步 - 长度: \(lastSavedXMLContent.count)")
        Swift.print("[笔记切换] 📝 currentXMLContent 前200字符: '\(String(currentXMLContent.prefix(200)))'")
        
        // 关键修复：立即调用 loadFromXML 确保编辑器内容同步
        // 这解决了笔记切换时内容丢失的问题
        if isUsingNativeEditor {
            Swift.print("[笔记切换] 🔄 立即加载内容到原生编辑器")
            nativeEditorContext.loadFromXML(currentXMLContent)
            Swift.print("[笔记切换] ✅ 原生编辑器内容已加载 - nsAttributedText.length: \(nativeEditorContext.nsAttributedText.length)")
        }
        
        // 调试模式：同步内容到调试编辑器
        // _Requirements: 6.4_
        if isDebugMode {
            debugXMLContent = currentXMLContent
            debugSaveStatus = DebugSaveStatus.saved
            Swift.print("[笔记切换] 🔧 调试模式内容已同步 - 长度: \(debugXMLContent.count)")
        }
        
        // 4. 添加日志以便调试
        Swift.print("[笔记切换] ✅ 加载笔记内容 - ID: \(note.id.prefix(8))..., 标题: \(title), 内容长度: \(currentXMLContent.count)")
        
        // 5. 短暂延迟以确保编辑器正确初始化
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // 再次验证笔记ID（防止在延迟期间切换了笔记）
        guard note.id == currentEditingNoteId else {
            Swift.print("[笔记切换] ⚠️ 延迟后笔记ID不匹配，取消显示 - 传入ID: \(note.id.prefix(8))..., 当前编辑ID: \(currentEditingNoteId?.prefix(8) ?? "nil")")
            return
        }
        
        isInitializing = false
    }
    
    /// 编码 XML 实体
    /// 
    /// 将特殊字符转换为 XML 实体，以便安全地嵌入 XML 中
    /// 
    /// - Parameter text: 原始文本
    /// - Returns: 编码后的文本
    private func encodeXMLEntities(_ text: String) -> String {
        var result = text
        
        // 必须首先处理 &，避免重复编码
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&apos;")
        
        return result
    }
    
    @MainActor
    private func handleNoteChange(_ newValue: Note) async {
        let task = saveCurrentNoteBeforeSwitching(newNoteId: newValue.id)
        if let t = task { await t.value }
        await quickSwitchToNote(newValue)
    }
    
    @MainActor
    private func handleTitleChange(_ newValue: String) async {
        guard !isInitializing && newValue != originalTitle else { return }
        
        originalTitle = newValue
        await performTitleChangeSave(newTitle: newValue)
    }
    
    @MainActor
    private func performTitleChangeSave(newTitle: String) async {
        guard let note = viewModel.selectedNote, note.id == currentEditingNoteId else { return }
        if isSavingLocally {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if isSavingLocally { return }
        }
        isSavingLocally = true
        defer { isSavingLocally = false }
        let xmlContent = currentXMLContent.isEmpty ? note.primaryXMLContent : currentXMLContent
        let original = note.primaryXMLContent
        if original.count > 300 && xmlContent.count < 150 && xmlContent.count < original.count / 2 {
            Swift.print("[保存流程] 内容丢失保护触发")
            await saveTitleAndContent(title: newTitle, xmlContent: original, for: note)
        } else {
            await saveTitleAndContent(title: newTitle, xmlContent: xmlContent, for: note)
        }
    }
    
    @MainActor
    private func saveTitleAndContent(title: String, xmlContent: String, for note: Note) async {
        // 使用改进的内容变化检测
        // _需求: 1.3, 2.4_
        let hasActualChange = hasContentActuallyChanged(
            currentContent: xmlContent,
            savedContent: lastSavedXMLContent,
            currentTitle: title,
            originalTitle: originalTitle
        )
        
        // 只有在内容或标题真正变化时才更新时间戳
        let shouldUpdateTimestamp = hasActualChange
        
        // 使用 buildUpdatedNote 方法构建更新的笔记对象
        // 临时设置 editedTitle 以便 buildUpdatedNote 使用正确的标题
        let previousEditedTitle = editedTitle
        editedTitle = title
        var updated = buildUpdatedNote(from: note, xmlContent: xmlContent, shouldUpdateTimestamp: shouldUpdateTimestamp)
        editedTitle = previousEditedTitle
        
        Swift.print("[保存流程] 📝 saveTitleAndContent - 内容变化: \(hasActualChange), 更新时间戳: \(shouldUpdateTimestamp)")
        
        // 注意：Note模型中没有htmlContent属性，HTML缓存由DatabaseService单独管理
        
        // 使用异步保存
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DatabaseService.shared.saveNoteAsync(updated) { error in
                Task { @MainActor in
                    if let error = error {
                        Swift.print("[保存流程] ❌ 标题和内容保存失败: \(error)")
                        continuation.resume()
                        return
                    }
                    
                    // 关键修复：确保 lastSavedXMLContent 与 currentXMLContent 同步
                    // _需求: 2.2_
                    self.lastSavedXMLContent = xmlContent
                    self.originalTitle = title
                    self.currentXMLContent = xmlContent
                    Swift.print("[保存流程] 📝 标题和内容保存成功，lastSavedXMLContent 已同步 - 长度: \(self.lastSavedXMLContent.count)")
                    // 更新笔记列表和选中的笔记
                    if let index = self.viewModel.notes.firstIndex(where: { $0.id == updated.id }) {
                        self.viewModel.notes[index] = updated
                    }
                    if self.viewModel.selectedNote?.id == updated.id {
                        self.viewModel.selectedNote = updated
                        
                        // 通过 coordinator 更新笔记内容，保持选择状态不变 
                        self.viewModel.stateCoordinator.updateNoteContent(updated)
                    }
                    self.scheduleCloudUpload(for: updated, xmlContent: xmlContent)
                    continuation.resume()
                }
            }
        }
    }
    
    /// 立即更新内存缓存（Tier 0）
    /// 
    /// 无延迟更新内存中的笔记对象，实现即时保存
    /// 
    /// - Parameters:
    ///   - xmlContent: XML内容
    ///   - htmlContent: HTML内容
    ///   - note: 笔记对象
    /// 
    /// _Requirements: 6.1_ - 内容变化时设置为 unsaved 状态
    @MainActor
    private func updateMemoryCache(xmlContent: String, htmlContent: String?, for note: Note) async {
        // 关键修复：确保只有当前编辑的笔记才会被更新
        guard note.id == currentEditingNoteId else {
            Swift.print("[保存流程] ⚠️ updateMemoryCache: 笔记ID不匹配，忽略更新 - 传入ID: \(note.id.prefix(8))..., 当前编辑ID: \(currentEditingNoteId?.prefix(8) ?? "nil")")
            return
        }
        
        // 关键修复：确保使用传入的note的标题，而不是editedTitle（editedTitle可能在切换笔记后已改变）
        // 只有在当前编辑的笔记才使用editedTitle
        let titleToUse: String
        if note.id == currentEditingNoteId {
            titleToUse = editedTitle
        } else {
            titleToUse = note.title
        }
        
        // 构建更新的笔记对象（保留所有字段）
        var updated = Note(
            id: note.id,
            title: titleToUse,
            content: xmlContent,
            folderId: note.folderId,
            isStarred: note.isStarred,
            createdAt: note.createdAt,
            updatedAt: Date(),
            tags: note.tags,
            rawData: note.rawData,
            snippet: note.snippet,
            colorId: note.colorId,
            subject: note.subject,
            alertDate: note.alertDate,
            type: note.type,
            serverTag: note.serverTag,
            status: note.status,
            settingJson: note.settingJson,
            extraInfoJson: note.extraInfoJson
        )
        // 注意：Note模型中没有htmlContent属性，HTML缓存由DatabaseService单独管理
        
        // 立即更新内存缓存（<1ms）
        await MemoryCacheManager.shared.cacheNote(updated)
        
        // 更新viewModel.notes数组（不更新selectedNote，避免闪烁）
        if let index = viewModel.notes.firstIndex(where: { $0.id == updated.id }) {
            viewModel.notes[index] = updated
        }
        
        // _Requirements: 6.1_ - 内容变化时设置为 unsaved 状态
        // 只有在当前状态不是 saving 时才更新为 unsaved
        if case .saving = saveStatus {
            // 保持 saving 状态，不覆盖
            Swift.print("[保存状态] ⏳ 保持保存中状态")
        } else {
            saveStatus = .unsaved
            Swift.print("[保存状态] 📝 内容变化 - 设置为未保存")
        }
        
        // 标记 coordinator 有未保存的内容 
        // - 6.1: 切换文件夹时检查是否有未保存内容
        viewModel.stateCoordinator.hasUnsavedContent = true
        
        Swift.print("[保存流程] ✅ Tier 0 内存缓存更新 - 笔记ID: \(note.id.prefix(8))..., XML长度: \(xmlContent.count)")
    }
    
    @MainActor
    private func flashSaveHTML(_ html: String, for note: Note) {
        // [Tier 0] 极速 HTML 缓存保存 - 异步执行，不阻塞UI
        
        // 取消之前的HTML保存任务（如果存在）
        htmlSaveTask?.cancel()
        
        // 检查当前列表中的笔记是否已经有相同的HTML内容
        if let index = viewModel.notes.firstIndex(where: { $0.id == note.id }) {
            let currentNote = viewModel.notes[index]
            // 检查HTML内容是否变化（注意：DatabaseService中没有HTML缓存方法）
            // 直接保存HTML内容
            Swift.print("[保存流程] 🔄 Tier 0 HTML缓存保存 - 内容变化")
        }
        
        // 注意：DatabaseService中没有HTML缓存方法
        // HTML缓存功能已移除，直接跳过HTML缓存保存
        Swift.print("[保存流程] ⏭️ Tier 0 HTML缓存跳过 - DatabaseService中没有HTML缓存方法")
    }

    /// 计划XML保存（带防抖）
    /// 
    /// - Parameters:
    ///   - xmlContent: XML内容
    ///   - note: 笔记对象
    ///   - extractedTitle: 提取的标题结果（可选）
    ///   - immediate: 是否立即保存（切换笔记时使用），默认false（防抖保存）
    /// 
    /// _Requirements: 6.2_ - 保存中显示"保存中..."状态
    @MainActor
    private func scheduleXMLSave(xmlContent: String, for note: Note, extractedTitle: TitleExtractionResult? = nil, immediate: Bool = false) {
        // 检查是否是当前编辑的笔记
        guard note.id == currentEditingNoteId else {
            Swift.print("[保存流程] ⏭️ Tier 1 跳过 - 不是当前编辑笔记，ID: \(note.id.prefix(8))..., currentEditingNoteId: \(currentEditingNoteId?.prefix(8) ?? "nil")")
            return
        }
        
        // 取消之前的防抖任务
        xmlSaveDebounceTask?.cancel()
        
        let noteId = note.id
        
        if immediate {
            // 立即保存（切换笔记时）
            // 使用改进的内容变化检测
            // _需求: 1.3, 2.4_
            let hasActualChange = hasContentActuallyChanged(
                currentContent: xmlContent,
                savedContent: lastSavedXMLContent,
                currentTitle: editedTitle,
                originalTitle: originalTitle
            )
            guard hasActualChange else {
                Swift.print("[保存流程] ⏭️ Tier 1 立即保存跳过 - 内容无实际变化")
                if case .unsaved = saveStatus {
                    saveStatus = .saved
                }
                return
            }
            Swift.print("[保存流程] 🔄 Tier 1 立即保存 - 笔记ID: \(noteId.prefix(8))..., XML长度: \(xmlContent.count)")
            performXMLSave(xmlContent: xmlContent, for: note, extractedTitle: extractedTitle)
        } else {
            // 防抖保存（正常编辑时）
            // _Requirements: 6.1_ - 内容未保存时显示"未保存"状态
            // 关键修复：在防抖期间显示"未保存"状态，而不是"保存中"
            // 这样用户知道内容还没有被保存
            if case .saved = saveStatus {
                saveStatus = .unsaved
                Swift.print("[保存状态] 📝 内容变化 - 设置为未保存")
            }
            
            xmlSaveDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: xmlSaveDebounceDelay)
                
                // 检查任务是否被取消或笔记已切换
                guard !Task.isCancelled && self.currentEditingNoteId == noteId else {
                    Swift.print("[保存流程] ⏸️ Tier 1 防抖保存已取消")
                    return
                }
                
                // 关键修复：获取最新的内容进行保存
                // 而不是使用防抖任务创建时捕获的旧内容
                var latestXMLContent = xmlContent
                
                // 如果使用原生编辑器，从 nativeEditorContext 获取最新内容
                if self.isUsingNativeEditor {
                    let exportedXML = self.nativeEditorContext.exportToXML()
                    if !exportedXML.isEmpty {
                        latestXMLContent = exportedXML
                        Swift.print("[保存流程] 📝 使用原生编辑器最新内容 - 长度: \(latestXMLContent.count)")
                    }
                }
                
                // 使用改进的内容变化检测
                // _需求: 1.3, 2.4_
                let hasActualChange = self.hasContentActuallyChanged(
                    currentContent: latestXMLContent,
                    savedContent: self.lastSavedXMLContent,
                    currentTitle: self.editedTitle,
                    originalTitle: self.originalTitle
                )
                guard hasActualChange else {
                    Swift.print("[保存流程] ⏭️ Tier 1 防抖保存跳过 - 内容无实际变化")
                    // 如果内容无实际变化，设置为已保存
                    self.saveStatus = .saved
                    return
                }
                
                Swift.print("[保存流程] 🔄 Tier 1 防抖保存触发 - 笔记ID: \(noteId.prefix(8))..., XML长度: \(latestXMLContent.count)")
                self.performXMLSave(xmlContent: latestXMLContent, for: note, extractedTitle: extractedTitle)
            }
        }
    }
    
    /// 执行XML保存
    /// 
    /// _Requirements: 6.2_ - 保存中显示"保存中..."状态
    /// _Requirements: 6.3_ - 保存完成显示"已保存"状态
    /// _Requirements: 6.4_ - 保存失败显示"保存失败"状态
    /// _Requirements: 2.5, 9.1_ - 保存失败时保留编辑内容在内存中
    @MainActor
    private func performXMLSave(xmlContent: String, for note: Note, extractedTitle: TitleExtractionResult? = nil) {
        // 任务 4.3: 集成 SavePipelineCoordinator
        // _需求: 1.2, 3.1_ - 确保使用新的保存流程
        
        // 取消之前的保存任务
        xmlSaveTask?.cancel()
        
        let noteId = note.id
        
        // _Requirements: 6.2_ - 保存中显示"保存中..."状态
        saveStatus = .saving
        Swift.print("[保存状态] ⏳ 开始保存 - 设置为保存中")
        
        // _Requirements: 2.5, 9.1_ - 保存前备份内容
        if isUsingNativeEditor {
            nativeEditorContext.backupCurrentContent()
        }
        
        xmlSaveTask = Task { @MainActor in
            // 检查任务是否被取消或笔记已切换
            guard !Task.isCancelled && self.currentEditingNoteId == noteId else {
                Swift.print("[保存流程] ⏸️ Tier 1 XML保存已取消")
                return
            }
            
            do {
                // 使用 SavePipelineCoordinator 执行完整的保存流程
                // _需求: 1.2, 3.1_ - 确保正确的执行顺序
                let textStorage = self.isUsingNativeEditor ? NSTextStorage(attributedString: self.nativeEditorContext.nsAttributedText) : nil
                
                let result = try await self.savePipelineCoordinator.executeSavePipeline(
                    xmlContent: xmlContent,
                    textStorage: textStorage,
                    noteId: noteId
                ) { noteId, title, content in
                    // API 保存处理器
                    // 构建更新的笔记对象，使用 SavePipelineCoordinator 提取的标题
                    let titleResult = TitleExtractionResult(
                        title: title,
                        source: textStorage != nil ? .nativeEditor : .xml,
                        isValid: true,
                        extractionTime: Date(),
                        originalLength: xmlContent.count,
                        processedLength: content.count
                    )
                    
                    let updated = self.buildUpdatedNote(from: note, xmlContent: xmlContent, extractedTitle: titleResult)
                    
                    // 使用 NoteOperationCoordinator 进行保存
                    let saveResult = await NoteOperationCoordinator.shared.saveNote(updated)
                    
                    switch saveResult {
                    case .success:
                        // 保存成功，更新本地状态
                        await self.handleSaveSuccess(xmlContent: xmlContent, noteId: noteId, updatedNote: updated)
                    case .failure(let error):
                        throw error
                    }
                }
                
                Swift.print("[保存流程] ✅ SavePipelineCoordinator 保存成功 - 标题: '\(result.extractedTitle)', 耗时: \(String(format: "%.2f", result.executionTime))秒")
                
            } catch {
                // 检查任务是否被取消或笔记已切换
                guard !Task.isCancelled && self.currentEditingNoteId == noteId else {
                    Swift.print("[保存流程] ⏸️ Tier 1 XML保存已取消（错误处理）")
                    return
                }
                
                Swift.print("[保存流程] ❌ SavePipelineCoordinator 保存失败: \(error)")
                
                // 处理保存失败
                await self.handleSaveFailure(error: error, xmlContent: xmlContent, note: note)
            }
        }
    }
    
    /// 处理保存成功
    /// 
    /// _需求: 6.3_ - 保存完成显示"已保存"状态
    @MainActor
    private func handleSaveSuccess(xmlContent: String, noteId: String, updatedNote: Note) async {
        // 关键修复：确保 lastSavedXMLContent 与 currentXMLContent 同步
        // _需求: 2.2_
        self.lastSavedXMLContent = xmlContent
        self.currentXMLContent = xmlContent
        Swift.print("[保存流程] 📝 XML保存成功，lastSavedXMLContent 已同步 - 长度: \(self.lastSavedXMLContent.count)")
        
        // 清除重试状态
        self.pendingRetryXMLContent = nil
        self.pendingRetryNote = nil
        
        // 更新视图模型中的笔记 
        let oldSelectedNoteId = self.viewModel.selectedNote?.id
        Swift.print("[保存流程] 🔄 更新 notes 数组 - 笔记ID: \(noteId.prefix(8))..., 当前选中: \(oldSelectedNoteId?.prefix(8) ?? "nil")")
        
        if let index = self.viewModel.notes.firstIndex(where: { $0.id == noteId }) {
            self.viewModel.notes[index] = updatedNote
            Swift.print("[保存流程] ✅ notes[\(index)] 已更新")
        }
        
        // 同步更新 selectedNote（如果当前选中的是这个笔记）
        if self.viewModel.selectedNote?.id == noteId {
            self.viewModel.selectedNote = updatedNote
            Swift.print("[保存流程] ✅ selectedNote 已同步更新")
        }
        
        let newSelectedNoteId = self.viewModel.selectedNote?.id
        Swift.print("[保存流程] 📊 更新后选中状态: \(newSelectedNoteId?.prefix(8) ?? "nil")")
        
        // 更新内存缓存
        await MemoryCacheManager.shared.cacheNote(updatedNote)
        
        // _Requirements: 6.3_ - 保存完成显示"已保存"状态
        self.saveStatus = .saved
        Swift.print("[保存状态] ✅ 保存完成 - 设置为已保存")
        
        // 清除 coordinator 的未保存内容标志 
        self.viewModel.stateCoordinator.hasUnsavedContent = false
        
        // 通知原生编辑器内容已保存
        if self.isUsingNativeEditor {
            self.nativeEditorContext.markContentSaved()
        }
        
        Swift.print("[保存流程] ✅ Tier 1 本地保存成功 - 笔记ID: \(noteId.prefix(8))..., 标题: \(self.editedTitle)")
    }
    
    /// 处理保存失败
    /// 
    /// _需求: 6.4_ - 保存失败显示"保存失败"状态
    /// _需求: 2.5, 9.1_ - 保存失败时保留编辑内容
    @MainActor
    private func handleSaveFailure(error: Error, xmlContent: String, note: Note) async {
        // _Requirements: 6.4_ - 保存失败显示"保存失败"状态
        let errorMessage = "保存笔记失败: \(error.localizedDescription)"
        self.saveStatus = .error(errorMessage)
        Swift.print("[保存状态] ❌ 保存失败 - 设置为错误状态")
        
        // _Requirements: 2.5, 9.1_ - 保存失败时保留编辑内容
        // 标记保存失败，保留内容在内存中
        if self.isUsingNativeEditor {
            self.nativeEditorContext.markSaveFailed(error: errorMessage)
        }
        // 保存失败的 XML 内容到状态变量，用于重试
        self.pendingRetryXMLContent = xmlContent
        self.pendingRetryNote = note
    }
    
    /// 重试保存操作
    /// 
    /// 当保存失败后，用户可以点击重试按钮重新尝试保存
    /// 
    /// _Requirements: 2.5, 9.1_ - 提供重试选项
    @MainActor
    private func retrySave() {
        Swift.print("[保存流程] 🔄 用户触发重试保存")
        
        // 获取待重试的内容和笔记
        guard let xmlContent = pendingRetryXMLContent,
              let note = pendingRetryNote ?? viewModel.selectedNote else {
            Swift.print("[保存流程] ⚠️ 重试失败 - 无待重试内容或笔记")
            return
        }
        
        // 如果使用原生编辑器，尝试从备份获取内容
        var contentToSave = xmlContent
        if isUsingNativeEditor {
            let backupContent = nativeEditorContext.getContentForRetry()
            if backupContent.length > 0 {
                // 使用安全转换方法，确保即使转换失败也能保存纯文本
                contentToSave = XiaoMiFormatConverter.shared.safeNSAttributedStringToXML(backupContent)
                Swift.print("[保存流程] 📝 使用备份内容进行重试 - 长度: \(contentToSave.count)")
            }
        }
        
        Swift.print("[保存流程] 🔄 开始重试保存 - 笔记ID: \(note.id.prefix(8))..., 内容长度: \(contentToSave.count)")
        
        // 执行保存
        performXMLSave(xmlContent: contentToSave, for: note)
    }
    
    /// 保存XML内容（兼容旧接口）
    @MainActor
    private func saveToLocalOnlyWithContent(xmlContent: String, for note: Note) async {
        scheduleXMLSave(xmlContent: xmlContent, for: note, immediate: true)
        // 等待保存完成
        await xmlSaveTask?.value
    }
    
    @MainActor
    private func performSaveImmediately() async {
        guard let note = viewModel.selectedNote else { return }
        let content = await getLatestContentFromEditor()
        await saveToLocalOnlyWithContent(xmlContent: content, for: note)
        scheduleCloudUpload(for: note, xmlContent: content)
    }
    
    @State private var cloudUploadTask: Task<Void, Never>? = nil
    /// 每个笔记的最后上传内容（按笔记 ID 存储）
    @State private var lastUploadedContentByNoteId: [String: String] = [:]
    
    private func scheduleCloudUpload(for note: Note, xmlContent: String) {
        // _Requirements: 4.1_ - 网络不可用时将编辑操作加入离线队列
        guard viewModel.isOnline && viewModel.isLoggedIn else {
            // 网络不可用或未登录时，将操作添加到离线队列
            queueOfflineUpdateOperation(for: note, xmlContent: xmlContent)
            return
        }
        
        // 关键修复：使用笔记 ID 作为 key 来存储每个笔记的最后上传内容
        // 这样可以避免不同笔记之间的内容比较混淆
        let lastUploadedForThisNote = lastUploadedContentByNoteId[note.id] ?? ""
        guard xmlContent != lastUploadedForThisNote else {
            Swift.print("[保存流程] ⏭️ Tier 2 跳过 - 内容与上次上传相同，笔记ID: \(note.id.prefix(8))...")
            return
        }
        
        cloudUploadTask?.cancel()
        let noteId = note.id
        
        // 关键修复：在闭包中捕获 xmlContent，但在执行时使用 currentXMLContent
        // 这样可以确保上传的是最新的内容
        cloudUploadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled && self.currentEditingNoteId == noteId else { return }
            
            // 关键修复：使用当前最新的 XML 内容，而不是闭包捕获的旧内容
            // 因为在 3 秒延迟期间，用户可能继续编辑了内容
            let latestXMLContent = self.currentXMLContent.isEmpty ? xmlContent : self.currentXMLContent
            
            // 再次检查内容是否与上次上传相同
            let lastUploaded = self.lastUploadedContentByNoteId[noteId] ?? ""
            guard latestXMLContent != lastUploaded else {
                Swift.print("[保存流程] ⏭️ Tier 2 跳过（延迟后检查）- 内容与上次上传相同，笔记ID: \(noteId.prefix(8))...")
                return
            }
            
            // 再次检查网络状态（3秒延迟期间可能变化）
            // _Requirements: 4.1_ - 网络不可用时将编辑操作加入离线队列
            guard self.viewModel.isOnline && self.viewModel.isLoggedIn else {
                self.queueOfflineUpdateOperation(for: note, xmlContent: latestXMLContent)
                return
            }
            
            await performCloudUpload(for: note, xmlContent: latestXMLContent)
            self.lastUploadedContentByNoteId[noteId] = latestXMLContent
        }
    }
    
    /// 将更新操作添加到离线队列
    /// 
    /// 当网络不可用时，将编辑操作保存到离线队列，等待网络恢复后同步
    /// 
    /// _Requirements: 4.1_ - 网络不可用时将编辑操作加入离线队列
    /// _Requirements: 4.2_ - 离线队列中有待处理操作时在 UI 中显示待同步状态
    @MainActor
    private func queueOfflineUpdateOperation(for note: Note, xmlContent: String) {
        Swift.print("[离线队列] 📥 网络不可用，将操作添加到离线队列 - 笔记ID: \(note.id.prefix(8))...")
        
        // 构建操作数据
        let dataDict: [String: Any] = [
            "title": editedTitle.isEmpty ? note.title : editedTitle,
            "content": xmlContent,
            "folderId": note.folderId,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        do {
            // 将字典编码为 Data
            let jsonData = try JSONSerialization.data(withJSONObject: dataDict, options: [])
            
            // 使用新的 UnifiedOperationQueue 创建操作
            let operation = NoteOperation(
                type: .cloudUpload,
                noteId: note.id,
                data: jsonData,
                localSaveTimestamp: Date()
            )
            try UnifiedOperationQueue.shared.enqueue(operation)
            Swift.print("[离线队列] ✅ 操作已添加到统一操作队列 - 笔记ID: \(note.id.prefix(8))...")
            
            // 更新最后上传内容记录（避免重复添加）
            lastUploadedContentByNoteId[note.id] = xmlContent
            
        } catch {
            Swift.print("[离线队列] ❌ 添加操作到统一操作队列失败: \(error)")
        }
    }
    
    @MainActor
    private func performCloudUpload(for note: Note, xmlContent: String) async {
        // 关键修复：确保使用传入的 xmlContent 构建笔记，而不是依赖 note.content
        // 因为 note 对象可能是旧的（闭包捕获的）
        let updated = buildUpdatedNote(from: note, xmlContent: xmlContent)
        isUploading = true
        
        // 添加详细日志，帮助调试上传内容问题
        Swift.print("[保存流程] 🔄 Tier 2 开始云端同步")
        Swift.print("[保存流程]   - 笔记ID: \(note.id.prefix(8))...")
        Swift.print("[保存流程]   - 标题: \(updated.title)")
        Swift.print("[保存流程]   - XML长度: \(xmlContent.count)")
        Swift.print("[保存流程]   - 内容预览: \(String(xmlContent.prefix(200)))...")
        
        do {
            try await viewModel.updateNote(updated)
            withAnimation { showSaveSuccess = true; isUploading = false }
            Swift.print("[保存流程] ✅ Tier 2 云端同步成功 - 笔记ID: \(note.id.prefix(8))..., 标题: \(editedTitle)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { showSaveSuccess = false } }
        } catch { 
            isUploading = false
            Swift.print("[保存流程] ❌ Tier 2 云端同步失败: \(error)")
            
            // _Requirements: 3.4, 4.1_ - 云端同步失败时将操作加入离线队列
            // 检查是否是网络相关错误
            if isNetworkRelatedError(error) {
                queueOfflineUpdateOperation(for: note, xmlContent: xmlContent)
            }
        }
    }
    
    /// 判断错误是否是网络相关错误
    /// 
    /// 用于决定是否将失败的操作添加到离线队列
    private func isNetworkRelatedError(_ error: Error) -> Bool {
        // 检查 MiNoteError
        if let miNoteError = error as? MiNoteError {
            switch miNoteError {
            case .networkError:
                return true
            case .cookieExpired, .notAuthenticated:
                return true // Cookie 过期也视为需要离线处理
            case .invalidResponse:
                return false // 无效响应可能是服务器问题，不一定需要离线处理
            }
        }
        
        // 检查 NSError
        if let nsError = error as NSError? {
            // 网络相关错误域
            if nsError.domain == NSURLErrorDomain {
                return true
            }
            // 服务器错误（5xx）
            if nsError.code >= 500 && nsError.code < 600 {
                return true
            }
        }
        
        return false
    }
    
    /// _需求: 3.5_
    private func saveCurrentNoteBeforeSwitching(newNoteId: String) -> Task<Void, Never>? {
        guard let currentId = currentEditingNoteId, currentId != newNoteId else { 
            Swift.print("[笔记切换] ⏭️ 无需保存 - 无当前编辑笔记或笔记ID相同")
            return nil 
        }
        
        // 关键修复：在方法开始时保存当前编辑的笔记引用
        // 因为viewModel.selectedNote可能在切换时已经更新为新笔记
        guard let currentNote = viewModel.notes.first(where: { $0.id == currentId }) else {
            Swift.print("[笔记切换] ⚠️ 无法找到当前编辑的笔记 - ID: \(currentId.prefix(8))...")
            return nil
        }
        
        Swift.print("[笔记切换] 💾 保存当前笔记 - ID: \(currentId.prefix(8))..., 标题: \(currentNote.title)")
        
        // 关键修复：在切换前立即捕获当前编辑的标题和内容
        // 这样即使后续状态变化，我们仍然有正确的数据
        let capturedTitle = editedTitle
        let capturedOriginalTitle = originalTitle
        let capturedLastSavedXMLContent = lastSavedXMLContent
        
        // 关键修复：立即获取原生编辑器的内容（在切换前）
        // 这是同步操作，确保在切换笔记前捕获到最新内容
        var capturedContent: String = ""
        if isUsingNativeEditor {
            capturedContent = nativeEditorContext.exportToXML()
            Swift.print("[笔记切换] 📝 立即捕获原生编辑器内容 - 长度: \(capturedContent.count)")
            
            // 如果导出为空，使用 currentXMLContent
            if capturedContent.isEmpty && !currentXMLContent.isEmpty {
                capturedContent = currentXMLContent
                Swift.print("[笔记切换] 📝 使用 currentXMLContent - 长度: \(capturedContent.count)")
            }
        }
        
        // 增强日志：记录笔记切换保存的详细信息
        // _需求: 3.3_
        Swift.print("[笔记切换] ═══════════════════════════════════════")
        Swift.print("[笔记切换] 🔄 开始保存当前笔记")
        Swift.print("[笔记切换] 📝 从笔记ID: \(currentId.prefix(8))... 切换到: \(newNoteId.prefix(8))...")
        Swift.print("[笔记切换] 📝 捕获的标题: \(capturedTitle)")
        Swift.print("[笔记切换] 📝 原始标题: \(capturedOriginalTitle)")
        Swift.print("[笔记切换] 📏 捕获的内容长度: \(capturedContent.count)")
        Swift.print("[笔记切换] 📏 lastSavedXMLContent 长度: \(capturedLastSavedXMLContent.count)")
        Swift.print("[笔记切换] ═══════════════════════════════════════")
        isSavingBeforeSwitch = true
        
        // 关键修复：不等待保存完成，立即返回 nil 让界面切换
        // 保存在后台异步进行
        Task { @MainActor in
            // 性能监控：记录后台保存开始时间
            // _需求: 3.5_
            let taskStartTime = CFAbsoluteTimeGetCurrent()
            
            defer { isSavingBeforeSwitch = false }
            
            // 1. 使用捕获的内容
            let content: String = capturedContent
            
            Swift.print("[笔记切换] 📝 后台保存内容 - 长度: \(content.count)")
            
            // 2. 使用改进的内容变化检测
            // _需求: 3.1, 3.2_
            let hasActualChange = hasContentActuallyChanged(
                currentContent: content,
                savedContent: capturedLastSavedXMLContent,
                currentTitle: capturedTitle,
                originalTitle: capturedOriginalTitle
            )
            
            if hasActualChange {
                Swift.print("[笔记切换] 💾 后台保存 - 检测到实际内容变化")
                
                // 构建更新的笔记对象，更新时间戳
                // _需求: 3.3, 3.4_
                let updated = buildUpdatedNote(from: currentNote, xmlContent: content, shouldUpdateTimestamp: true)
                
                // 立即更新内存缓存（不阻塞）
                await MemoryCacheManager.shared.cacheNote(updated)
                
                // 更新视图模型中的笔记（不阻塞）
                if let index = self.viewModel.notes.firstIndex(where: { $0.id == updated.id }) {
                    self.viewModel.notes[index] = updated
                }
                
                // 后台异步保存到数据库
                DatabaseService.shared.saveNoteAsync(updated) { error in
                    Task { @MainActor in
                        if let error = error {
                            Swift.print("[笔记切换] ❌ 后台保存失败: \(error)")
                        } else {
                            Swift.print("[笔记切换] ✅ 后台保存成功 - 笔记ID: \(currentId.prefix(8))...")
                            
                            // 调度云端同步（后台执行）
                            self.scheduleCloudUpload(for: updated, xmlContent: content)
                        }
                    }
                }
            } else {
                Swift.print("[笔记切换] ⏭️ 内容无实际变化，跳过保存")
            }
            
            // 性能监控：记录后台保存完成时间
            // _需求: 3.5_
            let totalDuration = (CFAbsoluteTimeGetCurrent() - taskStartTime) * 1000
            Swift.print("[性能监控] ═══════════════════════════════════════")
            Swift.print("[性能监控] ⏱️ 笔记切换后台保存总耗时: \(String(format: "%.2f", totalDuration))ms")
            Swift.print("[性能监控] 📊 保存决策: \(hasActualChange ? "执行保存" : "跳过保存")")
            if totalDuration > 100 {
                Swift.print("[性能监控] ⚠️ 警告: 后台保存耗时超过 100ms，可能影响用户体验")
            } else {
                Swift.print("[性能监控] ✅ 后台保存性能正常")
            }
            Swift.print("[性能监控] ═══════════════════════════════════════")
        }
        
        // 关键修复：返回 nil，不阻塞界面切换
        // 保存在后台异步进行
        return nil
    }
    
    private func handleSelectedNoteChange(oldValue: Note?, newValue: Note?) {
        guard let newNote = newValue else { return }
        if oldValue?.id != newNote.id {
            let task = saveCurrentNoteBeforeSwitching(newNoteId: newNote.id)
            Task { @MainActor in
                if let t = task { await t.value }
                await quickSwitchToNote(newNote)
            }
        }
    }
    
    @MainActor
    private func getLatestContentFromEditor() async -> String {
        // 从原生编辑器获取内容
        if isUsingNativeEditor {
            // 原生编辑器：从 nativeEditorContext 导出 XML
            let xmlContent = nativeEditorContext.exportToXML()
            if !xmlContent.isEmpty {
                Swift.print("[保存流程] 📝 从原生编辑器获取内容 - 长度: \(xmlContent.count)")
                return xmlContent
            }
        }
        
        // 回退到当前 XML 内容
        Swift.print("[保存流程] 📝 使用 currentXMLContent - 长度: \(currentXMLContent.count)")
        return currentXMLContent
    }
    
    /// _需求: 1.5, 3.3_
    private func buildUpdatedNote(from note: Note, xmlContent: String, extractedTitle: TitleExtractionResult? = nil, shouldUpdateTimestamp: Bool = true) -> Note {
        // 任务 4.2: 修改标题使用逻辑，优先使用传入的提取标题
        // _需求: 1.3, 3.2_ - 优先使用传入的提取标题
        let titleToUse: String
        if let extractedTitle = extractedTitle, extractedTitle.isValid && !extractedTitle.title.isEmpty {
            // 优先使用提取的标题
            titleToUse = extractedTitle.title
            Swift.print("[buildUpdatedNote] 📝 使用提取的标题: '\(titleToUse)' (来源: \(extractedTitle.source.displayName))")
        } else if note.id == currentEditingNoteId {
            // 后备方案：使用当前编辑的标题
            titleToUse = editedTitle
            Swift.print("[buildUpdatedNote] 📝 使用编辑的标题: '\(titleToUse)' (后备方案)")
        } else {
            // 最后方案：使用原始标题
            titleToUse = note.title
            Swift.print("[buildUpdatedNote] 📝 使用原始标题: '\(titleToUse)' (最后方案)")
        }
        
        // ✅ 关键修复：移除 XML 中的 <title> 标签
        // 数据库中只存储正文内容，标题单独存储在 Note.title 字段
        let contentWithoutTitle = removeTitleTag(from: xmlContent)
        
        // 关键修复：合并 rawData，确保包含最新的 setting.data（音频/图片元数据）
        // 从 viewModel.selectedNote 获取最新的 rawData，因为音频上传后会更新 setting.data
        var mergedRawData = note.rawData ?? [:]
        if let latestNote = viewModel.selectedNote, latestNote.id == note.id {
            if let latestRawData = latestNote.rawData {
                // 合并 setting.data
                if let latestSetting = latestRawData["setting"] as? [String: Any] {
                    mergedRawData["setting"] = latestSetting
                }
            }
        }
        
        // 根据参数决定是否更新时间戳
        let updatedAt = shouldUpdateTimestamp ? Date() : note.updatedAt
        
        // 增强日志：记录时间戳更新决策过程
        // _需求: 3.3_
        Swift.print("[buildUpdatedNote] ═══════════════════════════════════════")
        Swift.print("[buildUpdatedNote] 📝 笔记ID: \(note.id.prefix(8))...")
        Swift.print("[buildUpdatedNote] 📝 标题: \(titleToUse)")
        Swift.print("[buildUpdatedNote] 📏 原始内容长度: \(xmlContent.count)")
        Swift.print("[buildUpdatedNote] 📏 移除标题后内容长度: \(contentWithoutTitle.count)")
        Swift.print("[buildUpdatedNote] 🕐 shouldUpdateTimestamp: \(shouldUpdateTimestamp)")
        Swift.print("[buildUpdatedNote] 🕐 原始时间戳: \(note.updatedAt)")
        Swift.print("[buildUpdatedNote] 🕐 新时间戳: \(updatedAt)")
        Swift.print("[buildUpdatedNote] 🕐 时间戳决策: \(shouldUpdateTimestamp ? "更新为当前时间" : "保持原始时间戳")")
        Swift.print("[buildUpdatedNote] ═══════════════════════════════════════")
        
        return Note(
            id: note.id,
            title: titleToUse,
            content: contentWithoutTitle,
            folderId: note.folderId,
            isStarred: note.isStarred,
            createdAt: note.createdAt,
            updatedAt: updatedAt,
            tags: note.tags,
            rawData: mergedRawData,
            subject: note.subject, serverTag: note.serverTag,
            settingJson: note.settingJson,
            extraInfoJson: note.extraInfoJson
        )
    }
    
    /// 从 XML 中移除 <title> 标签
    /// 
    /// 数据库中只存储正文内容，标题单独存储在 Note.title 字段
    /// 
    /// - Parameter xml: 包含标题的完整 XML
    /// - Returns: 移除标题后的 XML（只包含正文）
    private func removeTitleTag(from xml: String) -> String {
        // 使用正则表达式移除 <title>...</title> 标签
        // 支持多行标题和特殊字符
        let pattern = "<title>.*?</title>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            Swift.print("[removeTitleTag] ⚠️ 正则表达式创建失败，返回原始内容")
            return xml
        }
        
        let range = NSRange(xml.startIndex..., in: xml)
        let result = regex.stringByReplacingMatches(in: xml, range: range, withTemplate: "")
        
        // 如果移除了标题，记录日志
        if result != xml {
            Swift.print("[removeTitleTag] ✅ 已移除 <title> 标签 - 原始长度: \(xml.count), 移除后长度: \(result.count)")
        }
        
        return result
    }
    
    private func updateViewModelDelayed(with updated: Note) {
        if let index = viewModel.notes.firstIndex(where: { $0.id == updated.id }) {
            viewModel.notes[index] = updated
        }
        if viewModel.selectedNote?.id == updated.id {
            viewModel.selectedNote = updated
            
            // 通过 coordinator 更新笔记内容，保持选择状态不变 
            // - 1.1: 编辑笔记内容时保持选中状态不变
            // - 1.2: 笔记内容保存触发 notes 数组更新时不重置 selectedNote
            // - 1.3: 笔记的 updatedAt 时间戳变化时保持选中笔记的高亮状态
            viewModel.stateCoordinator.updateNoteContent(updated)
        }
    }
    
    private func hasContentChanged(xmlContent: String) -> Bool {
        lastSavedXMLContent != xmlContent || editedTitle != originalTitle
    }
    
    /// 改进的内容变化检测方法
    /// 
    /// 使用标准化的内容比较方法，准确识别内容是否真正发生了变化
    /// 
    /// - Parameters:
    ///   - currentContent: 当前的 XML 内容
    ///   - savedContent: 上次保存的 XML 内容
    ///   - currentTitle: 当前编辑的标题
    ///   - originalTitle: 原始标题
    /// - Returns: 如果内容或标题发生实际变化则返回 true
    /// 
    /// _需求: 2.1, 2.2, 3.3_
    private func hasContentActuallyChanged(currentContent: String, savedContent: String, currentTitle: String, originalTitle: String) -> Bool {
        // 记录检测开始时间（用于性能监控）
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // 使用 XMLNormalizer 进行语义比较
        // _需求: 2.1.2, 2.1.3_
        let normalizedCurrent = XMLNormalizer.shared.normalize(currentContent)
        let normalizedSaved = XMLNormalizer.shared.normalize(savedContent)
        
        let contentChanged = normalizedCurrent != normalizedSaved
        let titleChanged = currentTitle != originalTitle
        
        // 计算检测耗时
        let elapsedTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        // 增强日志：记录详细的内容变化检测信息
        // _需求: 2.1.4, 2.2.1, 2.2.2, 2.2.3, 3.3_
        Swift.print("[内容检测] ═══════════════════════════════════════")
        Swift.print("[内容检测] 📊 检测结果: 内容变化=\(contentChanged), 标题变化=\(titleChanged)")
        Swift.print("[内容检测] 📏 原始内容长度: 当前=\(currentContent.count), 保存=\(savedContent.count)")
        Swift.print("[内容检测] 📏 规范化后长度: 当前=\(normalizedCurrent.count), 保存=\(normalizedSaved.count)")
        Swift.print("[内容检测] ⏱️ 检测耗时: \(String(format: "%.2f", elapsedTime))ms")
        
        if contentChanged {
            // 如果内容长度差异较大，记录更详细的信息
            let originalLengthDiff = abs(currentContent.count - savedContent.count)
            let normalizedLengthDiff = abs(normalizedCurrent.count - normalizedSaved.count)
            
            Swift.print("[内容检测] 📝 原始内容长度差异: \(originalLengthDiff) 字符")
            Swift.print("[内容检测] 📝 规范化后长度差异: \(normalizedLengthDiff) 字符")
            
            if normalizedLengthDiff > 10 {
                Swift.print("[内容检测] ⚠️ 规范化后仍有显著差异，这是实际内容变化")
            } else {
                Swift.print("[内容检测] ℹ️ 规范化后差异较小")
            }
            
            // 如果规范化后内容变化较小，记录完整内容用于调试
            if normalizedLengthDiff <= 50 {
                Swift.print("[内容检测] 🔍 当前内容完整: \(normalizedCurrent)")
                Swift.print("[内容检测] 🔍 保存内容完整: \(normalizedSaved)")
                
                // 找出第一个不同的字符位置
                let minLength = min(normalizedCurrent.count, normalizedSaved.count)
                var firstDiffIndex: Int? = nil
                for i in 0..<minLength {
                    let currentIndex = normalizedCurrent.index(normalizedCurrent.startIndex, offsetBy: i)
                    let savedIndex = normalizedSaved.index(normalizedSaved.startIndex, offsetBy: i)
                    if normalizedCurrent[currentIndex] != normalizedSaved[savedIndex] {
                        firstDiffIndex = i
                        break
                    }
                }
                
                if let diffIndex = firstDiffIndex {
                    Swift.print("[内容检测] 🔍 第一个不同的位置: \(diffIndex)")
                    let contextStart = max(0, diffIndex - 20)
                    let contextEnd = min(minLength, diffIndex + 20)
                    let currentContext = String(normalizedCurrent[normalizedCurrent.index(normalizedCurrent.startIndex, offsetBy: contextStart)..<normalizedCurrent.index(normalizedCurrent.startIndex, offsetBy: contextEnd)])
                    let savedContext = String(normalizedSaved[normalizedSaved.index(normalizedSaved.startIndex, offsetBy: contextStart)..<normalizedSaved.index(normalizedSaved.startIndex, offsetBy: contextEnd)])
                    Swift.print("[内容检测] 🔍 当前内容上下文: \(currentContext)")
                    Swift.print("[内容检测] 🔍 保存内容上下文: \(savedContext)")
                } else if normalizedCurrent.count != normalizedSaved.count {
                    Swift.print("[内容检测] 🔍 内容长度不同，较短的内容是另一个的前缀")
                }
            }
        } else {
            Swift.print("[内容检测] ✅ 内容无变化（规范化后相同）")
            
            // 如果原始内容不同但规范化后相同，说明只是格式差异
            if currentContent != savedContent {
                let originalLengthDiff = abs(currentContent.count - savedContent.count)
                Swift.print("[内容检测] ℹ️ 原始内容有差异（\(originalLengthDiff) 字符），但规范化后相同 - 这是格式化差异")
            }
        }
        
        if titleChanged {
            Swift.print("[内容检测] 📝 标题变化: '\(originalTitle)' -> '\(currentTitle)'")
        } else {
            Swift.print("[内容检测] ✅ 标题无变化")
        }
        
        // 记录时间戳更新决策
        // _需求: 3.2.3, 3.3_
        let shouldUpdateTimestamp = contentChanged || titleChanged
        Swift.print("[内容检测] 🕐 时间戳决策: \(shouldUpdateTimestamp ? "需要更新" : "保持不变")")
        Swift.print("[内容检测] ═══════════════════════════════════════")
        
        return contentChanged || titleChanged
    }
}

@available(macOS 14.0, *)
struct ImageInsertStatusView: View {
    let isInserting: Bool
    let message: String
    let status: NoteDetailView.ImageInsertStatus
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 20) {
            if isInserting { ProgressView().scaleEffect(1.2) }
            else { Image(systemName: status == .success ? "checkmark.circle.fill" : "xmark.circle.fill").font(.system(size: 48)).foregroundColor(status == .success ? .green : .red) }
            Text(isInserting ? "正在插入图片" : (status == .success ? "插入成功" : "插入失败")).font(.headline)
            Text(message).font(.body).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            if !isInserting { Button("确定") { onDismiss(); dismiss() }.buttonStyle(.borderedProminent) }
        }.padding(30).frame(width: 400)
    }
}


// MARK: - 格式菜单弹出内容视图

/// 格式菜单弹出内容视图
/// 
/// 显示原生编辑器的格式菜单
@available(macOS 14.0, *)
struct FormatMenuPopoverContent: View {
    
    /// 原生编辑器上下文
    @ObservedObject var nativeEditorContext: NativeEditorContext
    
    /// 关闭回调
    let onDismiss: () -> Void
    
    var body: some View {
        NativeFormatMenuView(context: nativeEditorContext) { _ in onDismiss() }
            .onAppear {
                print("[FormatMenuPopoverContent] onAppear - 使用原生编辑器")
                
                // 请求内容同步并更新格式状态
                nativeEditorContext.requestContentSync()
                // 延迟一小段时间后强制更新格式状态
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    nativeEditorContext.forceUpdateFormats()
                }
            }
    }
}
