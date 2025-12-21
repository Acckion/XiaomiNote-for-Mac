import SwiftUI
import AppKit
import RichTextKit

/// 笔记详情视图
/// 
/// 负责显示和编辑单个笔记的内容，包括：
/// - 标题编辑
/// - 富文本内容编辑（使用 RichTextKit）
/// - 自动保存（本地立即保存，云端延迟上传）
/// - 格式工具栏
/// 
@available(macOS 14.0, *)
struct NoteDetailView: View {
    @ObservedObject var viewModel: NotesViewModel
    @State private var editedTitle: String = ""
    @State private var editedAttributedText: AttributedString = AttributedStringConverter.createEmptyAttributedString()  // 使用 AttributedString（SwiftUI 原生），带有默认属性
    @State private var editedRTFData: Data? = nil  // RTF数据（用于RichTextKit编辑器）
    @State private var isSaving: Bool = false
    @State private var isUploading: Bool = false  // 上传状态
    @State private var showSaveSuccess: Bool = false
    @State private var showSaveError: Bool = false
    @State private var saveError: String = ""
    @State private var isEditable: Bool = true // New state for editor editability
    @State private var isInitializing: Bool = true // 标记是否正在初始化
    @State private var originalTitle: String = "" // 保存原始标题用于比较
    @State private var originalAttributedText: AttributedString = AttributedStringConverter.createEmptyAttributedString() // 保存原始 AttributedString 用于比较，带有默认属性
    @State private var useRichTextKit: Bool = true  // 是否使用RichTextKit编辑器
    @StateObject private var editorContext = RichTextContext()  // RichTextContext（用于格式栏同步）
    @State private var pendingSaveWorkItem: DispatchWorkItem? = nil  // 待执行的保存任务
    @State private var pendingCloudUploadWorkItem: DispatchWorkItem? = nil  // 待执行的云端上传任务
    @State private var currentEditingNoteId: String? = nil  // 当前正在编辑的笔记ID
    @State private var isSavingBeforeSwitch: Bool = false  // 标记是否正在为切换笔记而保存
    @State private var pendingSwitchNoteId: String? = nil  // 等待切换的笔记ID
    @State private var lastSavedRTFData: Data? = nil  // 上次保存的 RTF 数据，用于避免重复保存
    @State private var isSavingLocally: Bool = false  // 标记是否正在本地保存
    
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
        .navigationTitle("")  // 添加空的 navigationTitle 以确保 toolbar 绑定到 detail 列
        .toolbar {
            // 最左侧：新建笔记按钮和格式工具按钮组（放在同一个 ToolbarItem 中，避免自动分割线）
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 8) {
                    newNoteButton
                    formatToolbarGroup
                }
            }
            
            // 搜索框（自动位置）
            ToolbarItem(placement: .automatic) {
                searchToolbarItem
            }
            
            // 最右侧：共享和更多按钮
            ToolbarItemGroup(placement: .primaryAction) {
                if let note = viewModel.selectedNote {
                    shareAndMoreButtons(for: note)
                }
            }
        }
    }
    
    @ViewBuilder
    private func noteEditorView(for note: Note) -> some View {
        ZStack {
            Color(nsColor: NSColor.textBackgroundColor)
                .ignoresSafeArea()
            
            // 标题现在作为编辑器内容的一部分，可以随正文滚动
            editorContentView(for: note)
        }
        .onAppear {
            handleNoteAppear(note)
        }
        .onChange(of: note) { oldValue, newValue in
            handleNoteChange(newValue)
        }
        .onChange(of: editedTitle) { oldValue, newValue in
            handleTitleChange(newValue)
        }
        .onChange(of: editedAttributedText) { oldValue, newValue in
            handleContentChange(newValue)
        }
        // 移除保存失败弹窗，改为静默处理
        // .alert("保存失败", isPresented: $showSaveError) {
        //     Button("重试") {
        //         saveChanges()
        //     }
        //     Button("取消", role: .cancel) {}
        // } message: {
        //     Text(saveError)
        // }
    }
    
    @ViewBuilder
    private var saveStatusIndicator: some View {
        HStack(spacing: 4) {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
                if isUploading {
                    Text("上传中...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("保存中...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if showSaveSuccess {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("已保存")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.trailing, 16)
        .padding(.top, 16)
    }
    
    private func editorContentView(for note: Note) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 标题编辑区域
                    titleEditorView
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .frame(minHeight: 60) // 增加最小高度，确保40pt字体完整显示
                    
                    // 日期和字数信息（只读）
                    metaInfoView(for: note)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    
                    // 间距
                    Spacer()
                        .frame(height: 16)
                    
                    // 正文编辑区域 - 填充剩余空间
                    bodyEditorView
                        .padding(.horizontal, 16) // 与标题左边对齐
                        .frame(minHeight: max(600, geometry.size.height - 200)) // 填充窗口高度，减去标题和间距
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    /// 标题编辑区域
    private var titleEditorView: some View {
        TitleEditorView(
            title: $editedTitle,
            isEditable: $isEditable
        )
    }
    
    /// 日期和字数信息视图（只读）
    private func metaInfoView(for note: Note) -> some View {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy年MM月dd日 HH:mm"
        let updateDateString = dateFormatter.string(from: note.updatedAt)
        
        // 计算字数（从 AttributedString 计算）
        let wordCount = calculateWordCount(from: editedAttributedText)
        
        return Text("\(updateDateString) · \(wordCount) 字")
            .font(.system(size: 10))
            .foregroundColor(.secondary)
    }
    
    /// 计算字数（从 AttributedString）
    private func calculateWordCount(from attributedText: AttributedString) -> Int {
        return attributedText.characters.count
    }
    
    /// 正文编辑区域（使用RichTextKit编辑器）
    private var bodyEditorView: some View {
        Group {
            if useRichTextKit {
                // 使用新的RichTextKit编辑器
                RichTextEditorWrapper(
                    rtfData: $editedRTFData,
                    isEditable: $isEditable,
                    editorContext: editorContext,
                    noteRawData: viewModel.selectedNote?.rawData,
                    xmlContent: viewModel.selectedNote?.primaryXMLContent,
                    onContentChange: { newRTFData in
                        // RTF数据变化时，更新 editedRTFData 并检查是否需要保存
                        guard !isInitializing, let rtfData = newRTFData else {
                            return
                        }
                        
                        // 检查内容是否真的变化了（避免仅打开笔记就触发保存）
                        // 比较 RTF 数据，如果相同则跳过保存
                        if let lastSaved = lastSavedRTFData, lastSaved == rtfData {
                            // RTF 数据相同，不需要保存（避免不必要的网络请求和修改时间更新）
                            // 但需要更新 editedRTFData 以确保状态一致
                            print("![[debug]]数据相同，不需要保存")
                            editedRTFData = rtfData
                            return
                        }
                        
                        editedRTFData = rtfData
                        
                        // 转换为 AttributedString 用于显示和保存
                        if let attributedText = AttributedStringConverter.rtfDataToAttributedString(rtfData) {
                            editedAttributedText = attributedText
                        }
                        
                        // 内容确实变化了，触发保存
                        guard let note = viewModel.selectedNote else {
                            return
                        }
                        
                        Task { @MainActor in
                            await saveToLocalOnly(for: note)
                            scheduleCloudUpload(for: note)
                        }
                    }
                )
                .padding(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
        }
    }
    
    private var emptyNoteView: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("选择笔记或创建新笔记")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Button(action: {
                viewModel.createNewNote()
            }) {
                Label("新建笔记", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var formatToolbarGroup: some View {
        HStack(spacing: 6) {
            undoButton
            redoButton
            Divider()
                .frame(height: 16)
            formatMenu
            checkboxButton
            imageButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
    }
    
    /// 撤销按钮
    ///
    /// 注意：键盘快捷键 Cmd+Z 和 Cmd+Shift+Z 由 NSTextView 自动处理，无需手动设置
    private var undoButton: some View {
        Button {
            editorContext.handle(.undoLatestChange)
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 16))
        }
        .buttonStyle(.plain)
        .disabled(!editorContext.canUndoLatestChange)
        .help("撤销 (⌘Z)")
    }
    
    /// 重做按钮
    ///
    /// 注意：键盘快捷键 Cmd+Z 和 Cmd+Shift+Z 由 NSTextView 自动处理，无需手动设置
    private var redoButton: some View {
        Button {
            editorContext.handle(.redoLatestChange)
        } label: {
            Image(systemName: "arrow.uturn.forward")
                .font(.system(size: 16))
        }
        .buttonStyle(.plain)
        .disabled(!editorContext.canRedoLatestChange)
        .help("重做 (⌘⇧Z)")
    }
    
    @State private var showFormatMenu: Bool = false
    
    private var formatMenu: some View {
        Button {
            showFormatMenu.toggle()
        } label: {
            Image(systemName: "textformat")
                .font(.system(size: 16))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showFormatMenu, arrowEdge: .top) {
            FormatMenuView(context: editorContext) { action in
                // FormatMenuView 使用 RichTextContext 直接处理格式操作，这里只需要关闭菜单
                showFormatMenu = false
            }
        }
    }
    
    
    private var checkboxButton: some View {
        Button {
            insertCheckbox()
        } label: {
            Image(systemName: "checklist")
        }
        .help("插入待办")
    }
    
    private var imageButton: some View {
        Button {
            insertImage()
        } label: {
            Image(systemName: "paperclip")
        }
        .help("插入图片")
    }
    
    /// 处理格式操作（目前 FormatMenuView 已经直接使用 RichTextContext 处理，此函数保留用于未来扩展）
    private func handleFormatAction(_ action: MiNoteEditor.FormatAction) {
        // FormatMenuView 已经通过 RichTextContext 直接处理格式操作
        // 这里可以添加额外的逻辑，例如记录操作历史等
        print("[NoteDetailView] 格式操作: \(action)")
    }
    
    /// 插入复选框
    private func insertCheckbox() {
        // 使用 RichTextContext 在当前位置插入复选框
        let checkbox = CheckboxTextAttachment()
        let checkboxString = NSAttributedString(attachment: checkbox)
        // 在复选框后添加一个空格
        let checkboxWithSpace = NSMutableAttributedString(attributedString: checkboxString)
        checkboxWithSpace.append(NSAttributedString(string: " "))
        
        // 获取插入位置
        let insertLocation: Int
        if editorContext.hasSelectedRange {
            insertLocation = editorContext.selectedRange.location
            // 替换选中的文本
            editorContext.handle(.replaceSelectedText(with: checkboxWithSpace))
        } else {
            // 如果没有选中范围，在光标位置或文档末尾插入
            insertLocation = editorContext.selectedRange.location < editorContext.attributedString.length 
                ? editorContext.selectedRange.location 
                : editorContext.attributedString.length
            // 在指定位置插入
            editorContext.handle(.replaceText(in: NSRange(location: insertLocation, length: 0), with: checkboxWithSpace))
        }
        
        print("[NoteDetailView] 已插入复选框")
    }
    
    /// 插入图片
    private func insertImage() {
        // 打开文件选择器选择图片
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.image, .png, .jpeg, .gif]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                // 在主线程处理图片插入
                Task { @MainActor in
                    await self.insertImage(from: url)
                }
            }
        }
    }
    
    /// 从 URL 插入图片
    @MainActor
    private func insertImage(from url: URL) async {
        guard let image = NSImage(contentsOf: url) else {
            print("[NoteDetailView] ⚠️ 无法加载图片: \(url)")
            return
        }
        
        // 调整图片大小（最大宽度 600pt）
        let maxWidth: CGFloat = 600
        let imageSize = image.size
        let aspectRatio = imageSize.width / imageSize.height
        let newSize: NSSize
        if imageSize.width > maxWidth {
            newSize = NSSize(width: maxWidth, height: maxWidth / aspectRatio)
        } else {
            newSize = imageSize
        }
        
        // 创建图片附件
        let imageAttachment = NSTextAttachment()
        imageAttachment.image = image
        imageAttachment.bounds = NSRect(origin: .zero, size: newSize)
        
        let imageString = NSMutableAttributedString(attributedString: NSAttributedString(attachment: imageAttachment))
        // 在图片后添加换行
        imageString.append(NSAttributedString(string: "\n"))
        
        // 插入图片到编辑器
        let insertLocation: Int
        if editorContext.hasSelectedRange {
            insertLocation = editorContext.selectedRange.location
            // 替换选中的文本
            editorContext.handle(.replaceSelectedText(with: imageString))
        } else {
            // 如果没有选中范围，在光标位置或文档末尾插入
            insertLocation = editorContext.selectedRange.location < editorContext.attributedString.length 
                ? editorContext.selectedRange.location 
                : editorContext.attributedString.length
            // 在指定位置插入
            editorContext.handle(.replaceText(in: NSRange(location: insertLocation, length: 0), with: imageString))
        }
        
        print("[NoteDetailView] 已插入图片: \(url.lastPathComponent)")
        
        // 触发保存（图片插入后需要保存）
        Task { @MainActor in
            await performSaveImmediately()
        }
    }
    
    @ViewBuilder
    private func shareAndMoreButtons(for note: Note) -> some View {
        Button {
            let sharingPicker = NSSharingServicePicker(items: [note.content])
            if let keyWindow = NSApplication.shared.keyWindow,
               let contentView = keyWindow.contentView {
                sharingPicker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        
        Menu {
            Button {
                viewModel.toggleStar(note)
            } label: {
                Label(note.isStarred ? "取消置顶备忘录" : "置顶备忘录",
                      systemImage: note.isStarred ? "pin.slash" : "pin")
            }
            
            Divider()
            
            Button(role: .destructive) {
                viewModel.deleteNote(note)
            } label: {
                Label("删除备忘录", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
    
    private var searchToolbarItem: some View {
        HStack {
            Spacer()
            TextField("搜索", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
        }
    }
    
    /// 新建笔记按钮
    private var newNoteButton: some View {
        Button {
            viewModel.createNewNote()
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 13, weight: .medium))
                .offset(y:-1)
            // 中等粗细
        }
        .help("新建笔记")
    }
    
    private func handleNoteAppear(_ note: Note) {
        // 在加载新笔记前，确保保存当前笔记的更改
        // 等待保存任务完成，确保保存完成后再加载新笔记
        let saveTask = saveCurrentNoteBeforeSwitching(newNoteId: note.id)
        
        // 如果保存任务存在，等待它完成后再继续
        if let saveTask = saveTask {
            Task { @MainActor in
                await saveTask.value
                await loadNoteContent(note)
            }
        } else {
            // 没有保存任务，直接加载笔记内容
            Task { @MainActor in
                await loadNoteContent(note)
            }
        }
    }
    
    /// 加载笔记内容到编辑器
    /// 
    /// 优先使用 rtfData，如果没有则从 XML 生成并保存。
    /// 
    /// - Parameter note: 要加载的笔记对象
    @MainActor
    private func loadNoteContent(_ note: Note) async {
        isInitializing = true
        currentEditingNoteId = note.id
        
        // 如果标题为空或者是默认的"未命名笔记_xxx"，设置为空字符串以显示占位符
        let cleanTitle = note.title.isEmpty || note.title.hasPrefix("未命名笔记_") ? "" : note.title
        editedTitle = cleanTitle
        originalTitle = cleanTitle
        
        var finalRTFData: Data? = note.rtfData
        var finalAttributedText: AttributedString?
        
        // 如果有 rtfData，直接从 rtfData 加载
        if let rtfData = note.rtfData {
            finalRTFData = rtfData
            finalAttributedText = AttributedStringConverter.rtfDataToAttributedString(rtfData)
        } else if !note.primaryXMLContent.isEmpty {
            // 如果没有 rtfData，从 XML 转换生成 rtfData
            let nsAttributedString = MiNoteContentParser.parseToAttributedString(note.primaryXMLContent, noteRawData: note.rawData)
            
            // 尝试使用 archivedData 格式（支持图片附件）
            var generatedRTFData: Data?
            do {
                generatedRTFData = try nsAttributedString.richTextData(for: .archivedData)
            } catch {
                // 回退到 RTF 格式
                let rtfRange = NSRange(location: 0, length: nsAttributedString.length)
                generatedRTFData = try? nsAttributedString.data(from: rtfRange, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            }
            
            // 如果成功生成 rtfData，保存到数据库
            if let rtfData = generatedRTFData {
                finalRTFData = rtfData
                
                // 保存到数据库
                var updatedNote = note
                updatedNote.rtfData = rtfData
                do {
                    try LocalStorageService.shared.saveNote(updatedNote)
                    
                    // 更新 ViewModel 中的笔记对象
                    await MainActor.run {
                        if let index = viewModel.notes.firstIndex(where: { $0.id == note.id }) {
                            viewModel.notes[index] = updatedNote
                            if viewModel.selectedNote?.id == note.id {
                                viewModel.selectedNote = updatedNote
                            }
                        }
                    }
                } catch {
                    print("[NoteDetailView] ⚠️ 保存生成的 rtfData 到数据库失败: \(error)")
                }
                
                // 转换为 AttributedString
                finalAttributedText = AttributedStringConverter.rtfDataToAttributedString(rtfData)
            } else {
                // 如果无法生成 rtfData，从 XML 直接转换 AttributedString（向后兼容）
                finalAttributedText = AttributedStringConverter.xmlToAttributedString(note.primaryXMLContent, noteRawData: note.rawData)
            }
        } else {
            // 内容为空，创建空 AttributedString
            finalAttributedText = AttributedStringConverter.createEmptyAttributedString()
        }
        
        // 设置编辑器状态
        editedRTFData = finalRTFData
        if let attributedText = finalAttributedText {
            editedAttributedText = attributedText
            originalAttributedText = attributedText
        } else {
            // 如果仍然无法获取内容，创建空 AttributedString
            editedAttributedText = AttributedStringConverter.createEmptyAttributedString()
            originalAttributedText = AttributedStringConverter.createEmptyAttributedString()
        }
        
        // 重置 lastSavedRTFData，确保下次编辑能正确保存
        lastSavedRTFData = finalRTFData
        
        if note.content.isEmpty {
            await viewModel.ensureNoteHasFullContent(note)
            if let updatedNote = viewModel.selectedNote {
                // 更新RTF数据
                if let rtfData = updatedNote.rtfData {
                    editedRTFData = rtfData
                } else if let attributedText = AttributedStringConverter.xmlToAttributedString(updatedNote.primaryXMLContent, noteRawData: updatedNote.rawData),
                          let rtfData = AttributedStringConverter.attributedStringToRTFData(attributedText) {
                    editedRTFData = rtfData
                }
                
                // 更新AttributedString
                if let rtfData = updatedNote.rtfData,
                   let attributedText = AttributedStringConverter.rtfDataToAttributedString(rtfData) {
                    editedAttributedText = attributedText
                    originalAttributedText = attributedText
                } else if let attributedText = AttributedStringConverter.xmlToAttributedString(updatedNote.primaryXMLContent, noteRawData: updatedNote.rawData) {
                    editedAttributedText = attributedText
                    originalAttributedText = attributedText
                }
            }
        }
        
        // 延迟一小段时间后标记初始化完成
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
        isInitializing = false
    }
    
    /// 处理笔记变化
    /// 
    /// 在加载新笔记前，确保保存当前笔记的更改。
    /// 
    /// - Parameter newValue: 新的笔记对象
    private func handleNoteChange(_ newValue: Note) {
        let saveTask = saveCurrentNoteBeforeSwitching(newNoteId: newValue.id)
        
        Task { @MainActor in
            // 如果有保存任务，等待它完成
            if let saveTask = saveTask {
                await saveTask.value
            }
            // 加载新笔记内容
            await loadNoteContent(newValue)
        }
    }
    
    private func handleTitleChange(_ newValue: String) {
        guard !isInitializing else {
            print("[[调试]]步骤4.3 [NoteDetailView] 标题变化检测，但正在初始化，跳过处理")
            return
        }
        if newValue != originalTitle {
            print("[[调试]]步骤5 [NoteDetailView] 标题变化检测到，立即保存，旧标题: '\(originalTitle)', 新标题: '\(newValue)'")
            originalTitle = newValue
            // 立即保存，不使用防抖
            Task { @MainActor in
                print("[[调试]]步骤6 [NoteDetailView] 触发立即保存，笔记ID: \(viewModel.selectedNote?.id ?? "无")")
                await performSaveImmediately()
            }
        }
    }
    
    /// 处理内容变化
    /// 
    /// 当 AttributedString 变化时，立即保存。
    /// 
    /// - Parameter newValue: 新的 AttributedString
    private func handleContentChange(_ newValue: AttributedString) {
        guard !isInitializing else {
            return
        }
        
        // 检查内容是否真的改变了
        let newString = String(newValue.characters)
        let originalString = String(originalAttributedText.characters)
        
        guard newString != originalString else {
            return
        }
        
        originalAttributedText = newValue
        
        // 立即保存
        Task { @MainActor in
            await performSaveImmediately()
        }
    }
    
    
    
    /// 保存更改（优化策略：本地立即保存，云端延迟上传）
    /// 
    /// 此方法已废弃，现在使用 `performSaveImmediately` 替代。
    /// 保留用于向后兼容。
    /// 
    @available(*, deprecated, message: "使用 performSaveImmediately 替代")
    private func saveChanges() {
        guard let note = viewModel.selectedNote,
              !isSavingBeforeSwitch else {
            return
        }
        
        // 检查是否有未保存的更改
        let hasTitleChanges = editedTitle != originalTitle
        let hasContentChanges = String(editedAttributedText.characters) != String(originalAttributedText.characters)
        
        guard hasTitleChanges || hasContentChanges else {
            return
        }
        
        // 取消之前的云端上传任务
        pendingCloudUploadWorkItem?.cancel()
        
        // 立即保存到本地
        Task { @MainActor in
            await saveToLocalOnly(for: note)
        }
        
        // 延迟上传到云端
        scheduleCloudUpload(for: note)
    }
    
    /// 仅保存到本地（立即执行，无延迟）
    /// 
    /// 从编辑器获取最新内容，保存到本地数据库，不触发云端上传。
    /// 云端上传由 `scheduleCloudUpload` 单独处理。
    /// 
    /// - Parameter note: 要保存的笔记对象
    @MainActor
    private func saveToLocalOnly(for note: Note) async {
        // 验证笔记ID
        guard note.id == currentEditingNoteId else {
            return
        }
        
        // 防止并发保存
        if isSavingLocally {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
            if isSavingLocally {
                return
            }
        }
        
        isSavingLocally = true
        defer { isSavingLocally = false }
        
        do {
            // 获取最新内容
            let (rtfData, attributedText) = getLatestContentFromEditor()
            
            // 验证内容不是标题（防止标题被错误地保存为正文）
            let contentString = String(attributedText.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            let titleString = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if contentString == titleString && !contentString.isEmpty {
                print("⚠️ [NoteDetailView] 错误：正文内容与标题相同，跳过保存以防止数据丢失")
                // 如果内容与标题相同，使用 editedAttributedText 作为后备
                // 这确保即使 getLatestContentFromEditor 返回了错误的内容，我们也能使用正确的正文
                let fallbackAttributedText = editedAttributedText
                let fallbackRtfData = editedRTFData
                
                // 检查是否有变化（避免重复保存）
                guard hasContentChanged(rtfData: fallbackRtfData) else {
                    return
                }
                
                // 构建更新的笔记对象（使用后备内容）
                let updatedNote = buildUpdatedNote(from: note, rtfData: fallbackRtfData, attributedText: fallbackAttributedText)
                
                // 保存到数据库
                try LocalStorageService.shared.saveNote(updatedNote)
                
                // 更新状态
                updateSaveState(rtfData: fallbackRtfData, attributedText: fallbackAttributedText)
                
                // 延迟更新 ViewModel（避免触发重新加载）
                updateViewModelDelayed(with: updatedNote)
                return
            }
            
            // 检查是否有变化（避免重复保存）
            guard hasContentChanged(rtfData: rtfData) else {
                return
            }
            
            // 构建更新的笔记对象
            let updatedNote = buildUpdatedNote(from: note, rtfData: rtfData, attributedText: attributedText)
            
            // 保存到数据库
            try LocalStorageService.shared.saveNote(updatedNote)
            
            // 更新状态
            updateSaveState(rtfData: rtfData, attributedText: attributedText)
            
            // 延迟更新 ViewModel（避免触发重新加载）
            updateViewModelDelayed(with: updatedNote)
            
        } catch {
            print("[NoteDetailView] ❌ 本地保存失败: \(error.localizedDescription)")
        }
    }
    
    /// 安排云端上传（智能防抖）
    /// 
    /// 根据内容大小智能调整防抖时间，避免频繁上传。
    /// 大文件延迟更长，小文件延迟较短。
    /// 
    /// - Parameter note: 要上传的笔记对象
    private func scheduleCloudUpload(for note: Note) {
        guard viewModel.isOnline && viewModel.isLoggedIn else {
            return
        }
        
        // 取消之前的云端上传任务
        pendingCloudUploadWorkItem?.cancel()
        
        // 根据内容大小智能调整防抖时间
        let rtfDataSize = editedRTFData?.count ?? 0
        let debounceTime: TimeInterval = {
            if rtfDataSize > 1_000_000 { return 3.0 }      // > 1MB: 3秒
            else if rtfDataSize > 500_000 { return 2.0 } // > 500KB: 2秒
            else { return 1.0 }                          // 小文件: 1秒
        }()
        
        // 捕获当前状态
        let currentNoteId = currentEditingNoteId
        let viewModelRef = viewModel
        
        let uploadWorkItem = DispatchWorkItem {
            Task { @MainActor in
                guard let note = viewModelRef.selectedNote, note.id == currentNoteId else {
                    return
                }
                
                // 获取最新内容
                let (rtfData, attributedText) = self.getLatestContentFromEditor()
                
                // 构建更新的笔记对象
                let updatedNote = self.buildUpdatedNote(from: note, rtfData: rtfData, attributedText: attributedText)
                
                // 开始上传
                isUploading = true
                
                do {
                    // 触发云端上传（updateNote 会再次保存到本地，这是幂等操作）
                    try await viewModelRef.updateNote(updatedNote)
                    
                    // 显示成功提示
                    withAnimation {
                        showSaveSuccess = true
                        isUploading = false
                    }
                    
                    // 2秒后隐藏成功提示
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            showSaveSuccess = false
                        }
                    }
                } catch {
                    print("[NoteDetailView] ❌ 云端上传失败: \(error.localizedDescription)")
                    isUploading = false
                    // 上传失败不影响本地数据，离线时会自动添加到队列
                }
            }
        }
        
        pendingCloudUploadWorkItem = uploadWorkItem
        
        // 智能防抖：根据内容大小调整延迟时间
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceTime, execute: uploadWorkItem)
    }
    
    /// 立即保存更改（用于切换笔记前）
    /// 
    /// 在切换到新笔记前，确保当前笔记的更改已保存。
    /// 
    /// - Parameter note: 要保存的笔记对象
    @MainActor
    private func saveChangesImmediately(for note: Note) async {
        // 取消待执行的保存任务
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        pendingCloudUploadWorkItem?.cancel()
        
        // 如果使用 RichTextKit，确保从 editorContext 获取最新内容并更新状态
        if useRichTextKit {
            let contextAttributedString = editorContext.attributedString
            if contextAttributedString.length > 0 {
                let swiftUIAttributedString = AttributedString(contextAttributedString)
                editedAttributedText = swiftUIAttributedString
                
                // 更新 RTF 数据
                do {
                    let archivedData = try contextAttributedString.richTextData(for: .archivedData)
                    editedRTFData = archivedData
                } catch {
                    // 如果 archivedData 失败，尝试使用 RTF 格式
                    editedRTFData = AttributedStringConverter.attributedStringToRTFData(swiftUIAttributedString)
                }
            }
        }
        
        // 直接调用 saveToLocalOnly，确保保存最新内容
        await saveToLocalOnly(for: note)
    }
    
    /// 立即执行保存操作（编辑即保存）
    /// 
    /// 立即保存到本地，并安排云端上传。
    /// 
    @MainActor
    private func performSaveImmediately() async {
        guard let note = viewModel.selectedNote,
              note.id == currentEditingNoteId,
              !isSavingBeforeSwitch else {
            return
        }
        
        // 立即保存到本地
        await saveToLocalOnly(for: note)
        
        // 安排云端上传（如果在线）
        scheduleCloudUpload(for: note)
    }
    
    /// 执行保存操作（已废弃，使用 saveToLocalOnly + scheduleCloudUpload）
    /// 
    /// 此方法保留用于向后兼容，但推荐使用新的分层保存策略：
    /// - `saveToLocalOnly`: 立即保存到本地
    /// - `scheduleCloudUpload`: 延迟上传到云端
    /// 
    /// - Parameter note: 要保存的笔记对象
    @MainActor
    @available(*, deprecated, message: "使用 saveToLocalOnly + scheduleCloudUpload 替代")
    private func performSave(for note: Note) async {
        guard note.id == currentEditingNoteId else {
            return
        }
        
        isSaving = true
        let willUpload = viewModel.isOnline && viewModel.isLoggedIn
        isUploading = willUpload
        
        do {
            // 获取最新内容
            let (rtfData, attributedText) = getLatestContentFromEditor()
            
            // 构建更新的笔记对象
            let updatedNote = buildUpdatedNote(from: note, rtfData: rtfData, attributedText: attributedText)
            
            // updateNote 会先保存到本地，然后上传到云端（如果在线）
            try await viewModel.updateNote(updatedNote)
            
            // 更新状态
            updateSaveState(rtfData: rtfData, attributedText: attributedText)
            
            // 保存成功反馈
            withAnimation {
                showSaveSuccess = true
                isSaving = false
                isUploading = false
            }
            
            // 2秒后隐藏成功提示
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showSaveSuccess = false
                }
            }
        } catch {
            print("[NoteDetailView] ❌ 保存失败: \(error.localizedDescription)")
            isSaving = false
            isUploading = false
        }
    }
    
    // MARK: - 切换笔记保存逻辑
    
    /// 在切换到新笔记前保存当前笔记的更改
    /// 
    /// 返回一个 Task，调用者可以等待它完成。
    /// 确保在切换笔记前，当前笔记的所有更改都已保存。
    /// 
    /// - Parameter newNoteId: 要切换到的新笔记ID
    /// - Returns: 保存任务，如果不需要保存则返回 nil
    @discardableResult
    private func saveCurrentNoteBeforeSwitching(newNoteId: String) -> Task<Void, Never>? {
        guard let currentNoteId = currentEditingNoteId,
              currentNoteId != newNoteId,
              let currentNote = viewModel.selectedNote,
              currentNote.id == currentNoteId else {
            return nil
        }
        
        // 取消待执行的保存任务
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        pendingCloudUploadWorkItem?.cancel()
        
        // 标记正在为切换而保存
        isSavingBeforeSwitch = true
        
        return Task { @MainActor in
            // 如果使用 RichTextKit，确保从 editorContext 获取最新内容并更新状态
            if useRichTextKit {
                let contextAttributedString = editorContext.attributedString
                if contextAttributedString.length > 0 {
                    let swiftUIAttributedString = AttributedString(contextAttributedString)
                    editedAttributedText = swiftUIAttributedString
                    
                    // 更新 RTF 数据
                    do {
                        let archivedData = try contextAttributedString.richTextData(for: .archivedData)
                        editedRTFData = archivedData
                    } catch {
                        // 如果 archivedData 失败，尝试使用 RTF 格式
                        editedRTFData = AttributedStringConverter.attributedStringToRTFData(swiftUIAttributedString)
                    }
                }
            }
            
            // 直接调用 saveToLocalOnly，确保保存最新内容
            await saveToLocalOnly(for: currentNote)
            isSavingBeforeSwitch = false
        }
    }
    
    /// 处理选中的笔记变化
    private func handleSelectedNoteChange(oldValue: Note?, newValue: Note?) {
        print("[[调试]]步骤61 [NoteDetailView] 检测笔记切换，旧笔记ID: \(oldValue?.id ?? "无"), 新笔记ID: \(newValue?.id ?? "无")")
        guard let oldNote = oldValue, let newNote = newValue else {
            // 如果没有旧笔记或新笔记，直接处理
            if let note = newValue {
                handleNoteChange(note)
            }
            return
        }
        
        // 如果切换到不同的笔记
        if oldNote.id != newNote.id {
            print("[[调试]]步骤61.1 [NoteDetailView] 切换到新笔记: \(oldNote.id) -> \(newNote.id)")
            // 保存当前笔记的更改，并等待保存任务完成
            let saveTask = saveCurrentNoteBeforeSwitching(newNoteId: newNote.id)
            
            // 如果保存任务存在，等待它完成后再加载新笔记
            if let saveTask = saveTask {
                print("[[调试]]步骤66 [NoteDetailView] 等待切换前保存完成，保存任务存在: true")
                Task { @MainActor in
                    await saveTask.value
                    await handleNoteChangeAsync(newNote)
                }
            } else {
                // 没有保存任务，直接加载新笔记
                print("[[调试]]步骤66 [NoteDetailView] 等待切换前保存完成，保存任务存在: false，直接加载新笔记")
                Task { @MainActor in
                    await handleNoteChangeAsync(newNote)
                }
            }
        } else {
            // 相同笔记，只是内容更新
            // 注意：如果这是保存操作导致的更新，不应该重新加载内容（会覆盖编辑器状态）
            // 只有在外部更新（如云端同步）时才重新加载
            print("[[调试]]步骤61.2 [NoteDetailView] 相同笔记，只是内容更新，笔记ID: \(newNote.id)")
            
            // 检查是否是保存操作导致的更新（通过检查是否正在保存）
            if isSavingLocally || isSavingBeforeSwitch {
                print("[[调试]]步骤61.3 [NoteDetailView] ⚠️ 正在保存，跳过重新加载（避免覆盖编辑器状态）")
                return
            }
            
            // 检查是否是初始化阶段
            if isInitializing {
                print("[[调试]]步骤61.4 [NoteDetailView] ⚠️ 正在初始化，跳过重新加载")
                return
            }
            
            // 只有非保存操作导致的更新才重新加载
            Task { @MainActor in
                await handleNoteChangeAsync(newNote)
            }
        }
    }
    
    /// 异步处理笔记变化
    @MainActor
    private func handleNoteChangeAsync(_ newValue: Note) async {
        // 直接加载新笔记内容
        // 保存已经在 handleSelectedNoteChange 中处理过了
        print("[[调试]]步骤67 [NoteDetailView] 异步处理笔记变化，笔记ID: \(newValue.id)")
        await loadNoteContent(newValue)
    }
    
    // MARK: - 保存辅助方法
    
    /// 从编辑器获取最新的内容（RTF数据和AttributedString）
    /// - Returns: (rtfData: 存档数据, attributedText: SwiftUI AttributedString)
    private func getLatestContentFromEditor() -> (rtfData: Data?, attributedText: AttributedString) {
        if useRichTextKit {
            let contextAttributedString = editorContext.attributedString
            
            // 验证内容不是标题（标题不应该出现在正文编辑器中）
            // 如果 context 的内容与标题相同，说明可能出现了错误，使用 editedAttributedText 作为后备
            let contextString = contextAttributedString.string.trimmingCharacters(in: .whitespacesAndNewlines)
            let titleString = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if contextAttributedString.length > 0 && contextString != titleString {
                let swiftUIAttributedText = AttributedString(contextAttributedString)
                
                // 尝试生成 archivedData（支持图片附件）
                do {
                    let archivedData = try contextAttributedString.richTextData(for: .archivedData)
                    return (archivedData, swiftUIAttributedText)
                } catch {
                    // 如果失败，使用 editedRTFData 作为后备
                    return (editedRTFData, swiftUIAttributedText)
                }
            } else {
                // 如果 context 为空或内容与标题相同，使用 editedRTFData 或 editedAttributedText
                // 这确保即使 context 被错误地设置为标题，我们也能使用正确的正文内容
                if contextString == titleString && contextAttributedString.length > 0 {
                    print("⚠️ [NoteDetailView] 警告：editorContext 的内容与标题相同，使用 editedAttributedText 作为后备")
                }
                return (editedRTFData, editedAttributedText)
            }
        } else {
            // 非 RichTextKit 模式
            let rtfData = AttributedStringConverter.attributedStringToRTFData(editedAttributedText)
            return (rtfData, editedAttributedText)
        }
    }
    
    /// 构建更新的笔记对象
    /// - Parameters:
    ///   - note: 原始笔记对象
    ///   - rtfData: RTF数据
    ///   - attributedText: AttributedString
    /// - Returns: 更新后的笔记对象
    private func buildUpdatedNote(
        from note: Note,
        rtfData: Data?,
        attributedText: AttributedString
    ) -> Note {
        let xmlContent = AttributedStringConverter.attributedStringToXML(attributedText)
        
        return Note(
            id: note.id,
            title: editedTitle,
            content: xmlContent,
            folderId: note.folderId,
            isStarred: note.isStarred,
            createdAt: note.createdAt,
            updatedAt: Date(),
            tags: note.tags,
            rawData: note.rawData,
            rtfData: rtfData
        )
    }
    
    /// 更新保存后的状态变量
    /// - Parameters:
    ///   - rtfData: 保存的RTF数据
    ///   - attributedText: 保存的AttributedString
    private func updateSaveState(rtfData: Data?, attributedText: AttributedString) {
        lastSavedRTFData = rtfData
        originalTitle = editedTitle
        originalAttributedText = attributedText
        
        if useRichTextKit {
            editedRTFData = rtfData
        }
    }
    
    /// 更新 ViewModel 中的笔记对象（延迟更新，避免触发重新加载）
    /// - Parameter updatedNote: 更新后的笔记对象
    private func updateViewModelDelayed(with updatedNote: Note) {
        guard let index = viewModel.notes.firstIndex(where: { $0.id == updatedNote.id }) else {
            return
        }
        
        // 延迟更新 ViewModel，确保保存操作完全完成后再更新
        // 这样可以避免触发重新加载
        Task { @MainActor in
            // 等待一小段时间，确保保存操作完全完成
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05秒
            
            // 临时标记正在保存，避免触发重新加载
            let wasSaving = isSavingLocally
            isSavingLocally = true
            
            viewModel.notes[index] = updatedNote
            if viewModel.selectedNote?.id == updatedNote.id {
                viewModel.selectedNote = updatedNote
            }
            
            // 恢复保存状态
            isSavingLocally = wasSaving
        }
    }
    
    /// 检查内容是否真的变化了（避免重复保存）
    /// - Parameters:
    ///   - rtfData: 当前的RTF数据
    /// - Returns: 如果内容或标题有变化，返回true
    private func hasContentChanged(rtfData: Data?) -> Bool {
        // 检查RTF数据是否变化
        if let lastSaved = lastSavedRTFData, let current = rtfData, lastSaved == current {
            // RTF数据相同，检查标题是否变化
            return editedTitle != originalTitle
        }
        // RTF数据不同，肯定有变化
        return true
    }
}

#Preview {
    NoteDetailView(viewModel: NotesViewModel())
        .frame(width: 600, height: 400)
}
