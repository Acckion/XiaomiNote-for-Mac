//
//  AudioPanelViewModel.swift
//  MiNoteMac
//
//  Created on 2026-01-23.
//  音频面板视图模型 - 管理音频功能
//

import Foundation
import Combine

/// 音频面板视图模型
///
/// 负责管理音频面板功能，包括：
/// - 音频播放
/// - 音频录制
/// - 音频上传/下载
@MainActor
public final class AudioPanelViewModel: ObservableObject {
    // MARK: - Published Properties
    
    /// 是否正在播放
    @Published public var isPlaying: Bool = false
    
    /// 是否正在录制
    @Published public var isRecording: Bool = false
    
    /// 当前音频 URL
    @Published public var currentAudioURL: String?
    
    /// 录制时长
    @Published public var recordingDuration: TimeInterval = 0
    
    /// 播放进度 (0.0 - 1.0)
    @Published public var playbackProgress: Double = 0.0
    
    /// 当前播放时间
    @Published public var currentTime: TimeInterval = 0
    
    /// 音频总时长
    @Published public var duration: TimeInterval = 0
    
    /// 错误消息
    @Published public var errorMessage: String?
    
    // MARK: - Dependencies
    
    private let audioService: AudioServiceProtocol
    private let noteStorage: NoteStorageProtocol
    
    // MARK: - Private Properties
    
    /// 录制的音频数据
    private var recordedAudioData: Data?
    
    /// Cancellables
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    /// 初始化音频面板视图模型
    /// - Parameters:
    ///   - audioService: 音频服务
    ///   - noteStorage: 笔记存储服务
    public init(
        audioService: AudioServiceProtocol,
        noteService: NoteStorageProtocol
    ) {
        self.audioService = audioService
        self.noteStorage = noteService
        
        // 监听音频服务状态
        setupAudioServiceObservers()
    }
    
    // MARK: - Public Methods - 录制
    
    /// 开始录制
    public func startRecording() {
        errorMessage = nil
        
        do {
            try audioService.startRecording()
            isRecording = true
            recordingDuration = 0
            
            // 启动录制时长计时器
            startRecordingTimer()
            
        } catch {
            errorMessage = "开始录制失败: \(error.localizedDescription)"
            print("[AudioPanelViewModel] 开始录制失败: \(error)")
        }
    }
    
    /// 停止录制
    public func stopRecording() {
        errorMessage = nil
        
        do {
            let audioData = try audioService.stopRecording()
            recordedAudioData = audioData
            isRecording = false
            
            print("[AudioPanelViewModel] 录制完成，音频大小: \(audioData.count) bytes")
            
        } catch {
            errorMessage = "停止录制失败: \(error.localizedDescription)"
            print("[AudioPanelViewModel] 停止录制失败: \(error)")
            isRecording = false
        }
    }
    
    // MARK: - Public Methods - 播放
    
    /// 播放音频
    /// - Parameter url: 音频 URL
    public func playAudio(url: String) async {
        errorMessage = nil
        
        do {
            // 先检查缓存
            if let cachedData = audioService.getCachedAudio(for: url) {
                print("[AudioPanelViewModel] 使用缓存的音频")
                // 使用缓存的音频
            } else {
                // 下载音频
                print("[AudioPanelViewModel] 下载音频...")
                let audioData = try await audioService.downloadAudio(from: url)
                
                // 缓存音频
                audioService.cacheAudio(audioData, for: url)
            }
            
            // 播放音频
            try await audioService.play(url: url)
            currentAudioURL = url
            isPlaying = true
            
        } catch {
            errorMessage = "播放音频失败: \(error.localizedDescription)"
            print("[AudioPanelViewModel] 播放音频失败: \(error)")
        }
    }
    
    /// 暂停播放
    public func pauseAudio() {
        audioService.pause()
        isPlaying = false
    }
    
    /// 停止播放
    public func stopAudio() {
        audioService.stop()
        isPlaying = false
        currentAudioURL = nil
        playbackProgress = 0.0
        currentTime = 0
    }
    
    /// 跳转到指定时间
    /// - Parameter time: 目标时间
    public func seek(to time: TimeInterval) {
        audioService.seek(to: time)
    }
    
    // MARK: - Public Methods - 上传/下载
    
    /// 上传录制的音频
    /// - Returns: 音频 URL
    public func uploadRecordedAudio() async -> String? {
        guard let audioData = recordedAudioData else {
            errorMessage = "没有可上传的音频"
            return nil
        }
        
        errorMessage = nil
        
        do {
            let audioURL = try await audioService.uploadAudio(audioData)
            print("[AudioPanelViewModel] 音频上传成功: \(audioURL)")
            
            // 清除录制的音频数据
            recordedAudioData = nil
            
            return audioURL
            
        } catch {
            errorMessage = "上传音频失败: \(error.localizedDescription)"
            print("[AudioPanelViewModel] 上传音频失败: \(error)")
            return nil
        }
    }
    
    /// 下载音频
    /// - Parameter url: 音频 URL
    /// - Returns: 音频数据
    public func downloadAudio(url: String) async -> Data? {
        errorMessage = nil
        
        do {
            let audioData = try await audioService.downloadAudio(from: url)
            print("[AudioPanelViewModel] 音频下载成功，大小: \(audioData.count) bytes")
            
            // 缓存音频
            audioService.cacheAudio(audioData, for: url)
            
            return audioData
            
        } catch {
            errorMessage = "下载音频失败: \(error.localizedDescription)"
            print("[AudioPanelViewModel] 下载音频失败: \(error)")
            return nil
        }
    }
    
    // MARK: - Private Methods
    
    /// 设置音频服务观察者
    private func setupAudioServiceObservers() {
        // 监听播放状态
        audioService.isPlaying
            .sink { [weak self] playing in
                self?.isPlaying = playing
            }
            .store(in: &cancellables)
        
        // 监听当前播放时间
        audioService.currentTime
            .sink { [weak self] time in
                guard let self = self else { return }
                self.currentTime = time
                
                // 更新播放进度
                if self.duration > 0 {
                    self.playbackProgress = time / self.duration
                }
            }
            .store(in: &cancellables)
        
        // 监听音频总时长
        audioService.duration
            .sink { [weak self] duration in
                self?.duration = duration
            }
            .store(in: &cancellables)
    }
    
    /// 启动录制时长计时器
    private func startRecordingTimer() {
        Task {
            while isRecording {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                recordingDuration += 0.1
            }
        }
    }
}
