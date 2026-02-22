import SwiftUI

/// 保存状态
enum SaveStatus: Equatable {
    case idle
    case saving
    case saved
    case failed(String)
}

/// 笔记编辑器状态管理
///
/// 替代 NotesViewModel 中的编辑器交互功能和 NoteEditingCoordinator 的对外接口，
/// 负责当前笔记的加载、保存、历史记录和图片上传。
@MainActor
public final class NoteEditorState: ObservableObject {
    // MARK: - Published 属性

    @Published var currentNote: Note?
    @Published var saveStatus: SaveStatus = .idle
    @Published var hasUnsavedContent = false
    @Published var nativeEditorContext = NativeEditorContext()

    /// 外部注入的保存回调，由编辑器层设置
    var saveContentCallback: (() async -> Bool)?

    /// ID 迁移回调，通知 NoteEditingCoordinator 更新编辑状态
    var onIdMigrated: ((String, String, Note) -> Void)?

    // MARK: - 依赖

    private let eventBus: EventBus
    private let noteStore: NoteStore

    // MARK: - 事件订阅任务

    private var noteEventTask: Task<Void, Never>?
    private var syncEventTask: Task<Void, Never>?

    // MARK: - 初始化

    init(eventBus: EventBus = .shared, noteStore: NoteStore) {
        self.eventBus = eventBus
        self.noteStore = noteStore
    }

    // MARK: - 生命周期

    func start() {
        noteEventTask = Task { [weak self] in
            guard let self else { return }
            let stream = await eventBus.subscribe(to: NoteEvent.self)
            for await event in stream {
                guard !Task.isCancelled else { break }
                switch event {
                case let .saved(note):
                    handleNoteSaved(note)
                case let .idMigrated(oldId, _, note):
                    handleIdMigrated(oldId: oldId, note: note)
                default:
                    break
                }
            }
        }

        syncEventTask = Task { [weak self] in
            guard let self else { return }
            let stream = await eventBus.subscribe(to: SyncEvent.self)
            for await event in stream {
                guard !Task.isCancelled else { break }
                switch event {
                case let .tagUpdated(noteId, newTag):
                    handleTagUpdated(noteId: noteId, newTag: newTag)
                default:
                    break
                }
            }
        }
    }

    func stop() {
        noteEventTask?.cancel()
        syncEventTask?.cancel()
        noteEventTask = nil
        syncEventTask = nil
    }

    // MARK: - 笔记加载

    func loadNote(_ note: Note) {
        currentNote = note
        saveStatus = .idle
        hasUnsavedContent = false
    }

    // MARK: - 内容保存

    func saveContent(title: String, content: String) async {
        guard let note = currentNote else { return }

        saveStatus = .saving
        hasUnsavedContent = false

        await eventBus.publish(NoteEvent.contentUpdated(noteId: note.id, title: title, content: content))

        saveStatus = .saved
    }

    /// 文件夹切换前保存当前编辑内容
    func saveForFolderSwitch() async -> Bool {
        guard hasUnsavedContent else { return true }

        if let callback = saveContentCallback {
            let success = await callback()
            if success {
                saveStatus = .saved
                hasUnsavedContent = false
            } else {
                saveStatus = .failed("文件夹切换前保存失败")
            }
            return success
        }

        return true
    }

    // MARK: - 笔记历史

    func getNoteHistoryTimes(noteId: String) async throws -> [NoteHistoryVersion] {
        let response = try await MiNoteService.shared.getNoteHistoryTimes(noteId: noteId)

        guard let code = response["code"] as? Int, code == 0,
              let data = response["data"] as? [String: Any],
              let tvList = data["tvList"] as? [[String: Any]]
        else {
            throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "无效的响应"])
        }

        var versions: [NoteHistoryVersion] = []
        for item in tvList {
            if let updateTime = item["updateTime"] as? Int64,
               let version = item["version"] as? Int64
            {
                versions.append(NoteHistoryVersion(version: version, updateTime: updateTime))
            }
        }
        return versions
    }

    func getNoteHistory(noteId: String, version: Int64) async throws -> Note {
        let response = try await MiNoteService.shared.getNoteHistory(noteId: noteId, version: version)

        guard let code = response["code"] as? Int, code == 0,
              let data = response["data"] as? [String: Any],
              let entry = data["entry"] as? [String: Any]
        else {
            throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "无效的响应"])
        }

        guard var note = NoteMapper.fromMinoteListData(entry) else {
            throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "无法解析笔记数据"])
        }

        NoteMapper.updateFromServerDetails(&note, details: response)
        return note
    }

    func restoreNoteHistory(noteId: String, version: Int64) async throws {
        let response = try await MiNoteService.shared.restoreNoteHistory(noteId: noteId, version: version)

        guard let code = response["code"] as? Int, code == 0 else {
            throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "恢复历史记录失败"])
        }

        // 恢复成功后发布同步请求
        await eventBus.publish(SyncEvent.requested(mode: .full(.normal)))
    }

    // MARK: - 图片上传

    func uploadImageAndInsertToNote(imageURL: URL) async throws -> String {
        guard currentNote != nil else {
            throw NSError(domain: "MiNote", code: 400, userInfo: [NSLocalizedDescriptionKey: "请先选择笔记"])
        }

        let imageData = try Data(contentsOf: imageURL)
        let fileName = imageURL.lastPathComponent
        let fileExtension = (imageURL.pathExtension as NSString).lowercased
        let mimeType = switch fileExtension {
        case "jpg", "jpeg": "image/jpeg"
        case "png": "image/png"
        case "gif": "image/gif"
        case "webp": "image/webp"
        default: "image/jpeg"
        }

        let uploadResult = try await MiNoteService.shared.uploadImage(
            imageData: imageData, fileName: fileName, mimeType: mimeType
        )

        guard let fileId = uploadResult["fileId"] as? String,
              let _ = uploadResult["digest"] as? String
        else {
            throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "上传图片失败"])
        }

        let fileType = String(mimeType.dropFirst("image/".count))
        try LocalStorageService.shared.saveImage(imageData: imageData, fileId: fileId, fileType: fileType)

        LogService.shared.info(.editor, "图片上传成功: fileId=\(fileId)")
        return fileId
    }

    // MARK: - 事件处理（内部）

    /// 处理笔记保存事件：只更新元数据，不干扰编辑中的 content
    private func handleNoteSaved(_ note: Note) {
        guard let current = currentNote, current.id == note.id else { return }
        var updated = current
        updated.serverTag = note.serverTag
        updated.updatedAt = note.updatedAt
        currentNote = updated
    }

    /// 处理 serverTag 更新事件
    private func handleTagUpdated(noteId: String, newTag: String) {
        guard var current = currentNote, current.id == noteId else { return }
        current.serverTag = newTag
        currentNote = current
    }

    /// 处理笔记 ID 迁移（临时 ID -> 正式 ID）
    private func handleIdMigrated(oldId: String, note: Note) {
        guard let current = currentNote, current.id == oldId else { return }
        currentNote = note
        onIdMigrated?(oldId, note.id, note)
        LogService.shared.debug(.editor, "NoteEditorState 更新当前笔记 ID: \(oldId.prefix(8))... -> \(note.id.prefix(8))...")
    }
}
