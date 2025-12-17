import SwiftUI

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
                        MiNoteEditor(xmlContent: $editedContent, isEditable: $isEditable)
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
                            // 格式操作由 EditorToolbar 处理
                        }
                        Button("标题") {}
                        Button("副标题") {}
                        Divider()
                        Button("加粗") {}
                        Button("斜体") {}
                    } label: {
                        Image(systemName: "textformat")
                    }
                    
                    Button {
                        // TODO: 插入代办
                    } label: {
                        Image(systemName: "checklist")
                    }
                    
                    Button {
                        // TODO: 插入附件
                    } label: {
                        Image(systemName: "paperclip")
                    }
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
