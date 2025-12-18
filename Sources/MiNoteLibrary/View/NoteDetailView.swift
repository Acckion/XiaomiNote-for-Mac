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
                noteEditorView(for: note)
            } else {
                emptyNoteView
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                formatToolbarGroup
            }
            
            ToolbarItemGroup(placement: .primaryAction) {
                if let note = viewModel.selectedNote {
                    shareAndMoreButtons(for: note)
                }
            }
            
            ToolbarItem(placement: .automatic) {
                searchToolbarItem
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
        .onChange(of: editedContent) { oldValue, newValue in
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
    
    private func editorContentView(for note: Note) -> some View {
        MiNoteEditor(
            xmlContent: $editedContent,
            isEditable: $isEditable,
            noteRawData: note.rawData,
            onTextViewCreated: { tv in
                textView = tv
            },
            title: editedTitle,
            onTitleChange: { newTitle in
                // 标题变化时更新 editedTitle
                if newTitle != editedTitle {
                    editedTitle = newTitle
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            // 三个点菜单
            Menu {
                Button("更多选项") {
                    // TODO: 实现更多选项
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            
            // 编辑按钮
            Button {
                isEditable.toggle()
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            
            formatMenu
            checkboxButton
            
            // 表格按钮
            Button {
                // TODO: 插入表格
            } label: {
                Image(systemName: "tablecells")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("插入表格")
            
            imageButton
            
            // 设置按钮
            Button {
                // TODO: 打开设置
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("设置")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
    }
    
    private var formatMenu: some View {
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
    
    private func handleNoteAppear(_ note: Note) {
        isInitializing = true
        editedTitle = note.title
        originalTitle = note.title
        editedContent = note.primaryXMLContent
        originalContent = note.primaryXMLContent
        
        if note.content.isEmpty {
            Task {
                await viewModel.ensureNoteHasFullContent(note)
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
    
    private func handleNoteChange(_ newValue: Note) {
        isInitializing = true
        editedTitle = newValue.title
        originalTitle = newValue.title
        editedContent = newValue.primaryXMLContent
        originalContent = newValue.primaryXMLContent
        
        if newValue.content.isEmpty {
            Task {
                await viewModel.ensureNoteHasFullContent(newValue)
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
    
    private func handleTitleChange(_ newValue: String) {
        guard !isInitializing else { return }
        if newValue != originalTitle {
            originalTitle = newValue
            saveChanges()
        }
    }
    
    private func handleContentChange(_ newValue: String) {
        guard !isInitializing else { return }
        if newValue != originalContent {
            originalContent = newValue
            saveChanges()
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
                    // 保存失败：静默处理，不显示弹窗
                    print("[NoteDetailView] 保存失败: \(error.localizedDescription)")
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
