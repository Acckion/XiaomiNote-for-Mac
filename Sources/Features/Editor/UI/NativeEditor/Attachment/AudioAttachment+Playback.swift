//
//  AudioAttachment+Playback.swift
//  MiNoteMac
//
//  AudioAttachment 的播放状态管理与控制逻辑

import AppKit
import Combine

// MARK: - 播放控制

extension AudioAttachment {

    // MARK: - 播放器通知订阅

    /// 订阅播放器状态变化通知
    func subscribeToPlayerNotifications() {
        // 订阅播放状态变化
        NotificationCenter.default.publisher(for: AudioPlayerService.playbackStateDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handlePlaybackStateChange(notification)
            }
            .store(in: &cancellables)

        // 订阅播放进度变化
        NotificationCenter.default.publisher(for: AudioPlayerService.playbackProgressDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handlePlaybackProgressChange(notification)
            }
            .store(in: &cancellables)

        // 订阅播放完成
        NotificationCenter.default.publisher(for: AudioPlayerService.playbackDidFinishNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handlePlaybackFinished(notification)
            }
            .store(in: &cancellables)

        // 订阅播放错误
        NotificationCenter.default.publisher(for: AudioPlayerService.playbackErrorNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handlePlaybackError(notification)
            }
            .store(in: &cancellables)
    }

    // MARK: - 通知处理

    /// 处理播放状态变化
    private func handlePlaybackStateChange(_ notification: Notification) {
        guard let notificationFileId = notification.userInfo?["fileId"] as? String,
              notificationFileId == fileId
        else {
            return
        }

        if let newState = notification.userInfo?["newState"] as? AudioPlayerService.PlaybackState {
            // 转换播放器状态到附件状态
            switch newState {
            case .idle:
                playbackState = .idle
            case .loading:
                playbackState = .loading
            case .playing:
                playbackState = .playing
            case .paused:
                playbackState = .paused
            case let .error(message):
                playbackState = .error(message)
            }
        }
    }

    /// 处理播放进度变化
    private func handlePlaybackProgressChange(_ notification: Notification) {
        guard let notificationFileId = notification.userInfo?["fileId"] as? String,
              notificationFileId == fileId
        else {
            return
        }

        if let progress = notification.userInfo?["progress"] as? Double {
            playbackProgress = progress
        }
        if let time = notification.userInfo?["currentTime"] as? TimeInterval {
            currentTime = time
        }
        if let dur = notification.userInfo?["duration"] as? TimeInterval {
            duration = dur
        }
    }

    /// 处理播放完成
    private func handlePlaybackFinished(_ notification: Notification) {
        guard let notificationFileId = notification.userInfo?["fileId"] as? String,
              notificationFileId == fileId
        else {
            return
        }

        playbackState = .idle
        playbackProgress = 0
        currentTime = 0
    }

    /// 处理播放错误
    private func handlePlaybackError(_ notification: Notification) {
        guard let notificationFileId = notification.userInfo?["fileId"] as? String,
              notificationFileId == fileId
        else {
            return
        }

        if let error = notification.userInfo?["error"] as? String {
            playbackState = .error(error)
        }
    }

    /// 通知状态变化
    func notifyStateChange() {
        NotificationCenter.default.post(
            name: Self.playbackStateDidChangeNotification,
            object: self,
            userInfo: [
                "fileId": fileId as Any,
                "state": playbackState,
            ]
        )
    }

    // MARK: - 播放控制

    /// 开始播放（自动下载和缓存）
    ///
    /// - Throws: 播放失败时抛出错误
    @MainActor
    func play() async throws {
        guard let fileId else {
            let error = "无法播放：缺少文件 ID"
            playbackState = .error(error)
            throw NSError(domain: "AudioAttachment", code: -1, userInfo: [NSLocalizedDescriptionKey: error])
        }

        // 延迟获取 fileAPI
        let api: FileAPI
        if let existing = fileAPI {
            api = existing
        } else {
            let nm = NetworkModule()
            api = nm.fileAPI
            fileAPI = api
        }

        // 设置加载状态
        playbackState = .loading

        // 延迟获取 audioCacheService
        let cache: AudioCacheService
        if let existing = audioCacheService {
            cache = existing
        } else {
            let c = AudioCacheService()
            audioCacheService = c
            cache = c
        }

        do {
            // 检查缓存
            let audioURL: URL
            if let cachedURL = await cache.getCachedFile(for: fileId) {
                audioURL = cachedURL
                cachedFileURL = cachedURL
            } else {
                // 需要下载
                let audioData = try await api.downloadAudio(fileId: fileId)

                // 缓存文件
                let mimeType = mimeType ?? "audio/mpeg"
                audioURL = try await cache.cacheFile(data: audioData, fileId: fileId, mimeType: mimeType)
                cachedFileURL = audioURL
            }

            // 播放音频
            try AudioPlayerService.shared.play(url: audioURL, fileId: fileId)

            // 更新时长
            if let dur = AudioPlayerService.shared.getDuration(for: audioURL) {
                duration = dur
            }

            playbackState = .playing
        } catch {
            let errorMsg = "播放失败: \(error.localizedDescription)"
            playbackState = .error(errorMsg)
            throw error
        }
    }

    /// 暂停播放
    @MainActor
    func pause() {
        guard let fileId,
              AudioPlayerService.shared.currentFileId == fileId
        else {
            return
        }

        AudioPlayerService.shared.pause()
        playbackState = .paused
    }

    /// 停止播放
    @MainActor
    func stop() {
        guard let fileId,
              AudioPlayerService.shared.currentFileId == fileId
        else {
            return
        }

        AudioPlayerService.shared.stop()
        playbackState = .idle
        playbackProgress = 0
        currentTime = 0
    }

    /// 跳转到指定位置
    ///
    /// - Parameter progress: 进度值（0.0 - 1.0）
    @MainActor
    func seek(to progress: Double) {
        guard let fileId,
              AudioPlayerService.shared.currentFileId == fileId
        else {
            return
        }

        let clampedProgress = max(0, min(1, progress))
        AudioPlayerService.shared.seek(to: clampedProgress)
        playbackProgress = clampedProgress
        currentTime = duration * clampedProgress
    }

    /// 切换播放/暂停状态
    @MainActor
    func togglePlayPause() async throws {
        switch playbackState {
        case .idle, .paused:
            try await play()
        case .playing:
            pause()
        case .loading:
            // 加载中，忽略
            break
        case .error:
            // 出错后重试
            try await play()
        }
    }
}
