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
    @State private var isEditable: Bool = true
    @State private var isInitializing: Bool = true
    @State private var originalTitle: String = ""
    @State private var originalXMLContent: String = ""
    @State private var currentEditingNoteId: String? = nil
    @State private var isSavingBeforeSwitch: Bool = false
    @State private var lastSavedXMLContent: String = ""
    @State private var isSavingLocally: Bool = false
    
    @State private var showImageInsertAlert: Bool = false
    @State private var imageInsertMessage: String = ""
    @State private var isInsertingImage: Bool = false
    @State private var imageInsertStatus: ImageInsertStatus = .idle
    
    enum ImageInsertStatus {
        case idle, uploading, success, failed
    }
    
    @State private var showingHistoryView: Bool = false
    @StateObject private var webEditorContext = WebEditorContext()
    
    var body: some View {
        Group {
            if let note = viewModel.selectedNote {
                noteEditorView(for: note)
            } else {
                emptyNoteView
            }
        }
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
        return Text("\(updateDateString) · \(wordCount) 字").font(.system(size: 10)).foregroundColor(.secondary)
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
            if let note = viewModel.selectedNote {
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
                        Task { @MainActor in
                            // [Tier 0] 立即保存 HTML 缓存，不阻塞，不触发全量刷新
                            if let html = newHTML {
                                flashSaveHTML(html, for: note)
                            }
                            
                            // [Tier 1] 异步保存 XML
                            self.currentXMLContent = newXML
                            await saveToLocalOnlyWithContent(xmlContent: newXML, for: note)
                            
                            // [Tier 2] 计划同步云端
                            scheduleCloudUpload(for: note, xmlContent: newXML)
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
        guard let note = viewModel.selectedNote else { return }
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
        
        Button { showingHistoryView = true } label: { Label("历史版本", systemImage: "clock.arrow.circlepath") }
        
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
            await loadNoteContent(note)
        }
    }
    
    @MainActor
    private func loadNoteContent(_ note: Note) async {
        // 防止内容污染：在加载新笔记前，确保所有状态正确重置
        isInitializing = true
        
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
            }
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
        await loadNoteContent(newValue)
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
        do {
            let updated = Note(id: note.id, title: title, content: xmlContent, folderId: note.folderId, isStarred: note.isStarred, createdAt: note.createdAt, updatedAt: Date(), tags: note.tags, rawData: note.rawData)
            try LocalStorageService.shared.saveNote(updated)
            lastSavedXMLContent = xmlContent
            originalTitle = title
            currentXMLContent = xmlContent
            updateViewModelDelayed(with: updated)
            scheduleCloudUpload(for: updated, xmlContent: xmlContent)
        } catch { Swift.print("Save failed") }
    }
    
    @MainActor
    private func flashSaveHTML(_ html: String, for note: Note) {
        // [Tier 0] 极速 HTML 缓存保存
        var updated = note
        updated.htmlContent = html
        updated.updatedAt = Date()
        
        do {
            // 直接写入数据库，不经过复杂逻辑
            try LocalStorageService.shared.saveNote(updated)
            
            // 优化：只在HTML内容真正变化时才更新列表，避免不必要的重新渲染
            // 检查当前列表中的笔记是否已经有相同的HTML内容
            if let index = viewModel.notes.firstIndex(where: { $0.id == note.id }) {
                let currentNote = viewModel.notes[index]
                // 只有当HTML内容不同时才更新数组
                if currentNote.htmlContent != html {
                    viewModel.notes[index] = updated
                    Swift.print("[保存流程] 🔄 Tier 0 更新列表HTML缓存")
                }
            }
            
            // [Tier 0] 成功日志
            Swift.print("[保存流程] ✅ Tier 0 HTML缓存保存成功 - 笔记ID: \(note.id.prefix(8))..., HTML长度: \(html.count)")
        } catch {
            Swift.print("[保存流程] ❌ Tier 0 HTML缓存保存失败: \(error)")
        }
    }

    @MainActor
    private func saveToLocalOnlyWithContent(xmlContent: String, for note: Note) async {
        guard note.id == currentEditingNoteId && hasContentChanged(xmlContent: xmlContent) else { 
            Swift.print("[保存流程] ⏭️ Tier 1 本地保存跳过 - 内容未变化或不是当前编辑笔记")
            return 
        }
        if isSavingLocally { 
            Swift.print("[保存流程] ⏸️ Tier 1 本地保存跳过 - 正在保存中")
            return 
        }
        isSavingLocally = true
        defer { isSavingLocally = false }
        do {
            var updated = buildUpdatedNote(from: note, xmlContent: xmlContent)
            // 保持当前的 HTML 缓存，如果存在的话
            updated.htmlContent = viewModel.notes.first(where: { $0.id == note.id })?.htmlContent
            
            Swift.print("[保存流程] 🔄 Tier 1 开始本地保存 - 笔记ID: \(note.id.prefix(8))..., XML长度: \(xmlContent.count)")
            try LocalStorageService.shared.saveNote(updated)
            lastSavedXMLContent = xmlContent
            currentXMLContent = xmlContent
            updateViewModelDelayed(with: updated)
            Swift.print("[保存流程] ✅ Tier 1 本地保存成功 - 笔记ID: \(note.id.prefix(8))..., 标题: \(editedTitle)")
        } catch { 
            Swift.print("[保存流程] ❌ Tier 1 本地保存失败: \(error)")
        }
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
        guard let currentId = currentEditingNoteId, currentId != newNoteId, let note = viewModel.selectedNote else { 
            Swift.print("[笔记切换] ⏭️ 无需保存 - 无当前编辑笔记或笔记ID相同")
            return nil 
        }
        
        Swift.print("[笔记切换] 🔄 开始保存当前笔记 - 从ID: \(currentId.prefix(8))... 切换到ID: \(newNoteId.prefix(8))...")
        isSavingBeforeSwitch = true
        
        return Task { @MainActor in
            defer { isSavingBeforeSwitch = false }
            
            // 1. 强制编辑器保存当前内容
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in 
                webEditorContext.forceSaveContent { c.resume() } 
            }
            
            // 2. 获取最新内容
            let content = await getLatestContentFromEditor()
            Swift.print("[笔记切换] 📝 获取编辑器内容 - 长度: \(content.count)")
            
            // 3. 检查内容是否变化，如果有变化则保存
            if hasContentChanged(xmlContent: content) {
                Swift.print("[笔记切换] 💾 内容有变化，开始保存")
                await saveToLocalOnlyWithContent(xmlContent: content, for: note)
            } else {
                Swift.print("[笔记切换] ⏭️ 内容无变化，跳过保存")
            }
            
            // 4. 确保保存完成
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms延迟确保保存完成
            
            Swift.print("[笔记切换] ✅ 保存完成，准备切换到新笔记")
        }
    }
    
    private func handleSelectedNoteChange(oldValue: Note?, newValue: Note?) {
        guard let newNote = newValue else { return }
        if oldValue?.id != newNote.id {
            let task = saveCurrentNoteBeforeSwitching(newNoteId: newNote.id)
            Task { @MainActor in
                if let t = task { await t.value }
                await loadNoteContent(newNote)
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
        Note(id: note.id, title: editedTitle, content: xmlContent, folderId: note.folderId, isStarred: note.isStarred, createdAt: note.createdAt, updatedAt: Date(), tags: note.tags, rawData: note.rawData)
    }
    
    private func updateViewModelDelayed(with updated: Note) {
        guard let index = viewModel.notes.firstIndex(where: { $0.id == updated.id }) else { return }
        Task { @MainActor in
            // 原子化更新：同时更新 notes 数组和 selectedNote（如果相关）
            // 这样可以减少不必要的UI重新渲染
            let isSelectedNote = viewModel.selectedNote?.id == updated.id
            
            // 更新笔记列表
            viewModel.notes[index] = updated
            
            // 如果当前选中的笔记就是被更新的笔记，确保 selectedNote 也更新
            // 使用相同的对象引用，避免不必要的视图重建
            if isSelectedNote {
                viewModel.selectedNote = updated
            }
            
            Swift.print("[保存流程] 🔄 更新视图模型 - 笔记ID: \(updated.id.prefix(8))..., 是否选中: \(isSelectedNote)")
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
