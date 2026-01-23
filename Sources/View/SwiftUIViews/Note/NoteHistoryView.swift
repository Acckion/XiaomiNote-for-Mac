import SwiftUI
import OSLog

/// 笔记历史记录视图
/// 
/// 显示笔记的历史记录列表，支持查看和恢复历史记录
@available(macOS 14.0, *)
struct NoteHistoryView: View {
    @ObservedObject var viewModel: NotesViewModel
    let noteId: String
    @Environment(\.dismiss) private var dismiss
    
    @State private var historyVersions: [NoteHistoryVersion] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var selectedVersion: NoteHistoryVersion?
    @State private var versionContent: Note?
    @State private var isLoadingContent: Bool = false
    @State private var isRestoring: Bool = false
    @State private var restoreError: String?
    
    // 日志记录器
    private let logger = Logger(subsystem: "com.xiaomi.minote.mac", category: "NoteHistoryView")
    
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
            // 主内容区域
            HSplitView {
                // 左侧：历史记录列表
                leftPanel
                    .frame(minWidth: 300, idealWidth: 350, maxWidth: 400)
                
                // 右侧：预览区域
                rightPanel
                    .frame(minWidth: 400)
            }
        }
        .alert("恢复历史记录", isPresented: .constant(isRestoring && restoreError == nil)) {
            Button("取消", role: .cancel) {
                isRestoring = false
            }
        } message: {
            Text("正在恢复历史记录...")
        }
        .alert("恢复失败", isPresented: .constant(restoreError != nil)) {
            Button("确定", role: .cancel) {
                restoreError = nil
            }
        } message: {
            if let error = restoreError {
                Text(error)
            }
        }
        .task {
            loadHistoryVersions()
        }
        .frame(minWidth: 800, idealWidth: 1000, maxWidth: 1200, minHeight: 500, idealHeight: 700, maxHeight: 800)
    }
    
    // MARK: - 左侧面板
    
    @ViewBuilder
    private var leftPanel: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView("加载历史记录...")
                    Text("正在加载...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text("加载失败")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("重试") {
                        loadHistoryVersions()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if historyVersions.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("暂无历史记录")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(historyVersions) { version in
                            HistoryVersionRow(
                                version: version,
                                isSelected: selectedVersion?.id == version.id,
                                onRestore: {
                                    restoreVersion(version)
                                }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedVersion = version
                            }
                            .background(
                                selectedVersion?.id == version.id
                                    ? Color.accentColor.opacity(0.1)
                                    : Color.clear
                            )
                        }
                    }
                }
            }
        }
        .onChange(of: selectedVersion) { oldValue, newValue in
            if let version = newValue {
                viewVersion(version)
            }
        }
    }
    
    // MARK: - 右侧面板
    
    @ViewBuilder
    private var rightPanel: some View {
        Group {
            if selectedVersion == nil {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("选择一个历史记录查看内容")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoadingContent {
                VStack(spacing: 16) {
                    ProgressView("加载内容...")
                    Text("正在加载版本内容...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let content = versionContent {
                VersionPreviewView(
                    version: selectedVersion,
                    note: content,
                    onRestore: {
                        if let version = selectedVersion {
                            restoreVersion(version)
                        }
                    }
                )
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
    }
    
    private func loadHistoryVersions() {
        logger.info("开始加载历史记录列表，noteId: \(self.noteId)")
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let versions = try await viewModel.getNoteHistoryTimes(noteId: noteId)
                await MainActor.run {
                    self.historyVersions = versions
                    self.isLoading = false
                    self.logger.info("成功加载历史记录列表，共 \(versions.count) 个版本")
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    self.logger.error("加载历史记录列表失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func viewVersion(_ version: NoteHistoryVersion) {
        logger.info("开始加载历史记录内容，version: \(version.version), noteId: \(self.noteId)")
        isLoadingContent = true
        versionContent = nil
        
        Task {
            do {
                let note = try await viewModel.getNoteHistory(noteId: noteId, version: version.version)
                await MainActor.run {
                    self.versionContent = note
                    self.isLoadingContent = false
                    self.logger.info("成功加载历史记录内容，标题: \(note.title), 内容长度: \(note.content.count) 字符")
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "加载版本内容失败: \(error.localizedDescription)"
                    self.isLoadingContent = false
                    self.logger.error("加载历史记录内容失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func restoreVersion(_ version: NoteHistoryVersion) {
        isRestoring = true
        restoreError = nil
        
        Task {
            do {
                try await viewModel.restoreNoteHistory(noteId: noteId, version: version.version)
                await MainActor.run {
                    isRestoring = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isRestoring = false
                    restoreError = error.localizedDescription
                }
            }
        }
    }
}

/// 历史记录行视图
@available(macOS 14.0, *)
private struct HistoryVersionRow: View {
    let version: NoteHistoryVersion
    let isSelected: Bool
    let onRestore: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(version.formattedUpdateTime)
                    .font(.headline)
                Text("版本: \(version.version)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                onRestore()
            } label: {
                Text("恢复")
            }
            .buttonStyle(.bordered)
            .help("恢复此版本")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }
}

/// 版本预览视图（右侧面板）
@available(macOS 14.0, *)
private struct VersionPreviewView: View {
    let version: NoteHistoryVersion?
    let note: Note
    let onRestore: () -> Void
    
    // 创建只读的编辑器上下文
    @StateObject private var editorContext: NativeEditorContext = {
        let context = NativeEditorContext()
        return context
    }()
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                if let version = version {
                    Text("版本时间: \(version.formattedUpdateTime)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button {
                    onRestore()
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("恢复此版本")
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .border(Color(NSColor.separatorColor), width: 0.5)
            
            // 内容区域 - 使用原生编辑器（只读模式）
            VStack(alignment: .leading, spacing: 0) {
                if !note.content.isEmpty {
                    NativeEditorView(
                        editorContext: editorContext,
                        isEditable: false  // 设置为只读
                    )
                    .opacity(0.9)  // 降低透明度表示只读
                    .onAppear {
                        // 加载内容到编辑器
                        loadContentToEditor()
                    }
                } else {
                    VStack {
                        Spacer()
                        Text("此版本暂无内容")
                            .font(.body)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
        }
    }
    
    /// 加载内容到编辑器
    private func loadContentToEditor() {
        Task { @MainActor in
            do {
                // 使用 XiaoMiFormatConverter 将 XML 转换为 NSAttributedString
                let attributedString = try XiaoMiFormatConverter.shared.xmlToNSAttributedString(
                    note.content,
                    folderId: note.folderId
                )
                
                // 设置到编辑器上下文
                editorContext.updateNSContent(attributedString)
            } catch {
                print("[VersionPreviewView] 加载内容失败: \(error.localizedDescription)")
                // 如果转换失败，显示纯文本
                let plainText = note.content
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">")
                editorContext.updateNSContent(NSAttributedString(string: plainText))
            }
        }
    }
}

