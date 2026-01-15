import Foundation
import Combine

/// 录音模板状态枚举
/// 
/// 跟踪录音模板从插入到完成的完整状态 
enum RecordingTemplateState: Equatable, CustomStringConvertible {
    case none                           // 无模板
    case inserted(templateId: String)   // 模板已插入
    case recording(templateId: String)  // 正在录制
    case uploading(templateId: String)  // 正在上传
    case updating(templateId: String, fileId: String)  // 正在更新模板
    case completed(templateId: String, fileId: String) // 完成
    case failed(templateId: String, error: String)     // 失败
    
    var description: String {
        switch self {
        case .none:
            return "无模板"
        case .inserted(let templateId):
            return "已插入(\(templateId.prefix(8))...)"
        case .recording(let templateId):
            return "录制中(\(templateId.prefix(8))...)"
        case .uploading(let templateId):
            return "上传中(\(templateId.prefix(8))...)"
        case .updating(let templateId, let fileId):
            return "更新中(\(templateId.prefix(8))... -> \(fileId.prefix(8))...)"
        case .completed(let templateId, let fileId):
            return "已完成(\(templateId.prefix(8))... -> \(fileId.prefix(8))...)"
        case .failed(let templateId, let error):
            return "失败(\(templateId.prefix(8))...): \(error)"
        }
    }
    
    /// 获取模板 ID（如果有）
    var templateId: String? {
        switch self {
        case .none:
            return nil
        case .inserted(let id), .recording(let id), .uploading(let id):
            return id
        case .updating(let id, _), .completed(let id, _), .failed(let id, _):
            return id
        }
    }
    
    /// 获取文件 ID（如果有）
    var fileId: String? {
        switch self {
        case .updating(_, let id), .completed(_, let id):
            return id
        default:
            return nil
        }
    }
    
    /// 是否处于活动状态（需要跟踪）
    var isActive: Bool {
        switch self {
        case .none, .completed, .failed:
            return false
        default:
            return true
        }
    }
}

/// 音频面板状态管理器
///
/// 负责管理音频面板的显示状态、模式和与其他组件的协调。
/// 音频面板是主窗口的第四栏，用于录制和播放音频。
/// 
@MainActor
final class AudioPanelStateManager: ObservableObject {
    
    // MARK: - 单例
    
    static let shared = AudioPanelStateManager()
    
    // MARK: - 面板模式枚举
    
    /// 面板模式
    enum Mode: Equatable {
        case recording  // 录制模式
        case playback   // 播放模式
    }
    
    // MARK: - 发布属性
    
    /// 面板是否可见 
    @Published private(set) var isVisible: Bool = false
    
    /// 当前模式 
    @Published private(set) var mode: Mode = .recording
    
    /// 当前播放的文件 ID（播放模式）
    @Published private(set) var currentFileId: String?
    
    /// 当前关联的笔记 ID 
    @Published private(set) var currentNoteId: String?
    
    /// 当前录音模板状态 
    @Published private(set) var recordingTemplateState: RecordingTemplateState = .none
    
    /// 当前录制的模板 ID（用于录制完成后更新模板）
    /// 便捷属性，从 recordingTemplateState 获取
    var currentRecordingTemplateId: String? {
        get {
            return recordingTemplateState.templateId
        }
        set {
            if let templateId = newValue {
                // 设置新的模板 ID，进入已插入状态
                recordingTemplateState = .inserted(templateId: templateId)
                print("[AudioPanelState] 📝 模板状态: \(recordingTemplateState)")
            } else {
                // 清除模板状态
                recordingTemplateState = .none
                print("[AudioPanelState] 📝 模板状态已清除")
            }
        }
    }
    
    // MARK: - 服务引用
    
    /// 录制服务引用
    private let recorderService: AudioRecorderService
    
    /// 播放服务引用
    private let playerService: AudioPlayerService
    
    // MARK: - 私有属性
    
    /// 取消订阅集合
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 通知名称
    
    /// 面板可见性变化通知
    static let visibilityDidChangeNotification = Notification.Name("AudioPanelStateManager.visibilityDidChange")
    
    /// 面板模式变化通知
    static let modeDidChangeNotification = Notification.Name("AudioPanelStateManager.modeDidChange")
    
    /// 需要显示确认对话框通知
    static let needsConfirmationNotification = Notification.Name("AudioPanelStateManager.needsConfirmation")
    
    // MARK: - 初始化
    
    private init(
        recorderService: AudioRecorderService = .shared,
        playerService: AudioPlayerService = .shared
    ) {
        self.recorderService = recorderService
        self.playerService = playerService
        
        setupObservers()
        
        print("[AudioPanelState] 初始化完成")
    }
    
    /// 设置观察者
    private func setupObservers() {
        // 监听录制状态变化
        NotificationCenter.default.publisher(for: AudioRecorderService.recordingStateDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleRecordingStateChange(notification)
            }
            .store(in: &cancellables)
        
        // 监听播放完成
        NotificationCenter.default.publisher(for: AudioPlayerService.playbackDidFinishNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handlePlaybackFinished()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 公开方法
    
    /// 显示面板进入录制模式
    ///
    /// - Parameter noteId: 当前笔记 ID 
    func showForRecording(noteId: String) {
        print("[AudioPanelState] 显示面板 - 录制模式，笔记: \(noteId)")
        
        // 如果正在播放，先停止
        if playerService.isPlaying {
            playerService.stop()
        }
        
        // 更新状态
        let wasVisible = isVisible
        let oldMode = mode
        
        mode = .recording
        currentFileId = nil
        currentNoteId = noteId
        isVisible = true
        
        // 发送通知
        if !wasVisible {
            postVisibilityNotification(visible: true)
        }
        if oldMode != .recording {
            postModeNotification(mode: .recording)
        }
    }
    
    /// 显示面板进入播放模式
    ///
    /// - Parameters:
    ///   - fileId: 音频文件 ID
    ///   - noteId: 当前笔记 ID 
    func showForPlayback(fileId: String, noteId: String) {
        print("[AudioPanelState] 显示面板 - 播放模式，文件: \(fileId)，笔记: \(noteId)")
        
        // 如果正在录制，需要先确认
        if isRecording() {
            print("[AudioPanelState] ⚠️ 正在录制中，无法切换到播放模式")
            return
        }
        
        // 更新状态
        let wasVisible = isVisible
        let oldMode = mode
        
        mode = .playback
        currentFileId = fileId
        currentNoteId = noteId
        isVisible = true
        
        // 发送通知
        if !wasVisible {
            postVisibilityNotification(visible: true)
        }
        if oldMode != .playback {
            postModeNotification(mode: .playback)
        }
    }
    
    /// 隐藏面板
    ///
    /// - Returns: 是否成功隐藏（录制中可能需要确认） 
    @discardableResult
    func hide() -> Bool {
        print("[AudioPanelState] 请求隐藏面板")
        
        // 检查是否可以安全关闭
        if !canClose() {
            print("[AudioPanelState] ⚠️ 无法关闭：正在录制中")
            postNeedsConfirmationNotification()
            return false
        }
        
        // 停止播放
        if playerService.isPlaying {
            playerService.stop()
        }
        
        // 重置状态
        let wasVisible = isVisible
        
        isVisible = false
        currentFileId = nil
        currentNoteId = nil
        
        // 发送通知
        if wasVisible {
            postVisibilityNotification(visible: false)
        }
        
        print("[AudioPanelState] ✅ 面板已隐藏")
        return true
    }
    
    /// 强制隐藏面板（用于用户确认后）
    ///
    /// 即使正在录制也会关闭面板，应该在用户确认后调用
    func forceHide() {
        print("[AudioPanelState] 强制隐藏面板")
        
        // 取消录制
        if isRecording() {
            recorderService.cancelRecording()
        }
        
        // 停止播放
        if playerService.isPlaying {
            playerService.stop()
        }
        
        // 重置状态
        let wasVisible = isVisible
        
        isVisible = false
        currentFileId = nil
        currentNoteId = nil
        
        // 发送通知
        if wasVisible {
            postVisibilityNotification(visible: false)
        }
        
        print("[AudioPanelState] ✅ 面板已强制隐藏")
    }
    
    /// 检查是否可以安全关闭
    ///
    /// - Returns: 是否可以关闭（录制中返回 false） 
    func canClose() -> Bool {
        // 如果正在录制或暂停，不能直接关闭
        let recordingState = recorderService.state
        switch recordingState {
        case .recording, .paused, .preparing:
            return false
        case .idle, .finished, .error:
            return true
        }
    }
    
    /// 处理笔记切换
    ///
    /// - Parameter newNoteId: 新笔记 ID
    /// - Returns: 是否允许切换（录制中可能需要确认） 
    @discardableResult
    func handleNoteSwitch(to newNoteId: String) -> Bool {
        print("[AudioPanelState] 处理笔记切换: \(currentNoteId ?? "nil") -> \(newNoteId)")
        
        // 如果面板不可见，直接允许切换
        guard isVisible else {
            return true
        }
        
        // 如果是同一个笔记，不需要处理
        if currentNoteId == newNoteId {
            return true
        }
        
        // 如果正在录制，需要确认
        if isRecording() {
            print("[AudioPanelState] ⚠️ 正在录制中，需要用户确认")
            postNeedsConfirmationNotification()
            return false
        }
        
        // 如果正在播放，停止播放并关闭面板
        if mode == .playback {
            print("[AudioPanelState] 停止播放并关闭面板")
            playerService.stop()
            hide()
        }
        
        return true
    }
    
    /// 处理音频附件删除
    ///
    /// - Parameter fileId: 被删除的文件 ID 
    func handleAudioAttachmentDeleted(fileId: String) {
        print("[AudioPanelState] 处理音频附件删除: \(fileId)")
        
        // 如果正在播放被删除的文件，关闭面板
        if mode == .playback && currentFileId == fileId {
            print("[AudioPanelState] 正在播放的文件被删除，关闭面板")
            playerService.stop()
            hide()
        }
    }
    
    // MARK: - 状态查询
    
    /// 检查是否正在录制
    func isRecording() -> Bool {
        let state = recorderService.state
        return state == .recording || state == .paused || state == .preparing
    }
    
    /// 检查是否正在播放
    func isPlayingAudio() -> Bool {
        return playerService.isPlaying
    }
    
    /// 获取当前状态信息
    func getStateInfo() -> [String: Any] {
        return [
            "isVisible": isVisible,
            "mode": String(describing: mode),
            "currentFileId": currentFileId as Any,
            "currentNoteId": currentNoteId as Any,
            "isRecording": isRecording(),
            "isPlaying": isPlayingAudio(),
            "canClose": canClose(),
            "templateState": String(describing: recordingTemplateState)
        ]
    }
    
    // MARK: - 录音模板状态管理
    
    /// 更新录音模板状态为录制中
    /// - Parameter templateId: 模板 ID
    func setTemplateRecording(templateId: String) {
        recordingTemplateState = .recording(templateId: templateId)
        print("[AudioPanelState] 📝 模板状态: \(recordingTemplateState)")
    }
    
    /// 更新录音模板状态为上传中
    /// - Parameter templateId: 模板 ID
    func setTemplateUploading(templateId: String) {
        recordingTemplateState = .uploading(templateId: templateId)
        print("[AudioPanelState] 📝 模板状态: \(recordingTemplateState)")
    }
    
    /// 更新录音模板状态为更新中
    /// - Parameters:
    ///   - templateId: 模板 ID
    ///   - fileId: 文件 ID
    func setTemplateUpdating(templateId: String, fileId: String) {
        recordingTemplateState = .updating(templateId: templateId, fileId: fileId)
        print("[AudioPanelState] 📝 模板状态: \(recordingTemplateState)")
    }
    
    /// 更新录音模板状态为完成
    /// - Parameters:
    ///   - templateId: 模板 ID
    ///   - fileId: 文件 ID
    func setTemplateCompleted(templateId: String, fileId: String) {
        recordingTemplateState = .completed(templateId: templateId, fileId: fileId)
        print("[AudioPanelState] 📝 模板状态: \(recordingTemplateState)")
        
        // 完成后延迟清除状态
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
            if case .completed = self.recordingTemplateState {
                self.recordingTemplateState = .none
                print("[AudioPanelState] 📝 模板状态已自动清除")
            }
        }
    }
    
    /// 更新录音模板状态为失败
    /// - Parameters:
    ///   - templateId: 模板 ID
    ///   - error: 错误信息
    func setTemplateFailed(templateId: String, error: String) {
        recordingTemplateState = .failed(templateId: templateId, error: error)
        print("[AudioPanelState] 📝 模板状态: \(recordingTemplateState)")
    }
    
    /// 清除录音模板状态
    func clearTemplateState() {
        recordingTemplateState = .none
        print("[AudioPanelState] 📝 模板状态已清除")
    }
    
    // MARK: - 私有方法
    
    /// 处理录制状态变化
    private func handleRecordingStateChange(_ notification: Notification) {
        guard let newState = notification.userInfo?["newState"] as? AudioRecorderService.RecordingState else {
            return
        }
        
        print("[AudioPanelState] 录制状态变化: \(newState)")
        
        // 如果录制完成或出错，可能需要更新 UI
        switch newState {
        case .finished:
            // 录制完成，等待用户确认
            break
        case .error(let message):
            print("[AudioPanelState] ❌ 录制错误: \(message)")
        default:
            break
        }
    }
    
    /// 处理播放完成
    private func handlePlaybackFinished() {
        print("[AudioPanelState] 播放完成")
        // 播放完成后保持面板打开，用户可以重新播放或关闭
    }
    
    // MARK: - 通知发送
    
    /// 发送可见性变化通知
    private func postVisibilityNotification(visible: Bool) {
        NotificationCenter.default.post(
            name: Self.visibilityDidChangeNotification,
            object: self,
            userInfo: [
                "visible": visible,
                "mode": mode,
                "noteId": currentNoteId as Any
            ]
        )
    }
    
    /// 发送模式变化通知
    private func postModeNotification(mode: Mode) {
        NotificationCenter.default.post(
            name: Self.modeDidChangeNotification,
            object: self,
            userInfo: [
                "mode": mode,
                "fileId": currentFileId as Any,
                "noteId": currentNoteId as Any
            ]
        )
    }
    
    /// 发送需要确认通知
    private func postNeedsConfirmationNotification() {
        NotificationCenter.default.post(
            name: Self.needsConfirmationNotification,
            object: self,
            userInfo: [
                "mode": mode,
                "noteId": currentNoteId as Any
            ]
        )
    }
}
