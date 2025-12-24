import SwiftUI
import WebKit
import OSLog

/// 回收站视图
/// 
/// 显示已删除的笔记列表，使用与历史版本相同的UI布局
@available(macOS 14.0, *)
struct TrashView: View {
    @ObservedObject var viewModel: NotesViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedDeletedNote: DeletedNote?
    @State private var noteContent: Note?
    @State private var isLoadingContent: Bool = false
    
    // 日志记录器
    private let logger = Logger(subsystem: "com.xiaomi.minote.mac", category: "TrashView")
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏（与 NoteHistoryView 相同）
            HStack {
                Text("回收站")
                    .font(.headline)
                    .padding(.leading, 16)
                
                Spacer()
                
                Button("关闭") {
                    dismiss()
                }
                .padding(.trailing, 16)
            }
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(Color(NSColor.separatorColor)),
                alignment: .bottom
            )
            
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
        .frame(width: 1000, height: 700)
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
            if let note = noteContent {
                if isLoadingContent {
                    VStack(spacing: 16) {
                        ProgressView("加载内容...")
                        Text("正在加载笔记内容...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HistoryContentWebView(content: note.content)
                }
            } else {
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
    
    // MARK: - 辅助方法
    
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

