import SwiftUI
import OSLog

/// 回收站视图
/// 
/// 显示已删除的笔记列表，使用与历史记录相同的UI布局
@available(macOS 14.0, *)
struct TrashView: View {
    @ObservedObject var viewModel: NotesViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedDeletedNote: DeletedNote?
    @State private var noteContent: Note?
    @State private var isLoadingContent: Bool = false
    @State private var showingRestoreConfirm: Bool = false
    @State private var showingDeleteConfirm: Bool = false
    @State private var isRestoring: Bool = false
    @State private var isPermanentlyDeleting: Bool = false
    @State private var operationError: String?
    
    // 创建只读的编辑器上下文
    @StateObject private var editorContext: NativeEditorContext = {
        let context = NativeEditorContext()
        return context
    }()
    
    // 日志记录器
    private let logger = Logger(subsystem: "com.xiaomi.minote.mac", category: "TrashView")
    
    // 自定义关闭方法，用于AppKit环境
    private func closeSheet() {
        // 尝试使用dismiss环境变量
        dismiss()
        
        // 如果dismiss无效，尝试通过NSApp关闭窗口
        DispatchQueue.main.async {
            if let window = NSApp.keyWindow,
               let sheetParent = window.sheetParent {
                sheetParent.endSheet(window)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 主内容区域（左右分栏）
            HSplitView {
                // 左侧：回收站笔记列表
                leftPanel
                    .frame(minWidth: 300, idealWidth: 350, maxWidth: 400)
                
                // 右侧：预览区域
                rightPanel
                    .frame(minWidth: 400)
            }
        }
        .task {
            // 打开时自动获取回收站笔记
            await viewModel.fetchDeletedNotes()
        }
        .alert("恢复笔记", isPresented: $showingRestoreConfirm) {
            Button("取消", role: .cancel) {}
            Button("恢复") {
                if let deletedNote = selectedDeletedNote {
                    restoreNote(deletedNote)
                }
            }
        } message: {
            Text("确定要恢复这个笔记吗？")
        }
        .alert("永久删除", isPresented: $showingDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("永久删除", role: .destructive) {
                if let deletedNote = selectedDeletedNote {
                    permanentlyDeleteNote(deletedNote)
                }
            }
        } message: {
            Text("确定要永久删除这个笔记吗？此操作不可恢复！")
        }
        .alert("操作失败", isPresented: .constant(operationError != nil)) {
            Button("确定", role: .cancel) {
                operationError = nil
            }
        } message: {
            if let error = operationError {
                Text(error)
            }
        }
        .frame(minWidth: 800, idealWidth: 1000, maxWidth: 1200, minHeight: 500, idealHeight: 700, maxHeight: 800)
    }
    
    // MARK: - 左侧面板
    
    @ViewBuilder
    private var leftPanel: some View {
        Group {
            if viewModel.isLoadingDeletedNotes {
                VStack(spacing: 16) {
                    ProgressView("加载回收站...")
                    Text("正在加载...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.deletedNotes.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "trash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("回收站为空")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("已删除的笔记将显示在这里")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.deletedNotes) { deletedNote in
                            DeletedNoteRow(
                                deletedNote: deletedNote,
                                isSelected: selectedDeletedNote?.id == deletedNote.id
                            )
                            .onTapGesture {
                                selectedDeletedNote = deletedNote
                                loadNoteContent(deletedNote)
                            }
                        }
                    }
                    .padding(.top, -8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - 右侧面板
    
    @ViewBuilder
    private var rightPanel: some View {
        Group {
            if selectedDeletedNote == nil {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("选择笔记查看")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("从左侧列表中选择一个笔记以查看其内容")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoadingContent {
                VStack(spacing: 16) {
                    ProgressView("加载内容...")
                    Text("正在加载笔记内容...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let note = noteContent {
                // 使用原生编辑器（只读模式）
                VStack(spacing: 0) {
                    // 工具栏
                    HStack {
                        if let deletedNote = selectedDeletedNote {
                            Text("删除于: \(deletedNote.formattedDeleteTime)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // 恢复按钮
                        Button {
                            showingRestoreConfirm = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.uturn.backward")
                                Text("恢复")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRestoring || isPermanentlyDeleting)
                        
                        // 永久删除按钮
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("永久删除")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRestoring || isPermanentlyDeleting)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .border(Color(NSColor.separatorColor), width: 0.5)
                    
                    // 内容区域
                    if !note.content.isEmpty {
                        NativeEditorView(
                            editorContext: editorContext,
                            isEditable: false  // 设置为只读
                        )
                        .opacity(0.9)  // 降低透明度表示只读
                    } else {
                        VStack {
                            Spacer()
                            Text("此笔记暂无内容")
                                .font(.body)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text("无法加载内容")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
        .onChange(of: noteContent) { oldValue, newValue in
            if let note = newValue {
                loadContentToEditor(note)
            }
        }
    }
    
    // MARK: - 辅助方法
    
    /// 加载内容到编辑器
    private func loadContentToEditor(_ note: Note) {
        Task { @MainActor in
            do {
                // 使用 XiaoMiFormatConverter 将 XML 转换为 NSAttributedString
                let attributedString = try XiaoMiFormatConverter.shared.xmlToNSAttributedString(
                    note.content,
                    folderId: note.folderId
                )
                
                // 设置到编辑器上下文
                editorContext.setContent(attributedString)
            } catch {
                print("[TrashView] 加载内容失败: \(error.localizedDescription)")
                // 如果转换失败，显示纯文本
                let plainText = note.content
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">")
                editorContext.setContent(NSAttributedString(string: plainText))
            }
        }
    }
    
    /// 加载笔记内容
    private func loadNoteContent(_ deletedNote: DeletedNote) {
        isLoadingContent = true
        
        Task {
            do {
                // 尝试获取笔记的完整内容
                // 注意：回收站的笔记可能无法直接获取完整内容，先尝试使用 snippet
                // 如果需要完整内容，可能需要调用特定的 API
                let response = try await viewModel.service.fetchNoteDetails(noteId: deletedNote.id)
                
                // 解析响应并创建 Note 对象
                if let note = Note.fromMinoteData(response) {
                    await MainActor.run {
                        self.noteContent = note
                        self.isLoadingContent = false
                    }
                } else {
                    // 如果无法获取完整内容，至少显示 snippet
                    throw NSError(domain: "TrashView", code: 404, userInfo: [NSLocalizedDescriptionKey: "无法获取笔记内容"])
                }
            } catch {
                logger.error("加载笔记内容失败: \(error.localizedDescription)")
                
                // 如果获取失败，将 snippet 包装成简单的 XML 格式以便显示
                // snippet 可能是 HTML 或纯文本，我们需要将其转换为 XML
                let snippetContent = deletedNote.snippet.isEmpty ? "无内容" : deletedNote.snippet
                
                // 尝试将 snippet 包装成 XML 格式
                // 如果 snippet 已经是 XML，直接使用；否则包装成简单的 XML
                let xmlContent: String
                if snippetContent.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
                    // 看起来已经是 XML/HTML 格式
                    xmlContent = snippetContent
                } else {
                    // 纯文本，包装成 XML
                    let escapedText = snippetContent
                        .replacingOccurrences(of: "&", with: "&amp;")
                        .replacingOccurrences(of: "<", with: "&lt;")
                        .replacingOccurrences(of: ">", with: "&gt;")
                    xmlContent = "<en-note><p>\(escapedText)</p></en-note>"
                }
                
                let note = Note(
                    id: deletedNote.id,
                    title: deletedNote.subject.isEmpty ? "无标题" : deletedNote.subject,
                    content: xmlContent,
                    folderId: deletedNote.folderId,
                    isStarred: false,
                    createdAt: Date(timeIntervalSince1970: TimeInterval(deletedNote.createDate) / 1000.0),
                    updatedAt: Date(timeIntervalSince1970: TimeInterval(deletedNote.modifyDate) / 1000.0),
                    rawData: [
                        "id": deletedNote.id,
                        "tag": deletedNote.tag,
                        "subject": deletedNote.subject,
                        "snippet": deletedNote.snippet,
                        "folderId": deletedNote.folderId,
                        "createDate": deletedNote.createDate,
                        "modifyDate": deletedNote.modifyDate,
                        "deleteTime": deletedNote.deleteTime,
                        "status": deletedNote.status
                    ]
                )
                
                await MainActor.run {
                    self.noteContent = note
                    self.isLoadingContent = false
                }
            }
        }
    }
    
    /// 恢复笔记
    private func restoreNote(_ deletedNote: DeletedNote) {
        isRestoring = true
        operationError = nil
        
        Task {
            do {
                // 调用 ViewModel 的恢复方法
                try await viewModel.restoreDeletedNote(noteId: deletedNote.id, tag: deletedNote.tag)
                
                await MainActor.run {
                    isRestoring = false
                    // 清除选中状态
                    selectedDeletedNote = nil
                    noteContent = nil
                    // 刷新回收站列表
                    Task {
                        await viewModel.fetchDeletedNotes()
                    }
                }
            } catch {
                await MainActor.run {
                    isRestoring = false
                    operationError = "恢复失败: \(error.localizedDescription)"
                    logger.error("恢复笔记失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// 永久删除笔记
    private func permanentlyDeleteNote(_ deletedNote: DeletedNote) {
        isPermanentlyDeleting = true
        operationError = nil
        
        Task {
            do {
                // 调用 ViewModel 的永久删除方法
                try await viewModel.permanentlyDeleteNote(noteId: deletedNote.id, tag: deletedNote.tag)
                
                await MainActor.run {
                    isPermanentlyDeleting = false
                    // 清除选中状态
                    selectedDeletedNote = nil
                    noteContent = nil
                    // 刷新回收站列表
                    Task {
                        await viewModel.fetchDeletedNotes()
                    }
                }
            } catch {
                await MainActor.run {
                    isPermanentlyDeleting = false
                    operationError = "永久删除失败: \(error.localizedDescription)"
                    logger.error("永久删除笔记失败: \(error.localizedDescription)")
                }
            }
        }
    }
}

/// 回收站笔记行视图
struct DeletedNoteRow: View {
    let deletedNote: DeletedNote
    let isSelected: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // 标题
                Text(deletedNote.subject.isEmpty ? "无标题" : deletedNote.subject)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundColor(isSelected ? .white : .primary)
                
                // 摘要
                if !deletedNote.snippet.isEmpty {
                    Text(deletedNote.snippet)
                        .font(.caption)
                        .lineLimit(3)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
                
                // 删除时间
                Text("删除于 \(deletedNote.formattedDeleteTime)")
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.6) : .secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor : Color.clear)
        .cornerRadius(6)
    }
}
