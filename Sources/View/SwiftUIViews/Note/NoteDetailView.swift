import AppKit
import Combine
import SwiftUI

/// 笔记详情视图
@available(macOS 14.0, *)
struct NoteDetailView: View {
    /// 应用协调器（共享数据层）
    let coordinator: AppCoordinator

    /// 窗口状态（窗口独立状态）
    @ObservedObject var windowState: WindowState

    /// State 对象引用（从 coordinator 获取）
    @ObservedObject private var noteListState: NoteListState
    @ObservedObject private var noteEditorState: NoteEditorState
    @ObservedObject private var folderState: FolderState
    @ObservedObject private var authState: AuthState

    /// 编辑会话协调器
    @StateObject private var editingCoordinator = NoteEditingCoordinator()

    // MARK: - 调试模式状态

    @State private var isDebugMode = false
    @State private var debugXMLContent = ""
    @State private var debugSaveStatus: DebugSaveStatus = .saved

    // MARK: - UI 状态

    @State private var showSaveErrorAlert = false
    @State private var saveErrorMessage = ""
    @State private var isEditable = true
    @State private var showImageInsertAlert = false
    @State private var imageInsertMessage = ""
    @State private var isInsertingImage = false
    @State private var imageInsertStatus: ImageInsertStatus = .idle
    @State private var showingHistoryView = false
    @State private var showTrashView = false

    enum ImageInsertStatus {
        case idle, uploading, success, failed
    }

    /// 编辑器偏好设置服务
    @ObservedObject private var editorPreferencesService = EditorPreferencesService.shared

    /// 当前是否使用原生编辑器
    private var isUsingNativeEditor: Bool {
        editorPreferencesService.isNativeEditorAvailable
    }

    // MARK: - 初始化

    init(coordinator: AppCoordinator, windowState: WindowState) {
        self.coordinator = coordinator
        self._windowState = ObservedObject(wrappedValue: windowState)
        self._noteListState = ObservedObject(wrappedValue: coordinator.noteListState)
        self._noteEditorState = ObservedObject(wrappedValue: coordinator.noteEditorState)
        self._folderState = ObservedObject(wrappedValue: coordinator.folderState)
        self._authState = ObservedObject(wrappedValue: coordinator.authState)
    }

    var body: some View {
        mainContentView
            .onChange(of: windowState.selectedNote) { oldValue, newValue in
                handleSelectedNoteChange(oldValue: oldValue, newValue: newValue)
            }
            .onAppear {
                editingCoordinator.configure(noteEditorState: noteEditorState, noteStore: coordinator.noteStore)
                registerSaveCallback()
            }
            .onDisappear {
                noteEditorState.saveContentCallback = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleDebugMode)) { _ in
                toggleDebugMode()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nativeEditorSaveStatusDidChange)) { notification in
                handleNativeEditorSaveStatusChange(notification)
            }
            .navigationTitle("详情")
            .toolbar {
                toolbarContent
            }
    }

    // MARK: - 事件处理

    private func handleNativeEditorSaveStatusChange(_ notification: Notification) {
        guard isUsingNativeEditor, !isDebugMode else { return }
        guard let userInfo = notification.userInfo,
              let needsSave = userInfo["needsSave"] as? Bool
        else { return }

        if needsSave {
            if case .saving = editingCoordinator.saveStatus {
                // 保持 saving 状态
            }
        }
    }

    private func registerSaveCallback() {
        noteEditorState.saveContentCallback = { [editingCoordinator] in
            await editingCoordinator.saveForFolderSwitch()
        }
    }

    private func handleSelectedNoteChange(oldValue: Note?, newValue: Note?) {
        guard let newNote = newValue else { return }
        if oldValue?.id != newNote.id {
            let task = editingCoordinator.saveBeforeSwitching(newNoteId: newNote.id)
            Task { @MainActor in
                if let t = task { await t.value }
                await editingCoordinator.switchToNote(newNote)
                if isDebugMode {
                    debugXMLContent = editingCoordinator.currentXMLContent
                    debugSaveStatus = .saved
                }
            }
        }
    }

    // MARK: - 主内容视图

    @ViewBuilder
    private var mainContentView: some View {
        if let folder = folderState.selectedFolder, folder.id == "2", !authState.isPrivateNotesUnlocked {
            PrivateNotesVerificationView(authState: authState)
        } else if let note = windowState.selectedNote {
            noteEditorView(for: note)
        } else {
            emptyNoteView
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        NoteEditorToolbar(
            noteListState: noteListState,
            noteEditorState: noteEditorState,
            nativeEditorContext: noteEditorState.nativeEditorContext,
            isUsingNativeEditor: isUsingNativeEditor,
            isDebugMode: isDebugMode,
            selectedNote: windowState.selectedNote,
            onToggleDebugMode: { toggleDebugMode() },
            onInsertImage: { insertImage() },
            showingHistoryView: $showingHistoryView,
            showTrashView: $showTrashView
        )
    }

    private func noteEditorView(for note: Note) -> some View {
        ZStack {
            Color(nsColor: NSColor.textBackgroundColor).ignoresSafeArea()
            editorContentView(for: note)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    FloatingInfoBar(
                        note: note,
                        currentXMLContent: editingCoordinator.currentXMLContent,
                        isDebugMode: isDebugMode,
                        saveStatus: isDebugMode ? .debug(debugSaveStatus) : .normal(editingCoordinator.saveStatus),
                        showSaveErrorAlert: $showSaveErrorAlert,
                        saveErrorMessage: $saveErrorMessage,
                        onRetrySave: { editingCoordinator.retrySave() }
                    )
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .onAppear {
            if editingCoordinator.currentEditingNoteId != note.id {
                Task { @MainActor in
                    await editingCoordinator.switchToNote(note)
                    if isDebugMode {
                        debugXMLContent = editingCoordinator.currentXMLContent
                        debugSaveStatus = .saved
                    }
                }
            }
        }
        .onReceive(noteEditorState.nativeEditorContext.titleChangePublisher) { newValue in
            if editingCoordinator.editedTitle != newValue {
                editingCoordinator.editedTitle = newValue
            }
        }
        .onChange(of: editingCoordinator.editedTitle) { _, newValue in
            if noteEditorState.nativeEditorContext.titleText != newValue {
                noteEditorState.nativeEditorContext.titleText = newValue
            }
            Task { @MainActor in await editingCoordinator.handleTitleChange(newValue) }
        }
        .sheet(isPresented: $showImageInsertAlert) {
            ImageInsertStatusView(
                isInserting: isInsertingImage,
                message: imageInsertMessage,
                status: imageInsertStatus,
                onDismiss: { imageInsertStatus = .idle }
            )
        }
        .sheet(isPresented: $showingHistoryView) {
            NoteHistoryView(noteEditorState: noteEditorState, noteId: note.id)
        }
        .alert("保存失败", isPresented: $showSaveErrorAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
    }

    private func editorContentView(for _: Note) -> some View {
        bodyEditorView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .top)
    }

    private func hasRealTitle() -> Bool {
        guard let note = windowState.selectedNote else { return false }
        return !note.title.isEmpty && !note.title.hasPrefix("未命名笔记_")
    }

    // MARK: - 编辑器视图

    private var bodyEditorView: some View {
        Group {
            if editingCoordinator.isInitializing {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("加载中...")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if windowState.selectedNote != nil {
                if isDebugMode {
                    XMLDebugEditorView(
                        xmlContent: $debugXMLContent,
                        isEditable: $isEditable,
                        saveStatus: $debugSaveStatus,
                        onSave: {
                            Task { @MainActor in
                                await saveDebugContent()
                            }
                        },
                        onContentChange: { newContent in
                            handleDebugContentChange(newContent)
                        }
                    )
                } else {
                    UnifiedEditorWrapper(
                        content: $editingCoordinator.currentXMLContent,
                        isEditable: $isEditable,
                        nativeEditorContext: noteEditorState.nativeEditorContext,
                        xmlContent: editingCoordinator.currentXMLContent,
                        folderId: windowState.selectedNote?.folderId ?? "",
                        onContentChange: { newXML, newHTML in
                            guard !editingCoordinator.isInitializing else { return }
                            guard let currentNote = windowState.selectedNote,
                                  currentNote.id == editingCoordinator.currentEditingNoteId
                            else { return }

                            Task { @MainActor in
                                await editingCoordinator.handleContentChange(xmlContent: newXML, htmlContent: newHTML)
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - 调试模式

    private func toggleDebugMode() {
        if isDebugMode {
            if debugXMLContent != editingCoordinator.currentXMLContent {
                editingCoordinator.currentXMLContent = debugXMLContent
                if let note = windowState.selectedNote {
                    editingCoordinator.scheduleXMLSave(xmlContent: debugXMLContent, for: note, immediate: false)
                }
            }
            isDebugMode = false
        } else {
            if let note = windowState.selectedNote {
                debugXMLContent = editingCoordinator.currentXMLContent.isEmpty ? note.primaryXMLContent : editingCoordinator.currentXMLContent
            }
            debugSaveStatus = .saved
            isDebugMode = true
        }
    }

    private func handleDebugContentChange(_: String) {
        guard !editingCoordinator.isInitializing else { return }
        if debugSaveStatus != .saving {
            debugSaveStatus = .unsaved
        }
    }

    @MainActor
    private func saveDebugContent() async {
        guard let note = windowState.selectedNote, note.id == editingCoordinator.currentEditingNoteId else {
            debugSaveStatus = .error("无法保存：未选择笔记")
            return
        }

        let hasChanges = debugXMLContent != editingCoordinator.lastSavedXMLContent || editingCoordinator.editedTitle != editingCoordinator
            .originalTitle
        guard hasChanges else {
            debugSaveStatus = .saved
            return
        }

        debugSaveStatus = .saving
        editingCoordinator.currentXMLContent = debugXMLContent

        let updated = editingCoordinator.buildUpdatedNote(from: note, xmlContent: debugXMLContent)

        do {
            try await saveDebugContentToDatabase(updated)

            debugSaveStatus = .saved
            editingCoordinator.lastSavedXMLContent = debugXMLContent

            await MemoryCacheManager.shared.cacheNote(updated)
            editingCoordinator.updateViewModel(with: updated)
            noteEditorState.hasUnsavedContent = false
            editingCoordinator.scheduleCloudUpload(for: updated, xmlContent: debugXMLContent)
        } catch {
            let errorMessage = "保存失败: \(error.localizedDescription)"
            debugSaveStatus = .error(errorMessage)
            LogService.shared.error(.editor, "调试模式保存失败: \(error)")
        }
    }

    @MainActor
    private func saveDebugContentToDatabase(_ note: Note) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DatabaseService.shared.saveNoteAsync(note) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - 图片插入

    private func insertImage() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.image, .png, .jpeg, .gif]
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                Task { @MainActor in await insertImage(from: url) }
            }
        }
    }

    @MainActor
    private func insertImage(from url: URL) async {
        guard windowState.selectedNote != nil else { return }
        isInsertingImage = true
        imageInsertStatus = .uploading
        imageInsertMessage = "正在上传图片..."
        showImageInsertAlert = true
        do {
            let fileId = try await noteEditorState.uploadImageAndInsertToNote(imageURL: url)

            if isUsingNativeEditor {
                noteEditorState.nativeEditorContext.insertImage(fileId: fileId, src: "minote://image/\(fileId)")
            }

            imageInsertStatus = .success
            imageInsertMessage = "图片插入成功"
            isInsertingImage = false
            await editingCoordinator.performSaveImmediately()
        } catch {
            imageInsertStatus = .failed
            imageInsertMessage = "插入失败"
            isInsertingImage = false
        }
    }

    // MARK: - 空视图

    private var emptyNoteView: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text").font(.system(size: 48)).foregroundColor(.secondary)
            Text("选择笔记或创建新笔记").font(.title2).foregroundColor(.secondary)
            Button(action: {
                Task { await noteListState.createNewNote(inFolder: folderState.selectedFolder?.id ?? "0") }
            }) {
                Label("新建笔记", systemImage: "plus")
            }.buttonStyle(.borderedProminent)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 图片插入状态视图

@available(macOS 14.0, *)
struct ImageInsertStatusView: View {
    let isInserting: Bool
    let message: String
    let status: NoteDetailView.ImageInsertStatus
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 20) {
            if isInserting { ProgressView().scaleEffect(1.2) } else {
                Image(systemName: status == .success ? "checkmark.circle.fill" : "xmark.circle.fill").font(.system(size: 48))
                    .foregroundColor(status == .success ? .green : .red)
            }
            Text(isInserting ? "正在插入图片" : (status == .success ? "插入成功" : "插入失败")).font(.headline)
            Text(message).font(.body).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            if !isInserting { Button("确定") { onDismiss()
                dismiss()
            }.buttonStyle(.borderedProminent) }
        }.padding(30).frame(width: 400)
    }
}

// MARK: - 格式菜单弹出内容视图

@available(macOS 14.0, *)
struct FormatMenuPopoverContent: View {
    @ObservedObject var nativeEditorContext: NativeEditorContext
    let onDismiss: () -> Void

    var body: some View {
        NativeFormatMenuView(context: nativeEditorContext) { _ in onDismiss() }
            .onAppear {
                nativeEditorContext.requestContentSync()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    nativeEditorContext.forceUpdateFormats()
                }
            }
    }
}
