import AVFoundation
import Combine
import Foundation

/// 音频播放服务
///
/// 负责音频文件的播放控制，包括：
/// - 播放/暂停/停止
/// - 进度跳转
/// - 播放状态管理
/// - 播放完成通知
///
final class AudioPlayerService: NSObject, ObservableObject, @unchecked Sendable {

    // MARK: - 单例

    static let shared = AudioPlayerService()

    // MARK: - 发布属性（用于 SwiftUI 绑定）

    /// 当前播放的音频 URL
    @Published private(set) var currentURL: URL?

    /// 当前播放的文件 ID
    @Published private(set) var currentFileId: String?

    /// 是否正在播放
    @Published private(set) var isPlaying = false

    /// 是否正在加载
    @Published private(set) var isLoading = false

    /// 当前播放时间（秒）
    @Published private(set) var currentTime: TimeInterval = 0

    /// 总时长（秒）
    @Published private(set) var duration: TimeInterval = 0

    /// 播放错误信息
    @Published private(set) var errorMessage: String?

    /// 播放进度（0.0 - 1.0）
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    // MARK: - 播放状态枚举

    /// 播放状态
    enum PlaybackState: Equatable {
        case idle // 空闲
        case loading // 加载中
        case playing // 播放中
        case paused // 暂停
        case error(String) // 错误

        static func == (lhs: PlaybackState, rhs: PlaybackState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.loading, .loading), (.playing, .playing), (.paused, .paused):
                true
            case let (.error(lhsMsg), .error(rhsMsg)):
                lhsMsg == rhsMsg
            default:
                false
            }
        }
    }

    /// 当前播放状态
    @Published private(set) var playbackState: PlaybackState = .idle

    // MARK: - 私有属性

    /// 音频播放器
    private var audioPlayer: AVAudioPlayer?

    /// 进度更新定时器
    private var progressTimer: Timer?

    /// 进度更新间隔（秒）
    private let progressUpdateInterval: TimeInterval = 0.1

    /// 状态访问锁
    private let stateLock = NSLock()

    // MARK: - 通知名称

    /// 播放状态变化通知
    static let playbackStateDidChangeNotification = Notification.Name("AudioPlayerService.playbackStateDidChange")

    /// 播放进度变化通知
    static let playbackProgressDidChangeNotification = Notification.Name("AudioPlayerService.playbackProgressDidChange")

    /// 播放完成通知
    static let playbackDidFinishNotification = Notification.Name("AudioPlayerService.playbackDidFinish")

    /// 播放错误通知
    static let playbackErrorNotification = Notification.Name("AudioPlayerService.playbackError")

    // MARK: - 初始化

    override private init() {
        super.init()
    }

    deinit {
        stopProgressTimer()
        audioPlayer?.stop()
    }

    // MARK: - 播放控制方法

    /// 播放音频文件
    ///
    /// - Parameter url: 音频文件 URL
    /// - Throws: 播放失败时抛出错误
    func play(url: URL) throws {
        stateLock.lock()
        defer { stateLock.unlock() }

        if let currentURL, currentURL == url, let player = audioPlayer {
            if !player.isPlaying {
                let success = player.play()
                if success {
                    updateState(.playing)
                    startProgressTimer()
                } else {
                    LogService.shared.error(.audio, "继续播放失败: \(url.lastPathComponent)")
                }
            }
            return
        }

        stopInternal()

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.volume = 1.0

            currentURL = url
            duration = audioPlayer?.duration ?? 0
            currentTime = 0
            errorMessage = nil

            let playSuccess = audioPlayer?.play() ?? false
            if playSuccess {
                updateState(.playing)
                startProgressTimer()
                LogService.shared.info(.audio, "播放开始: \(url.lastPathComponent), 时长: \(formatTime(duration))")
            } else {
                let errorMsg = "播放启动失败"
                LogService.shared.error(.audio, errorMsg)
                updateState(.error(errorMsg))
                throw NSError(domain: "AudioPlayerService", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMsg])
            }
        } catch {
            let errorMsg = "播放失败: \(error.localizedDescription)"
            LogService.shared.error(.audio, errorMsg)
            updateState(.error(errorMsg))
            throw error
        }
    }

    /// 播放音频文件（带文件 ID）
    ///
    /// - Parameters:
    ///   - url: 音频文件 URL
    ///   - fileId: 文件 ID
    /// - Throws: 播放失败时抛出错误
    func play(url: URL, fileId: String) throws {
        currentFileId = fileId
        try play(url: url)
    }

    /// 暂停播放
    ///
    func pause() {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard let player = audioPlayer, player.isPlaying else {
            return
        }

        player.pause()
        stopProgressTimer()
        updateState(.paused)
    }

    func stop() {
        stateLock.lock()
        defer { stateLock.unlock() }

        stopInternal()
    }

    /// 内部停止方法（不加锁）
    private func stopInternal() {
        stopProgressTimer()

        audioPlayer?.stop()
        audioPlayer = nil

        // 重置状态
        currentURL = nil
        currentFileId = nil
        currentTime = 0
        duration = 0
        errorMessage = nil

        updateStateInternal(.idle)
    }

    /// 跳转到指定位置
    ///
    /// - Parameter progress: 进度值（0.0 - 1.0）
    func seek(to progress: Double) {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard let player = audioPlayer else {
            return
        }

        let clampedProgress = max(0, min(1, progress))
        let targetTime = duration * clampedProgress

        player.currentTime = targetTime
        currentTime = targetTime

        postProgressNotification()
    }

    /// 跳转到指定时间
    ///
    /// - Parameter time: 目标时间（秒）
    func seek(toTime time: TimeInterval) {
        guard duration > 0 else { return }
        let progress = time / duration
        seek(to: progress)
    }

    /// 快进指定秒数
    ///
    /// - Parameter seconds: 快进秒数
    func skipForward(_ seconds: TimeInterval = 15) {
        guard duration > 0 else { return }
        let newProgress = min(1, (currentTime + seconds) / duration)
        seek(to: newProgress)
    }

    /// 快退指定秒数
    ///
    /// - Parameter seconds: 快退秒数
    func skipBackward(_ seconds: TimeInterval = 15) {
        guard duration > 0 else { return }
        let newProgress = max(0, (currentTime - seconds) / duration)
        seek(to: newProgress)
    }

    /// 切换播放/暂停状态
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else if let url = currentURL {
            try? play(url: url)
        }
    }

    // MARK: - 播放状态管理

    /// 更新播放状态（加锁版本）
    private func updateState(_ newState: PlaybackState) {
        updateStateInternal(newState)
    }

    /// 更新播放状态（内部版本，不加锁）
    private func updateStateInternal(_ newState: PlaybackState) {
        let oldState = playbackState
        playbackState = newState

        // 更新相关属性
        switch newState {
        case .idle:
            isPlaying = false
            isLoading = false
            errorMessage = nil
        case .loading:
            isPlaying = false
            isLoading = true
            errorMessage = nil
        case .playing:
            isPlaying = true
            isLoading = false
            errorMessage = nil
        case .paused:
            isPlaying = false
            isLoading = false
            errorMessage = nil
        case let .error(message):
            isPlaying = false
            isLoading = false
            errorMessage = message
        }

        // 发送状态变化通知
        if oldState != newState {
            postStateNotification(oldState: oldState, newState: newState)
        }
    }

    // MARK: - 进度定时器

    /// 启动进度更新定时器
    private func startProgressTimer() {
        stopProgressTimer()

        progressTimer = Timer.scheduledTimer(withTimeInterval: progressUpdateInterval, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }

        // 确保定时器在 RunLoop 中运行
        if let timer = progressTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    /// 停止进度更新定时器
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    /// 更新播放进度
    private func updateProgress() {
        guard let player = audioPlayer else { return }

        let newTime = player.currentTime

        // 只有当时间变化时才更新
        if abs(newTime - currentTime) > 0.01 {
            currentTime = newTime
            postProgressNotification()
        }
    }

    // MARK: - 通知发送

    /// 发送状态变化通知
    private func postStateNotification(oldState: PlaybackState, newState: PlaybackState) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.playbackStateDidChangeNotification,
                object: self,
                userInfo: [
                    "oldState": oldState,
                    "newState": newState,
                    "fileId": self.currentFileId as Any,
                ]
            )
        }
    }

    /// 发送进度变化通知
    private func postProgressNotification() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.playbackProgressDidChangeNotification,
                object: self,
                userInfo: [
                    "currentTime": self.currentTime,
                    "duration": self.duration,
                    "progress": self.progress,
                    "fileId": self.currentFileId as Any,
                ]
            )
        }
    }

    /// 发送播放完成通知
    private func postFinishNotification() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.playbackDidFinishNotification,
                object: self,
                userInfo: [
                    "fileId": self.currentFileId as Any,
                ]
            )
        }
    }

    /// 发送播放错误通知
    private func postErrorNotification(_ error: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.playbackErrorNotification,
                object: self,
                userInfo: [
                    "error": error,
                    "fileId": self.currentFileId as Any,
                ]
            )
        }
    }

    // MARK: - 辅助方法

    /// 获取音频文件时长
    ///
    /// - Parameter url: 音频文件 URL
    /// - Returns: 时长（秒），如果无法获取则返回 nil
    func getDuration(for url: URL) -> TimeInterval? {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            return player.duration
        } catch {
            return nil
        }
    }

    /// 检查是否正在播放指定文件
    ///
    /// - Parameter fileId: 文件 ID
    /// - Returns: 是否正在播放
    func isPlaying(fileId: String) -> Bool {
        currentFileId == fileId && isPlaying
    }

    /// 检查是否已加载指定文件
    ///
    /// - Parameter fileId: 文件 ID
    /// - Returns: 是否已加载
    func isLoaded(fileId: String) -> Bool {
        currentFileId == fileId && audioPlayer != nil
    }

    /// 获取指定文件的播放状态
    ///
    /// - Parameter fileId: 文件 ID
    /// - Returns: 播放状态，如果不是当前文件则返回 .idle
    func getPlaybackState(for fileId: String) -> PlaybackState {
        if currentFileId == fileId {
            return playbackState
        }
        return .idle
    }

    /// 格式化时间为 mm:ss 格式
    ///
    /// - Parameter time: 时间（秒）
    /// - Returns: 格式化的时间字符串
    func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }

        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        return String(format: "%d:%02d", minutes, seconds)
    }

    /// 获取当前播放信息
    ///
    /// - Returns: 播放信息字典
    func getPlaybackInfo() -> [String: Any] {
        [
            "fileId": currentFileId as Any,
            "url": currentURL?.absoluteString as Any,
            "state": String(describing: playbackState),
            "isPlaying": isPlaying,
            "currentTime": currentTime,
            "duration": duration,
            "progress": progress,
            "formattedCurrentTime": formatTime(currentTime),
            "formattedDuration": formatTime(duration),
        ]
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlayerService: AVAudioPlayerDelegate {

    /// 播放完成回调
    ///
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stateLock.lock()
        defer { stateLock.unlock() }

        stopProgressTimer()

        if flag {
            currentTime = 0
            player.currentTime = 0
            updateStateInternal(.idle)
            postFinishNotification()
        } else {
            let errorMsg = "播放异常结束"
            LogService.shared.error(.audio, errorMsg)
            updateStateInternal(.error(errorMsg))
            postErrorNotification(errorMsg)
        }
    }

    func audioPlayerDecodeErrorDidOccur(_: AVAudioPlayer, error: Error?) {
        stateLock.lock()
        defer { stateLock.unlock() }

        stopProgressTimer()

        let errorMsg = error?.localizedDescription ?? "音频解码错误"
        LogService.shared.error(.audio, "解码错误: \(errorMsg)")

        updateStateInternal(.error(errorMsg))
        postErrorNotification(errorMsg)
    }
}
