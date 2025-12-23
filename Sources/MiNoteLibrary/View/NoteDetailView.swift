import SwiftUI
import AppKit

/// 笔记详情视图
/// 
/// 负责显示和编辑单个笔记的内容，包括：
/// - 标题编辑
/// - 富文本内容编辑（使用 Web 编辑器）
/// - 自动保存（本地立即保存，云端延迟上传）
/// - 格式工具栏
/// 
@available(macOS 14.0, *)
struct NoteDetailView: View {
    @ObservedObject var viewModel: NotesViewModel
    @State private var editedTitle: String = ""
    @State private var currentXMLContent: String = ""  // 当前编辑的 XML 内容
    @State private var isSaving: Bool = false
    @State private var isUploading: Bool = false  // 上传状态
    @State private var showSaveSuccess: Bool = false
    @State private var showSaveError: Bool = false
    @State private var saveError: String = ""
    @State private var isEditable: Bool = true // New state for editor editability
    @State private var isInitializing: Bool = true // 标记是否正在初始化
    @State private var originalTitle: String = "" // 保存原始标题用于比较
    @State private var originalXMLContent: String = "" // 保存原始 XML 内容用于比较
    @State private var pendingSaveWorkItem: DispatchWorkItem? = nil  // 待执行的保存任务
    @State private var pendingCloudUploadWorkItem: DispatchWorkItem? = nil  // 待执行的云端上传任务
    @State private var currentEditingNoteId: String? = nil  // 当前正在编辑的笔记ID
    @State private var isSavingBeforeSwitch: Bool = false  // 标记是否正在为切换笔记而保存
    @State private var pendingSwitchNoteId: String? = nil  // 等待切换的笔记ID
    @State private var lastSavedXMLContent: String = ""  // 上次保存的 XML 内容，用于避免重复保存
    @State private var isSavingLocally: Bool = false  // 标记是否正在本地保存
    
    // 图片插入相关状态
    @State private var showImageInsertAlert: Bool = false  // 控制图片插入弹窗显示
    @State private var imageInsertMessage: String = ""  // 图片插入弹窗消息
    @State private var isInsertingImage: Bool = false  // 标记是否正在插入图片
    @State private var imageInsertStatus: ImageInsertStatus = .idle  // 图片插入状态
    
    // 图片插入状态枚举
    enum ImageInsertStatus {
        case idle
        case uploading
        case success
        case failed
    }
    
    // Web编辑器上下文
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
            // 如果笔记ID相同，跳过处理（避免打断用户编辑）
            if oldValue.id == newValue.id {
                print("[NoteDetailView] onChange(note): 笔记ID相同，跳过处理")
                return
            }
            // 使用 Task 异步执行，避免在视图更新过程中修改状态
            Task { @MainActor in
                await handleNoteChange(newValue)
            }
        }
        .onChange(of: editedTitle) { oldValue, newValue in
            // 使用 Task 异步执行，避免在视图更新过程中修改状态
            Task { @MainActor in
                await handleTitleChange(newValue)
            }
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
        .sheet(isPresented: $showImageInsertAlert) {
            ImageInsertStatusView(
                isInserting: isInsertingImage,
                message: imageInsertMessage,
                status: imageInsertStatus,
                onDismiss: {
                    imageInsertStatus = .idle
                }
            )
        }
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
            isEditable: $isEditable,
            hasRealTitle: hasRealTitle()
        )
    }
    
    /// 检查当前笔记是否有真正的标题
    private func hasRealTitle() -> Bool {
        guard let note = viewModel.selectedNote else { return false }
        
        // 如果标题为空，没有真正的标题
        if note.title.isEmpty {
            return false
        }
        
        // 如果标题是"未命名笔记_xxx"格式，没有真正的标题
        if note.title.hasPrefix("未命名笔记_") {
            return false
        }
        
        // 检查 rawData 中的 extraInfo 是否有真正的标题
        if let rawData = note.rawData,
           let extraInfo = rawData["extraInfo"] as? String,
           let extraData = extraInfo.data(using: .utf8),
           let extraJson = try? JSONSerialization.jsonObject(with: extraData) as? [String: Any],
           let realTitle = extraJson["title"] as? String,
           !realTitle.isEmpty {
            // 如果 extraInfo 中有标题，且与当前标题匹配，说明有真正的标题
            if realTitle == note.title {
                return true
            }
        }
        
        // 检查标题是否与内容的第一行匹配（去除XML标签后）
        // 如果匹配，说明标题可能是从内容中提取的（处理旧数据），没有真正的标题
        if !note.content.isEmpty {
            // 移除XML标签，提取纯文本
            let textContent = note.content
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&apos;", with: "'")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 获取第一行
            let firstLine = textContent.split(separator: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            // 如果标题与第一行匹配，说明可能是从内容中提取的（处理旧数据）
            if !firstLine.isEmpty && note.title == firstLine {
                return false
            }
        }
        
        // 默认情况下，如果标题不为空且不是"未命名笔记_xxx"，认为有真正的标题
        return true
    }
    
    /// 日期和字数信息视图（只读）
    private func metaInfoView(for note: Note) -> some View {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy年MM月dd日 HH:mm"
        let updateDateString = dateFormatter.string(from: note.updatedAt)
        
        // 计算字数（从 XML 计算）
        let wordCount = calculateWordCount(from: currentXMLContent.isEmpty ? note.primaryXMLContent : currentXMLContent)
        
        return Text("\(updateDateString) · \(wordCount) 字")
            .font(.system(size: 10))
            .foregroundColor(.secondary)
    }
    
    /// 计算字数（从 XML 内容）
    /// 提取 XML 中的纯文本内容并计算字符数
    private func calculateWordCount(from xmlContent: String) -> Int {
        guard !xmlContent.isEmpty else { return 0 }
        
        // 使用正则表达式提取所有文本内容（去除 XML 标签）
        // 匹配 > 和 < 之间的文本，或者标签后的文本
        let pattern = ">([^<]+)<|([^<>]+)(?=<|$)"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let nsString = xmlContent as NSString
        let matches = regex?.matches(in: xmlContent, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
        
        var totalCount = 0
        for match in matches {
            // 提取匹配的文本（去除空白字符）
            for rangeIndex in 1..<match.numberOfRanges {
                let range = match.range(at: rangeIndex)
                if range.location != NSNotFound {
                    let text = nsString.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
                    totalCount += text.count
                }
            }
        }
        
        // 如果没有匹配到文本，尝试简单方法：去除所有标签
        if totalCount == 0 {
            let textOnly = xmlContent
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            totalCount = textOnly.count
        }
        
        return totalCount
    }
    
    /// 正文编辑区域（使用Web编辑器）
    private var bodyEditorView: some View {
        Group {
            if let note = viewModel.selectedNote {
                // 使用新的Web编辑器
                WebEditorWrapper(
                    content: Binding(
                        get: { note.primaryXMLContent },
                        set: { newContent in
                            // 内容变化时处理
                            guard !isInitializing else { return }
                            
                            // 检查内容是否真的变化了
                            if newContent != note.primaryXMLContent {
                                // 内容确实变化了，触发保存
                                Task { @MainActor in
                                    await saveToLocalOnly(for: note)
                                    // 获取最新内容用于上传
                                    let latestContent = await getLatestContentFromEditor()
                                    scheduleCloudUpload(for: note, xmlContent: latestContent)
                                }
                            }
                        }
                    ),
                    isEditable: $isEditable,
                    editorContext: webEditorContext,
                    noteRawData: {
                        if let rawData = note.rawData,
                           let jsonData = try? JSONSerialization.data(withJSONObject: rawData, options: []) {
                            return String(data: jsonData, encoding: .utf8)
                        }
                        return nil
                    }(),
                    xmlContent: note.primaryXMLContent,
                    onContentChange: { newContent in
                        // 内容变化回调
                        guard !isInitializing else { 
                            print("[保存流程] 步骤1: 内容变化，但正在初始化，跳过保存")
                            return 
                        }
                        
                        print("[保存流程] 步骤1: 收到内容变化通知，XML长度: \(newContent.count)")
                        
                        // 更新当前 XML 内容（用于字数统计）
                        Task { @MainActor in
                            print("[保存流程] 步骤2: 开始处理内容变化")
                            currentXMLContent = newContent
                            
                            // 触发保存，直接使用接收到的 XML 内容
                            guard let note = viewModel.selectedNote else { 
                                print("[保存流程] ⚠️ 步骤3: selectedNote 为 nil，无法保存")
                                return 
                            }
                            
                            print("[保存流程] 步骤3: 开始保存，笔记ID: \(note.id)")
                            print("[保存流程] 步骤4: 调用 saveToLocalOnlyWithContent，使用接收到的XML内容")
                            await saveToLocalOnlyWithContent(xmlContent: newContent, for: note)
                            print("[保存流程] 步骤5: 调用 scheduleCloudUpload")
                            scheduleCloudUpload(for: note, xmlContent: newContent)
                            print("[保存流程] ✅ 保存流程完成")
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
            horizontalRuleButton
            imageButton
            Divider()
                .frame(height: 16)
            indentButtons
            Divider()
                .frame(height: 16)
            debugButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
    }
    
    /// 撤销按钮
    private var undoButton: some View {
        Button {
            webEditorContext.undo()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 16))
        }
        .buttonStyle(.plain)
        .help("撤销 (⌘Z)")
    }
    
    /// 重做按钮
    private var redoButton: some View {
        Button {
            webEditorContext.redo()
        } label: {
            Image(systemName: "arrow.uturn.forward")
                .font(.system(size: 16))
        }
        .buttonStyle(.plain)
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
            WebFormatMenuView(context: webEditorContext) { action in
                // WebFormatMenuView 使用 WebEditorContext 处理格式操作，这里只需要关闭菜单
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
    
    private var horizontalRuleButton: some View {
        Button {
            insertHorizontalRule()
        } label: {
            Image(systemName: "minus")
        }
        .help("插入分割线")
    }
    
    private var imageButton: some View {
        Button {
            insertImage()
        } label: {
            Image(systemName: "paperclip")
        }
        .help("插入图片")
    }
    
    /// 缩进按钮组
    private var indentButtons: some View {
        HStack(spacing: 0) {
            Button {
                webEditorContext.increaseIndent()
            } label: {
                Image(systemName: "increase.indent")
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .help("增加缩进")
            
            Button {
                webEditorContext.decreaseIndent()
            } label: {
                Image(systemName: "decrease.indent")
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .help("减少缩进")
        }
    }
    
    private var debugButton: some View {
        Button {
            openWebInspector()
        } label: {
            Image(systemName: "ladybug")
        }
        .help("打开Web检查器 (⌘⌥I)")
        .keyboardShortcut("i", modifiers: [.command, .option])
    }
    
    /// 打开Web Inspector
    private func openWebInspector() {
        // 通过WebEditorContext打开Web Inspector
        webEditorContext.openWebInspector()
        
        // 同时输出测试日志
        Task { @MainActor in
            // 延迟一点时间，确保Web Inspector已打开
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            
            // 输出测试日志
            webEditorContext.getCurrentContentClosure? { _ in
                // 通过JavaScript输出测试日志
                // 注意：这需要在WebView中执行，但我们没有直接访问
                // 所以日志会通过editorBridge发送到Swift，然后打印到Xcode控制台
            }
        }
    }
    
    /// 处理格式操作（已废弃，WebFormatMenuView 通过 WebEditorContext 直接处理格式操作）
    private func handleFormatAction(_ action: FormatAction) {
        // WebFormatMenuView 已经通过 WebEditorContext 直接处理格式操作
        // 此函数保留用于向后兼容
        print("[NoteDetailView] 格式操作: \(action)")
    }
    
    /// 格式操作类型（用于向后兼容）
    enum FormatAction {
        case bold
        case italic
        case underline
        case strikethrough
        case heading(Int)
        case highlight
        case textAlignment(NSTextAlignment)
    }
    
    /// 插入复选框
    private func insertCheckbox() {
        // 使用 WebEditorContext 插入复选框
        webEditorContext.insertCheckbox()
        print("[NoteDetailView] 已插入复选框（Web编辑器）")
    }
    
    /// 插入分割线
    private func insertHorizontalRule() {
        // 使用 WebEditorContext 插入分割线
        webEditorContext.insertHorizontalRule()
        print("[NoteDetailView] 已插入分割线（Web编辑器）")
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
        // 先上传图片到服务器，获取 fileId
        // 然后使用 minote://image/{fileId} URL 插入图片
        // 这样可以避免将 base64 数据保存到 XML content 中
        
        guard let note = viewModel.selectedNote else {
            print("[NoteDetailView] ⚠️ 无法插入图片：未选择笔记")
            imageInsertMessage = "无法插入图片：未选择笔记"
            showImageInsertAlert = true
            return
        }
        
        // 显示"正在插入"的弹窗
        isInsertingImage = true
        imageInsertStatus = .uploading
        imageInsertMessage = "正在上传图片：\(url.lastPathComponent)..."
        showImageInsertAlert = true
        
        guard viewModel.isOnline && viewModel.isLoggedIn else {
            print("[NoteDetailView] ⚠️ 无法插入图片：未登录或离线")
            // 离线模式：暂时使用 base64，但应该提示用户
            guard let imageData = try? Data(contentsOf: url) else {
                print("[NoteDetailView] ⚠️ 无法加载图片: \(url)")
                isInsertingImage = false
                imageInsertStatus = .failed
                imageInsertMessage = "无法加载图片：\(url.lastPathComponent)"
                // 弹窗已经在显示，状态更新会自动刷新内容
                return
            }
            let base64String = imageData.base64EncodedString()
            let mimeType: String
            switch url.pathExtension.lowercased() {
            case "png":
                mimeType = "image/png"
            case "jpg", "jpeg":
                mimeType = "image/jpeg"
            case "gif":
                mimeType = "image/gif"
            default:
                mimeType = "image/jpeg"
            }
            let dataUrl = "data:\(mimeType);base64,\(base64String)"
            webEditorContext.insertImage(dataUrl, altText: url.lastPathComponent)
            print("[NoteDetailView] ⚠️ 离线模式：已插入 base64 图片（临时）: \(url.lastPathComponent)")
            
            // 显示离线模式提示
            // 延迟一下再显示结果，让用户看到"正在插入"的状态
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            isInsertingImage = false
            imageInsertStatus = .success
            imageInsertMessage = "已插入图片（离线模式，临时）：\(url.lastPathComponent)"
            // 弹窗已经在显示，状态更新会自动刷新内容
            return
        }
        
        do {
            // 使用 ViewModel 的上传方法，直接获取 fileId
            let fileId = try await viewModel.uploadImageAndInsertToNote(imageURL: url)
            
            // 使用 minote://image/{fileId} URL 插入图片到编辑器
            let imageUrl = "minote://image/\(fileId)"
            webEditorContext.insertImage(imageUrl, altText: url.lastPathComponent)
            
            print("[NoteDetailView] ✅ 已插入图片（Web编辑器）: \(url.lastPathComponent), fileId: \(fileId)")
            
            // 显示成功提示
            // 延迟一下再显示结果，让用户看到"正在插入"的状态
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            isInsertingImage = false
            imageInsertStatus = .success
            imageInsertMessage = "图片插入成功：\(url.lastPathComponent)"
            // 弹窗已经在显示，状态更新会自动刷新内容
            
            // 触发保存（图片插入后需要保存）
            Task { @MainActor in
                await performSaveImmediately()
            }
        } catch {
            print("[NoteDetailView] ❌ 上传图片失败: \(error.localizedDescription)")
            
            // 显示失败提示
            // 延迟一下再显示结果，让用户看到"正在插入"的状态
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            isInsertingImage = false
            imageInsertStatus = .failed
            imageInsertMessage = "图片插入失败：\(error.localizedDescription)"
            // 弹窗已经在显示，状态更新会自动刷新内容
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
    /// 从 XML 内容加载笔记到编辑器。
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
        
        // 设置 XML 内容
        let xmlContent = note.primaryXMLContent
        currentXMLContent = xmlContent
        originalXMLContent = xmlContent
        
        // 重置 lastSavedXMLContent，确保下次编辑能正确保存
        lastSavedXMLContent = xmlContent
        
        if note.content.isEmpty {
            await viewModel.ensureNoteHasFullContent(note)
            if let updatedNote = viewModel.selectedNote {
                // 更新 XML 内容
                let updatedXMLContent = updatedNote.primaryXMLContent
                currentXMLContent = updatedXMLContent
                originalXMLContent = updatedXMLContent
                lastSavedXMLContent = updatedXMLContent
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
    @MainActor
    private func handleNoteChange(_ newValue: Note) async {
        let saveTask = saveCurrentNoteBeforeSwitching(newNoteId: newValue.id)
        
        // 如果有保存任务，等待它完成
        if let saveTask = saveTask {
            await saveTask.value
        }
        // 加载新笔记内容
        await loadNoteContent(newValue)
    }
    
    @MainActor
    private func handleTitleChange(_ newValue: String) async {
        guard !isInitializing else {
            print("[NoteDetailView] 标题变化检测，但正在初始化，跳过处理")
            return
        }
        if newValue != originalTitle {
            print("[NoteDetailView] 标题变化: '\(originalTitle)' -> '\(newValue)'")
            originalTitle = newValue
            // 立即保存，不使用防抖
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
        let hasContentChanges = currentXMLContent != originalXMLContent
        
        guard hasTitleChanges || hasContentChanges else {
            return
        }
        
        // 取消之前的云端上传任务
        pendingCloudUploadWorkItem?.cancel()
        
        // 立即保存到本地
        Task { @MainActor in
            await saveToLocalOnly(for: note)
            
            // 延迟上传到云端 - 获取最新内容
            let latestContent = await getLatestContentFromEditor()
            scheduleCloudUpload(for: note, xmlContent: latestContent)
        }
    }
    
    /// 仅保存到本地（使用指定的内容）
    /// 
    /// 直接使用提供的 XML 内容保存，不重新从编辑器获取。
    /// 
    /// - Parameters:
    ///   - xmlContent: 要保存的 XML 内容
    ///   - note: 要保存的笔记对象
    @MainActor
    private func saveToLocalOnlyWithContent(xmlContent: String, for note: Note) async {
        // 验证笔记ID
        guard note.id == currentEditingNoteId else {
            print("[保存流程] ⚠️ saveToLocalOnlyWithContent: 笔记ID不匹配，当前编辑: \(currentEditingNoteId ?? "无"), 要保存: \(note.id)")
            return
        }
        
        // 防止并发保存
        if isSavingLocally {
            print("[保存流程] ⚠️ saveToLocalOnlyWithContent: 正在保存中，等待...")
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
            if isSavingLocally {
                print("[保存流程] ⚠️ saveToLocalOnlyWithContent: 仍在保存中，跳过")
                return
            }
        }
        
        isSavingLocally = true
        defer { isSavingLocally = false }
        
        do {
            print("[保存流程] saveToLocalOnlyWithContent 步骤1: 开始保存笔记到本地: \(note.id)")
            print("[保存流程] saveToLocalOnlyWithContent 步骤2: 使用提供的XML内容，长度: \(xmlContent.count)")
            
            // 检查是否有变化（避免重复保存）
            print("[保存流程] saveToLocalOnlyWithContent 步骤4: 检查内容是否变化")
            print("[保存流程]   当前XML: \(xmlContent.prefix(100))...")
            print("[保存流程]   上次保存XML: \(lastSavedXMLContent.prefix(100))...")
            print("[保存流程]   标题变化: \(editedTitle != originalTitle)")
            
            guard hasContentChanged(xmlContent: xmlContent) else {
                print("[保存流程] ⚠️ saveToLocalOnlyWithContent 步骤5: 内容未变化，跳过保存")
                return
            }
            
            print("[保存流程] saveToLocalOnlyWithContent 步骤3: 内容有变化，继续保存")
            
            // 构建更新的笔记对象
            let updatedNote = buildUpdatedNote(from: note, xmlContent: xmlContent)
            print("[保存流程] saveToLocalOnlyWithContent 步骤4: 已构建更新的笔记对象")
            
            // 保存到数据库
            print("[保存流程] saveToLocalOnlyWithContent 步骤5: 开始保存到数据库")
            try LocalStorageService.shared.saveNote(updatedNote)
            print("[保存流程] ✅ saveToLocalOnlyWithContent 步骤6: 笔记已保存到本地数据库，XML长度: \(updatedNote.content.count)")
            
            // 更新状态
            updateSaveState(xmlContent: xmlContent)
            print("[保存流程] saveToLocalOnlyWithContent 步骤7: 已更新保存状态")
            
            // 延迟更新 ViewModel（避免触发重新加载）
            updateViewModelDelayed(with: updatedNote)
            print("[保存流程] saveToLocalOnlyWithContent 步骤10: 已安排延迟更新 ViewModel")
            
        } catch {
            print("[保存流程] ❌ saveToLocalOnlyWithContent: 本地保存失败: \(error.localizedDescription)")
            print("[保存流程]   错误详情: \(error)")
        }
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
            print("[保存流程] ⚠️ saveToLocalOnly: 笔记ID不匹配，当前编辑: \(currentEditingNoteId ?? "无"), 要保存: \(note.id)")
            return
        }
        
        // 防止并发保存
        if isSavingLocally {
            print("[保存流程] ⚠️ saveToLocalOnly: 正在保存中，等待...")
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
            if isSavingLocally {
                print("[保存流程] ⚠️ saveToLocalOnly: 仍在保存中，跳过")
                return
            }
        }
        
        isSavingLocally = true
        defer { isSavingLocally = false }
        
        do {
            // 获取最新内容（从Web编辑器获取）
            print("[保存流程] saveToLocalOnly 步骤1: 开始保存笔记到本地: \(note.id)")
            print("[保存流程] saveToLocalOnly 步骤2: 调用 getLatestContentFromEditor")
            let xmlContent = await getLatestContentFromEditor()
            print("[保存流程] saveToLocalOnly 步骤3: 获取到内容，XML长度: \(xmlContent.count)")
            
            // 检查是否有变化（避免重复保存）
            print("[保存流程] saveToLocalOnly 步骤4: 检查内容是否变化")
            print("[保存流程]   当前XML: \(xmlContent.prefix(100))...")
            print("[保存流程]   上次保存XML: \(lastSavedXMLContent.prefix(100))...")
            print("[保存流程]   标题变化: \(editedTitle != originalTitle)")
            
            guard hasContentChanged(xmlContent: xmlContent) else {
                print("[保存流程] ⚠️ saveToLocalOnly 步骤5: 内容未变化，跳过保存")
                return
            }
            
            print("[保存流程] saveToLocalOnly 步骤5: 内容有变化，继续保存")
            
            // 构建更新的笔记对象
            let updatedNote = buildUpdatedNote(from: note, xmlContent: xmlContent)
            print("[保存流程] saveToLocalOnly 步骤6: 已构建更新的笔记对象")
            
            // 保存到数据库
            print("[保存流程] saveToLocalOnly 步骤7: 开始保存到数据库")
            try LocalStorageService.shared.saveNote(updatedNote)
            print("[保存流程] ✅ saveToLocalOnly 步骤8: 笔记已保存到本地数据库，XML长度: \(updatedNote.content.count)")
            
            // 更新状态
            updateSaveState(xmlContent: xmlContent)
            print("[保存流程] saveToLocalOnly 步骤9: 已更新保存状态")
            
            // 延迟更新 ViewModel（避免触发重新加载）
            updateViewModelDelayed(with: updatedNote)
            print("[保存流程] saveToLocalOnly 步骤10: 已安排延迟更新 ViewModel")
            
        } catch {
            print("[保存流程] ❌ saveToLocalOnly: 本地保存失败: \(error.localizedDescription)")
            print("[保存流程]   错误详情: \(error)")
        }
    }
    
    /// 安排云端上传（智能防抖）
    /// 
    /// 根据内容大小智能调整防抖时间，避免频繁上传。
    /// 大文件延迟更长，小文件延迟较短。
    /// 
    /// - Parameters:
    ///   - note: 要上传的笔记对象
    ///   - xmlContent: 要上传的 XML 内容（已保存的）
    // 云端上传任务
    @State private var cloudUploadTask: Task<Void, Never>? = nil
    @State private var lastUploadedContent: String = ""  // 上次上传的内容，用于检测是否有修改
    
    private func scheduleCloudUpload(for note: Note, xmlContent: String) {
        guard viewModel.isOnline && viewModel.isLoggedIn else {
            // 不在线，取消任务
            cloudUploadTask?.cancel()
            cloudUploadTask = nil
            return
        }
        
        // 检查内容是否有变化
        guard xmlContent != lastUploadedContent else {
            // 内容没有变化，取消任务（不循环上传）
            cloudUploadTask?.cancel()
            cloudUploadTask = nil
            return
        }
        
        // 取消之前的任务
        cloudUploadTask?.cancel()
        cloudUploadTask = nil
        
        // 捕获当前状态
        let currentNoteId = currentEditingNoteId
        let viewModelRef = viewModel
        
        // 使用 Task 实现定时检查（每5秒检查一次是否有修改）
        // 这样避免了在 struct 中使用 Timer 闭包的问题
        cloudUploadTask = Task { @MainActor in
            // 立即执行第一次上传（如果有修改）
            if xmlContent != lastUploadedContent {
                await performCloudUpload(for: note, xmlContent: xmlContent)
                lastUploadedContent = xmlContent
            }
            
            // 然后每5秒检查一次
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5秒
                
                // 检查任务是否已取消
                if Task.isCancelled {
                    break
                }
                
                // 检查笔记ID是否仍然匹配
                guard let note = viewModelRef.selectedNote,
                      note.id == currentNoteId,
                      note.id == currentEditingNoteId else {
                    break
                }
                
                // 获取当前内容
                let currentContent = await getLatestContentFromEditor()
                
                // 检查内容是否有变化
                if currentContent != lastUploadedContent {
                    // 有修改，执行上传
                    print("[保存流程] 定时上传: 检测到内容变化，开始上传")
                    await performCloudUpload(for: note, xmlContent: currentContent)
                    lastUploadedContent = currentContent
                } else {
                    // 无修改，停止任务（不循环上传）
                    print("[保存流程] 定时上传: 无修改，停止任务")
                    break
                }
            }
        }
        
        // 立即执行第一次上传（如果有修改）
        Task { @MainActor in
            if xmlContent != lastUploadedContent {
                await performCloudUpload(for: note, xmlContent: xmlContent)
                lastUploadedContent = xmlContent
            }
        }
    }
    
    /// 执行云端上传
    @MainActor
    private func performCloudUpload(for note: Note, xmlContent: String) async {
        // 验证笔记ID
        guard note.id == currentEditingNoteId else {
            return
        }
        
        // 直接使用传入的 XML 内容，不重新获取
        let updatedNote = buildUpdatedNote(from: note, xmlContent: xmlContent)
        
        // 开始上传
        isUploading = true
        
        do {
            // 触发云端上传（updateNote 会再次保存到本地，这是幂等操作）
            try await viewModel.updateNote(updatedNote)
            
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
        
        // 安排云端上传（如果在线）- 使用已保存的内容
        let savedContent = await getLatestContentFromEditor()
        scheduleCloudUpload(for: note, xmlContent: savedContent)
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
            // 获取最新内容（从Web编辑器获取）
            let xmlContent = await getLatestContentFromEditor()
            
            // 构建更新的笔记对象
            let updatedNote = buildUpdatedNote(from: note, xmlContent: xmlContent)
            
            // updateNote 会先保存到本地，然后上传到云端（如果在线）
            try await viewModel.updateNote(updatedNote)
            
            // 更新状态
            updateSaveState(xmlContent: xmlContent)
            
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
        
        // 取消待执行的保存任务和上传任务
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        pendingCloudUploadWorkItem?.cancel()
        cloudUploadTask?.cancel()
        cloudUploadTask = nil
        
        // 标记正在为切换而保存
        isSavingBeforeSwitch = true
        
        return Task { @MainActor in
            // 先强制保存编辑器中的最新内容
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                webEditorContext.forceSaveContent {
                    continuation.resume()
                }
            }
            
            // 等待一小段时间，确保内容变化回调已经处理
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
            
            // 然后保存到本地
            await saveToLocalOnly(for: currentNote)
            isSavingBeforeSwitch = false
        }
    }
    
    /// 处理选中的笔记变化
    private func handleSelectedNoteChange(oldValue: Note?, newValue: Note?) {
        print("[NoteDetailView] 检测笔记切换，旧笔记ID: \(oldValue?.id ?? "无"), 新笔记ID: \(newValue?.id ?? "无")")
        guard let oldNote = oldValue, let newNote = newValue else {
            // 如果没有旧笔记或新笔记，直接处理
            if let note = newValue {
                Task { @MainActor in
                    await handleNoteChange(note)
                }
            }
            return
        }
        
        // 如果切换到不同的笔记
        if oldNote.id != newNote.id {
            print("[NoteDetailView] 切换到新笔记: \(oldNote.id) -> \(newNote.id)")
            // 保存当前笔记的更改，并等待保存任务完成
            let saveTask = saveCurrentNoteBeforeSwitching(newNoteId: newNote.id)
            
            // 如果保存任务存在，等待它完成后再加载新笔记
            if let saveTask = saveTask {
                print("[NoteDetailView] 等待切换前保存完成")
                Task { @MainActor in
                    await saveTask.value
                    await handleNoteChangeAsync(newNote)
                }
            } else {
                // 没有保存任务，直接加载新笔记
                print("[NoteDetailView] 无待保存内容，直接加载新笔记")
                Task { @MainActor in
                    await handleNoteChangeAsync(newNote)
                }
            }
        } else {
            // 相同笔记，只是内容更新
            // 注意：如果这是保存操作导致的更新，不应该重新加载内容（会覆盖编辑器状态）
            // 只有在外部更新（如云端同步）时才重新加载
            print("[NoteDetailView] 相同笔记内容更新，笔记ID: \(newNote.id)")
            
            // 检查是否是当前正在编辑的笔记
            if currentEditingNoteId == newNote.id {
                print("[NoteDetailView] 这是当前正在编辑的笔记，跳过重新加载（避免打断用户编辑）")
                return
            }
            
            // 检查是否是保存操作导致的更新（通过检查是否正在保存或上传）
            if isSavingLocally || isSavingBeforeSwitch || isUploading {
                print("[NoteDetailView] 正在保存或上传，跳过重新加载（避免覆盖编辑器状态）")
                return
            }
            
            // 检查是否是初始化阶段
            if isInitializing {
                print("[NoteDetailView] 正在初始化，跳过重新加载")
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
        print("[NoteDetailView] 加载笔记内容，笔记ID: \(newValue.id)")
        await loadNoteContent(newValue)
    }
    
    // MARK: - 保存辅助方法
    
    /// 从编辑器获取最新的内容（XML内容）
    /// - Returns: XML内容字符串
    @MainActor
    private func getLatestContentFromEditor() async -> String {
        print("[保存流程] getLatestContentFromEditor: 开始获取编辑器内容")
        
        // Web编辑器模式：从WebEditorContext获取最新内容
        if let currentContent = await getCurrentEditorContent() {
            print("[保存流程] getLatestContentFromEditor: 从编辑器获取到内容，长度: \(currentContent.count)")
            return currentContent
        } else {
            print("[保存流程] ⚠️ getLatestContentFromEditor: 无法从编辑器获取内容，使用 currentXMLContent 作为后备")
            // 如果无法从编辑器获取，使用当前保存的 XML 内容作为后备
            return currentXMLContent.isEmpty ? (viewModel.selectedNote?.primaryXMLContent ?? "") : currentXMLContent
        }
    }
    
    /// 从Web编辑器获取当前内容
    @MainActor
    private func getCurrentEditorContent() async -> String? {
        return await withCheckedContinuation { continuation in
            webEditorContext.getCurrentContent { content in
                continuation.resume(returning: content.isEmpty ? nil : content)
            }
        }
    }
    
    /// 构建更新的笔记对象
    /// - Parameters:
    ///   - note: 原始笔记对象
    ///   - xmlContent: XML内容
    /// - Returns: 更新后的笔记对象
    private func buildUpdatedNote(
        from note: Note,
        xmlContent: String
    ) -> Note {
        return Note(
            id: note.id,
            title: editedTitle,
            content: xmlContent,
            folderId: note.folderId,
            isStarred: note.isStarred,
            createdAt: note.createdAt,
            updatedAt: Date(),
            tags: note.tags,
            rawData: note.rawData
        )
    }
    
    /// 更新保存后的状态变量
    /// - Parameter xmlContent: 保存的XML内容
    private func updateSaveState(xmlContent: String) {
        lastSavedXMLContent = xmlContent
        originalTitle = editedTitle
        originalXMLContent = xmlContent
        currentXMLContent = xmlContent
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
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
            
            // 确保保存标志仍然设置，避免触发重新加载
            // 注意：此时 isSavingLocally 应该已经是 false（因为 defer 已经执行）
            // 所以我们需要临时设置它
            let wasSaving = isSavingLocally
            isSavingLocally = true
            
            // 更新 ViewModel
            viewModel.notes[index] = updatedNote
            if viewModel.selectedNote?.id == updatedNote.id {
                viewModel.selectedNote = updatedNote
            }
            
            // 延迟恢复保存状态，确保 onChange 检查时标志仍然有效
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
            isSavingLocally = wasSaving
        }
    }
    
    /// 检查内容是否真的变化了（避免重复保存）
    /// - Parameters:
    ///   - xmlContent: 当前的XML内容
    /// - Returns: 如果内容或标题有变化，返回true
    private func hasContentChanged(xmlContent: String) -> Bool {
        // 检查XML内容是否变化
        if lastSavedXMLContent == xmlContent {
            // XML内容相同，检查标题是否变化
            return editedTitle != originalTitle
        }
        // XML内容不同，肯定有变化
        return true
    }
}

/// 图片插入状态视图
@available(macOS 14.0, *)
struct ImageInsertStatusView: View {
    let isInserting: Bool
    let message: String
    let status: NoteDetailView.ImageInsertStatus
    let onDismiss: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            if isInserting {
                ProgressView()
                    .scaleEffect(1.2)
                    .padding(.bottom, 8)
            } else {
                // 根据状态显示不同的图标
                Image(systemName: status == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(status == .success ? .green : .red)
                    .padding(.bottom, 8)
            }
            
            Text(isInserting ? "正在插入图片" : (status == .success ? "插入成功" : "插入失败"))
                .font(.headline)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if !isInserting {
                Button("确定") {
                    onDismiss()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
        }
        .padding(30)
        .frame(width: 400)
    }
}

#Preview {
    NoteDetailView(viewModel: NotesViewModel())
        .frame(width: 600, height: 400)
}
