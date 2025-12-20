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
                        // RTF数据变化时，更新 editedRTFData 和 editedAttributedText
                        guard !isInitializing else {
                            print("[[调试]]步骤2 [NoteDetailView] 编辑器内容变化回调触发，但正在初始化，跳过处理")
                            return
                        }
                        print("[[调试]]步骤2 [NoteDetailView] 编辑器内容变化回调触发，RTF数据长度: \(newRTFData?.count ?? 0)")
                        if let rtfData = newRTFData {
                            editedRTFData = rtfData
                            print("[[调试]]步骤3 [NoteDetailView] 更新本地状态，editedRTFData已更新: true, 长度: \(rtfData.count)")
                            // 转换为 AttributedString 用于比较和保存
                            if let attributedText = AttributedStringConverter.rtfDataToAttributedString(rtfData) {
                                // 检查内容是否真的改变了
                                let newString = String(attributedText.characters)
                                let originalString = String(originalAttributedText.characters)
                                print("[[调试]]步骤4 [NoteDetailView] 内容变化检测，新内容长度: \(newString.count), 原始内容长度: \(originalString.count), 是否变化: \(newString != originalString)")
                                if newString != originalString {
                                    editedAttributedText = attributedText
                                    print("[[调试]]步骤4.1 [NoteDetailView] 内容已变化，更新editedAttributedText，长度: \(attributedText.characters.count)")
                                    // 触发保存（通过 handleContentChange）
                                    handleContentChange(attributedText)
                                }
                            }
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
    
    @MainActor
    private func loadNoteContent(_ note: Note) async {
        print("[[调试]]步骤68 [NoteDetailView] 加载新笔记内容，笔记ID: \(note.id), 标题: \(note.title)")
        isInitializing = true
        // 更新当前编辑的笔记ID
        currentEditingNoteId = note.id
        
        // 如果标题为空或者是默认的"未命名笔记_xxx"，设置为空字符串以显示占位符
        let cleanTitle = note.title.isEmpty || note.title.hasPrefix("未命名笔记_") ? "" : note.title
        editedTitle = cleanTitle
        originalTitle = cleanTitle
        
        // 优化：优先使用 rtf_data，如果没有则从 XML 生成并保存
        print("[[调试]]步骤68.1 [NoteDetailView] 加载笔记内容，rtfData存在: \(note.rtfData != nil), XML长度: \(note.primaryXMLContent.count)")
        
        var finalRTFData: Data? = note.rtfData
        var finalAttributedText: AttributedString?
        
        // 如果有 rtfData，直接从 rtfData 加载
        if let rtfData = note.rtfData {
            print("[[调试]]步骤68.2 [NoteDetailView] ✅ 使用现有RTF数据，长度: \(rtfData.count)")
            finalRTFData = rtfData
            finalAttributedText = AttributedStringConverter.rtfDataToAttributedString(rtfData)
        } else if !note.primaryXMLContent.isEmpty {
            // 如果没有 rtfData，从 XML 转换生成 rtfData
            print("[[调试]]步骤68.2 [NoteDetailView] ⚠️ 没有RTF数据，从XML转换生成")
            
            // 从 XML 转换为 NSAttributedString
            let nsAttributedString = MiNoteContentParser.parseToAttributedString(note.primaryXMLContent, noteRawData: note.rawData)
            print("[[调试]]步骤68.2 [NoteDetailView] 解析AttributedString成功，长度: \(nsAttributedString.length)")
            
            // 尝试使用 archivedData 格式（支持图片附件）
            var generatedRTFData: Data?
            do {
                generatedRTFData = try nsAttributedString.richTextData(for: .archivedData)
                print("[[调试]]步骤68.2 [NoteDetailView] ✅ 使用 archivedData 格式生成 rtfData，长度: \(generatedRTFData?.count ?? 0) 字节")
            } catch {
                print("[[调试]]步骤68.2 [NoteDetailView] ⚠️ 生成 archivedData 失败: \(error)，尝试使用 RTF 格式")
                // 回退到 RTF 格式
                let rtfRange = NSRange(location: 0, length: nsAttributedString.length)
                generatedRTFData = try? nsAttributedString.data(from: rtfRange, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
                if let rtfData = generatedRTFData {
                    print("[[调试]]步骤68.2 [NoteDetailView] ✅ 使用 RTF 格式生成 rtfData，长度: \(rtfData.count) 字节")
                } else {
                    print("[[调试]]步骤68.2 [NoteDetailView] ⚠️ RTF 格式也失败，无法生成 rtfData")
                }
            }
            
            // 如果成功生成 rtfData，保存到数据库
            if let rtfData = generatedRTFData {
                finalRTFData = rtfData
                
                // 保存到数据库
                var updatedNote = note
                updatedNote.rtfData = rtfData
                do {
                    try LocalStorageService.shared.saveNote(updatedNote)
                    print("[[调试]]步骤68.2 [NoteDetailView] ✅ 成功保存 rtfData 到数据库")
                    
                    // 更新 ViewModel 中的笔记对象（在主线程上执行，确保线程安全）
                    await MainActor.run {
                        if let index = viewModel.notes.firstIndex(where: { $0.id == note.id }) {
                            viewModel.notes[index] = updatedNote
                            if viewModel.selectedNote?.id == note.id {
                                viewModel.selectedNote = updatedNote
                            }
                        }
                    }
                } catch {
                    print("[[调试]]步骤68.2 [NoteDetailView] ⚠️ 保存 rtfData 到数据库失败: \(error)")
                }
                
                // 转换为 AttributedString
                finalAttributedText = AttributedStringConverter.rtfDataToAttributedString(rtfData)
            } else {
                // 如果无法生成 rtfData，从 XML 直接转换 AttributedString（向后兼容）
                print("[[调试]]步骤68.2 [NoteDetailView] ⚠️ 无法生成 rtfData，使用 XML 直接转换")
                finalAttributedText = AttributedStringConverter.xmlToAttributedString(note.primaryXMLContent, noteRawData: note.rawData)
            }
        } else {
            // 内容为空，创建空 AttributedString
            print("[[调试]]步骤68.2 [NoteDetailView] 内容为空，创建空 AttributedString")
            finalAttributedText = AttributedStringConverter.createEmptyAttributedString()
        }
        
        // 设置编辑器状态
        editedRTFData = finalRTFData
        if let attributedText = finalAttributedText {
            editedAttributedText = attributedText
            originalAttributedText = attributedText
            print("[[调试]]步骤68.3 [NoteDetailView] 设置编辑器内容，AttributedString长度: \(attributedText.characters.count)")
        } else {
            // 如果仍然无法获取内容，创建空 AttributedString
            editedAttributedText = AttributedStringConverter.createEmptyAttributedString()
            originalAttributedText = AttributedStringConverter.createEmptyAttributedString()
            print("[[调试]]步骤68.3 [NoteDetailView] 创建空AttributedString")
        }
        
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
        print("[[调试]]步骤69 [NoteDetailView] 笔记加载完成，笔记ID: \(note.id), 初始化完成，editedAttributedText长度: \(editedAttributedText.characters.count)")
    }
    
    private func handleNoteChange(_ newValue: Note) {
        // 在加载新笔记前，确保保存当前笔记的更改
        // 等待保存任务完成，确保保存完成后再加载新笔记
        let saveTask = saveCurrentNoteBeforeSwitching(newNoteId: newValue.id)
        
        // 如果保存任务存在，等待它完成后再继续
        if let saveTask = saveTask {
            Task { @MainActor in
                await saveTask.value
                await loadNoteContent(newValue)
            }
        } else {
            // 没有保存任务，直接加载笔记内容
            Task { @MainActor in
                await loadNoteContent(newValue)
            }
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
    
    private func handleContentChange(_ newValue: AttributedString) {
        guard !isInitializing else {
            print("[[调试]]步骤4.2 [NoteDetailView] 内容变化检测，但正在初始化，跳过处理")
            return
        }
        // 比较 AttributedString 是否改变（通过字符串内容比较）
        let newString = String(newValue.characters)
        let originalString = String(originalAttributedText.characters)
        print("[[调试]]步骤4.2 [NoteDetailView] 内容变化检测，新内容长度: \(newString.count), 原始内容长度: \(originalString.count), 是否变化: \(newString != originalString)")
        if newString != originalString {
            print("[[调试]]步骤5 [NoteDetailView] 内容变化检测到，立即保存，笔记ID: \(viewModel.selectedNote?.id ?? "无")")
            originalAttributedText = newValue
            // 立即保存，不使用防抖
            Task { @MainActor in
                print("[[调试]]步骤6 [NoteDetailView] 触发立即保存，笔记ID: \(viewModel.selectedNote?.id ?? "无")")
                await performSaveImmediately()
            }
        }
    }
    
    
    
    /// 保存更改（优化策略：本地立即保存，云端延迟上传）
    private func saveChanges() {
        guard let note = viewModel.selectedNote else { return }
        
        // 如果正在为切换而保存，不执行防抖保存（避免冲突）
        if isSavingBeforeSwitch {
            print("[NoteDetailView] 正在为切换而保存，跳过防抖保存")
            return
        }
        
        // 检查是否有未保存的更改
        let hasTitleChanges = editedTitle != originalTitle
        let hasContentChanges = String(editedAttributedText.characters) != String(originalAttributedText.characters)
        
        // 如果没有更改，直接返回
        guard hasTitleChanges || hasContentChanges else { return }
        
        // 取消之前的云端上传任务（但保留本地保存）
        pendingCloudUploadWorkItem?.cancel()
        
        // 立即保存到本地（无延迟，确保数据不丢失）
        Task { @MainActor in
            await saveToLocalOnly(for: note)
        }
        
        // 延迟上传到云端（智能防抖：根据内容大小调整延迟时间）
        scheduleCloudUpload(for: note)
    }
    
    /// 仅保存到本地（立即执行，无延迟）
    @MainActor
    private func saveToLocalOnly(for note: Note) async {
        guard note.id == currentEditingNoteId else { return }
        
        // 如果正在保存，跳过
        if isSavingLocally {
            print("[NoteDetailView] 正在本地保存，跳过重复保存")
            return
        }
        
        // 检查 RTF 数据是否变化（避免重复保存相同内容）
        let currentRTFData = editedRTFData
        if let lastSaved = lastSavedRTFData, lastSaved == currentRTFData {
            print("[NoteDetailView] RTF数据未变化，跳过本地保存")
            return
        }
        
        isSavingLocally = true
        
        do {
            // 获取最新的编辑内容
            let finalRTFData: Data?
            let finalAttributedText: AttributedString
            
            if useRichTextKit {
                // 从 editorContext 获取最新的内容
                let contextAttributedString = editorContext.attributedString
                if contextAttributedString.length > 0 {
                    let swiftUIAttributedText = AttributedString(contextAttributedString)
                    do {
                        let archivedData = try contextAttributedString.richTextData(for: .archivedData)
                        finalRTFData = archivedData
                        finalAttributedText = swiftUIAttributedText
                    } catch {
                        print("[NoteDetailView] ⚠️ 生成 archivedData 失败: \(error)")
                        finalRTFData = editedRTFData
                        finalAttributedText = swiftUIAttributedText
                    }
                } else {
                    finalRTFData = editedRTFData
                    finalAttributedText = editedAttributedText
                }
            } else {
                finalRTFData = AttributedStringConverter.attributedStringToRTFData(editedAttributedText)
                finalAttributedText = editedAttributedText
            }
            
            // 转换为 XML（用于数据库存储）
            let xmlContent = AttributedStringConverter.attributedStringToXML(finalAttributedText)
            
            // 构建更新的笔记对象
            let updatedNote = Note(
                id: note.id,
                title: editedTitle,
                content: xmlContent,
                folderId: note.folderId,
                isStarred: note.isStarred,
                createdAt: note.createdAt,
                updatedAt: Date(),
                tags: note.tags,
                rawData: note.rawData,
                rtfData: finalRTFData
            )
            
            // 仅保存到本地数据库（不触发云端上传）
            try LocalStorageService.shared.saveNote(updatedNote)
            
            // 更新状态
            lastSavedRTFData = finalRTFData
            originalTitle = editedTitle
            originalAttributedText = finalAttributedText
            if useRichTextKit {
                editedRTFData = finalRTFData
            }
            
            print("[NoteDetailView] ✅ 本地保存成功: \(note.id), RTF长度: \(finalRTFData?.count ?? 0)")
            
            // 更新 ViewModel 中的笔记对象
            if let index = viewModel.notes.firstIndex(where: { $0.id == note.id }) {
                viewModel.notes[index] = updatedNote
                if viewModel.selectedNote?.id == note.id {
                    viewModel.selectedNote = updatedNote
                }
            }
            
        } catch {
            print("[NoteDetailView] ❌ 本地保存失败: \(error.localizedDescription)")
        }
        
        isSavingLocally = false
    }
    
    /// 安排云端上传（智能防抖）
    private func scheduleCloudUpload(for note: Note) {
        guard viewModel.isOnline && viewModel.isLoggedIn else {
            print("[NoteDetailView] 离线模式，跳过云端上传")
            return
        }
        
        // 取消之前的云端上传任务
        pendingCloudUploadWorkItem?.cancel()
        
        // 根据内容大小智能调整防抖时间
        let rtfDataSize = editedRTFData?.count ?? 0
        let debounceTime: TimeInterval
        
        if rtfDataSize > 1_000_000 {  // > 1MB
            debounceTime = 3.0  // 大文件延迟 3 秒
        } else if rtfDataSize > 500_000 {  // > 500KB
            debounceTime = 2.0  // 中等文件延迟 2 秒
        } else {
            debounceTime = 1.0  // 小文件延迟 1 秒
        }
        
        let currentNoteId = currentEditingNoteId
        let viewModelRef = viewModel
        let currentEditedTitle = editedTitle
        let currentEditedAttributedText = editedAttributedText
        let currentEditedRTFData = editedRTFData
        let currentUseRichTextKit = useRichTextKit
        
        let uploadWorkItem = DispatchWorkItem {
            Task { @MainActor in
                guard let note = viewModelRef.selectedNote, note.id == currentNoteId else {
                    print("[NoteDetailView] ⚠️ 笔记已切换，取消云端上传: \(currentNoteId ?? "nil")")
                    return
                }
                
                // 获取最新的内容
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
                
                // 标记开始上传
                isUploading = true
                print("[NoteDetailView] ✅ 开始云端上传: \(note.id)")
                
                do {
                    // 触发云端上传（updateNote 会再次保存到本地，但这是幂等操作，确保数据一致性）
                    // 注意：虽然本地已保存，但 updateNote 中的保存可以确保数据完全同步
                    try await viewModelRef.updateNote(updatedNote)
                    print("[NoteDetailView] ✅ 云端上传成功: \(note.id)")
                    
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
        print("[NoteDetailView] 📅 安排云端上传，延迟: \(debounceTime)秒, RTF大小: \(rtfDataSize)字节")
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
            // 确保使用最新的编辑内容进行保存
            // 如果使用 RichTextKit，需要从 editorContext 获取最新内容
            if useRichTextKit {
                // 从 editorContext 获取最新的 attributedString
                let contextAttributedString = editorContext.attributedString
                if contextAttributedString.length > 0 {
                    // 转换为 AttributedString (SwiftUI)
                    let swiftUIAttributedString = AttributedString(contextAttributedString)
                    editedAttributedText = swiftUIAttributedString
                    // 更新 RTF 数据（使用 archivedData 格式以支持图片附件）
                    do {
                        let archivedData = try contextAttributedString.richTextData(for: .archivedData)
                        editedRTFData = archivedData
                        print("[NoteDetailView] ✅ 从 editorContext 获取最新内容，长度: \(contextAttributedString.length)")
                    } catch {
                        print("[NoteDetailView] ⚠️ 从 editorContext 获取 RTF 数据失败: \(error)，尝试使用 RTF 格式")
                        // 如果 archivedData 失败，尝试使用 RTF 格式
                        if let rtfData = AttributedStringConverter.attributedStringToRTFData(swiftUIAttributedString) {
                            editedRTFData = rtfData
                        }
                    }
                }
            }
            await performSave(for: note)
        } else {
            print("[NoteDetailView] 当前笔记没有未保存的更改，跳过保存: \(note.id)")
        }
    }
    
    /// 立即执行保存操作（编辑即保存）
    @MainActor
    private func performSaveImmediately() async {
        guard let note = viewModel.selectedNote else {
            print("[[调试]]步骤7 [NoteDetailView] 执行立即保存，但selectedNote为nil，跳过")
            return
        }
        
        guard note.id == currentEditingNoteId else {
            print("[[调试]]步骤7 [NoteDetailView] ⚠️ 笔记ID不匹配，跳过保存: current=\(currentEditingNoteId ?? "nil"), note=\(note.id)")
            return
        }
        
        // 如果正在为切换而保存，不执行保存（避免冲突）
        if isSavingBeforeSwitch {
            print("[[调试]]步骤7 [NoteDetailView] 正在为切换而保存，跳过立即保存")
            return
        }
        
        // 检查是否有未保存的更改
        let hasTitleChanges = editedTitle != originalTitle
        let hasContentChanges = String(editedAttributedText.characters) != String(originalAttributedText.characters)
        
        // 如果没有更改，直接返回
        guard hasTitleChanges || hasContentChanges else {
            print("[[调试]]步骤7 [NoteDetailView] 没有未保存的更改，跳过保存")
            return
        }
        
        print("[[调试]]步骤7 [NoteDetailView] 执行立即保存，笔记ID: \(note.id)")
        await performSave(for: note)
    }
    
    /// 执行保存操作
    @MainActor
    private func performSave(for note: Note) async {
        print("[[调试]]步骤8 [NoteDetailView] 开始执行保存操作，笔记ID: \(note.id), 当前编辑笔记ID: \(currentEditingNoteId ?? "nil"), 是否匹配: \(note.id == currentEditingNoteId)")
        guard note.id == currentEditingNoteId else {
            print("[[调试]]步骤8 [NoteDetailView] ⚠️ 笔记ID不匹配，跳过保存: current=\(currentEditingNoteId ?? "nil"), note=\(note.id)")
            return
        }
        
        isSaving = true
        let willUpload = viewModel.isOnline && viewModel.isLoggedIn
        isUploading = willUpload
        
        if willUpload {
            print("[[调试]]步骤8.1 [NoteDetailView] ✅开始上传: \(note.id)")
        } else {
            print("[[调试]]步骤8.1 [NoteDetailView] 离线模式，仅保存到本地: \(note.id)")
        }
        
        do {
            // 优先使用RTF数据（如果使用RichTextKit编辑器）
            let finalRTFData: Data?
            let finalAttributedText: AttributedString
            
            if useRichTextKit {
                // 从 editorContext 获取最新的 attributedString（确保获取最新内容）
                let contextAttributedString = editorContext.attributedString
                print("[[调试]]步骤9 [NoteDetailView] 从editorContext获取内容，使用RichTextKit: true, context内容长度: \(contextAttributedString.length)")
                if contextAttributedString.length > 0 {
                    // 转换为 AttributedString (SwiftUI)
                    let swiftUIAttributedText = AttributedString(contextAttributedString)
                    // 更新 RTF 数据（使用 archivedData 格式以支持图片附件）
                    do {
                        let archivedData = try contextAttributedString.richTextData(for: .archivedData)
                        finalRTFData = archivedData
                        editedRTFData = archivedData
                        finalAttributedText = swiftUIAttributedText
                        print("[[调试]]步骤10 [NoteDetailView] ✅ 从 editorContext 获取最新内容，长度: \(contextAttributedString.length), RTF数据长度: \(archivedData.count)")
                    } catch {
                        print("[[调试]]步骤10 [NoteDetailView] ⚠️ 从 editorContext 获取 RTF 数据失败: \(error)，使用现有数据")
                        finalRTFData = editedRTFData
                        finalAttributedText = swiftUIAttributedText
                    }
                } else if let rtfData = editedRTFData {
                    // 如果 context 中没有内容，使用现有的 RTF 数据
                    print("[[调试]]步骤9.1 [NoteDetailView] context中没有内容，使用现有RTF数据，长度: \(rtfData.count)")
                    finalRTFData = rtfData
                    if let attributedText = AttributedStringConverter.rtfDataToAttributedString(rtfData) {
                        finalAttributedText = attributedText
                    } else {
                        finalAttributedText = editedAttributedText
                    }
                } else {
                    // 都没有，从 AttributedString 转换
                    print("[[调试]]步骤9.2 [NoteDetailView] 没有RTF数据，从AttributedString转换")
                    finalAttributedText = editedAttributedText
                    finalRTFData = AttributedStringConverter.attributedStringToRTFData(editedAttributedText)
                }
            } else {
                // 从AttributedString转换
                print("[[调试]]步骤9 [NoteDetailView] 不使用RichTextKit，从AttributedString转换")
                finalAttributedText = editedAttributedText
                finalRTFData = AttributedStringConverter.attributedStringToRTFData(editedAttributedText)
            }
            
            print("[[调试]]步骤11 [NoteDetailView] 准备转换为XML，AttributedString长度: \(finalAttributedText.characters.count)")
            // 从 AttributedString 转换为 XML（用于同步到云端）
            let xmlContent = AttributedStringConverter.attributedStringToXML(finalAttributedText)
            print("[[调试]]步骤16 [NoteDetailView] 获得XML内容，长度: \(xmlContent.count), 笔记ID: \(note.id), 内容预览: \(xmlContent.prefix(100))")
            
            print("[[调试]]步骤17 [NoteDetailView] 构建更新的Note对象，ID: \(note.id), 标题: \(editedTitle), XML长度: \(xmlContent.count), RTF长度: \(finalRTFData?.count ?? 0)")
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
            
            // 验证 rtfData 是否正确设置
            print("[[调试]]步骤17.1 [NoteDetailView] 验证updatedNote.rtfData，存在: \(updatedNote.rtfData != nil), 长度: \(updatedNote.rtfData?.count ?? 0)")
            if updatedNote.rtfData == nil {
                print("[[调试]]步骤17.1 [NoteDetailView] ⚠️ 警告：updatedNote.rtfData为nil，finalRTFData存在: \(finalRTFData != nil)")
            }
            
            // updateNote 会先保存到本地，然后上传到云端（如果在线）
            print("[[调试]]步骤18 [NoteDetailView] 调用viewModel.updateNote，笔记ID: \(updatedNote.id), rtfData存在: \(updatedNote.rtfData != nil)")
            try await viewModel.updateNote(updatedNote)
            
            // 保存成功后更新原始值，避免重复保存
            print("[[调试]]步骤58 [NoteDetailView] 更新原始值，originalTitle: '\(editedTitle)', originalAttributedText长度: \(finalAttributedText.characters.count)")
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
            
            print("[[调试]]步骤60 [NoteDetailView] 保存完成，笔记ID: \(note.id), title: \(editedTitle), content长度: \(xmlContent.count)")
            print("[[调试]]步骤59 [NoteDetailView] 显示保存成功提示，笔记ID: \(note.id)")
            
            // 2秒后隐藏成功提示
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showSaveSuccess = false
                }
            }
        } catch {
            // 保存失败（本地保存应该在 updateNote 中已经完成）
            print("[[调试]]步骤57.1 [NoteDetailView] ⚠️ 保存失败: \(error.localizedDescription), 笔记ID: \(note.id)")
            isSaving = false
            isUploading = false
        }
    }
    
    // MARK: - 切换笔记保存逻辑
    
    /// 在切换到新笔记前保存当前笔记的更改
    /// 返回一个 Task，调用者可以等待它完成
    @discardableResult
    private func saveCurrentNoteBeforeSwitching(newNoteId: String) -> Task<Void, Never>? {
        guard let currentNoteId = currentEditingNoteId,
              currentNoteId != newNoteId else {
            print("[[调试]]步骤61 [NoteDetailView] 不需要保存当前笔记（相同笔记或没有当前笔记），当前ID: \(currentEditingNoteId ?? "nil"), 新ID: \(newNoteId)")
            return nil
        }
        
        // 检查是否有未保存的更改
        let hasTitleChanges = editedTitle != originalTitle
        let hasContentChanges = String(editedAttributedText.characters) != String(originalAttributedText.characters)
        
        print("[[调试]]步骤62 [NoteDetailView] 检查是否需要保存，当前笔记ID: \(currentNoteId), 新笔记ID: \(newNoteId), 标题变化: \(hasTitleChanges), 内容变化: \(hasContentChanges)")
        
        guard hasTitleChanges || hasContentChanges else {
            print("[[调试]]步骤62.1 [NoteDetailView] 当前笔记没有未保存的更改，跳过保存")
            return nil
        }
        
        guard let currentNote = viewModel.selectedNote,
              currentNote.id == currentNoteId else {
            print("[[调试]]步骤62.2 [NoteDetailView] ⚠️ 当前笔记不匹配，跳过保存: currentEditingNoteId=\(currentEditingNoteId ?? "nil")")
            return nil
        }
        
        print("[[调试]]步骤63 [NoteDetailView] 切换到新笔记前保存当前笔记: \(currentNoteId) -> \(newNoteId)")
        
        // 取消待执行的保存任务
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        
        // 标记正在为切换而保存
        isSavingBeforeSwitch = true
        
        return Task { @MainActor in
            // 确保使用最新的编辑内容进行保存
            // 如果使用 RichTextKit，需要从 editorContext 获取最新内容
            if useRichTextKit {
                // 从 editorContext 获取最新的 attributedString
                let contextAttributedString = editorContext.attributedString
                print("[[调试]]步骤64 [NoteDetailView] 切换前从editorContext获取内容，context长度: \(contextAttributedString.length)")
                if contextAttributedString.length > 0 {
                    // 转换为 AttributedString (SwiftUI)
                    let swiftUIAttributedString = AttributedString(contextAttributedString)
                    editedAttributedText = swiftUIAttributedString
                    // 更新 RTF 数据（使用 archivedData 格式以支持图片附件）
                    do {
                        let archivedData = try contextAttributedString.richTextData(for: .archivedData)
                        editedRTFData = archivedData
                        print("[[调试]]步骤64.1 [NoteDetailView] ✅ 从 editorContext 获取最新内容，长度: \(contextAttributedString.length), RTF数据长度: \(archivedData.count)")
                    } catch {
                        print("[[调试]]步骤64.1 [NoteDetailView] ⚠️ 从 editorContext 获取 RTF 数据失败: \(error)，尝试使用 RTF 格式")
                        // 如果 archivedData 失败，尝试使用 RTF 格式
                        if let rtfData = AttributedStringConverter.attributedStringToRTFData(swiftUIAttributedString) {
                            editedRTFData = rtfData
                        }
                    }
                }
            }
            
            print("[[调试]]步骤65 [NoteDetailView] 执行切换前保存，当前笔记ID: \(currentNote.id)")
            await performSave(for: currentNote)
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
            print("[[调试]]步骤61.2 [NoteDetailView] 相同笔记，只是内容更新，笔记ID: \(newNote.id)")
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
    
    // MARK: - 转换方法已移至 AttributedStringConverter
}

#Preview {
    NoteDetailView(viewModel: NotesViewModel())
        .frame(width: 600, height: 400)
}
