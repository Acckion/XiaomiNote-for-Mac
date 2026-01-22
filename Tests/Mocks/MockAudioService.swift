//
//  MockAudioService.swift
//  MiNoteMac
//
//  Created on 2026-01-23.
//  Mock 音频服务 - 用于测试
//

import Foundation
import Combine
@testable import MiNoteLibrary

/// Mock 音频服务
///
/// 用于测试的音频服务实现
public final class MockAudioService: AudioServiceProtocol, @unchecked Sendable {
    // MARK: - Mock 数据
    
    public var mockError: Error?
    public var mockAudioData: Data?
    public var mockAudioURL: String?
    public var mockIsRecording: Bool = false
    
    // MARK: - Published Properties
    
    private let isPlayingSubject = CurrentValueSubject<Bool, Never>(false)
    public var isPlaying: AnyPublisher<Bool, Never> {
        isPlayingSubject.eraseToAnyPublisher()
    }
    
    private let currentTimeSubject = CurrentValueSubject<TimeInterval, Never>(0)
    public var currentTime: AnyPublisher<TimeInterval, Never> {
        currentTimeSubject.eraseToAnyPublisher()
    }
    
    private let durationSubject = CurrentValueSubject<TimeInterval, Never>(0)
    public var duration: AnyPublisher<TimeInterval, Never> {
        durationSubject.eraseToAnyPublisher()
    }
    
    // MARK: - 调用计数
    
    public var playCallCount = 0
    public var pauseCallCount = 0
    public var stopCallCount = 0
    public var seekCallCount = 0
    public var startRecordingCallCount = 0
    public var stopRecordingCallCount = 0
    public var uploadAudioCallCount = 0
    public var downloadAudioCallCount = 0
    public var getCachedAudioCallCount = 0
    public var cacheAudioCallCount = 0
    public var clearAudioCacheCallCount = 0
    
    // MARK: - AudioServiceProtocol - 播放操作
    
    public func play(url: String) async throws {
        playCallCount += 1
        
        if let error = mockError {
            throw error
        }
        
        isPlayingSubject.send(true)
        durationSubject.send(60.0) // 模拟 60 秒音频
    }
    
    public func pause() {
        pauseCallCount += 1
        isPlayingSubject.send(false)
    }
    
    public func stop() {
        stopCallCount += 1
        isPlayingSubject.send(false)
        currentTimeSubject.send(0)
    }
    
    public func seek(to time: TimeInterval) {
        seekCallCount += 1
        currentTimeSubject.send(time)
    }
    
    // MARK: - AudioServiceProtocol - 录制操作
    
    public var isRecording: Bool {
        return mockIsRecording
    }
    
    public func startRecording() throws {
        startRecordingCallCount += 1
        
        if let error = mockError {
            throw error
        }
        
        mockIsRecording = true
    }
    
    public func stopRecording() throws -> Data {
        stopRecordingCallCount += 1
        
        if let error = mockError {
            throw error
        }
        
        mockIsRecording = false
        
        // 返回模拟的音频数据
        return mockAudioData ?? Data([0x00, 0x01, 0x02, 0x03])
    }
    
    // MARK: - AudioServiceProtocol - 上传下载
    
    public func uploadAudio(_ data: Data) async throws -> String {
        uploadAudioCallCount += 1
        
        if let error = mockError {
            throw error
        }
        
        // 返回模拟的音频 URL
        return mockAudioURL ?? "https://example.com/audio/\(UUID().uuidString).m4a"
    }
    
    public func downloadAudio(from url: String) async throws -> Data {
        downloadAudioCallCount += 1
        
        if let error = mockError {
            throw error
        }
        
        // 返回模拟的音频数据
        return mockAudioData ?? Data([0x00, 0x01, 0x02, 0x03])
    }
    
    // MARK: - AudioServiceProtocol - 缓存操作
    
    private var cache: [String: Data] = [:]
    
    public func getCachedAudio(for url: String) -> Data? {
        getCachedAudioCallCount += 1
        return cache[url]
    }
    
    public func cacheAudio(_ data: Data, for url: String) {
        cacheAudioCallCount += 1
        cache[url] = data
    }
    
    public func clearAudioCache() {
        clearAudioCacheCallCount += 1
        cache.removeAll()
    }
    
    // MARK: - Helper Methods
    
    /// 重置所有状态
    public func reset() {
        mockError = nil
        mockAudioData = nil
        mockAudioURL = nil
        mockIsRecording = false
        cache.removeAll()
        isPlayingSubject.send(false)
        currentTimeSubject.send(0)
        durationSubject.send(0)
        resetCallCounts()
    }
    
    /// 重置调用计数
    public func resetCallCounts() {
        playCallCount = 0
        pauseCallCount = 0
        stopCallCount = 0
        seekCallCount = 0
        startRecordingCallCount = 0
        stopRecordingCallCount = 0
        uploadAudioCallCount = 0
        downloadAudioCallCount = 0
        getCachedAudioCallCount = 0
        cacheAudioCallCount = 0
        clearAudioCacheCallCount = 0
    }
}
