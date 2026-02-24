//
//  NoteEditingCoordinator.swift
//  MiNoteMac
//
//  编辑会话协调器
//  统一管理笔记的加载、保存、缓存更新和云端同步调度
//

import AppKit
import Combine
import Foundation

/// 编辑会话协调器
///
/// 作为笔记编辑的唯一管理者，统一保存路径，消除双重保存竞态
@MainActor
public final class NoteEditingCoordinator: ObservableObject {

    // MARK: - 保存状态枚举

    public enum SaveStatus: Equatable {
        case saved
        case saving
        case unsaved
        case error(String)

        public static func == (lhs: SaveStatus, rhs: SaveStatus) -> Bool {
            switch (lhs, rhs) {
            case (.saved, .saved), (.saving, .saving), (.unsaved, .unsaved):
                true
            case let (.error(lhsMsg), .error(rhsMsg)):
                lhsMsg == rhsMsg
            default:
                false
            }
        }
    }

    // MARK: - Published 属性（驱动 UI）

    @Published public private(set) var currentEditingNoteId: String?
    @Published public var editedTitle = ""
    @Published public var currentXMLContent = ""
    @Published public private(set) var saveStatus: SaveStatus = .saved
    @Published public private(set) var isInitializing = true

    // MARK: - 内部状态

    var originalTitle = ""
    var originalXMLContent = ""
    var lastSavedXMLContent = ""

    // 保存任务跟踪
    var xmlSaveDebounceTask: Task<Void, Never>?
    var xmlSaveTask: Task<Void, Never>?
    var cloudUploadTask: Task<Void, Never>?

    /// 每个笔记的最后上传内容
    var lastUploadedContentByNoteId: [String: String] = [:]
    /// 每个笔记的最后上传标题
    var lastUploadedTitleByNoteId: [String: String] = [:]

    // 保存重试
    var pendingRetryXMLContent: String?
    var pendingRetryNote: Note?

    // 超时配置（从 SavePipelineCoordinator 吸收）
    let saveTimeout: TimeInterval = 30.0
    private var saveStartTime: Date?
    private var isCancelled = false

    /// XML 保存防抖延迟
    let xmlSaveDebounceDelay: UInt64 = 300_000_000 // 300ms

    // 本地保存锁
    var isSavingLocally = false
    var isSavingBeforeSwitch = false

    // MARK: - 依赖

    private let eventBus = EventBus.shared
    private let apiClient: APIClient
    private(set) weak var noteEditorState: NoteEditorState?
    private var noteStore: NoteStore?
    var nativeEditorContext: NativeEditorContext? {
        noteEditorState?.nativeEditorContext
    }

    // MARK: - 初始化

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    /// 配置依赖
    func configure(noteEditorState: NoteEditorState, noteStore: NoteStore) {
        self.noteEditorState = noteEditorState
        self.noteStore = noteStore

        // 设置 ID 迁移回调
        noteEditorState.onIdMigrated = { [weak self] oldId, newId, note in
            self?.handleIdMigration(oldId: oldId, newId: newId, note: note)
        }
    }

    // MARK: - ID 迁移处理

    /// 处理笔记 ID 迁移（临时 ID -> 正式 ID）
    public func handleIdMigration(oldId: String, newId: String, note _: Note) {
        guard currentEditingNoteId == oldId else { return }

        LogService.shared.info(.editor, "NoteEditingCoordinator ID 迁移: \(oldId.prefix(8))... -> \(newId.prefix(8))...")

        currentEditingNoteId = newId

        // 迁移内存缓存中的引用
        if let oldContent = lastUploadedContentByNoteId.removeValue(forKey: oldId) {
            lastUploadedContentByNoteId[newId] = oldContent
        }
        if let oldTitle = lastUploadedTitleByNoteId.removeValue(forKey: oldId) {
            lastUploadedTitleByNoteId[newId] = oldTitle
        }
    }

    // MARK: - 核心方法（保存）

    /// 处理编辑器内容变化（统一入口）
    public func handleContentChange(xmlContent: String) async {
        guard !isInitializing else {
            LogService.shared.debug(.editor, "handleContentChange 跳过 - isInitializing=true")
            return
        }
        guard let currentNote = noteEditorState?.currentNote,
              currentNote.id == currentEditingNoteId
        else {
            LogService.shared.warning(
                .editor,
                "handleContentChange 跳过 - currentNote: \(noteEditorState?.currentNote?.id.prefix(8) ?? "nil"), editingNoteId: \(currentEditingNoteId?.prefix(8) ?? "nil")"
            )
            return
        }

        // 标题直接从 nativeEditorContext.titleText 获取
        if let context = nativeEditorContext {
            let titleFromEditor = context.titleText
            if !titleFromEditor.isEmpty {
                editedTitle = titleFromEditor
            }
        }

        currentXMLContent = xmlContent

        // [Tier 0] 立即更新内存缓存
        await updateMemoryCache(xmlContent: xmlContent, for: currentNote)

        // [Tier 2] 异步保存 XML（防抖 300ms）
        scheduleXMLSave(xmlContent: xmlContent, for: currentNote, immediate: false)

        // [Tier 3] 计划同步云端（延迟 3s）
        scheduleCloudUpload(for: currentNote, xmlContent: xmlContent)
    }

    /// 处理标题变化
    public func handleTitleChange(_ newTitle: String) async {
        guard !isInitializing, newTitle != originalTitle else { return }
        await performTitleChangeSave(newTitle: newTitle)
    }

    /// 切换笔记前保存当前内容
    @discardableResult
    public func saveBeforeSwitching(newNoteId: String) -> Task<Void, Never>? {
        guard let currentId = currentEditingNoteId, currentId != newNoteId else {
            return nil
        }
        guard let currentNote = noteEditorState?.currentNote, currentNote.id == currentId else {
            return nil
        }

        let capturedTitle = editedTitle
        let capturedOriginalTitle = originalTitle
        let capturedLastSavedXMLContent = lastSavedXMLContent

        var capturedContent = ""
        if let context = nativeEditorContext {
            capturedContent = context.exportToXML()
            if capturedContent.isEmpty, !currentXMLContent.isEmpty {
                capturedContent = currentXMLContent
            }
        }

        isSavingBeforeSwitch = true

        return Task { @MainActor in
            defer { isSavingBeforeSwitch = false }

            let content = capturedContent
            let hasActualChange = hasContentActuallyChanged(
                currentContent: content,
                savedContent: capturedLastSavedXMLContent,
                currentTitle: capturedTitle,
                originalTitle: capturedOriginalTitle
            )

            if hasActualChange {
                let updated = buildUpdatedNote(from: currentNote, xmlContent: content, shouldUpdateTimestamp: false)
                await MemoryCacheManager.shared.cacheNote(updated)
                updateNotesArrayOnly(with: updated)

                await eventBus.publish(NoteEvent.contentUpdated(noteId: currentNote.id, title: capturedTitle, content: content))
                scheduleCloudUpload(for: updated, xmlContent: content)
            }
        }
    }

    /// 文件夹切换前保存
    public func saveForFolderSwitch() async -> Bool {
        guard let note = noteEditorState?.currentNote, note.id == currentEditingNoteId else {
            return true
        }

        let capturedTitle = editedTitle
        let capturedOriginalTitle = originalTitle
        let capturedLastSavedXMLContent = lastSavedXMLContent
        let capturedNote = note

        var capturedContent = ""
        if let context = nativeEditorContext {
            capturedContent = context.exportToXML()
            if capturedContent.isEmpty, !currentXMLContent.isEmpty {
                capturedContent = currentXMLContent
            }
        }

        // 后台异步保存，不阻塞界面切换
        Task { @MainActor in
            let content = capturedContent
            let hasContentChange = content != capturedLastSavedXMLContent
            let hasTitleChange = capturedTitle != capturedOriginalTitle

            guard hasContentChange || hasTitleChange else { return }

            // 文件夹切换时不更新时间戳，避免触发列表重排
            let updated = Note(
                id: capturedNote.id,
                title: capturedTitle,
                content: content,
                folderId: capturedNote.folderId,
                isStarred: capturedNote.isStarred,
                createdAt: capturedNote.createdAt,
                updatedAt: capturedNote.updatedAt,
                tags: capturedNote.tags,
                snippet: capturedNote.snippet,
                colorId: capturedNote.colorId,
                type: capturedNote.type,
                serverTag: capturedNote.serverTag,
                status: capturedNote.status,
                settingJson: capturedNote.settingJson,
                extraInfoJson: capturedNote.extraInfoJson
            )

            await MemoryCacheManager.shared.cacheNote(updated)
            updateNotesArrayOnly(with: updated)

            await eventBus.publish(NoteEvent.contentUpdated(noteId: capturedNote.id, title: capturedTitle, content: content))
            scheduleCloudUpload(for: updated, xmlContent: content)
        }

        return true
    }

    /// 取消保存
    public func cancelSave() {
        isCancelled = true
        xmlSaveDebounceTask?.cancel()
        xmlSaveTask?.cancel()
        cloudUploadTask?.cancel()
    }

    /// 重试保存
    public func retrySave() {
        guard let xmlContent = pendingRetryXMLContent,
              let note = pendingRetryNote ?? noteEditorState?.currentNote
        else { return }

        var contentToSave = xmlContent
        if let context = nativeEditorContext {
            let backupContent = context.getContentForRetry()
            if backupContent.length > 0 {
                contentToSave = XiaoMiFormatConverter.shared.safeNSAttributedStringToXML(backupContent)
            }
        }

        performXMLSave(xmlContent: contentToSave, for: note)
    }

    // MARK: - 核心方法（加载）

    /// 切换到新笔记（统一入口）
    public func switchToNote(_ note: Note) async {
        // 竞态防护：如果传入的是临时 ID 但 ID 迁移已完成，使用正式 ID 笔记
        var resolvedNote = note
        if NoteOperation.isTemporaryId(note.id) {
            let resolvedId = IdMappingRegistry.shared.resolveId(note.id)
            if resolvedId != note.id {
                if let officialNote = await noteStore?.getNote(byId: resolvedId) {
                    resolvedNote = officialNote
                } else if let dbNote = try? LocalStorageService.shared.loadNote(noteId: resolvedId) {
                    resolvedNote = dbNote
                }
                if resolvedNote.id != note.id {
                    LogService.shared.info(.editor, "switchToNote 临时 ID 已迁移: \(note.id.prefix(8))... -> \(resolvedId.prefix(8))...")
                }
            }
        }

        LogService.shared.debug(
            .editor,
            "switchToNote 开始 - 笔记ID: \(resolvedNote.id.prefix(8))..., noteEditorState.currentNote: \(noteEditorState?.currentNote?.id.prefix(8) ?? "nil")"
        )

        currentEditingNoteId = resolvedNote.id
        isInitializing = true
        saveStatus = .saved

        // 同步更新 NoteEditorState.currentNote，确保 handleContentChange 的 guard 能通过
        noteEditorState?.loadNote(resolvedNote)

        let title = resolvedNote.title.isEmpty || resolvedNote.title.hasPrefix("未命名笔记_") ? "" : resolvedNote.title
        editedTitle = title
        originalTitle = title

        xmlSaveTask?.cancel()
        xmlSaveDebounceTask?.cancel()
        xmlSaveTask = nil
        xmlSaveDebounceTask = nil

        currentXMLContent = ""
        lastSavedXMLContent = ""
        originalXMLContent = ""

        let cachedNote = await MemoryCacheManager.shared.getNote(noteId: resolvedNote.id)
        if let cachedNote, cachedNote.id == resolvedNote.id {
            await loadNoteContentFromCache(cachedNote)
            return
        }

        await loadNoteContent(resolvedNote)
    }

    // MARK: - 内部方法（保存）

    func updateMemoryCache(xmlContent: String, for note: Note) async {
        guard note.id == currentEditingNoteId else { return }

        let titleToUse: String = if note.id == currentEditingNoteId {
            editedTitle
        } else {
            note.title
        }

        let updated = Note(
            id: note.id,
            title: titleToUse,
            content: xmlContent,
            folderId: note.folderId,
            isStarred: note.isStarred,
            createdAt: note.createdAt,
            updatedAt: Date(),
            tags: note.tags,
            snippet: note.snippet,
            colorId: note.colorId,
            type: note.type,
            serverTag: note.serverTag,
            status: note.status,
            settingJson: note.settingJson,
            extraInfoJson: note.extraInfoJson
        )

        await MemoryCacheManager.shared.cacheNote(updated)
        updateNotesArrayOnly(with: updated)

        if case .saving = saveStatus {
            // 保持 saving 状态
        } else {
            saveStatus = .unsaved
        }

        noteEditorState?.hasUnsavedContent = true
    }

    func scheduleXMLSave(xmlContent: String, for note: Note, immediate: Bool = false) {
        guard note.id == currentEditingNoteId else { return }

        xmlSaveDebounceTask?.cancel()
        let noteId = note.id

        if immediate {
            let hasActualChange = hasContentActuallyChanged(
                currentContent: xmlContent,
                savedContent: lastSavedXMLContent,
                currentTitle: editedTitle,
                originalTitle: originalTitle
            )
            guard hasActualChange else {
                if case .unsaved = saveStatus {
                    saveStatus = .saved
                }
                return
            }
            performXMLSave(xmlContent: xmlContent, for: note)
        } else {
            if case .saved = saveStatus {
                saveStatus = .unsaved
            }

            xmlSaveDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: xmlSaveDebounceDelay)
                guard !Task.isCancelled, currentEditingNoteId == noteId else { return }

                var latestXMLContent = xmlContent
                if let context = nativeEditorContext {
                    let exportedXML = context.exportToXML()
                    if !exportedXML.isEmpty {
                        latestXMLContent = exportedXML
                    }
                }

                let hasActualChange = hasContentActuallyChanged(
                    currentContent: latestXMLContent,
                    savedContent: lastSavedXMLContent,
                    currentTitle: editedTitle,
                    originalTitle: originalTitle
                )
                guard hasActualChange else {
                    saveStatus = .saved
                    return
                }

                performXMLSave(xmlContent: latestXMLContent, for: note)
            }
        }
    }

    /// 执行 XML 保存（通过 EventBus 发布事件，由 NoteStore 统一处理 DB 写入）
    func performXMLSave(xmlContent: String, for note: Note) {
        xmlSaveTask?.cancel()
        let noteId = note.id

        LogService.shared.debug(.editor, "performXMLSave 开始 - 笔记ID: \(noteId.prefix(8))..., 内容长度: \(xmlContent.count)")

        saveStatus = .saving
        saveStartTime = Date()
        isCancelled = false

        if let context = nativeEditorContext {
            context.backupCurrentContent()
        }

        xmlSaveTask = Task { @MainActor in
            guard !Task.isCancelled, currentEditingNoteId == noteId else { return }

            // 超时检查
            if let startTime = saveStartTime,
               Date().timeIntervalSince(startTime) > saveTimeout
            {
                LogService.shared.error(.editor, "保存超时（\(saveTimeout)秒）")
                await handleSaveFailure(
                    error: NSError(
                        domain: "NoteEditingCoordinator",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "保存超时"]
                    ),
                    xmlContent: xmlContent, note: note
                )
                return
            }

            guard !isCancelled else {
                LogService.shared.info(.editor, "保存已取消")
                return
            }

            let updated = buildUpdatedNote(from: note, xmlContent: xmlContent)
            await eventBus.publish(NoteEvent.contentUpdated(noteId: note.id, title: editedTitle, content: xmlContent))
            await handleSaveSuccess(xmlContent: xmlContent, noteId: noteId, updatedNote: updated)
        }
    }

    func handleSaveSuccess(xmlContent: String, noteId: String, updatedNote: Note) async {
        // 保存完成后检查：如果任务已取消或已切换到其他笔记，丢弃结果
        guard !Task.isCancelled, currentEditingNoteId == noteId else { return }

        LogService.shared.debug(.editor, "handleSaveSuccess(Path A) - 笔记ID: \(noteId.prefix(8))...")

        lastSavedXMLContent = xmlContent
        currentXMLContent = xmlContent

        pendingRetryXMLContent = nil
        pendingRetryNote = nil

        updateViewModel(with: updatedNote)
        await MemoryCacheManager.shared.cacheNote(updatedNote)

        saveStatus = .saved
        noteEditorState?.hasUnsavedContent = false

        if let context = nativeEditorContext {
            context.markContentSaved()
        }
    }

    func handleSaveFailure(error: Error, xmlContent: String, note: Note) async {
        let errorMessage = "保存笔记失败: \(error.localizedDescription)"
        saveStatus = .error(errorMessage)
        LogService.shared.error(.editor, "保存失败: \(error)")

        if let context = nativeEditorContext {
            context.markSaveFailed(error: errorMessage)
        }
        pendingRetryXMLContent = xmlContent
        pendingRetryNote = note
    }

    func performTitleChangeSave(newTitle: String) async {
        guard let note = noteEditorState?.currentNote, note.id == currentEditingNoteId else { return }
        if isSavingLocally {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if isSavingLocally { return }
        }
        isSavingLocally = true
        defer { isSavingLocally = false }

        let xmlContent = currentXMLContent.isEmpty ? note.primaryXMLContent : currentXMLContent
        let original = note.primaryXMLContent

        // 内容丢失保护
        if original.count > 300, xmlContent.count < 150, xmlContent.count < original.count / 2 {
            LogService.shared.warning(.editor, "内容丢失保护触发 - 笔记ID: \(note.id.prefix(8))...")
            await saveTitleAndContent(title: newTitle, xmlContent: original, for: note)
        } else {
            await saveTitleAndContent(title: newTitle, xmlContent: xmlContent, for: note)
        }
    }

    func saveTitleAndContent(title: String, xmlContent: String, for note: Note) async {
        let hasActualChange = hasContentActuallyChanged(
            currentContent: xmlContent,
            savedContent: lastSavedXMLContent,
            currentTitle: title,
            originalTitle: originalTitle
        )
        let shouldUpdateTimestamp = hasActualChange

        let previousEditedTitle = editedTitle
        editedTitle = title
        let updated = buildUpdatedNote(from: note, xmlContent: xmlContent, shouldUpdateTimestamp: shouldUpdateTimestamp)
        editedTitle = previousEditedTitle

        await eventBus.publish(NoteEvent.contentUpdated(noteId: note.id, title: title, content: xmlContent))

        lastSavedXMLContent = xmlContent
        originalTitle = title
        currentXMLContent = xmlContent
        updateViewModel(with: updated)
        await MemoryCacheManager.shared.cacheNote(updated)
        scheduleCloudUpload(for: updated, xmlContent: xmlContent)
    }

    func performSaveImmediately() async {
        guard let note = noteEditorState?.currentNote else { return }
        let content = await getLatestContentFromEditor()
        scheduleXMLSave(xmlContent: content, for: note, immediate: true)
        await xmlSaveTask?.value
        scheduleCloudUpload(for: note, xmlContent: content)
    }

    // MARK: - 内部方法（加载）

    func loadNoteContent(_ note: Note) async {
        guard note.id == currentEditingNoteId else { return }

        isInitializing = true

        xmlSaveTask?.cancel()
        xmlSaveDebounceTask?.cancel()
        xmlSaveTask = nil
        xmlSaveDebounceTask = nil

        let title = note.title.isEmpty || note.title.hasPrefix("未命名笔记_") ? "" : note.title
        if editedTitle != title {
            editedTitle = title
            originalTitle = title
        }

        var contentToLoad = note.primaryXMLContent

        if note.content.isEmpty {
            // 优先从 NoteStore 内存缓存获取
            if let cachedNote = await noteStore?.getNote(byId: note.id), !cachedNote.content.isEmpty {
                guard note.id == currentEditingNoteId else { return }
                contentToLoad = cachedNote.primaryXMLContent
                await MemoryCacheManager.shared.cacheNote(cachedNote)
            } else if let fullNote = try? LocalStorageService.shared.loadNote(noteId: note.id) {
                // NoteStore 缓存也没有完整内容，回退到直接读 DB
                guard note.id == currentEditingNoteId else { return }
                contentToLoad = fullNote.primaryXMLContent
                await MemoryCacheManager.shared.cacheNote(fullNote)
            }
        } else {
            await MemoryCacheManager.shared.cacheNote(note)
        }

        currentXMLContent = contentToLoad
        lastSavedXMLContent = currentXMLContent
        originalXMLContent = currentXMLContent

        try? await Task.sleep(nanoseconds: 100_000_000)
        guard note.id == currentEditingNoteId else { return }

        isInitializing = false
    }

    func loadNoteContentFromCache(_ note: Note) async {
        guard note.id == currentEditingNoteId else { return }

        let title = note.title.isEmpty || note.title.hasPrefix("未命名笔记_") ? "" : note.title
        if editedTitle != title {
            editedTitle = title
            originalTitle = title
        }

        let contentToLoad = note.primaryXMLContent
        currentXMLContent = contentToLoad
        lastSavedXMLContent = currentXMLContent
        originalXMLContent = currentXMLContent

        await verifyAudioAttachmentPersistence(note: note)

        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        guard note.id == currentEditingNoteId else { return }

        isInitializing = false
    }

    func loadFullContentAsync(for note: Note) async {
        if note.content.isEmpty {
            // 优先从 NoteStore 内存缓存获取
            if let cachedNote = await noteStore?.getNote(byId: note.id), !cachedNote.content.isEmpty {
                await MemoryCacheManager.shared.cacheNote(cachedNote)
                currentXMLContent = cachedNote.primaryXMLContent
                lastSavedXMLContent = currentXMLContent
                originalXMLContent = currentXMLContent
            } else if let fullNote = try? LocalStorageService.shared.loadNote(noteId: note.id) {
                // NoteStore 缓存也没有完整内容，回退到直接读 DB
                await MemoryCacheManager.shared.cacheNote(fullNote)
                currentXMLContent = fullNote.primaryXMLContent
                lastSavedXMLContent = currentXMLContent
                originalXMLContent = currentXMLContent
            }
        } else {
            await MemoryCacheManager.shared.cacheNote(note)
        }
    }

    func verifyAudioAttachmentPersistence(note: Note) async {
        let contentToVerify = currentXMLContent.isEmpty ? note.primaryXMLContent : currentXMLContent

        let hasAudioAttachments = contentToVerify.contains("<sound fileid=")
        let hasTemporaryTemplates = contentToVerify.contains("des=\"temp\"")

        if hasAudioAttachments, hasTemporaryTemplates {
            LogService.shared.warning(.editor, "发现临时录音模板未更新 - 笔记ID: \(note.id.prefix(8))...")
        }

        if let context = nativeEditorContext {
            let isValid = await context.verifyContentPersistence(expectedContent: contentToVerify)
            if !isValid {
                LogService.shared.warning(.editor, "原生编辑器内容持久化验证失败 - 笔记ID: \(note.id.prefix(8))...")
            }
        }
    }

    // MARK: - 内部方法（云端同步）

    func scheduleCloudUpload(for note: Note, xmlContent: String) {
        Task {
            let isAuth = await apiClient.isAuthenticated()
            let hasCookie = apiClient.hasValidCookie()
            guard isAuth, hasCookie else {
                queueOfflineUpdateOperation(for: note, xmlContent: xmlContent)
                return
            }

            let lastUploadedForThisNote = lastUploadedContentByNoteId[note.id] ?? ""
            let lastUploadedTitle = lastUploadedTitleByNoteId[note.id] ?? ""
            let currentTitle = editedTitle.isEmpty ? note.title : editedTitle
            guard xmlContent != lastUploadedForThisNote || currentTitle != lastUploadedTitle else {
                return
            }

            cloudUploadTask?.cancel()
            let noteId = note.id

            cloudUploadTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled, currentEditingNoteId == noteId else { return }

                let latestXMLContent = currentXMLContent.isEmpty ? xmlContent : currentXMLContent
                let latestTitle = editedTitle.isEmpty ? note.title : editedTitle

                let lastUploaded = lastUploadedContentByNoteId[noteId] ?? ""
                let lastTitle = lastUploadedTitleByNoteId[noteId] ?? ""
                guard latestXMLContent != lastUploaded || latestTitle != lastTitle else { return }

                let isAuth2 = await apiClient.isAuthenticated()
                let hasCookie2 = apiClient.hasValidCookie()
                guard isAuth2, hasCookie2 else {
                    queueOfflineUpdateOperation(for: note, xmlContent: latestXMLContent)
                    return
                }

                await performCloudUpload(for: note, xmlContent: latestXMLContent)
                lastUploadedContentByNoteId[noteId] = latestXMLContent
                lastUploadedTitleByNoteId[noteId] = latestTitle
            }
        }
    }

    func performCloudUpload(for note: Note, xmlContent: String) async {
        queueOfflineUpdateOperation(for: note, xmlContent: xmlContent)

        // 入队后立即触发处理
        if let operation = UnifiedOperationQueue.shared.getPendingUpload(for: note.id) {
            await OperationProcessor.shared.processImmediately(operation)
        }
    }

    func queueOfflineUpdateOperation(for note: Note, xmlContent: String) {
        let dataDict: [String: Any] = [
            "title": editedTitle.isEmpty ? note.title : editedTitle,
            "content": xmlContent,
            "folderId": note.folderId,
            "timestamp": Date().timeIntervalSince1970,
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: dataDict, options: [])
            let operation = NoteOperation(
                type: .cloudUpload,
                noteId: note.id,
                data: jsonData,
                localSaveTimestamp: Date()
            )
            try UnifiedOperationQueue.shared.enqueue(operation)
            lastUploadedContentByNoteId[note.id] = xmlContent
        } catch {
            LogService.shared.error(.editor, "添加操作到离线队列失败: \(error)")
        }
    }

    func isNetworkRelatedError(_ error: Error) -> Bool {
        if let miNoteError = error as? MiNoteError {
            switch miNoteError {
            case .networkError:
                return true
            case .cookieExpired, .notAuthenticated:
                return true
            case .invalidResponse:
                return false
            }
        }

        if let nsError = error as NSError? {
            if nsError.domain == NSURLErrorDomain {
                return true
            }
            if nsError.code >= 500, nsError.code < 600 {
                return true
            }
        }

        return false
    }

    // MARK: - 辅助方法

    /// 笔记更新已通过 EventBus 发布，NoteStore 和 NoteListState 会自动处理
    func updateViewModel(with _: Note) {}

    /// 笔记更新已通过 EventBus 发布，NoteStore 和 NoteListState 会自动处理
    func updateNotesArrayOnly(with _: Note) {}

    func buildUpdatedNote(
        from note: Note,
        xmlContent: String,
        shouldUpdateTimestamp: Bool = true
    ) -> Note {
        let titleToUse: String = if note.id == currentEditingNoteId {
            editedTitle
        } else {
            note.title
        }

        // serverTag 由 NoteStore 处理 contentUpdated 事件时从 DB 读取最新值再更新，这里直接使用 note 自身的值
        let latestServerTag = note.serverTag

        // 同步更新 settingJson：合并最新的 setting 数据
        var mergedSettingJson = note.settingJson
        if let latestNote = noteEditorState?.currentNote, latestNote.id == note.id {
            if let latestSettingJson = latestNote.settingJson, !latestSettingJson.isEmpty {
                mergedSettingJson = latestSettingJson
            }
        }

        let updatedAt = shouldUpdateTimestamp ? Date() : note.updatedAt

        return Note(
            id: note.id,
            title: titleToUse,
            content: xmlContent,
            folderId: note.folderId,
            isStarred: note.isStarred,
            createdAt: note.createdAt,
            updatedAt: updatedAt,
            tags: note.tags,
            serverTag: latestServerTag,
            settingJson: mergedSettingJson,
            extraInfoJson: note.extraInfoJson
        )
    }

    func hasContentActuallyChanged(
        currentContent: String,
        savedContent: String,
        currentTitle: String,
        originalTitle: String
    ) -> Bool {
        let normalizedCurrent = XMLNormalizer.shared.normalize(currentContent)
        let normalizedSaved = XMLNormalizer.shared.normalize(savedContent)
        return normalizedCurrent != normalizedSaved || currentTitle != originalTitle
    }

    func hasContentChanged(xmlContent: String) -> Bool {
        lastSavedXMLContent != xmlContent || editedTitle != originalTitle
    }

    func getLatestContentFromEditor() async -> String {
        if let context = nativeEditorContext {
            let xmlContent = context.exportToXML()
            if !xmlContent.isEmpty {
                return xmlContent
            }
        }
        return currentXMLContent
    }
}
