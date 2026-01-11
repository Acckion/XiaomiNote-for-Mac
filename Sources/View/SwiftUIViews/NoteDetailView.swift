import SwiftUI
import AppKit
import Combine

/// 笔记详情视图
@available(macOS 14.0, *)
struct NoteDetailView: View {
    @ObservedObject var viewModel: NotesViewModel
    @State private var editedTitle: String = ""
    @State private var currentXMLContent: String = ""
    @State private var isSaving: Bool = false
    @State private var isUploading: Bool = false
    @State private var showSaveSuccess: Bool = false
    
    // 保存状态
    enum SaveStatus {
        case saved        // 已保存（绿色）
        case saving       // 保存中（黄色）
        case unsaved      // 未保存（红色）
        case error(String) // 保存失败（红色，带错误信息）
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
    
    @State private var showImageInsertAlert: Bool = false
    @State private var imageInsertMessage: String = ""
    @State private var isInsertingImage: Bool = false
    @State private var imageInsertStatus: ImageInsertStatus = .idle
    
    enum ImageInsertStatus {
        case idle, uploading, success, failed
    }
    
    @State private var showingHistoryView: Bool = false
    // 使用共享的WebEditorContext
    private var webEditorContext: WebEditorContext {
        viewModel.webEditorContext
    }
    
    // 使用共享的 NativeEditorContext（从 viewModel 获取）
    // 需求: 1.2 - 确保 MainWindowController 和 NoteDetailView 使用同一个上下文
    private var nativeEditorContext: NativeEditorContext {
        viewModel.nativeEditorContext
    }
    
    // 编辑器偏好设置服务 - 使用 @ObservedObject 因为是单例
    @ObservedObject private var editorPreferencesService = EditorPreferencesService.shared
    
    /// 当前是否使用原生编辑器
    private var isUsingNativeEditor: Bool {
        editorPreferencesService.selectedEditorType == .native && editorPreferencesService.isNativeEditorAvailable
    }
    
    var body: some View {
        mainContentView
            .onChange(of: viewModel.selectedNote) { oldValue, newValue in
                handleSelectedNoteChange(oldValue: oldValue, newValue: newValue)
            }
            .onChange(of: viewModel.searchText) { _, newValue in
                if webEditorContext.isEditorReady {
                    webEditorContext.highlightSearchText(newValue)
                }
            }
            .onAppear {
                // 注册保存回调到 ViewStateCoordinator
                // **Requirements: 3.5, 6.1, 6.2**
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
            .navigationTitle("详情")
            .toolbar {
                toolbarContent
            }
    }
    
    /// 注册保存回调到 ViewStateCoordinator
    /// 
    /// 当文件夹切换时，ViewStateCoordinator 会调用此回调来保存当前编辑的内容
    /// 
    /// **Requirements: 3.5, 6.1, 6.2**
    private func registerSaveCallback() {
        viewModel.stateCoordinator.saveContentCallback = { [self] in
            await self.saveCurrentContentForFolderSwitch()
        }
        Swift.print("[NoteDetailView] ✅ 已注册保存回调到 ViewStateCoordinator")
    }
    
    /// 为文件夹切换保存当前内容
    /// 
    /// 这个方法会被 ViewStateCoordinator 在文件夹切换前调用
    /// 
    /// **Requirements: 3.5, 6.1, 6.2**
    /// 
    /// - Returns: 是否保存成功
    @MainActor
    private func saveCurrentContentForFolderSwitch() async -> Bool {
        guard let note = viewModel.selectedNote, note.id == currentEditingNoteId else {
            Swift.print("[保存流程] ⏭️ 文件夹切换保存跳过 - 无当前编辑笔记")
            return true
        }
        
        Swift.print("[保存流程] 🔄 文件夹切换前保存 - 笔记ID: \(note.id.prefix(8))..., 标题: \(editedTitle)")
        
        // 1. 强制编辑器保存当前内容
        if isUsingNativeEditor {
            // 原生编辑器：导出 XML
            let xmlContent = nativeEditorContext.exportToXML()
            if !xmlContent.isEmpty {
                currentXMLContent = xmlContent
            }
        } else {
            // Web 编辑器：强制保存
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                webEditorContext.forceSaveContent { c.resume() }
            }
        }
        
        // 2. 获取最新内容
        let content = await getLatestContentFromEditor()
        
        // 3. 检查内容是否变化
        guard content != lastSavedXMLContent || editedTitle != originalTitle else {
            Swift.print("[保存流程] ⏭️ 文件夹切换保存跳过 - 内容无变化")
            return true
        }
        
        Swift.print("[保存流程] 💾 文件夹切换保存 - 内容长度: \(content.count)")
        
        // 4. 立即保存 XML
        scheduleXMLSave(xmlContent: content, for: note, immediate: true)
        
        // 5. 等待保存完成
        if let xmlTask = xmlSaveTask {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await xmlTask.value
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms 超时
                }
                await group.next()
                group.cancelAll()
            }
        }
        
        Swift.print("[保存流程] ✅ 文件夹切换保存完成")
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
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    titleEditorView.padding(.horizontal, 16).padding(.top, 16).frame(minHeight: 60)
                    metaInfoView(for: note).padding(.horizontal, 16).padding(.top, 8)
                    Spacer().frame(height: 16)
                    bodyEditorView.padding(.horizontal, 16).frame(minHeight: max(600, geometry.size.height - 200))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    private var titleEditorView: some View {
        TitleEditorView(title: $editedTitle, isEditable: $isEditable, hasRealTitle: hasRealTitle())
    }
    
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
            // _Requirements: 1.3_
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
    /// 
    /// _Requirements: 1.3_
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
    /// 
    /// _Requirements: 4.5, 4.6, 4.7_
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
    
    private var saveStatusIndicator: some View {
        Group {
            switch saveStatus {
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
                    // 普通模式：使用统一编辑器包装器，支持原生编辑器和 Web 编辑器切换
                    UnifiedEditorWrapper(
                        content: $currentXMLContent,
                        isEditable: $isEditable,
                        webEditorContext: webEditorContext,
                        nativeEditorContext: nativeEditorContext,
                        noteRawData: {
                            if let rawData = note.rawData, let jsonData = try? JSONSerialization.data(withJSONObject: rawData, options: []) {
                                return String(data: jsonData, encoding: .utf8)
                            }
                            return nil
                        }(),
                        xmlContent: note.primaryXMLContent,
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
                                // 更新当前内容状态
                                self.currentXMLContent = newXML
                                
                                // [Tier 0] 立即更新内存缓存（<1ms，无延迟）
                                await self.updateMemoryCache(xmlContent: newXML, htmlContent: newHTML, for: currentNote)
                                
                                // [Tier 1] 异步保存 HTML 缓存（后台，<10ms）
                                if let html = newHTML {
                                    self.flashSaveHTML(html, for: currentNote)
                                }
                                
                                // [Tier 2] 异步保存 XML（后台，<50ms，防抖300ms）
                                self.scheduleXMLSave(xmlContent: newXML, for: currentNote, immediate: false)
                                
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
    
    // MARK: - 工具栏按钮（支持原生编辑器和 Web 编辑器）
    
    private var undoButton: some View {
        Button {
            if isUsingNativeEditor {
                // 原生编辑器撤销（通过 NSTextView 的 undoManager）
                NSApp.sendAction(#selector(UndoManager.undo), to: nil, from: nil)
            } else {
                webEditorContext.undo()
            }
        } label: { Label("撤销", systemImage: "arrow.uturn.backward") }
    }
    
    private var redoButton: some View {
        Button {
            if isUsingNativeEditor {
                // 原生编辑器重做（通过 NSTextView 的 undoManager）
                NSApp.sendAction(#selector(UndoManager.redo), to: nil, from: nil)
            } else {
                webEditorContext.redo()
            }
        } label: { Label("重做", systemImage: "arrow.uturn.forward") }
    }
    
    @State private var showFormatMenu: Bool = false
    private var formatMenu: some View {
        Button { showFormatMenu.toggle() } label: { Label("格式", systemImage: "textformat") }
        .popover(isPresented: $showFormatMenu, arrowEdge: .top) {
            FormatMenuPopoverContent(
                nativeEditorContext: nativeEditorContext,
                webEditorContext: webEditorContext,
                onDismiss: { showFormatMenu = false }
            )
        }
    }
    
    private var checkboxButton: some View {
        Button {
            if isUsingNativeEditor {
                nativeEditorContext.insertCheckbox()
            } else {
                webEditorContext.insertCheckbox()
            }
        } label: { Label("插入待办", systemImage: "checklist") }
    }
    
    private var horizontalRuleButton: some View {
        Button {
            if isUsingNativeEditor {
                nativeEditorContext.insertHorizontalRule()
            } else {
                webEditorContext.insertHorizontalRule()
            }
        } label: { Label("插入分割线", systemImage: "minus") }
    }
    
    private var imageButton: some View { Button { insertImage() } label: { Label("插入图片", systemImage: "paperclip") } }
    
    @ViewBuilder
    private var indentButtons: some View {
        Button {
            if isUsingNativeEditor {
                // 原生编辑器增加缩进
                // 需求: 6.1, 6.3 - 调用 NativeEditorContext.increaseIndent()
                nativeEditorContext.increaseIndent()
            } else {
                webEditorContext.increaseIndent()
            }
        } label: { Label("增加缩进", systemImage: "increase.indent") }
        
        Button {
            if isUsingNativeEditor {
                // 原生编辑器减少缩进
                // 需求: 6.2, 6.4 - 调用 NativeEditorContext.decreaseIndent()
                nativeEditorContext.decreaseIndent()
            } else {
                webEditorContext.decreaseIndent()
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
            
            // 根据当前编辑器类型插入图片
            if isUsingNativeEditor {
                nativeEditorContext.insertImage(fileId: fileId, src: "minote://image/\(fileId)")
            } else {
                webEditorContext.insertImage("minote://image/\(fileId)", altText: url.lastPathComponent)
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
        currentXMLContent = ""
        lastSavedXMLContent = ""
        originalXMLContent = ""
        
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
        currentXMLContent = note.primaryXMLContent
        lastSavedXMLContent = currentXMLContent
        originalXMLContent = currentXMLContent
        
        // 调试模式：同步内容到调试编辑器
        // _Requirements: 6.4_
        if isDebugMode {
            debugXMLContent = currentXMLContent
            debugSaveStatus = DebugSaveStatus.saved
            Swift.print("[快速切换] 🔧 调试模式内容已同步 - 长度: \(debugXMLContent.count)")
        }
        
        Swift.print("[快速切换] ✅ 从缓存加载完成 - ID: \(note.id.prefix(8))..., 标题: \(title), 内容长度: \(currentXMLContent.count)")
        
        // 短暂延迟以确保编辑器正确初始化
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // 再次验证笔记ID（防止在延迟期间切换了笔记）
        guard note.id == currentEditingNoteId else {
            Swift.print("[快速切换] ⚠️ 延迟后笔记ID不匹配，取消显示 - 传入ID: \(note.id.prefix(8))..., 当前编辑ID: \(currentEditingNoteId?.prefix(8) ?? "nil")")
            return
        }
        
        isInitializing = false
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
        
        // 使用HTML内容（编辑器可以直接显示HTML）
        // 注意：这里我们需要将HTML转换为XML，或者让编辑器直接使用HTML
        // 暂时使用primaryXMLContent，后台会加载完整内容
        currentXMLContent = note.primaryXMLContent
        lastSavedXMLContent = currentXMLContent
        originalXMLContent = currentXMLContent
        
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
                lastSavedXMLContent = currentXMLContent
                originalXMLContent = currentXMLContent
                
                Swift.print("[快速切换] ✅ 完整内容加载完成 - ID: \(note.id.prefix(8))...")
            }
        } else {
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
        currentXMLContent = note.primaryXMLContent
        lastSavedXMLContent = currentXMLContent
        originalXMLContent = currentXMLContent
        
        // 3. 如果内容为空，确保获取完整内容
        if note.content.isEmpty {
            await viewModel.ensureNoteHasFullContent(note)
            
            // 再次验证笔记ID
            guard note.id == currentEditingNoteId else {
                Swift.print("[笔记切换] ⚠️ 获取完整内容后笔记ID不匹配，取消更新 - 传入ID: \(note.id.prefix(8))..., 当前编辑ID: \(currentEditingNoteId?.prefix(8) ?? "nil")")
                return
            }
            
            if let updated = viewModel.selectedNote, updated.id == note.id {
                currentXMLContent = updated.primaryXMLContent
                lastSavedXMLContent = currentXMLContent
                
                // 更新缓存
                await MemoryCacheManager.shared.cacheNote(updated)
            }
        } else {
            // 更新缓存
            await MemoryCacheManager.shared.cacheNote(note)
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
        var updated = Note(id: note.id, title: title, content: xmlContent, folderId: note.folderId, isStarred: note.isStarred, createdAt: note.createdAt, updatedAt: Date(), tags: note.tags, rawData: note.rawData)
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
                    
                    self.lastSavedXMLContent = xmlContent
                    self.originalTitle = title
                    self.currentXMLContent = xmlContent
                    // 更新笔记列表和选中的笔记
                    if let index = self.viewModel.notes.firstIndex(where: { $0.id == updated.id }) {
                        self.viewModel.notes[index] = updated
                    }
                    if self.viewModel.selectedNote?.id == updated.id {
                        self.viewModel.selectedNote = updated
                        
                        // 通过 coordinator 更新笔记内容，保持选择状态不变
                        // **Requirements: 1.1, 1.2, 1.3**
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
        
        // 构建更新的笔记对象
        var updated = Note(id: note.id, title: titleToUse, content: xmlContent, folderId: note.folderId, isStarred: note.isStarred, createdAt: note.createdAt, updatedAt: Date(), tags: note.tags, rawData: note.rawData)
        // 注意：Note模型中没有htmlContent属性，HTML缓存由DatabaseService单独管理
        
        // 立即更新内存缓存（<1ms）
        await MemoryCacheManager.shared.cacheNote(updated)
        
        // 更新viewModel.notes数组（不更新selectedNote，避免闪烁）
        if let index = viewModel.notes.firstIndex(where: { $0.id == updated.id }) {
            viewModel.notes[index] = updated
        }
        
        // 更新保存状态为"保存中"
        saveStatus = .saving
        
        // 标记 coordinator 有未保存的内容
        // **Requirements: 6.1**
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
    ///   - immediate: 是否立即保存（切换笔记时使用），默认false（防抖保存）
    @MainActor
    private func scheduleXMLSave(xmlContent: String, for note: Note, immediate: Bool = false) {
        // 检查是否是当前编辑的笔记
        guard note.id == currentEditingNoteId else {
            Swift.print("[保存流程] ⏭️ Tier 1 跳过 - 不是当前编辑笔记，ID: \(note.id.prefix(8))..., currentEditingNoteId: \(currentEditingNoteId?.prefix(8) ?? "nil")")
            return
        }
        
        // 检查内容是否变化
        guard xmlContent != lastSavedXMLContent || editedTitle != originalTitle else {
            Swift.print("[保存流程] ⏭️ Tier 1 跳过 - 内容未变化，XML长度: \(xmlContent.count), lastSaved: \(lastSavedXMLContent.count)")
            return
        }
        
        // 取消之前的防抖任务
        xmlSaveDebounceTask?.cancel()
        
        let noteId = note.id
        
        if immediate {
            // 立即保存（切换笔记时）
            Swift.print("[保存流程] 🔄 Tier 1 立即保存 - 笔记ID: \(noteId.prefix(8))..., XML长度: \(xmlContent.count)")
            performXMLSave(xmlContent: xmlContent, for: note)
        } else {
            // 防抖保存（正常编辑时）
            xmlSaveDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: xmlSaveDebounceDelay)
                
                // 检查任务是否被取消或笔记已切换
                guard !Task.isCancelled && self.currentEditingNoteId == noteId else {
                    Swift.print("[保存流程] ⏸️ Tier 1 防抖保存已取消")
                    return
                }
                
                // 再次检查内容是否变化（可能在防抖期间又变化了）
                guard xmlContent != self.lastSavedXMLContent || self.editedTitle != self.originalTitle else {
                    Swift.print("[保存流程] ⏭️ Tier 1 防抖保存跳过 - 内容已同步")
                    return
                }
                
                Swift.print("[保存流程] 🔄 Tier 1 防抖保存触发 - 笔记ID: \(noteId.prefix(8))..., XML长度: \(xmlContent.count)")
                self.performXMLSave(xmlContent: xmlContent, for: note)
            }
        }
    }
    
    /// 执行XML保存
    @MainActor
    private func performXMLSave(xmlContent: String, for note: Note) {
        // 取消之前的保存任务
        xmlSaveTask?.cancel()
        
        let noteId = note.id
        
        // 构建更新的笔记对象
        var updated = buildUpdatedNote(from: note, xmlContent: xmlContent)
        // 注意：Note模型中没有htmlContent属性，HTML缓存由DatabaseService单独管理
        
        // 使用SaveQueueManager管理保存任务（合并相同笔记的多次保存）
        SaveQueueManager.shared.enqueueSave(updated, priority: .normal)
        
        // 同时使用异步保存，不阻塞主线程（保持现有逻辑）
        xmlSaveTask = Task { @MainActor in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DatabaseService.shared.saveNoteAsync(updated) { error in
                    Task { @MainActor in
                        // 检查任务是否被取消或笔记已切换
                        guard !Task.isCancelled && self.currentEditingNoteId == noteId else {
                            Swift.print("[保存流程] ⏸️ Tier 1 XML保存已取消")
                            continuation.resume()
                            return
                        }
                        
                        if let error = error {
                            Swift.print("[保存流程] ❌ Tier 1 本地保存失败: \(error)")
                            // 更新保存状态为"错误"（保存失败）
                            let errorMessage = "保存笔记失败: \(error.localizedDescription)"
                            self.saveStatus = .error(errorMessage)
                            continuation.resume()
                            return
                        }
                        
                        // 保存成功后更新状态
                        self.lastSavedXMLContent = xmlContent
                        self.currentXMLContent = xmlContent
                        
                        // 更新视图模型中的笔记
                        // **Requirements: 1.1, 1.2** - 编辑笔记内容时保持选中状态不变
                        // 由于 Note 的 Equatable 现在只比较 id，所以更新 notes 数组不会影响选择状态
                        let oldSelectedNoteId = self.viewModel.selectedNote?.id
                        Swift.print("[保存流程] 🔄 更新 notes 数组 - 笔记ID: \(noteId.prefix(8))..., 当前选中: \(oldSelectedNoteId?.prefix(8) ?? "nil")")
                        
                        if let index = self.viewModel.notes.firstIndex(where: { $0.id == noteId }) {
                            self.viewModel.notes[index] = updated
                            Swift.print("[保存流程] ✅ notes[\(index)] 已更新")
                        }
                        
                        // 同步更新 selectedNote（如果当前选中的是这个笔记）
                        // 这确保 selectedNote 的内容与 notes 数组中的笔记保持一致
                        if self.viewModel.selectedNote?.id == noteId {
                            self.viewModel.selectedNote = updated
                            Swift.print("[保存流程] ✅ selectedNote 已同步更新")
                        }
                        
                        let newSelectedNoteId = self.viewModel.selectedNote?.id
                        Swift.print("[保存流程] 📊 更新后选中状态: \(newSelectedNoteId?.prefix(8) ?? "nil")")
                        
                        // 更新内存缓存
                        await MemoryCacheManager.shared.cacheNote(updated)
                        
                        // 更新保存状态为"已保存"
                        self.saveStatus = .saved
                        
                        // 清除 coordinator 的未保存内容标志
                        // **Requirements: 6.1**
                        self.viewModel.stateCoordinator.hasUnsavedContent = false
                        
                        Swift.print("[保存流程] ✅ Tier 1 本地保存成功 - 笔记ID: \(noteId.prefix(8))..., 标题: \(self.editedTitle)")
                        continuation.resume()
                    }
                }
            }
        }
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
        guard viewModel.isOnline && viewModel.isLoggedIn else { return }
        
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
            
            await performCloudUpload(for: note, xmlContent: latestXMLContent)
            self.lastUploadedContentByNoteId[noteId] = latestXMLContent
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
        }
    }
    
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
        
        Swift.print("[笔记切换] 🔄 开始保存当前笔记 - 从ID: \(currentId.prefix(8))... 切换到ID: \(newNoteId.prefix(8))...")
        isSavingBeforeSwitch = true
        
        return Task { @MainActor in
            defer { isSavingBeforeSwitch = false }
            
            // 再次验证：确保当前编辑的笔记ID没有变化
            guard self.currentEditingNoteId == currentId else {
                Swift.print("[笔记切换] ⚠️ 笔记已切换，取消保存 - 当前ID: \(self.currentEditingNoteId?.prefix(8) ?? "nil"), 期望ID: \(currentId.prefix(8))...")
                return
            }
            
            // 1. 强制编辑器保存当前内容
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in 
                webEditorContext.forceSaveContent { c.resume() } 
            }
            
            // 2. 获取最新内容
            let content = await getLatestContentFromEditor()
            Swift.print("[笔记切换] 📝 获取编辑器内容 - 长度: \(content.count)")
            
            // 再次验证：确保笔记ID仍然匹配
            guard self.currentEditingNoteId == currentId else {
                Swift.print("[笔记切换] ⚠️ 笔记已切换，取消保存 - 当前ID: \(self.currentEditingNoteId?.prefix(8) ?? "nil"), 期望ID: \(currentId.prefix(8))...")
                return
            }
            
            // 3. 检查内容是否变化，如果有变化则立即保存XML（不等待HTML）
            if content != lastSavedXMLContent || editedTitle != originalTitle {
                Swift.print("[笔记切换] 💾 内容有变化，立即保存XML - 内容长度: \(content.count), 已保存: \(lastSavedXMLContent.count)")
                
                // 立即保存XML（关键数据），不等待HTML缓存
                // 使用保存的currentNote，而不是viewModel.selectedNote
                scheduleXMLSave(xmlContent: content, for: currentNote, immediate: true)
                
                // 只等待XML保存完成（关键数据），不等待HTML缓存（后台继续）
                if let xmlTask = xmlSaveTask {
                    // 使用超时机制，避免无限等待
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask {
                            await xmlTask.value
                        }
                        group.addTask {
                            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms超时
                        }
                        await group.next()
                        group.cancelAll()
                    }
                }
            } else {
                Swift.print("[笔记切换] ⏭️ 内容无变化，跳过保存")
            }
            
            // HTML保存任务在后台继续，不阻塞切换
            
            Swift.print("[笔记切换] ✅ 保存完成，准备切换到新笔记")
        }
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
        // 关键修复：根据当前使用的编辑器类型获取内容
        if isUsingNativeEditor {
            // 原生编辑器：从 nativeEditorContext 导出 XML
            let xmlContent = nativeEditorContext.exportToXML()
            if !xmlContent.isEmpty {
                Swift.print("[保存流程] 📝 从原生编辑器获取内容 - 长度: \(xmlContent.count)")
                return xmlContent
            }
        } else {
            // Web 编辑器：从 webEditorContext 获取内容
            if let content = await withCheckedContinuation({ (c: CheckedContinuation<String?, Never>) in webEditorContext.getCurrentContent { c.resume(returning: $0) } }) {
                Swift.print("[保存流程] 📝 从 Web 编辑器获取内容 - 长度: \(content.count)")
                return content
            }
        }
        
        // 回退到当前 XML 内容
        Swift.print("[保存流程] 📝 使用 currentXMLContent - 长度: \(currentXMLContent.count)")
        return currentXMLContent
    }
    
    private func buildUpdatedNote(from note: Note, xmlContent: String) -> Note {
        // 关键修复：确保使用传入的note的标题，而不是editedTitle（editedTitle可能在切换笔记后已改变）
        // 只有在当前编辑的笔记才使用editedTitle
        let titleToUse: String
        if note.id == currentEditingNoteId {
            titleToUse = editedTitle
        } else {
            titleToUse = note.title
        }
        
        return Note(id: note.id, title: titleToUse, content: xmlContent, folderId: note.folderId, isStarred: note.isStarred, createdAt: note.createdAt, updatedAt: Date(), tags: note.tags, rawData: note.rawData)
    }
    
    private func updateViewModelDelayed(with updated: Note) {
        if let index = viewModel.notes.firstIndex(where: { $0.id == updated.id }) {
            viewModel.notes[index] = updated
        }
        if viewModel.selectedNote?.id == updated.id {
            viewModel.selectedNote = updated
            
            // 通过 coordinator 更新笔记内容，保持选择状态不变
            // **Requirements: 1.1, 1.2, 1.3**
            // - 1.1: 编辑笔记内容时保持选中状态不变
            // - 1.2: 笔记内容保存触发 notes 数组更新时不重置 selectedNote
            // - 1.3: 笔记的 updatedAt 时间戳变化时保持选中笔记的高亮状态
            viewModel.stateCoordinator.updateNoteContent(updated)
        }
    }
    
    private func hasContentChanged(xmlContent: String) -> Bool {
        lastSavedXMLContent != xmlContent || editedTitle != originalTitle
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
/// 这个视图在每次显示时会重新检查编辑器类型，
/// 确保显示正确的格式菜单（原生或 Web）
@available(macOS 14.0, *)
struct FormatMenuPopoverContent: View {
    
    /// 原生编辑器上下文
    @ObservedObject var nativeEditorContext: NativeEditorContext
    
    /// Web 编辑器上下文
    @ObservedObject var webEditorContext: WebEditorContext
    
    /// 关闭回调
    let onDismiss: () -> Void
    
    /// 编辑器偏好设置服务
    @ObservedObject private var preferencesService = EditorPreferencesService.shared
    
    /// 当前是否使用原生编辑器
    private var isUsingNativeEditor: Bool {
        preferencesService.selectedEditorType == .native && preferencesService.isNativeEditorAvailable
    }
    
    var body: some View {
        Group {
            // 添加调试日志
            let _ = print("显示格式菜单")
            let _ = print("  - isUsingNativeEditor: \(isUsingNativeEditor)")
            let _ = print("  - selectedEditorType: \(preferencesService.selectedEditorType)")
            let _ = print("  - isNativeEditorAvailable: \(preferencesService.isNativeEditorAvailable)")
            
            if isUsingNativeEditor {
                NativeFormatMenuView(context: nativeEditorContext) { _ in onDismiss() }
            } else {
                WebFormatMenuView(context: webEditorContext) { _ in onDismiss() }
            }
        }
        .onAppear {
            print("[FormatMenuPopoverContent] onAppear")
            print("  - selectedEditorType: \(preferencesService.selectedEditorType.rawValue)")
            print("  - isNativeEditorAvailable: \(preferencesService.isNativeEditorAvailable)")
            
            // 如果使用原生编辑器，请求内容同步并更新格式状态
            if isUsingNativeEditor {
                print("  - 使用原生编辑器，请求内容同步")
                nativeEditorContext.requestContentSync()
                // 延迟一小段时间后强制更新格式状态
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    nativeEditorContext.forceUpdateFormats()
                }
            }
        }
    }
}
