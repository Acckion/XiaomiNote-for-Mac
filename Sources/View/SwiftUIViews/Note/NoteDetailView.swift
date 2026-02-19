import AppKit
import Combine
import SwiftUI

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

    @State private var editedTitle = ""
    @State private var currentXMLContent = ""
    @State private var isSaving = false
    @State private var isUploading = false
    @State private var showSaveSuccess = false

    /// 标题提取服务
    private let titleExtractionService = TitleExtractionService.shared

    /// 保存流程协调器
    private let savePipelineCoordinator = SavePipelineCoordinator()

    /// 保存状态
    /// 保存状态枚举
    ///
    /// 用于显示当前笔记的保存状态
    ///
    enum SaveStatus: Equatable {
        case saved // 已保存（绿色）
        case saving // 保存中（黄色）
        case unsaved // 未保存（红色）
        case error(String) // 保存失败（红色，带错误信息）

        /// 实现 Equatable 协议
        static func == (lhs: SaveStatus, rhs: SaveStatus) -> Bool {
            switch (lhs, rhs) {
            case (.saved, .saved), (.saving, .saving), (.unsaved, .unsaved):
                true
            case let (.error(lhsMessage), .error(rhsMessage)):
                lhsMessage == rhsMessage
            default:
                false
            }
        }
    }

    @State private var saveStatus: SaveStatus = .saved

    // MARK: - 调试模式状态


    /// 是否处于调试模式
    ///
    /// 当为 true 时，显示 XML 调试编辑器；当为 false 时，显示普通编辑器
    @State private var isDebugMode = false

    /// 调试模式下的 XML 内容
    ///
    /// 用于在调试模式下编辑的 XML 内容，切换模式时与 currentXMLContent 同步
    @State private var debugXMLContent = ""

    /// 调试模式下的保存状态
    @State private var debugSaveStatus: DebugSaveStatus = .saved
    @State private var showSaveErrorAlert = false
    @State private var saveErrorMessage = ""
    @State private var isEditable = true
    @State private var isInitializing = true
    @State private var originalTitle = ""
    @State private var originalXMLContent = ""
    @State private var currentEditingNoteId: String?
    @State private var isSavingBeforeSwitch = false
    @State private var lastSavedXMLContent = ""
    @State private var isSavingLocally = false

    // 保存任务跟踪
    @State private var htmlSaveTask: Task<Void, Never>?
    @State private var xmlSaveTask: Task<Void, Never>?
    @State private var xmlSaveDebounceTask: Task<Void, Never>?

    /// XML保存防抖延迟（毫秒）
    private let xmlSaveDebounceDelay: UInt64 = 300_000_000 // 300ms

    // MARK: - 保存重试状态


    /// 待重试保存的 XML 内容
    @State private var pendingRetryXMLContent: String?

    /// 待重试保存的笔记对象
    @State private var pendingRetryNote: Note?

    /// 是否显示重试保存确认对话框
    @State private var showRetrySaveAlert = false

    @State private var showImageInsertAlert = false
    @State private var imageInsertMessage = ""
    @State private var isInsertingImage = false
    @State private var imageInsertStatus: ImageInsertStatus = .idle

    enum ImageInsertStatus {
        case idle, uploading, success, failed
    }

    @State private var showingHistoryView = false

    /// 使用共享的 NativeEditorContext（从 viewModel 获取）
    private var nativeEditorContext: NativeEditorContext {
        viewModel.nativeEditorContext
    }

    /// 编辑器偏好设置服务 - 使用 @ObservedObject 因为是单例
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
                toggleDebugMode()
            }
            // 监听原生编辑器保存状态变化通知
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
    private func handleNativeEditorSaveStatusChange(_ notification: Notification) {
        // 只在使用原生编辑器时处理
        guard isUsingNativeEditor else { return }

        // 只在非调试模式下处理
        guard !isDebugMode else { return }

        // 获取 needsSave 状态
        guard let userInfo = notification.userInfo,
              let needsSave = userInfo["needsSave"] as? Bool
        else {
            return
        }

        // 更新保存状态
        if needsSave {
            // 只有在当前状态不是 saving 时才更新为 unsaved
            // 避免在保存过程中被覆盖
            if case .saving = saveStatus {
                // 保持 saving 状态
            } else {
                saveStatus = .unsaved
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
            await saveCurrentContentForFolderSwitch()
        }
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
            return true
        }

        // 关键修复：在切换前立即捕获当前编辑的标题和内容
        let capturedTitle = editedTitle
        let capturedOriginalTitle = originalTitle
        let capturedLastSavedXMLContent = lastSavedXMLContent
        let capturedNote = note

        // 关键修复：立即获取原生编辑器的内容（在切换前）
        var capturedContent = ""
        if isUsingNativeEditor {
            capturedContent = nativeEditorContext.exportToXML()

            // 如果导出为空，使用 currentXMLContent
            if capturedContent.isEmpty, !currentXMLContent.isEmpty {
                capturedContent = currentXMLContent
            }
        }

        // 后台异步保存，不阻塞界面切换
        Task { @MainActor in
            // 1. 使用捕获的内容
            let content: String = capturedContent

            // 2. 检查内容是否变化
            let hasContentChange = content != capturedLastSavedXMLContent
            let hasTitleChange = capturedTitle != capturedOriginalTitle

            guard hasContentChange || hasTitleChange else {
                return
            }

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
            if let index = viewModel.notes.firstIndex(where: { $0.id == updated.id }) {
                viewModel.notes[index] = updated
            }

            // 4. 后台异步保存到数据库
            DatabaseService.shared.saveNoteAsync(updated) { error in
                Task { @MainActor in
                    if let error {
                        LogService.shared.error(.editor, "文件夹切换后台保存失败: \(error)")
                    } else {
                        // 调度云端同步（后台执行）
                        scheduleCloudUpload(for: updated, xmlContent: content)
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
            debugModeToggleButton
            if let note = viewModel.selectedNote {
                shareAndMoreButtons(for: note)
            }
        }
    }

    /// 调试模式切换按钮
    ///
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
            ImageInsertStatusView(
                isInserting: isInsertingImage,
                message: imageInsertMessage,
                status: imageInsertStatus,
                onDismiss: { imageInsertStatus = .idle }
            )
        }
        .alert("保存失败", isPresented: $showSaveErrorAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
    }

    private func editorContentView(for _: Note) -> some View {
        bodyEditorView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .top) // 允许内容延伸到工具栏下方
    }

    /// 标题编辑器已移除,标题将在后续任务中作为编辑器的第一个段落
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
            case let .error(message):
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
    private var saveStatusIndicator: some View {
        Group {
            switch saveStatus {
            case .saved:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 8))
                    Text("已保存")
                        .font(.system(size: 10))
                }
                .foregroundColor(.green)
            case .saving:
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 10, height: 10)
                    Text("保存中...")
                        .font(.system(size: 10))
                }
                .foregroundColor(.orange)
            case .unsaved:
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 8))
                    Text("未保存")
                        .font(.system(size: 10))
                }
                .foregroundColor(.red)
            case let .error(message):
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
            .replacingOccurrences(of: "&quot;", with: "\"") // 修复此处：转义双引号
            .replacingOccurrences(of: "&apos;", with: "'") // 修复此处：转义单引号
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
                if isDebugMode {
                    // 调试模式：显示 XML 调试编辑器
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
                                  currentNote.id == currentEditingNoteId
                            else {
                                return
                            }

                            Task { @MainActor in
                                // 任务 4.1: 集成 TitleExtractionService 进行标题提取

                                // 1. 优先从原生编辑器提取标题
                                var titleResult: TitleExtractionResult
                                let nsAttributedText = nativeEditorContext.nsAttributedText
                                if nsAttributedText.length > 0 {
                                    // 创建临时的 NSTextStorage 用于标题提取
                                    let textStorage = NSTextStorage(attributedString: nsAttributedText)
                                    titleResult = titleExtractionService.extractTitleFromEditor(textStorage)
                                } else {
                                    // 2. 后备方案：从 XML 内容提取标题
                                    titleResult = titleExtractionService.extractTitleFromXML(newXML)
                                }

                                // 3. 验证提取的标题
                                let validation = titleExtractionService.validateTitle(titleResult.title)
                                if validation.isValid {
                                    // 更新 editedTitle 状态（保持 UI 同步）
                                    if !titleResult.title.isEmpty {
                                        editedTitle = titleResult.title
                                    }
                                } else {
                                    // 保持原有标题不变
                                }

                                // 4. 更新当前内容状态
                                currentXMLContent = newXML

                                // [Tier 0] 立即更新内存缓存（<1ms，无延迟）
                                await updateMemoryCache(xmlContent: newXML, htmlContent: newHTML, for: currentNote)

                                // [Tier 1] 异步保存 HTML 缓存（后台，<10ms）
                                if let html = newHTML {
                                    flashSaveHTML(html, for: currentNote)
                                }

                                // [Tier 2] 异步保存 XML（后台，<50ms，防抖300ms）
                                // 传递提取的标题结果，确保在保存前正确提取和设置标题
                                scheduleXMLSave(xmlContent: newXML, for: currentNote, extractedTitle: titleResult, immediate: false)

                                // [Tier 3] 计划同步云端（延迟3秒）
                                scheduleCloudUpload(for: currentNote, xmlContent: newXML)
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
    private func toggleDebugMode() {
        if isDebugMode {
            // 从调试模式切换到普通模式
            // 保留调试模式下编辑的内容
            if debugXMLContent != currentXMLContent {
                currentXMLContent = debugXMLContent
                // 标记内容已修改，触发保存
                if let note = viewModel.selectedNote {
                    scheduleXMLSave(xmlContent: debugXMLContent, for: note, immediate: false)
                }
            }
            isDebugMode = false
        } else {
            // 从普通模式切换到调试模式
            // 同步当前内容到调试编辑器
            if let note = viewModel.selectedNote {
                // 优先使用当前编辑的内容，如果为空则使用笔记的原始内容
                debugXMLContent = currentXMLContent.isEmpty ? note.primaryXMLContent : currentXMLContent
            }
            debugSaveStatus = DebugSaveStatus.saved
            isDebugMode = true
        }
    }

    /// 处理调试模式下的内容变化
    ///
    private func handleDebugContentChange(_ newContent: String) {
        guard !isInitializing else { return }

        // 标记为未保存
        if debugSaveStatus != .saving {
            debugSaveStatus = DebugSaveStatus.unsaved
        }
    }

    /// 保存调试编辑器中的内容
    ///
    /// 实现完整的保存流程：
    /// 1. 更新 Note.content 为编辑后的 XML 内容
    /// 2. 触发本地数据库保存
    /// 3. 调度云端同步
    ///
    @MainActor
    private func saveDebugContent() async {
        guard let note = viewModel.selectedNote, note.id == currentEditingNoteId else {
            debugSaveStatus = .error("无法保存：未选择笔记")
            return
        }

        // 检查内容是否有变化
        let hasChanges = debugXMLContent != lastSavedXMLContent || editedTitle != originalTitle
        guard hasChanges else {
            debugSaveStatus = .saved
            return
        }

        debugSaveStatus = .saving

        // 同步内容到 currentXMLContent
        currentXMLContent = debugXMLContent

        // 构建更新的笔记对象
        let updated = buildUpdatedNote(from: note, xmlContent: debugXMLContent)

        do {
            try await saveDebugContentToDatabase(updated)

            debugSaveStatus = .saved
            // 关键修复：确保 lastSavedXMLContent 与 debugXMLContent 同步
            lastSavedXMLContent = debugXMLContent

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

            scheduleCloudUpload(for: updated, xmlContent: debugXMLContent)
        } catch {
            let errorMessage = "保存失败: \(error.localizedDescription)"
            debugSaveStatus = .error(errorMessage)
            LogService.shared.error(.editor, "调试模式保存失败: \(error)")
        }
    }

    /// 将调试内容保存到数据库
    ///
    @MainActor
    private func saveDebugContentToDatabase(_ note: Note) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DatabaseService.shared.saveNoteAsync(note) { error in
                if let error {
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

    @State private var showFormatMenu = false
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

    private var imageButton: some View {
        Button { insertImage() } label: { Label("插入图片", systemImage: "paperclip") }
    }

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
                Task { @MainActor in await insertImage(from: url) }
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

    private var newNoteButton: some View {
        Button { viewModel.createNewNote() } label: { Label("新建笔记", systemImage: "square.and.pencil") }
    }

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
        currentEditingNoteId = note.id

        isInitializing = true
        saveStatus = .saved

        let title = note.title.isEmpty || note.title.hasPrefix("未命名笔记_") ? "" : note.title
        editedTitle = title
        originalTitle = title

        htmlSaveTask?.cancel()
        xmlSaveTask?.cancel()
        xmlSaveDebounceTask?.cancel()
        htmlSaveTask = nil
        xmlSaveTask = nil
        xmlSaveDebounceTask = nil

        currentXMLContent = ""
        lastSavedXMLContent = ""
        originalXMLContent = ""

        if isDebugMode {
            let newNoteContent = note.primaryXMLContent
            debugXMLContent = newNoteContent.isEmpty ? "" : newNoteContent
            debugSaveStatus = DebugSaveStatus.saved
        } else {
            debugXMLContent = ""
            debugSaveStatus = DebugSaveStatus.saved
        }

        let cachedNote = await MemoryCacheManager.shared.getNote(noteId: note.id)
        if let cachedNote {
            if cachedNote.id == note.id {
                await loadNoteContentFromCache(cachedNote)
                return
            }
        }

        await loadNoteContent(note)
    }

    /// 从缓存加载笔记内容
    @MainActor
    private func loadNoteContentFromCache(_ note: Note) async {
        // 关键修复：确保笔记ID匹配
        guard note.id == currentEditingNoteId else {
            return
        }

        // 加载标题（不要重置，因为在 quickSwitchToNote 中已经设置）
        let title = note.title.isEmpty || note.title.hasPrefix("未命名笔记_") ? "" : note.title
        if editedTitle != title {
            editedTitle = title
            originalTitle = title
        }

        // 加载内容
        var contentToLoad = note.primaryXMLContent

        // 关键修复：插入标题到 XML（与 loadNoteContent 保持一致）
        // 任务 22.2: 如果有标题，将标题插入到内容的开头
        // 标题将作为编辑器的第一个段落显示
        if !title.isEmpty {
            // 检查 XML 中是否已经有 <title> 标签
            if !contentToLoad.contains("<title>") {
                // 如果没有 <title> 标签，添加一个
                // 将标题插入到内容的最前面（在 <new-format/> 之后）
                let titleTag = "<title>\(encodeXMLEntities(title))</title>"

                if contentToLoad.hasPrefix("<new-format/>") {
                    // 在 <new-format/> 后插入标题
                    let afterPrefix = String(contentToLoad.dropFirst("<new-format/>".count))
                    contentToLoad = "<new-format/>\(titleTag)\(afterPrefix)"
                } else {
                    // 直接在开头插入标题
                    contentToLoad = "\(titleTag)\(contentToLoad)"
                }
            }
        }

        currentXMLContent = contentToLoad
        // 关键修复：确保 lastSavedXMLContent 与 currentXMLContent 同步
        lastSavedXMLContent = currentXMLContent
        originalXMLContent = currentXMLContent

        // 关键修复：立即调用 loadFromXML 确保编辑器内容同步
        // 这解决了笔记切换时内容丢失的问题
        if isUsingNativeEditor {
            nativeEditorContext.loadFromXML(currentXMLContent)
        }

        // 调试模式：同步内容到调试编辑器
        if isDebugMode {
            debugXMLContent = currentXMLContent
            debugSaveStatus = DebugSaveStatus.saved
        }

        // 验证内容持久化 - 检查是否包含音频附件
        await verifyAudioAttachmentPersistence(note: note)

        // 短暂延迟以确保编辑器正确初始化
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // 再次验证笔记ID（防止在延迟期间切换了笔记）
        guard note.id == currentEditingNoteId else {
            return
        }

        isInitializing = false
    }

    @MainActor
    private func verifyAudioAttachmentPersistence(note: Note) async {
        let contentToVerify = currentXMLContent.isEmpty ? note.primaryXMLContent : currentXMLContent

        let hasAudioAttachments = contentToVerify.contains("<sound fileid=")
        let hasTemporaryTemplates = contentToVerify.contains("des=\"temp\"")

        if hasAudioAttachments, hasTemporaryTemplates {
            LogService.shared.warning(.editor, "发现临时录音模板未更新 - 笔记ID: \(note.id.prefix(8))...")
        }

        if isUsingNativeEditor {
            let isValid = await nativeEditorContext.verifyContentPersistence(expectedContent: contentToVerify)
            if !isValid {
                LogService.shared.warning(.editor, "原生编辑器内容持久化验证失败 - 笔记ID: \(note.id.prefix(8))...")
            }
        }
    }

    /// 使用HTML缓存快速加载笔记
    @MainActor
    private func loadNoteContentWithHTML(note: Note, htmlContent _: String) async {
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
        lastSavedXMLContent = currentXMLContent
        originalXMLContent = currentXMLContent

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
                await MemoryCacheManager.shared.cacheNote(updated)
                currentXMLContent = updated.primaryXMLContent
                lastSavedXMLContent = currentXMLContent
                originalXMLContent = currentXMLContent
            }
        } else {
            // 关键修复：确保 lastSavedXMLContent 与 currentXMLContent 同步
            // 更新缓存
            await MemoryCacheManager.shared.cacheNote(note)
        }
    }

    @MainActor
    private func loadNoteContent(_ note: Note) async {
        guard note.id == currentEditingNoteId else {
            return
        }

        isInitializing = true

        htmlSaveTask?.cancel()
        xmlSaveTask?.cancel()
        xmlSaveDebounceTask?.cancel()
        htmlSaveTask = nil
        xmlSaveTask = nil
        xmlSaveDebounceTask = nil

        let title = note.title.isEmpty || note.title.hasPrefix("未命名笔记_") ? "" : note.title
        if editedTitle != title {
            editedTitle = title
            originalTitle = title
        }

        var contentToLoad = note.primaryXMLContent

        if note.content.isEmpty {
            await viewModel.ensureNoteHasFullContent(note)

            guard note.id == currentEditingNoteId else {
                return
            }

            if let updated = viewModel.selectedNote, updated.id == note.id {
                contentToLoad = updated.primaryXMLContent
                await MemoryCacheManager.shared.cacheNote(updated)
            }
        } else {
            await MemoryCacheManager.shared.cacheNote(note)
        }

        // 任务 22.2: 如果有标题，将标题插入到内容的开头
        if !title.isEmpty {
            if !contentToLoad.contains("<title>") {
                let titleTag = "<title>\(encodeXMLEntities(title))</title>"
                if contentToLoad.hasPrefix("<new-format/>") {
                    let afterPrefix = String(contentToLoad.dropFirst("<new-format/>".count))
                    contentToLoad = "<new-format/>\(titleTag)\(afterPrefix)"
                } else {
                    contentToLoad = "\(titleTag)\(contentToLoad)"
                }
            }
        }

        currentXMLContent = contentToLoad
        lastSavedXMLContent = currentXMLContent
        originalXMLContent = currentXMLContent

        if isUsingNativeEditor {
            nativeEditorContext.loadFromXML(currentXMLContent)
        }

        if isDebugMode {
            debugXMLContent = currentXMLContent
            debugSaveStatus = DebugSaveStatus.saved
        }

        try? await Task.sleep(nanoseconds: 100_000_000)

        guard note.id == currentEditingNoteId else {
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
        guard !isInitializing, newValue != originalTitle else { return }

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
        if original.count > 300, xmlContent.count < 150, xmlContent.count < original.count / 2 {
            LogService.shared.warning(.editor, "内容丢失保护触发 - 笔记ID: \(note.id.prefix(8))...")
            await saveTitleAndContent(title: newTitle, xmlContent: original, for: note)
        } else {
            await saveTitleAndContent(title: newTitle, xmlContent: xmlContent, for: note)
        }
    }

    @MainActor
    private func saveTitleAndContent(title: String, xmlContent: String, for note: Note) async {
        // 使用改进的内容变化检测
        let hasActualChange = hasContentActuallyChanged(
            currentContent: xmlContent,
            savedContent: lastSavedXMLContent,
            currentTitle: title,
            originalTitle: originalTitle
        )

        // 只有在内容或标题真正变化时才更新时间戳
        let shouldUpdateTimestamp = hasActualChange

        let previousEditedTitle = editedTitle
        editedTitle = title
        var updated = buildUpdatedNote(from: note, xmlContent: xmlContent, shouldUpdateTimestamp: shouldUpdateTimestamp)
        editedTitle = previousEditedTitle

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DatabaseService.shared.saveNoteAsync(updated) { error in
                Task { @MainActor in
                    if let error {
                        LogService.shared.error(.editor, "标题和内容保存失败: \(error)")
                        continuation.resume()
                        return
                    }

                    lastSavedXMLContent = xmlContent
                    originalTitle = title
                    currentXMLContent = xmlContent
                    // 更新笔记列表和选中的笔记
                    if let index = viewModel.notes.firstIndex(where: { $0.id == updated.id }) {
                        viewModel.notes[index] = updated
                    }
                    if viewModel.selectedNote?.id == updated.id {
                        viewModel.selectedNote = updated

                        // 通过 coordinator 更新笔记内容，保持选择状态不变
                        viewModel.stateCoordinator.updateNoteContent(updated)
                    }
                    scheduleCloudUpload(for: updated, xmlContent: xmlContent)
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
    @MainActor
    private func updateMemoryCache(xmlContent: String, htmlContent _: String?, for note: Note) async {
        guard note.id == currentEditingNoteId else {
            return
        }

        let titleToUse: String = if note.id == currentEditingNoteId {
            editedTitle
        } else {
            note.title
        }

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

        // 只有在当前状态不是 saving 时才更新为 unsaved
        if case .saving = saveStatus {
            // 保持 saving 状态，不覆盖
        } else {
            saveStatus = .unsaved
        }

        // 标记 coordinator 有未保存的内容
        // - 6.1: 切换文件夹时检查是否有未保存内容
        viewModel.stateCoordinator.hasUnsavedContent = true
    }

    @MainActor
    private func flashSaveHTML(_: String, for note: Note) {
        htmlSaveTask?.cancel()

        if viewModel.notes.firstIndex(where: { $0.id == note.id }) != nil {
            // HTML 缓存功能已移除，直接跳过
        }
    }

    /// 计划XML保存（带防抖）
    ///
    /// - Parameters:
    ///   - xmlContent: XML内容
    ///   - note: 笔记对象
    ///   - extractedTitle: 提取的标题结果（可选）
    ///   - immediate: 是否立即保存（切换笔记时使用），默认false（防抖保存）
    ///
    @MainActor
    private func scheduleXMLSave(xmlContent: String, for note: Note, extractedTitle: TitleExtractionResult? = nil, immediate: Bool = false) {
        guard note.id == currentEditingNoteId else {
            return
        }

        xmlSaveDebounceTask?.cancel()

        let noteId = note.id

        if immediate {
            let hasActualChange = hasContentActuallyChanged(
                currentContent: xmlContent,
                savedContent: lastSavedXMLContent,
                currentTitle: editedTitle,
                originalTitle: originalTitle
            )
            guard hasActualChange else {
                if case .unsaved = saveStatus {
                    saveStatus = .saved
                }
                return
            }
            performXMLSave(xmlContent: xmlContent, for: note, extractedTitle: extractedTitle)
        } else {
            if case .saved = saveStatus {
                saveStatus = .unsaved
            }

            xmlSaveDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: xmlSaveDebounceDelay)

                guard !Task.isCancelled, currentEditingNoteId == noteId else {
                    return
                }

                var latestXMLContent = xmlContent

                if isUsingNativeEditor {
                    let exportedXML = nativeEditorContext.exportToXML()
                    if !exportedXML.isEmpty {
                        latestXMLContent = exportedXML
                    }
                }

                let hasActualChange = hasContentActuallyChanged(
                    currentContent: latestXMLContent,
                    savedContent: lastSavedXMLContent,
                    currentTitle: editedTitle,
                    originalTitle: originalTitle
                )
                guard hasActualChange else {
                    saveStatus = .saved
                    return
                }

                performXMLSave(xmlContent: latestXMLContent, for: note, extractedTitle: extractedTitle)
            }
        }
    }

    /// 执行XML保存
    ///
    @MainActor
    private func performXMLSave(xmlContent: String, for note: Note, extractedTitle _: TitleExtractionResult? = nil) {
        // 任务 4.3: 集成 SavePipelineCoordinator

        xmlSaveTask?.cancel()

        let noteId = note.id

        saveStatus = .saving

        if isUsingNativeEditor {
            nativeEditorContext.backupCurrentContent()
        }

        xmlSaveTask = Task { @MainActor in
            guard !Task.isCancelled, currentEditingNoteId == noteId else {
                return
            }

            do {
                let textStorage = isUsingNativeEditor ? NSTextStorage(attributedString: nativeEditorContext.nsAttributedText) : nil

                let result = try await savePipelineCoordinator.executeSavePipeline(
                    xmlContent: xmlContent,
                    textStorage: textStorage,
                    noteId: noteId
                ) { noteId, title, content in
                    let titleResult = TitleExtractionResult(
                        title: title,
                        source: textStorage != nil ? .nativeEditor : .xml,
                        isValid: true,
                        extractionTime: Date(),
                        originalLength: xmlContent.count,
                        processedLength: content.count
                    )

                    let updated = buildUpdatedNote(from: note, xmlContent: xmlContent, extractedTitle: titleResult)

                    let saveResult = await NoteOperationCoordinator.shared.saveNote(updated)

                    switch saveResult {
                    case .success:
                        await handleSaveSuccess(xmlContent: xmlContent, noteId: noteId, updatedNote: updated)
                    case let .failure(error):
                        throw error
                    }
                }

                LogService.shared.info(.editor, "保存成功 - 标题: '\(result.extractedTitle)', 耗时: \(String(format: "%.2f", result.executionTime))秒")
            } catch {
                guard !Task.isCancelled, currentEditingNoteId == noteId else {
                    return
                }

                LogService.shared.error(.editor, "保存失败: \(error)")
                await handleSaveFailure(error: error, xmlContent: xmlContent, note: note)
            }
        }
    }

    @MainActor
    private func handleSaveSuccess(xmlContent: String, noteId: String, updatedNote: Note) async {
        lastSavedXMLContent = xmlContent
        currentXMLContent = xmlContent

        pendingRetryXMLContent = nil
        pendingRetryNote = nil

        if let index = viewModel.notes.firstIndex(where: { $0.id == noteId }) {
            viewModel.notes[index] = updatedNote
        }

        if viewModel.selectedNote?.id == noteId {
            viewModel.selectedNote = updatedNote
        }

        await MemoryCacheManager.shared.cacheNote(updatedNote)

        saveStatus = .saved
        viewModel.stateCoordinator.hasUnsavedContent = false

        if isUsingNativeEditor {
            nativeEditorContext.markContentSaved()
        }
    }

    @MainActor
    private func handleSaveFailure(error: Error, xmlContent: String, note: Note) async {
        let errorMessage = "保存笔记失败: \(error.localizedDescription)"
        saveStatus = .error(errorMessage)
        LogService.shared.error(.editor, "保存失败: \(error)")

        if isUsingNativeEditor {
            nativeEditorContext.markSaveFailed(error: errorMessage)
        }
        pendingRetryXMLContent = xmlContent
        pendingRetryNote = note
    }

    @MainActor
    private func retrySave() {
        guard let xmlContent = pendingRetryXMLContent,
              let note = pendingRetryNote ?? viewModel.selectedNote
        else {
            return
        }

        var contentToSave = xmlContent
        if isUsingNativeEditor {
            let backupContent = nativeEditorContext.getContentForRetry()
            if backupContent.length > 0 {
                contentToSave = XiaoMiFormatConverter.shared.safeNSAttributedStringToXML(backupContent)
            }
        }

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

    @State private var cloudUploadTask: Task<Void, Never>?
    /// 每个笔记的最后上传内容（按笔记 ID 存储）
    @State private var lastUploadedContentByNoteId: [String: String] = [:]

    private func scheduleCloudUpload(for note: Note, xmlContent: String) {
        guard viewModel.isOnline, viewModel.isLoggedIn else {
            // 网络不可用或未登录时，将操作添加到离线队列
            queueOfflineUpdateOperation(for: note, xmlContent: xmlContent)
            return
        }

        let lastUploadedForThisNote = lastUploadedContentByNoteId[note.id] ?? ""
        guard xmlContent != lastUploadedForThisNote else {
            return
        }

        cloudUploadTask?.cancel()
        let noteId = note.id

        cloudUploadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, currentEditingNoteId == noteId else { return }

            let latestXMLContent = currentXMLContent.isEmpty ? xmlContent : currentXMLContent

            let lastUploaded = lastUploadedContentByNoteId[noteId] ?? ""
            guard latestXMLContent != lastUploaded else {
                return
            }

            guard viewModel.isOnline, viewModel.isLoggedIn else {
                queueOfflineUpdateOperation(for: note, xmlContent: latestXMLContent)
                return
            }

            await performCloudUpload(for: note, xmlContent: latestXMLContent)
            lastUploadedContentByNoteId[noteId] = latestXMLContent
        }
    }

    /// 将更新操作添加到离线队列
    ///
    /// 当网络不可用时，将编辑操作保存到离线队列，等待网络恢复后同步
    ///
    @MainActor
    private func queueOfflineUpdateOperation(for note: Note, xmlContent: String) {
        let dataDict: [String: Any] = [
            "title": editedTitle.isEmpty ? note.title : editedTitle,
            "content": xmlContent,
            "folderId": note.folderId,
            "timestamp": Date().timeIntervalSince1970,
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: dataDict, options: [])
            let operation = NoteOperation(
                type: .cloudUpload,
                noteId: note.id,
                data: jsonData,
                localSaveTimestamp: Date()
            )
            try UnifiedOperationQueue.shared.enqueue(operation)
            lastUploadedContentByNoteId[note.id] = xmlContent
        } catch {
            LogService.shared.error(.editor, "添加操作到离线队列失败: \(error)")
        }
    }

    @MainActor
    private func performCloudUpload(for note: Note, xmlContent: String) async {
        let updated = buildUpdatedNote(from: note, xmlContent: xmlContent)
        isUploading = true

        do {
            try await viewModel.updateNote(updated)
            withAnimation { showSaveSuccess = true
                isUploading = false
            }
            LogService.shared.info(.editor, "云端同步成功 - 笔记ID: \(note.id.prefix(8))...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { showSaveSuccess = false } }
        } catch {
            isUploading = false
            LogService.shared.error(.editor, "云端同步失败: \(error)")

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
            if nsError.code >= 500, nsError.code < 600 {
                return true
            }
        }

        return false
    }

    private func saveCurrentNoteBeforeSwitching(newNoteId: String) -> Task<Void, Never>? {
        guard let currentId = currentEditingNoteId, currentId != newNoteId else {
            return nil
        }

        guard let currentNote = viewModel.notes.first(where: { $0.id == currentId }) else {
            return nil
        }

        let capturedTitle = editedTitle
        let capturedOriginalTitle = originalTitle
        let capturedLastSavedXMLContent = lastSavedXMLContent

        var capturedContent = ""
        if isUsingNativeEditor {
            capturedContent = nativeEditorContext.exportToXML()
            if capturedContent.isEmpty, !currentXMLContent.isEmpty {
                capturedContent = currentXMLContent
            }
        }

        isSavingBeforeSwitch = true

        Task { @MainActor in
            defer { isSavingBeforeSwitch = false }

            let content: String = capturedContent

            let hasActualChange = hasContentActuallyChanged(
                currentContent: content,
                savedContent: capturedLastSavedXMLContent,
                currentTitle: capturedTitle,
                originalTitle: capturedOriginalTitle
            )

            if hasActualChange {
                let updated = buildUpdatedNote(from: currentNote, xmlContent: content, shouldUpdateTimestamp: true)

                await MemoryCacheManager.shared.cacheNote(updated)

                if let index = viewModel.notes.firstIndex(where: { $0.id == updated.id }) {
                    viewModel.notes[index] = updated
                }

                DatabaseService.shared.saveNoteAsync(updated) { error in
                    Task { @MainActor in
                        if let error {
                            LogService.shared.error(.editor, "笔记切换后台保存失败: \(error)")
                        } else {
                            scheduleCloudUpload(for: updated, xmlContent: content)
                        }
                    }
                }
            }
        }

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
        if isUsingNativeEditor {
            let xmlContent = nativeEditorContext.exportToXML()
            if !xmlContent.isEmpty {
                return xmlContent
            }
        }
        return currentXMLContent
    }

    private func buildUpdatedNote(
        from note: Note,
        xmlContent: String,
        extractedTitle: TitleExtractionResult? = nil,
        shouldUpdateTimestamp: Bool = true
    ) -> Note {
        // 任务 4.2: 修改标题使用逻辑，优先使用传入的提取标题
        let titleToUse: String
        if let extractedTitle, extractedTitle.isValid, !extractedTitle.title.isEmpty {
            titleToUse = extractedTitle.title
        } else if note.id == currentEditingNoteId {
            titleToUse = editedTitle
        } else {
            titleToUse = note.title
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
            LogService.shared.warning(.app, "removeTitleTag: 正则表达式创建失败，返回原始内容")
            return xml
        }

        let range = NSRange(xml.startIndex..., in: xml)
        let result = regex.stringByReplacingMatches(in: xml, range: range, withTemplate: "")

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
    private func hasContentActuallyChanged(currentContent: String, savedContent: String, currentTitle: String, originalTitle: String) -> Bool {
        let normalizedCurrent = XMLNormalizer.shared.normalize(currentContent)
        let normalizedSaved = XMLNormalizer.shared.normalize(savedContent)

        let contentChanged = normalizedCurrent != normalizedSaved
        let titleChanged = currentTitle != originalTitle

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
            if isInserting { ProgressView().scaleEffect(1.2) } else {
                Image(systemName: status == .success ? "checkmark.circle.fill" : "xmark.circle.fill").font(.system(size: 48))
                    .foregroundColor(status == .success ? .green : .red)
            }
            Text(isInserting ? "正在插入图片" : (status == .success ? "插入成功" : "插入失败")).font(.headline)
            Text(message).font(.body).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            if !isInserting { Button("确定") { onDismiss()
                dismiss()
            }.buttonStyle(.borderedProminent) }
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
                nativeEditorContext.requestContentSync()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    nativeEditorContext.forceUpdateFormats()
                }
            }
    }
}
