//
//  AudioAttachment.swift
//  MiNoteMac
//
//  语音文件附件 - 核心属性定义和生命周期管理

import AppKit
import Combine
import SwiftUI

// MARK: - 播放状态枚举

/// 音频播放状态
enum AudioPlaybackState: Equatable {
    case idle // 空闲（未播放）
    case loading // 加载中（下载/缓存）
    case playing // 播放中
    case paused // 暂停
    case error(String) // 错误

    static func == (lhs: AudioPlaybackState, rhs: AudioPlaybackState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.playing, .playing), (.paused, .paused):
            true
        case let (.error(lhsMsg), .error(rhsMsg)):
            lhsMsg == rhsMsg
        default:
            false
        }
    }

    /// 是否可以播放
    var canPlay: Bool {
        switch self {
        case .idle, .paused:
            true
        default:
            false
        }
    }

    /// 是否正在播放
    var isPlaying: Bool {
        if case .playing = self {
            return true
        }
        return false
    }

    /// 是否正在加载
    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    /// 错误信息（如果有）
    var errorMessage: String? {
        if case let .error(message) = self {
            return message
        }
        return nil
    }
}

// MARK: - 语音文件附件

/// 语音文件附件 - 用于在 NSTextView 中显示语音文件占位符和播放控件
/// 支持播放控制、进度显示和状态管理
final class AudioAttachment: NSTextAttachment, ThemeAwareAttachment, FileAttachmentProtocol {

    // MARK: - 基础属性

    /// 语音文件 ID（对应 XML 中的 fileid 属性）
    var fileId: String?

    /// 文件摘要（digest）
    var digest: String?

    /// MIME 类型
    var mimeType: String?

    /// 文件 API（用于下载音频）
    var fileAPI: FileAPI?

    /// 音频缓存服务
    var audioCacheService: AudioCacheService?

    /// 是否为临时占位符（录音中）
    /// 临时占位符的 fileId 以 "temp_" 开头，导出时会添加 des="temp" 属性
    var isTemporaryPlaceholder = false

    /// 是否为深色模式
    var isDarkMode = false {
        didSet {
            if oldValue != isDarkMode {
                invalidateCache()
            }
        }
    }

    /// 占位符尺寸（带播放控件时更大）
    var placeholderSize = NSSize(width: 240, height: 56)

    /// 缓存的图像
    var cachedImage: NSImage?

    /// 当前播放状态
    var playbackState: AudioPlaybackState = .idle {
        didSet {
            if oldValue != playbackState {
                invalidateCache()
                notifyStateChange()
            }
        }
    }

    /// 播放进度（0.0 - 1.0）
    var playbackProgress = 0.0 {
        didSet {
            if abs(oldValue - playbackProgress) > 0.01 {
                invalidateCache()
            }
        }
    }

    /// 当前播放时间（秒）
    var currentTime: TimeInterval = 0 {
        didSet {
            if abs(oldValue - currentTime) > 0.1 {
                invalidateCache()
            }
        }
    }

    /// 总时长（秒）
    var duration: TimeInterval = 0 {
        didSet {
            if abs(oldValue - duration) > 0.1 {
                invalidateCache()
            }
        }
    }

    /// 本地缓存文件 URL
    var cachedFileURL: URL?

    /// 通知订阅
    var cancellables = Set<AnyCancellable>()

    /// 状态变化通知名称
    static let playbackStateDidChangeNotification = Notification.Name("AudioAttachment.playbackStateDidChange")

    // MARK: - Initialization

    override nonisolated init(data contentData: Data?, ofType uti: String?) {
        super.init(data: contentData, ofType: uti)
        setupAttachment()
    }

    required nonisolated init?(coder: NSCoder) {
        super.init(coder: coder)
        setupAttachment()
    }

    /// 便捷初始化方法
    /// - Parameters:
    ///   - fileId: 语音文件 ID
    ///   - digest: 文件摘要（可选）
    ///   - mimeType: MIME 类型（可选）
    convenience init(fileId: String, digest: String? = nil, mimeType: String? = nil) {
        self.init(data: nil, ofType: nil)
        self.fileId = fileId
        self.digest = digest
        self.mimeType = mimeType
    }

    private func setupAttachment() {
        updateTheme()
        bounds = CGRect(origin: .zero, size: placeholderSize)
        // 预先创建占位符图像
        image = createPlaceholderImage()
        // 订阅播放器状态变化
        subscribeToPlayerNotifications()
    }

    deinit {
        // 如果当前正在播放此附件的音频，停止播放
        let capturedFileId = fileId
        Task { @MainActor in
            if let capturedFileId, AudioPlayerService.shared.currentFileId == capturedFileId {
                AudioPlayerService.shared.stop()
            }
        }
        cancellables.removeAll()
    }

    // MARK: - 辅助方法

    /// 格式化时间为 mm:ss 格式
    func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }

        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        return String(format: "%d:%02d", minutes, seconds)
    }

    /// 获取当前时间的格式化字符串
    var formattedCurrentTime: String {
        formatTime(currentTime)
    }

    /// 获取总时长的格式化字符串
    var formattedDuration: String {
        formatTime(duration)
    }

    /// 获取播放信息
    func getPlaybackInfo() -> [String: Any] {
        [
            "fileId": fileId as Any,
            "state": String(describing: playbackState),
            "progress": playbackProgress,
            "currentTime": currentTime,
            "duration": duration,
            "formattedCurrentTime": formattedCurrentTime,
            "formattedDuration": formattedDuration,
        ]
    }

    // MARK: - ThemeAwareAttachment

    func updateTheme() {
        guard let currentAppearance = NSApp?.effectiveAppearance else {
            return
        }
        let newIsDarkMode = currentAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        if isDarkMode != newIsDarkMode {
            isDarkMode = newIsDarkMode
        }
    }

    // MARK: - FileAttachmentProtocol

    /// 从播放状态推导加载状态
    var loadingState: FileAttachmentLoadingState {
        switch playbackState {
        case .loading:
            .loading
        case .playing, .paused:
            .loaded
        case .idle:
            .idle
        case let .error(message):
            .error(message)
        }
    }

    /// 开始加载音频文件
    nonisolated func startLoading() {
        // nonisolated(unsafe) 绕过 Swift 6 并发检查，AudioAttachment 的播放操作需要在主线程执行
        nonisolated(unsafe) let unsafeSelf = self
        Task { @MainActor in
            try? await unsafeSelf.play()
        }
    }

    // MARK: - Cache Management

    /// 清除缓存的图像
    func invalidateCache() {
        cachedImage = nil
        // 重新创建图像
        image = createPlaceholderImage()
    }
}
