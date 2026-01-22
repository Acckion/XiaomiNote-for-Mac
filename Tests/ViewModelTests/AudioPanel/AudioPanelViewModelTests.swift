//
//  AudioPanelViewModelTests.swift
//  MiNoteMac
//
//  Created on 2026-01-23.
//  音频面板视图模型单元测试
//

import XCTest
@testable import MiNoteLibrary

@MainActor
final class AudioPanelViewModelTests: XCTestCase {
    var sut: AudioPanelViewModel!
    var mockAudioService: MockAudioService!
    var mockNoteStorage: MockNoteStorage!
    
    override func setUp() {
        super.setUp()
        mockAudioService = MockAudioService()
        mockNoteStorage = MockNoteStorage()
        sut = AudioPanelViewModel(
            audioService: mockAudioService,
            noteService: mockNoteStorage
        )
    }
    
    override func tearDown() {
        sut = nil
        mockAudioService = nil
        mockNoteStorage = nil
        super.tearDown()
    }
    
    // MARK: - 录制功能测试
    
    func testStartRecording_Success_SetsIsRecording() {
        // When
        sut.startRecording()
        
        // Then
        XCTAssertTrue(sut.isRecording)
        XCTAssertEqual(mockAudioService.startRecordingCallCount, 1)
        XCTAssertNil(sut.errorMessage)
    }
    
    func testStartRecording_WithError_SetsErrorMessage() {
        // Given
        mockAudioService.mockError = NSError(domain: "test", code: -1)
        
        // When
        sut.startRecording()
        
        // Then
        XCTAssertFalse(sut.isRecording)
        XCTAssertNotNil(sut.errorMessage)
    }
    
    func testStopRecording_Success_ReturnsAudioData() {
        // Given
        let mockData = Data([0x01, 0x02, 0x03])
        mockAudioService.mockAudioData = mockData
        sut.startRecording()
        
        // When
        sut.stopRecording()
        
        // Then
        XCTAssertFalse(sut.isRecording)
        XCTAssertEqual(mockAudioService.stopRecordingCallCount, 1)
        XCTAssertNil(sut.errorMessage)
    }
    
    func testStopRecording_WithError_SetsErrorMessage() {
        // Given
        mockAudioService.mockError = NSError(domain: "test", code: -1)
        
        // When
        sut.stopRecording()
        
        // Then
        XCTAssertFalse(sut.isRecording)
        XCTAssertNotNil(sut.errorMessage)
    }
    
    // MARK: - 播放功能测试
    
    func testPlayAudio_Success_SetsIsPlaying() async {
        // Given
        let audioURL = "https://example.com/audio.m4a"
        
        // When
        await sut.playAudio(url: audioURL)
        
        // Wait for async operation
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Then
        XCTAssertTrue(sut.isPlaying)
        XCTAssertEqual(sut.currentAudioURL, audioURL)
        XCTAssertEqual(mockAudioService.playCallCount, 1)
        XCTAssertNil(sut.errorMessage)
    }
    
    func testPlayAudio_WithCachedAudio_UsesCachedData() async {
        // Given
        let audioURL = "https://example.com/audio.m4a"
        let cachedData = Data([0x01, 0x02, 0x03])
        mockAudioService.cacheAudio(cachedData, for: audioURL)
        
        // When
        await sut.playAudio(url: audioURL)
        
        // Wait for async operation
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Then
        XCTAssertTrue(sut.isPlaying)
        XCTAssertEqual(mockAudioService.getCachedAudioCallCount, 1)
    }
    
    func testPlayAudio_WithError_SetsErrorMessage() async {
        // Given
        mockAudioService.mockError = NSError(domain: "test", code: -1)
        
        // When
        await sut.playAudio(url: "https://example.com/audio.m4a")
        
        // Then
        XCTAssertFalse(sut.isPlaying)
        XCTAssertNotNil(sut.errorMessage)
    }
    
    func testPauseAudio_StopsPlayback() {
        // Given
        sut.isPlaying = true
        
        // When
        sut.pauseAudio()
        
        // Then
        XCTAssertFalse(sut.isPlaying)
        XCTAssertEqual(mockAudioService.pauseCallCount, 1)
    }
    
    func testStopAudio_ResetsPlaybackState() {
        // Given
        sut.isPlaying = true
        sut.currentAudioURL = "https://example.com/audio.m4a"
        sut.playbackProgress = 0.5
        
        // When
        sut.stopAudio()
        
        // Then
        XCTAssertFalse(sut.isPlaying)
        XCTAssertNil(sut.currentAudioURL)
        XCTAssertEqual(sut.playbackProgress, 0.0)
        XCTAssertEqual(mockAudioService.stopCallCount, 1)
    }
    
    func testSeek_UpdatesCurrentTime() {
        // Given
        let targetTime: TimeInterval = 30.0
        
        // When
        sut.seek(to: targetTime)
        
        // Then
        XCTAssertEqual(mockAudioService.seekCallCount, 1)
    }
    
    // MARK: - 上传/下载功能测试
    
    func testUploadRecordedAudio_Success_ReturnsURL() async {
        // Given
        let mockData = Data([0x01, 0x02, 0x03])
        mockAudioService.mockAudioData = mockData
        mockAudioService.mockAudioURL = "https://example.com/audio.m4a"
        sut.startRecording()
        sut.stopRecording()
        
        // When
        let audioURL = await sut.uploadRecordedAudio()
        
        // Then
        XCTAssertNotNil(audioURL)
        XCTAssertEqual(mockAudioService.uploadAudioCallCount, 1)
        XCTAssertNil(sut.errorMessage)
    }
    
    func testUploadRecordedAudio_WithoutRecording_ReturnsNil() async {
        // When
        let audioURL = await sut.uploadRecordedAudio()
        
        // Then
        XCTAssertNil(audioURL)
        XCTAssertNotNil(sut.errorMessage)
    }
    
    func testUploadRecordedAudio_WithError_SetsErrorMessage() async {
        // Given
        mockAudioService.mockError = NSError(domain: "test", code: -1)
        sut.startRecording()
        sut.stopRecording()
        mockAudioService.mockError = NSError(domain: "test", code: -1)
        
        // When
        let audioURL = await sut.uploadRecordedAudio()
        
        // Then
        XCTAssertNil(audioURL)
        XCTAssertNotNil(sut.errorMessage)
    }
    
    func testDownloadAudio_Success_ReturnsData() async {
        // Given
        let audioURL = "https://example.com/audio.m4a"
        let mockData = Data([0x01, 0x02, 0x03])
        mockAudioService.mockAudioData = mockData
        
        // When
        let audioData = await sut.downloadAudio(url: audioURL)
        
        // Then
        XCTAssertNotNil(audioData)
        XCTAssertEqual(mockAudioService.downloadAudioCallCount, 1)
        XCTAssertEqual(mockAudioService.cacheAudioCallCount, 1)
        XCTAssertNil(sut.errorMessage)
    }
    
    func testDownloadAudio_WithError_SetsErrorMessage() async {
        // Given
        mockAudioService.mockError = NSError(domain: "test", code: -1)
        
        // When
        let audioData = await sut.downloadAudio(url: "https://example.com/audio.m4a")
        
        // Then
        XCTAssertNil(audioData)
        XCTAssertNotNil(sut.errorMessage)
    }
}
