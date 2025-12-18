import SwiftUI
import AppKit

struct NoteDetailView: View {
    @ObservedObject var viewModel: NotesViewModel
    @State private var editedTitle: String = ""
    @State private var editedContent: String = ""
    @State private var isSaving: Bool = false
    @State private var showSaveSuccess: Bool = false
    @State private var showSaveError: Bool = false
    @State private var saveError: String = ""
    @State private var isEditable: Bool = true // New state for editor editability
    @State private var isInitializing: Bool = true // 标记是否正在初始化
    @State private var originalTitle: String = "" // 保存原始标题用于比较
    @State private var originalContent: String = "" // 保存原始内容用于比较
    @State private var textView: NSTextView? = nil // 存储 NSTextView 引用
    
    var body: some View {
        Group {
            if let note = viewModel.selectedNote {
                ZStack {
                    // 编辑器背景
                    Color(nsColor: NSColor.textBackgroundColor)
                        .ignoresSafeArea()
                    
                VStack(spacing: 0) {
                        // 标题（作为放大的正文，不单独区分）
                    HStack {
                        TextField("笔记标题", text: $editedTitle)
                                .font(.system(size: 28, weight: .regular))
                            .textFieldStyle(.plain)
                                .foregroundColor(Color(nsColor: NSColor.labelColor))
                            .padding(.horizontal, 16)
                                .padding(.top, 16)
                                .padding(.bottom, 8)
                        
                        Spacer()
                        
                        // 保存状态指示器
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 16)
                                    .padding(.top, 16)
                        } else if showSaveSuccess {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .padding(.trailing, 16)
                                    .padding(.top, 16)
                            }
                        }
                        
                        // 编辑器区域（正文）
                        MiNoteEditor(
                            xmlContent: $editedContent,
                            isEditable: $isEditable,
                            noteRawData: note.rawData,
                            onTextViewCreated: { tv in
                                textView = tv
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .onAppear {
                    // 初始化时设置标志，避免触发保存
                    isInitializing = true
                    editedTitle = note.title
                    originalTitle = note.title
                    // 使用 Note.primaryXMLContent 统一决定展示/编辑用的正文
                    editedContent = note.primaryXMLContent
                    originalContent = note.primaryXMLContent
                    
                    // 如果笔记内容为空，尝试获取完整内容
                    if note.content.isEmpty {
                        Task {
                            await viewModel.ensureNoteHasFullContent(note)
                            // 获取完成后，更新显示内容
                            if let updatedNote = viewModel.selectedNote {
                                editedContent = updatedNote.primaryXMLContent
                                originalContent = updatedNote.primaryXMLContent
                            }
                        }
                    }
                    
                    // 延迟一点时间后取消初始化标志，确保所有 onChange 都已处理
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isInitializing = false
                    }
                }
                .onChange(of: note) { oldValue, newValue in
                    // 笔记变化时更新内容，但不触发保存
                    isInitializing = true
                    editedTitle = newValue.title
                    originalTitle = newValue.title
                    editedContent = newValue.primaryXMLContent
                    originalContent = newValue.primaryXMLContent
                    
                    // 如果新笔记内容为空，尝试获取完整内容
                    if newValue.content.isEmpty {
                        Task {
                            await viewModel.ensureNoteHasFullContent(newValue)
                            // 获取完成后，更新显示内容
                            if let updatedNote = viewModel.selectedNote {
                                editedContent = updatedNote.primaryXMLContent
                                originalContent = updatedNote.primaryXMLContent
                            }
                        }
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isInitializing = false
                    }
                }
                .onChange(of: editedTitle) { oldValue, newValue in
                    // 只有在非初始化状态且内容实际改变时才保存
                    guard !isInitializing else { return }
                    if newValue != originalTitle {
                        originalTitle = newValue // 更新原始值
                        saveChanges()
                    }
                }
                .onChange(of: editedContent) { oldValue, newValue in
                    // 只有在非初始化状态且内容实际改变时才保存
                    guard !isInitializing else { return }
                    if newValue != originalContent {
                        originalContent = newValue // 更新原始值
                        saveChanges()
                    }
                }
                .alert("保存失败", isPresented: $showSaveError) {
                    Button("重试") {
                        saveChanges()
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text(saveError)
                }
            } else {
                // 无笔记选中时的占位视图
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
        }
        .toolbar {
            // 编辑区域上方导航栏（macOS原生样式）
            // 1. 新建笔记（单独部分，居左）
            ToolbarItem(placement: .navigation) {
                Button {
                    viewModel.createNewNote()
                } label: {
                    Label("新建备忘录", systemImage: "square.and.pencil")
                }
            }
            
            // 2. 格式、代办、附件（中间，被同一个区域包裹）
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 8) {
                    Menu {
                        Button("大标题") {
                            applyHeading(level: 1)
                        }
                        Button("标题") {
                            applyHeading(level: 2)
                        }
                        Button("副标题") {
                            applyHeading(level: 3)
                        }
                        Divider()
                        Button("加粗") {
                            toggleBold()
                        }
                        Button("斜体") {
                            toggleItalic()
                        }
                    } label: {
                        Image(systemName: "textformat")
                    }
                    
                    Button {
                        insertCheckbox()
                    } label: {
                        Image(systemName: "checklist")
                    }
                    .help("插入待办")
                    
                    Button {
                        insertImage()
                    } label: {
                        Image(systemName: "paperclip")
                    }
                    .help("插入图片")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: NSColor.controlBackgroundColor))
                )
            }
            
            // 3. 分享和更多（右侧第二个）
            ToolbarItemGroup(placement: .primaryAction) {
                if let note = viewModel.selectedNote {
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
            }
            
            // 4. 搜索（最右侧，居右放置，页面够长时显示为搜索框，否则为按钮）
            ToolbarItem(placement: .automatic) {
                GeometryReader { proxy in
                    let isCompact = proxy.size.width < 720
                    
                    HStack {
                        Spacer()
                        if isCompact {
                            Button {
                                // TODO: 触发聚焦到全局搜索
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                        } else {
                            TextField("搜索", text: $viewModel.searchText)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 220)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
    
    // MARK: - 格式操作
    
    /// 应用标题格式
    private func applyHeading(level: Int) {
        guard let textView = textView,
              let textStorage = textView.textStorage else { return }
        
        let range = textView.selectedRange()
        var targetRange = range
        
        // 如果没有选择，选择当前段落
        if range.length == 0 {
            let paragraphRange = (textView.string as NSString).paragraphRange(for: range)
            if paragraphRange.length > 0 {
                targetRange = paragraphRange
                textView.setSelectedRange(targetRange)
            } else {
                return
            }
        }
        
        var fontSize: CGFloat
        var isBold = true
        
        switch level {
        case 1:
            fontSize = 24
        case 2:
            fontSize = 18
        case 3:
            fontSize = 14
        default:
            fontSize = NSFont.systemFontSize
            isBold = false
        }
        
        let font = isBold
            ? NSFont.boldSystemFont(ofSize: fontSize)
            : NSFont.systemFont(ofSize: fontSize)
        
        textStorage.beginEditing()
        textStorage.addAttribute(.font, value: font, range: targetRange)
        textStorage.endEditing()
        
        textView.didChangeText()
    }
    
    /// 切换加粗
    private func toggleBold() {
        guard let textView = textView,
              let textStorage = textView.textStorage else { return }
        
        let range = textView.selectedRange()
        guard range.length > 0 && range.location < textView.string.count else { return }
        
        // 检查当前是否加粗
        var shouldBold = true
        if range.location < textStorage.length {
            if let font = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont {
                if font.fontDescriptor.symbolicTraits.contains(.bold) {
                    shouldBold = false
                }
            }
        }
        
        // 应用或移除加粗
        textStorage.beginEditing()
        textStorage.enumerateAttribute(.font, in: range, options: []) { (value, subrange, _) in
            if let oldFont = value as? NSFont {
                let fontSize = oldFont.pointSize
                let newFont: NSFont
                if shouldBold {
                    newFont = NSFont.boldSystemFont(ofSize: fontSize)
                } else {
                    var fontDescriptor = oldFont.fontDescriptor
                    var traits = fontDescriptor.symbolicTraits
                    traits.remove(.bold)
                    fontDescriptor = fontDescriptor.withSymbolicTraits(traits)
                    newFont = NSFont(descriptor: fontDescriptor, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
                }
                textStorage.addAttribute(.font, value: newFont, range: subrange)
            } else {
                let baseFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
                let newFont = shouldBold
                    ? NSFont.boldSystemFont(ofSize: baseFont.pointSize)
                    : baseFont
                textStorage.addAttribute(.font, value: newFont, range: subrange)
            }
        }
        textStorage.endEditing()
        
        textView.didChangeText()
    }
    
    /// 切换斜体
    private func toggleItalic() {
        guard let textView = textView,
              let textStorage = textView.textStorage else { return }
        
        let range = textView.selectedRange()
        guard range.length > 0 && range.location < textView.string.count else { return }
        
        // 检查当前是否斜体
        var shouldItalic = true
        if range.location < textStorage.length {
            if let font = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont {
                if font.fontDescriptor.symbolicTraits.contains(.italic) {
                    shouldItalic = false
                }
            }
        }
        
        // 应用或移除斜体
        textStorage.beginEditing()
        textStorage.enumerateAttribute(.font, in: range, options: []) { (value, subrange, _) in
            if let oldFont = value as? NSFont {
                let fontSize = oldFont.pointSize
                var fontDescriptor = oldFont.fontDescriptor
                var traits = fontDescriptor.symbolicTraits
                
                if shouldItalic {
                    traits.insert(.italic)
                } else {
                    traits.remove(.italic)
                }
                
                fontDescriptor = fontDescriptor.withSymbolicTraits(traits)
                let newFont = NSFont(descriptor: fontDescriptor, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
                textStorage.addAttribute(.font, value: newFont, range: subrange)
            } else {
                let baseFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
                var fontDescriptor = baseFont.fontDescriptor
                if shouldItalic {
                    fontDescriptor = fontDescriptor.withSymbolicTraits([.italic])
                }
                let newFont = NSFont(descriptor: fontDescriptor, size: baseFont.pointSize) ?? baseFont
                textStorage.addAttribute(.font, value: newFont, range: subrange)
            }
        }
        textStorage.endEditing()
        
        textView.didChangeText()
    }
    
    /// 插入待办（复选框）
    private func insertCheckbox() {
        guard let textView = textView,
              let textStorage = textView.textStorage else { return }
        
        let range = textView.selectedRange()
        let checkboxText = "☐ " // 使用复选框符号
        
        // 在当前位置插入复选框
        let attributedString = NSAttributedString(string: checkboxText, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor
        ])
        
        textStorage.beginEditing()
        textStorage.insert(attributedString, at: range.location)
        textStorage.endEditing()
        
        // 移动光标到复选框后面
        let newRange = NSRange(location: range.location + checkboxText.count, length: 0)
        textView.setSelectedRange(newRange)
        
        // 触发 textDidChange，让 Coordinator 自动更新 XML
        textView.didChangeText()
    }
    
    private func insertImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .jpeg, .png, .gif]
        panel.message = "选择要插入的图片"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task {
                    do {
                        try await viewModel.uploadImageAndInsertToNote(imageURL: url)
                        // 刷新编辑器内容
                if let note = viewModel.selectedNote {
                            editedContent = note.primaryXMLContent
                            originalContent = note.primaryXMLContent
                        }
                    } catch {
                        saveError = "上传图片失败: \(error.localizedDescription)"
                        showSaveError = true
                    }
                }
            }
        }
    }
    
    private func saveChanges() {
        guard let note = viewModel.selectedNote else { return }
        
        // 防抖处理：延迟保存
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Task {
                isSaving = true
                
                do {
                    let updatedNote = Note(
                        id: note.id,
                        title: editedTitle,
                        content: editedContent, // editedContent is now XML string
                        folderId: note.folderId,
                        isStarred: note.isStarred,
                        createdAt: note.createdAt,
                        updatedAt: Date()
                    )
                    
                    try await viewModel.updateNote(updatedNote)
                    
                    // 保存成功后更新原始值，避免重复保存
                    originalTitle = editedTitle
                    originalContent = editedContent
                    
                    // 保存成功反馈
                    withAnimation {
                        showSaveSuccess = true
                        isSaving = false
                    }
                    
                    // 3秒后隐藏成功提示
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation {
                            showSaveSuccess = false
                        }
                    }
                    
                } catch {
                    saveError = error.localizedDescription
                    showSaveError = true
                    isSaving = false
                }
            }
        }
    }
}


#Preview {
    NoteDetailView(viewModel: NotesViewModel())
        .frame(width: 600, height: 400)
}
