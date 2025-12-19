import SwiftUI
import AppKit
import RichTextKit

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
    @State private var currentEditingNoteId: String? = nil  // 当前正在编辑的笔记ID
    
    var body: some View {
        Group {
            if let note = viewModel.selectedNote {
                noteEditorView(for: note)
            } else {
                emptyNoteView
            }
        }
        .onChange(of: viewModel.selectedNote) { oldValue, newValue in
            // 当 selectedNote 对象变化时（包括内容更新），更新视图
            // 在切换笔记前，先保存当前笔记的更改
            if let oldNote = oldValue, let newNote = newValue, oldNote.id != newNote.id {
                // 笔记ID变化，说明切换到了不同的笔记，先立即保存当前笔记
                Task { @MainActor in
                    await saveChangesImmediately(for: oldNote)
                    // 保存完成后再切换到新笔记
                    if let note = newValue {
                        handleNoteChange(note)
                    }
                }
            } else {
                // 不是切换笔记，正常处理
                if let note = newValue {
                    // 只有当笔记真正变化时才更新（避免重复更新）
                    if let oldNote = oldValue {
                        if oldNote.id != note.id || oldNote.content != note.content {
                            handleNoteChange(note)
                        }
                    } else {
                        // 如果之前没有选中的笔记，直接更新
                        handleNoteChange(note)
                    }
                }
            }
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
                        // RTF数据变化时，转换为AttributedString用于保存
                        if let rtfData = newRTFData,
                           let attributedText = AttributedStringConverter.rtfDataToAttributedString(rtfData) {
                            editedAttributedText = attributedText
                            handleContentChange(attributedText)
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
        saveChanges()
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
        isInitializing = true
        // 更新当前编辑的笔记ID
        currentEditingNoteId = note.id
        
        // 如果标题为空或者是默认的"未命名笔记_xxx"，设置为空字符串以显示占位符
        let cleanTitle = note.title.isEmpty || note.title.hasPrefix("未命名笔记_") ? "" : note.title
        editedTitle = cleanTitle
        originalTitle = cleanTitle
        
        // 加载RTF数据（用于RichTextKit编辑器）
        if let rtfData = note.rtfData {
            editedRTFData = rtfData
        } else {
            // 如果没有RTF数据，从XML转换生成RTF数据
            if let attributedText = AttributedStringConverter.xmlToAttributedString(note.primaryXMLContent, noteRawData: note.rawData),
               let rtfData = AttributedStringConverter.attributedStringToRTFData(attributedText) {
                editedRTFData = rtfData
            } else {
                editedRTFData = nil
            }
        }
        
        // 使用 AttributedString：优先从 RTF 数据转换，否则从 XML 转换
        if let rtfData = note.rtfData,
           let attributedText = AttributedStringConverter.rtfDataToAttributedString(rtfData) {
            editedAttributedText = attributedText
            originalAttributedText = attributedText
        } else {
            // 向后兼容：如果没有 RTF 数据，从 XML 转换
            if let attributedText = AttributedStringConverter.xmlToAttributedString(note.primaryXMLContent, noteRawData: note.rawData) {
                editedAttributedText = attributedText
                originalAttributedText = attributedText
            } else {
                // 新建笔记或内容为空时，创建带有默认属性的空 AttributedString
                // 确保文本颜色等属性正确设置，适配深色模式
                editedAttributedText = AttributedStringConverter.createEmptyAttributedString()
                originalAttributedText = AttributedStringConverter.createEmptyAttributedString()
            }
        }
        
        if note.content.isEmpty {
            Task {
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
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isInitializing = false
        }
    }
    
    private func handleNoteChange(_ newValue: Note) {
        isInitializing = true
        // 更新当前编辑的笔记ID
        currentEditingNoteId = newValue.id
        
        // 如果标题为空或者是默认的"未命名笔记_xxx"，设置为空字符串以显示占位符
        let cleanTitle = newValue.title.isEmpty || newValue.title.hasPrefix("未命名笔记_") ? "" : newValue.title
        editedTitle = cleanTitle
        originalTitle = cleanTitle
        
        // 加载RTF数据（用于RichTextKit编辑器）
        if let rtfData = newValue.rtfData {
            editedRTFData = rtfData
        } else {
            // 如果没有RTF数据，从XML转换生成RTF数据
            if let attributedText = AttributedStringConverter.xmlToAttributedString(newValue.primaryXMLContent, noteRawData: newValue.rawData),
               let rtfData = AttributedStringConverter.attributedStringToRTFData(attributedText) {
                editedRTFData = rtfData
            } else {
                editedRTFData = nil
            }
        }
        
        // 使用 AttributedString：优先从 RTF 数据转换，否则从 XML 转换
        if let rtfData = newValue.rtfData,
           let attributedText = AttributedStringConverter.rtfDataToAttributedString(rtfData) {
            editedAttributedText = attributedText
            originalAttributedText = attributedText
        } else {
            // 向后兼容：如果没有 RTF 数据，从 XML 转换
            if let attributedText = AttributedStringConverter.xmlToAttributedString(newValue.primaryXMLContent, noteRawData: newValue.rawData) {
                editedAttributedText = attributedText
                originalAttributedText = attributedText
            } else {
                // 新建笔记或内容为空时，创建带有默认属性的空 AttributedString
                // 确保文本颜色等属性正确设置，适配深色模式
                editedAttributedText = AttributedStringConverter.createEmptyAttributedString()
                originalAttributedText = AttributedStringConverter.createEmptyAttributedString()
            }
        }
        
        if newValue.content.isEmpty {
            Task {
                await viewModel.ensureNoteHasFullContent(newValue)
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
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isInitializing = false
        }
    }
    
    private func handleTitleChange(_ newValue: String) {
        guard !isInitializing else { return }
        if newValue != originalTitle {
            originalTitle = newValue
            saveChanges()
        }
    }
    
    private func handleContentChange(_ newValue: AttributedString) {
        guard !isInitializing else { return }
        // 比较 AttributedString 是否改变（通过字符串内容比较）
        let newString = String(newValue.characters)
        let originalString = String(originalAttributedText.characters)
        if newString != originalString {
            originalAttributedText = newValue
            saveChanges()
        }
    }
    
    
    
    /// 保存更改（带防抖，自动上传到云端）
    private func saveChanges() {
        guard let note = viewModel.selectedNote else { return }
        
        // 如果正在保存或上传，取消之前的任务并重新调度
        pendingSaveWorkItem?.cancel()
        
        // 创建新的保存任务
        // 注意：SwiftUI View 是 struct，不需要 weak 引用
        // 需要捕获必要的值，因为 struct 在闭包执行时可能已经被释放
        let currentNoteId = currentEditingNoteId
        let viewModelRef = viewModel  // 捕获 viewModel 引用
        
        // 捕获当前的编辑内容
        let currentEditedTitle = editedTitle
        let currentEditedAttributedText = editedAttributedText
        let currentEditedRTFData = editedRTFData
        let currentUseRichTextKit = useRichTextKit
        
        let workItem = DispatchWorkItem {
            Task { @MainActor in
                guard let note = viewModelRef.selectedNote, note.id == currentNoteId else {
                    print("[NoteDetailView] ⚠️ 笔记已切换，取消保存: \(currentNoteId ?? "nil")")
                    return
                }
                
                // 在闭包中，我们需要通过 viewModel 来更新笔记
                // 但由于 struct 的特性，我们直接构建 Note 并调用 updateNote
                let finalRTFData: Data?
                let finalAttributedText: AttributedString
                
                if currentUseRichTextKit, let rtfData = currentEditedRTFData {
                    finalRTFData = rtfData
                    if let attributedText = AttributedStringConverter.rtfDataToAttributedString(rtfData) {
                        finalAttributedText = attributedText
                    } else {
                        finalAttributedText = currentEditedAttributedText
                    }
                } else {
                    finalAttributedText = currentEditedAttributedText
                    finalRTFData = AttributedStringConverter.attributedStringToRTFData(currentEditedAttributedText)
                }
                
                let xmlContent = AttributedStringConverter.attributedStringToXML(finalAttributedText)
                
                let updatedNote = Note(
                    id: note.id,
                    title: currentEditedTitle,
                    content: xmlContent,
                    folderId: note.folderId,
                    isStarred: note.isStarred,
                    createdAt: note.createdAt,
                    updatedAt: Date(),
                    tags: note.tags,
                    rawData: note.rawData,
                    rtfData: finalRTFData
                )
                
                // 标记开始保存和上传
                isSaving = true
                isUploading = viewModelRef.isOnline && viewModelRef.isLoggedIn
                
                do {
                    // updateNote 会自动处理本地保存和云端上传
                    try await viewModelRef.updateNote(updatedNote)
                    print("[NoteDetailView] ✅ 自动保存并上传成功: \(note.id)")
                    
                    // 保存成功后更新原始值，避免重复保存
                    originalTitle = currentEditedTitle
                    originalAttributedText = finalAttributedText
                    if currentUseRichTextKit {
                        editedRTFData = finalRTFData
                    }
                    
                    // 显示成功提示（短暂显示）
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
                    print("[NoteDetailView] ❌ 自动保存失败: \(error.localizedDescription)")
                    isSaving = false
                    isUploading = false
                    
                    // 即使上传失败，本地已保存，不显示错误（离线时会自动添加到队列）
                }
            }
        }
        pendingSaveWorkItem = workItem
        
        // 防抖处理：延迟0.5秒后自动保存并上传（避免频繁上传）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
    
    /// 立即保存更改（用于切换笔记前）
    @MainActor
    private func saveChangesImmediately(for note: Note) async {
        // 取消待执行的保存任务
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        
        // 检查是否有未保存的更改
        let hasTitleChanges = editedTitle != originalTitle
        let hasContentChanges = String(editedAttributedText.characters) != String(originalAttributedText.characters)
        
        if hasTitleChanges || hasContentChanges {
            print("[NoteDetailView] 切换笔记前立即保存当前笔记: \(note.id), hasTitleChanges=\(hasTitleChanges), hasContentChanges=\(hasContentChanges)")
            await performSave(for: note)
        } else {
            print("[NoteDetailView] 当前笔记没有未保存的更改，跳过保存: \(note.id)")
        }
    }
    
    /// 执行保存操作
    @MainActor
    private func performSave(for note: Note) async {
        guard note.id == currentEditingNoteId else {
            print("[NoteDetailView] ⚠️ 笔记ID不匹配，跳过保存: current=\(currentEditingNoteId ?? "nil"), note=\(note.id)")
            return
        }
        
        isSaving = true
        isUploading = viewModel.isOnline && viewModel.isLoggedIn
        
        do {
            // 优先使用RTF数据（如果使用RichTextKit编辑器）
            let finalRTFData: Data?
            let finalAttributedText: AttributedString
            
            if useRichTextKit, let rtfData = editedRTFData {
                // 从RTF数据转换
                finalRTFData = rtfData
                if let attributedText = AttributedStringConverter.rtfDataToAttributedString(rtfData) {
                    finalAttributedText = attributedText
                } else {
                    finalAttributedText = editedAttributedText
                }
            } else {
                // 从AttributedString转换
                finalAttributedText = editedAttributedText
                finalRTFData = AttributedStringConverter.attributedStringToRTFData(editedAttributedText)
            }
            
            // 从 AttributedString 转换为 XML（用于同步到云端）
            let xmlContent = AttributedStringConverter.attributedStringToXML(finalAttributedText)
            
            let updatedNote = Note(
                id: note.id,
                title: editedTitle,
                content: xmlContent,  // 同步时使用 XML
                folderId: note.folderId,
                isStarred: note.isStarred,
                createdAt: note.createdAt,
                updatedAt: Date(),
                tags: note.tags,
                rawData: note.rawData,
                rtfData: finalRTFData  // 本地存储使用 RTF
            )
            
            // 保存到云端（如果失败，至少保存到本地）
            do {
                try await viewModel.updateNote(updatedNote)
                
                // 保存成功后更新原始值，避免重复保存
                originalTitle = editedTitle
                originalAttributedText = finalAttributedText
                if useRichTextKit {
                    editedRTFData = finalRTFData
                }
                
                // 保存成功反馈
                withAnimation {
                    showSaveSuccess = true
                    isSaving = false
                    isUploading = false
                }
                
                print("[NoteDetailView] ✅ 笔记保存成功: \(note.id), title=\(editedTitle), content长度=\(xmlContent.count)")
                
                // 2秒后隐藏成功提示
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        showSaveSuccess = false
                    }
                }
            } catch {
                // 保存到云端失败，但至少保存到本地，确保内容不丢失
                print("[NoteDetailView] ⚠️ 保存到云端失败，保存到本地: \(error.localizedDescription)")
                
                // 尝试保存到本地
                do {
                    try await viewModel.updateNote(updatedNote)
                    print("[NoteDetailView] ✅ 已保存到本地: \(note.id)")
                    
                    // 即使云端保存失败，也更新原始值，避免重复尝试保存
                    originalTitle = editedTitle
                    originalAttributedText = finalAttributedText
                    if useRichTextKit {
                        editedRTFData = finalRTFData
                    }
                } catch {
                    print("[NoteDetailView] ❌ 保存到本地也失败: \(error.localizedDescription)")
                }
                
                isSaving = false
                isUploading = false
            }
        }
    }
    
    // MARK: - 转换方法已移至 AttributedStringConverter
}

#Preview {
    NoteDetailView(viewModel: NotesViewModel())
        .frame(width: 600, height: 400)
}

