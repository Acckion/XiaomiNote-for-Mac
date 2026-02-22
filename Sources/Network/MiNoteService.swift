import Foundation

/// 小米笔记服务（Facade 转发层）
///
/// 所有方法已迁移到独立的 API 类，此类仅作为向后兼容的转发层。
/// 新代码应直接使用 APIClient、NoteAPI、FolderAPI、FileAPI、SyncAPI、UserAPI。
public final class MiNoteService: @unchecked Sendable {
    public static let shared = MiNoteService()

    private let apiClient = APIClient.shared
    private let noteAPI = NoteAPI.shared
    private let folderAPI = FolderAPI.shared
    private let fileAPI = FileAPI.shared
    private let syncAPI = SyncAPI.shared
    private let userAPI = UserAPI.shared

    private init() {}

    // MARK: - APIClient 转发（认证与请求基础设施）

    @available(*, deprecated, message: "请使用 APIClient.shared.baseURL")
    var baseURL: String {
        apiClient.baseURL
    }

    @available(*, deprecated, message: "请使用 APIClient.shared.serviceToken")
    var serviceToken: String {
        apiClient.serviceToken
    }

    @available(*, deprecated, message: "请使用 APIClient.shared.performRequest()")
    func performRequest(
        url: String,
        method: String = "GET",
        headers: [String: String]? = nil,
        body: Data? = nil,
        priority: RequestPriority = .normal,
        cachePolicy: NetworkRequest.CachePolicy = .noCache
    ) async throws -> [String: Any] {
        try await apiClient.performRequest(url: url, method: method, headers: headers, body: body, priority: priority, cachePolicy: cachePolicy)
    }

    @available(*, deprecated, message: "请使用 APIClient.shared.getHeaders()")
    func getHeaders() -> [String: String] {
        apiClient.getHeaders()
    }

    @available(*, deprecated, message: "请使用 APIClient.shared.getPostHeaders()")
    func getPostHeaders() -> [String: String] {
        apiClient.getPostHeaders()
    }

    @available(*, deprecated, message: "请使用 APIClient.shared.encodeURIComponent()")
    func encodeURIComponent(_ string: String) -> String {
        apiClient.encodeURIComponent(string)
    }

    @available(*, deprecated, message: "请使用 APIClient.shared.handle401Error()")
    func handle401Error(responseBody: String, urlString: String) throws {
        try apiClient.handle401Error(responseBody: responseBody, urlString: urlString)
    }

    @available(*, deprecated, message: "请使用 APIClient.shared.setCookie()")
    func setCookie(_ newCookie: String) {
        apiClient.setCookie(newCookie)
    }

    @available(*, deprecated, message: "请使用 APIClient.shared.clearCookie()")
    func clearCookie() {
        apiClient.clearCookie()
    }

    @available(*, deprecated, message: "请使用 APIClient.shared.isAuthenticated()")
    public func isAuthenticated() -> Bool {
        apiClient.isAuthenticated()
    }

    @available(*, deprecated, message: "请使用 APIClient.shared.hasValidCookie()")
    @MainActor func hasValidCookie() -> Bool {
        apiClient.hasValidCookie()
    }

    @available(*, deprecated, message: "请使用 APIClient.shared.refreshCookie()")
    func refreshCookie() async throws -> Bool {
        try await apiClient.refreshCookie()
    }

    // MARK: - NoteAPI 转发（笔记操作）

    @available(*, deprecated, message: "请使用 NoteAPI.shared.createNote()")
    func createNote(title: String, content: String, folderId: String = "0") async throws -> [String: Any] {
        try await noteAPI.createNote(title: title, content: content, folderId: folderId)
    }

    @available(*, deprecated, message: "请使用 NoteAPI.shared.updateNote()")
    func updateNote(
        noteId: String,
        title: String,
        content: String,
        folderId: String = "0",
        existingTag: String = "",
        originalCreateDate: Int? = nil,
        imageData: [[String: Any]]? = nil
    ) async throws -> [String: Any] {
        try await noteAPI.updateNote(
            noteId: noteId,
            title: title,
            content: content,
            folderId: folderId,
            existingTag: existingTag,
            originalCreateDate: originalCreateDate,
            imageData: imageData
        )
    }

    @available(*, deprecated, message: "请使用 NoteAPI.shared.deleteNote()")
    func deleteNote(noteId: String, tag: String, purge: Bool = false) async throws -> [String: Any] {
        try await noteAPI.deleteNote(noteId: noteId, tag: tag, purge: purge)
    }

    @available(*, deprecated, message: "请使用 NoteAPI.shared.restoreDeletedNote()")
    func restoreDeletedNote(noteId: String, tag: String) async throws -> [String: Any] {
        try await noteAPI.restoreDeletedNote(noteId: noteId, tag: tag)
    }

    @available(*, deprecated, message: "请使用 NoteAPI.shared.fetchNoteDetails()")
    func fetchNoteDetails(noteId: String) async throws -> [String: Any] {
        try await noteAPI.fetchNoteDetails(noteId: noteId)
    }

    @available(*, deprecated, message: "请使用 NoteAPI.shared.fetchPage()")
    func fetchPage(syncTag: String = "") async throws -> [String: Any] {
        try await noteAPI.fetchPage(syncTag: syncTag)
    }

    @available(*, deprecated, message: "请使用 NoteAPI.shared.fetchPrivateNotes()")
    func fetchPrivateNotes(folderId: String = "2", limit: Int = 200) async throws -> [String: Any] {
        try await noteAPI.fetchPrivateNotes(folderId: folderId, limit: limit)
    }

    @available(*, deprecated, message: "请使用 NoteAPI.shared.fetchDeletedNotes()")
    func fetchDeletedNotes(limit: Int = 200, ts: Int64? = nil) async throws -> [String: Any] {
        try await noteAPI.fetchDeletedNotes(limit: limit, ts: ts)
    }

    @available(*, deprecated, message: "请使用 NoteAPI.shared.fetchNoteHistoryVersions()")
    func fetchNoteHistoryVersions(noteId: String, timestamp: Int? = nil) async throws -> [String: Any] {
        try await noteAPI.fetchNoteHistoryVersions(noteId: noteId, timestamp: timestamp)
    }

    @available(*, deprecated, message: "请使用 NoteAPI.shared.getNoteHistoryTimes()")
    func getNoteHistoryTimes(noteId: String) async throws -> [String: Any] {
        try await noteAPI.getNoteHistoryTimes(noteId: noteId)
    }

    @available(*, deprecated, message: "请使用 NoteAPI.shared.getNoteHistory()")
    func getNoteHistory(noteId: String, version: Int64) async throws -> [String: Any] {
        try await noteAPI.getNoteHistory(noteId: noteId, version: version)
    }

    @available(*, deprecated, message: "请使用 NoteAPI.shared.restoreNoteHistory()")
    func restoreNoteHistory(noteId: String, version: Int64) async throws -> [String: Any] {
        try await noteAPI.restoreNoteHistory(noteId: noteId, version: version)
    }

    // MARK: - FolderAPI 转发（文件夹操作）

    @available(*, deprecated, message: "请使用 FolderAPI.shared.createFolder()")
    func createFolder(name: String) async throws -> [String: Any] {
        try await folderAPI.createFolder(name: name)
    }

    @available(*, deprecated, message: "请使用 FolderAPI.shared.renameFolder()")
    func renameFolder(folderId: String, newName: String, existingTag: String, originalCreateDate: Int? = nil) async throws -> [String: Any] {
        try await folderAPI.renameFolder(folderId: folderId, newName: newName, existingTag: existingTag, originalCreateDate: originalCreateDate)
    }

    @available(*, deprecated, message: "请使用 FolderAPI.shared.deleteFolder()")
    func deleteFolder(folderId: String, tag: String, purge: Bool = false) async throws -> [String: Any] {
        try await folderAPI.deleteFolder(folderId: folderId, tag: tag, purge: purge)
    }

    @available(*, deprecated, message: "请使用 FolderAPI.shared.fetchFolderDetails()")
    func fetchFolderDetails(folderId: String) async throws -> [String: Any] {
        try await folderAPI.fetchFolderDetails(folderId: folderId)
    }

    // MARK: - FileAPI 转发（文件上传/下载）

    @available(*, deprecated, message: "请使用 FileAPI.shared.uploadImage()")
    func uploadImage(imageData: Data, fileName: String, mimeType: String) async throws -> [String: Any] {
        try await fileAPI.uploadImage(imageData: imageData, fileName: fileName, mimeType: mimeType)
    }

    @available(*, deprecated, message: "请使用 FileAPI.shared.uploadAudio()")
    public func uploadAudio(audioData: Data, fileName: String, mimeType: String = "audio/mpeg") async throws -> [String: Any] {
        try await fileAPI.uploadAudio(audioData: audioData, fileName: fileName, mimeType: mimeType)
    }

    @available(*, deprecated, message: "请使用 FileAPI.shared.downloadAudio()")
    public func downloadAudio(fileId: String, progressHandler: ((Int64, Int64) -> Void)? = nil) async throws -> Data {
        try await fileAPI.downloadAudio(fileId: fileId, progressHandler: progressHandler)
    }

    @available(*, deprecated, message: "请使用 FileAPI.shared.downloadAndCacheAudio()")
    public func downloadAndCacheAudio(
        fileId: String,
        mimeType: String = "audio/mpeg",
        progressHandler: ((Int64, Int64) -> Void)? = nil
    ) async throws -> URL {
        try await fileAPI.downloadAndCacheAudio(fileId: fileId, mimeType: mimeType, progressHandler: progressHandler)
    }

    @available(*, deprecated, message: "请使用 FileAPI.shared.getAudioDownloadInfo()")
    func getAudioDownloadInfo(fileId: String) async throws -> FileAPI.AudioDownloadInfo {
        try await fileAPI.getAudioDownloadInfo(fileId: fileId)
    }

    @available(*, deprecated, message: "请使用 FileAPI.shared.getAudioDownloadURL()")
    public func getAudioDownloadURL(fileId: String) async throws -> URL {
        try await fileAPI.getAudioDownloadURL(fileId: fileId)
    }

    @available(*, deprecated, message: "请使用 FileAPI.shared.uploadFile(fileData:fileName:mimeType:)")
    func uploadFile(fileData: Data, fileName: String, mimeType: String) async throws -> [String: Any] {
        try await fileAPI.uploadFile(fileData: fileData, fileName: fileName, mimeType: mimeType)
    }

    @available(*, deprecated, message: "请使用 FileAPI.shared.uploadFile(from:)")
    func uploadFile(from fileURL: URL) async throws -> [String: Any] {
        try await fileAPI.uploadFile(from: fileURL)
    }

    @available(*, deprecated, message: "请使用 FileAPI.shared.downloadFile()")
    func downloadFile(fileId: String, type: String = "note_img") async throws -> Data {
        try await fileAPI.downloadFile(fileId: fileId, type: type)
    }

    // MARK: - SyncAPI 转发（同步操作）

    @available(*, deprecated, message: "请使用 SyncAPI.shared.syncFull()")
    func syncFull(syncTag: String = "", inactiveTime: Int = 10) async throws -> [String: Any] {
        try await syncAPI.syncFull(syncTag: syncTag, inactiveTime: inactiveTime)
    }

    // MARK: - UserAPI 转发（用户信息与状态检查）

    @available(*, deprecated, message: "请使用 UserAPI.shared.fetchUserProfile()")
    func fetchUserProfile() async throws -> [String: Any] {
        try await userAPI.fetchUserProfile()
    }

    @available(*, deprecated, message: "请使用 UserAPI.shared.checkServiceStatus()")
    func checkServiceStatus() async throws -> [String: Any] {
        try await userAPI.checkServiceStatus()
    }

    @available(*, deprecated, message: "请使用 UserAPI.shared.checkCookieValidity()")
    func checkCookieValidity() async throws -> Bool {
        try await userAPI.checkCookieValidity()
    }

    @available(*, deprecated, message: "请使用 UserAPI.shared.updateCookieValidityCache()")
    func updateCookieValidityCache() async {
        await userAPI.updateCookieValidityCache()
    }

    // MARK: - ResponseParser 转发（响应解析）

    @available(*, deprecated, message: "请使用 ResponseParser.extractSyncTag(from:)")
    func extractSyncTag(from response: [String: Any]) -> String {
        ResponseParser.extractSyncTag(from: response)
    }

    @available(*, deprecated, message: "请使用 ResponseParser.parseNotes(from:)")
    func parseNotes(from response: [String: Any]) -> [Note] {
        ResponseParser.parseNotes(from: response)
    }

    @available(*, deprecated, message: "请使用 ResponseParser.parseFolders(from:)")
    func parseFolders(from response: [String: Any]) -> [Folder] {
        ResponseParser.parseFolders(from: response)
    }
}
