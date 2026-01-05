import SwiftUI
import AppKit

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
            .navigationTitle("详情")
            .toolbar {
                toolbarContent
            }
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
        ToolbarSpacer()
        ToolbarItemGroup(placement: .automatic) {
            undoButton
            redoButton
        }
        ToolbarSpacer(.fixed)
        ToolbarItemGroup(placement: .automatic) {
            formatMenu
            checkboxButton
            horizontalRuleButton
            imageButton
        }
        ToolbarSpacer(.fixed)
        ToolbarItemGroup(placement: .automatic) {
            indentButtons
            Spacer()
            if let note = viewModel.selectedNote {
                shareAndMoreButtons(for: note)
            }
        }
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
            
            // 保存状态指示器
            saveStatusIndicator
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
                WebEditorWrapper(
                    content: $currentXMLContent,
                    isEditable: $isEditable,
                    editorContext: webEditorContext,
                    noteRawData: {
                        if let rawData = note.rawData, let jsonData = try? JSONSerialization.data(withJSONObject: rawData, options: []) {
                            return String(data: jsonData, encoding: .utf8)
                        }
                        return nil
                    }(),
                    xmlContent: note.primaryXMLContent,
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
    
    private var emptyNoteView: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text").font(.system(size: 48)).foregroundColor(.secondary)
            Text("选择笔记或创建新笔记").font(.title2).foregroundColor(.secondary)
            Button(action: { viewModel.createNewNote() }) { Label("新建笔记", systemImage: "plus") }.buttonStyle(.borderedProminent)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var undoButton: some View { Button { webEditorContext.undo() } label: { Label("撤销", systemImage: "arrow.uturn.backward") } }
    private var redoButton: some View { Button { webEditorContext.redo() } label: { Label("重做", systemImage: "arrow.uturn.forward") } }
    
    @State private var showFormatMenu: Bool = false
    private var formatMenu: some View {
        Button { showFormatMenu.toggle() } label: { Label("格式", systemImage: "textformat") }
        .popover(isPresented: $showFormatMenu, arrowEdge: .top) {
            WebFormatMenuView(context: webEditorContext) { _ in showFormatMenu = false }
        }
    }
    
    private var checkboxButton: some View { Button { webEditorContext.insertCheckbox() } label: { Label("插入待办", systemImage: "checklist") } }
    private var horizontalRuleButton: some View { Button { webEditorContext.insertHorizontalRule() } label: { Label("插入分割线", systemImage: "minus") } }
    private var imageButton: some View { Button { insertImage() } label: { Label("插入图片", systemImage: "paperclip") } }
    
    @ViewBuilder
    private var indentButtons: some View {
        Button { webEditorContext.increaseIndent() } label: { Label("增加缩进", systemImage: "increase.indent") }
        Button { webEditorContext.decreaseIndent() } label: { Label("减少缩进", systemImage: "decrease.indent") }
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
            webEditorContext.insertImage("minote://image/\(fileId)", altText: url.lastPathComponent)
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
        // 1. 立即显示占位符（<1ms）
        isInitializing = true
        currentEditingNoteId = note.id
        
        // 立即更新标题（显示占位符）
        let title = note.title.isEmpty || note.title.hasPrefix("未命名笔记_") ? "" : note.title
        editedTitle = title
        originalTitle = title
        
        // 清空内容，显示加载状态
        currentXMLContent = ""
        lastSavedXMLContent = ""
        originalXMLContent = ""
        
        // 取消之前的保存任务
        htmlSaveTask?.cancel()
        xmlSaveTask?.cancel()
        xmlSaveDebounceTask?.cancel()
        htmlSaveTask = nil
        xmlSaveTask = nil
        xmlSaveDebounceTask = nil
        
        // 2. 尝试从内存缓存获取完整笔记
        let cachedNote = await MemoryCacheManager.shared.getNote(noteId: note.id)
        if let cachedNote = cachedNote {
            // 关键修复：验证缓存的笔记ID是否匹配
            if cachedNote.id == note.id {
                Swift.print("[快速切换] 内存缓存命中 - ID: \(note.id.prefix(8))...")
                await loadNoteContentFromCache(cachedNote)
                
                return
            } else {
                Swift.print("[快速切换] ⚠️ 缓存笔记ID不匹配，忽略缓存 - 缓存ID: \(cachedNote.id.prefix(8))..., 期望ID: \(note.id.prefix(8))...")
                // 继续使用数据库加载
            }
        }
        
        // 3. 尝试从HTML缓存快速加载
        if let htmlContent = try? DatabaseService.shared.getHTMLContent(noteId: note.id), !htmlContent.isEmpty {
            Swift.print("[快速切换] HTML缓存命中 - ID: \(note.id.prefix(8))...")
            await loadNoteContentWithHTML(note: note, htmlContent: htmlContent)
            
            // 后台加载完整内容
            Task { @MainActor in
                await loadFullContentAsync(for: note)
            }
            
            return
        }
        
        // 4. 从数据库加载完整内容
        Swift.print("[快速切换] 从数据库加载 - ID: \(note.id.prefix(8))...")
        await loadNoteContent(note)
    }
    
    /// 从缓存加载笔记内容
    @MainActor
    private func loadNoteContentFromCache(_ note: Note) async {
        // 重置状态
        currentXMLContent = ""
        lastSavedXMLContent = ""
        originalXMLContent = ""
        
        // 加载标题
        let title = note.title.isEmpty || note.title.hasPrefix("未命名笔记_") ? "" : note.title
        editedTitle = title
        originalTitle = title
        
        // 加载内容
        currentXMLContent = note.primaryXMLContent
        lastSavedXMLContent = currentXMLContent
        originalXMLContent = currentXMLContent
        
        Swift.print("[快速切换] ✅ 从缓存加载完成 - ID: \(note.id.prefix(8))..., 标题: \(title), 内容长度: \(currentXMLContent.count)")
        
        // 短暂延迟以确保编辑器正确初始化
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
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
        // 防止内容污染：在加载新笔记前，确保所有状态正确重置
        isInitializing = true
        
        // 0. 取消之前的保存任务（如果存在）
        htmlSaveTask?.cancel()
        xmlSaveTask?.cancel()
        xmlSaveDebounceTask?.cancel()
        htmlSaveTask = nil
        xmlSaveTask = nil
        xmlSaveDebounceTask = nil
        
        // 1. 首先重置所有内容相关的状态
        currentXMLContent = ""
        lastSavedXMLContent = ""
        originalXMLContent = ""
        
        // 2. 更新当前编辑的笔记ID
        currentEditingNoteId = note.id
        
        // 3. 加载标题
        let title = note.title.isEmpty || note.title.hasPrefix("未命名笔记_") ? "" : note.title
        editedTitle = title
        originalTitle = title
        
        // 4. 加载内容
        currentXMLContent = note.primaryXMLContent
        lastSavedXMLContent = currentXMLContent
        originalXMLContent = currentXMLContent
        
        // 5. 如果内容为空，确保获取完整内容
        if note.content.isEmpty {
            await viewModel.ensureNoteHasFullContent(note)
            if let updated = viewModel.selectedNote {
                currentXMLContent = updated.primaryXMLContent
                lastSavedXMLContent = currentXMLContent
                
                // 更新缓存
                await MemoryCacheManager.shared.cacheNote(updated)
            }
        } else {
            // 更新缓存
            await MemoryCacheManager.shared.cacheNote(note)
        }
        
        // 6. 添加日志以便调试
        Swift.print("[笔记切换] ✅ 加载笔记内容 - ID: \(note.id.prefix(8))..., 标题: \(title), 内容长度: \(currentXMLContent.count)")
        
        // 7. 短暂延迟以确保编辑器正确初始化
        try? await Task.sleep(nanoseconds: 100_000_000)
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
        // 保持当前的 HTML 缓存
        updated.htmlContent = viewModel.notes.first(where: { $0.id == note.id })?.htmlContent
        
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
        updated.htmlContent = htmlContent
        
        // 立即更新内存缓存（<1ms）
        await MemoryCacheManager.shared.cacheNote(updated)
        
        // 更新viewModel.notes数组（不更新selectedNote，避免闪烁）
        if let index = viewModel.notes.firstIndex(where: { $0.id == updated.id }) {
            viewModel.notes[index] = updated
        }
        
        // 更新保存状态为"保存中"
        saveStatus = .saving
        
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
            // 如果HTML内容相同，跳过保存
            if currentNote.htmlContent == html {
                Swift.print("[保存流程] ⏭️ Tier 0 HTML缓存跳过 - 内容未变化")
                return
            }
        }
        
        let noteId = note.id
        htmlSaveTask = Task { @MainActor in
            // 使用异步数据库方法，不阻塞主线程
            DatabaseService.shared.updateHTMLContentOnly(noteId: noteId, htmlContent: html) { error in
                Task { @MainActor in
                    // 检查任务是否被取消
                    guard !Task.isCancelled else {
                        Swift.print("[保存流程] ⏸️ Tier 0 HTML缓存保存已取消")
                        return
                    }
                    
                    if let error = error {
                        Swift.print("[保存流程] ❌ Tier 0 HTML缓存保存失败: \(error)")
                        return
                    }
                    
                        // 更新视图模型中的HTML内容，但不更新selectedNote（避免闪烁）
                        if let index = self.viewModel.notes.firstIndex(where: { $0.id == noteId }) {
                            var updatedNote = self.viewModel.notes[index]
                            updatedNote.htmlContent = html
                            // 不更新selectedNote，避免闪烁
                            self.viewModel.notes[index] = updatedNote
                        Swift.print("[保存流程] ✅ Tier 0 HTML缓存保存成功 - 笔记ID: \(noteId.prefix(8))..., HTML长度: \(html.count)")
                    }
                }
            }
        }
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
        // 保持当前的 HTML 缓存
        updated.htmlContent = viewModel.notes.first(where: { $0.id == note.id })?.htmlContent
        
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
                        
                        // 更新视图模型，但不更新selectedNote（避免闪烁）
                        if let index = self.viewModel.notes.firstIndex(where: { $0.id == noteId }) {
                            self.viewModel.notes[index] = updated
                        }
                        
                        // 更新内存缓存
                        await MemoryCacheManager.shared.cacheNote(updated)
                        
                        // 更新保存状态为"已保存"
                        self.saveStatus = .saved
                        
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
    @State private var lastUploadedContent: String = ""
    
    private func scheduleCloudUpload(for note: Note, xmlContent: String) {
        guard viewModel.isOnline && viewModel.isLoggedIn && xmlContent != lastUploadedContent else { return }
        cloudUploadTask?.cancel()
        let noteId = note.id
        cloudUploadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled && self.currentEditingNoteId == noteId else { return }
            await performCloudUpload(for: note, xmlContent: xmlContent)
            lastUploadedContent = xmlContent
        }
    }
    
    @MainActor
    private func performCloudUpload(for note: Note, xmlContent: String) async {
        let updated = buildUpdatedNote(from: note, xmlContent: xmlContent)
        isUploading = true
        Swift.print("[保存流程] 🔄 Tier 2 开始云端同步 - 笔记ID: \(note.id.prefix(8))..., XML长度: \(xmlContent.count)")
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
        if let content = await withCheckedContinuation({ (c: CheckedContinuation<String?, Never>) in webEditorContext.getCurrentContent { c.resume(returning: $0) } }) {
            return content
        }
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
