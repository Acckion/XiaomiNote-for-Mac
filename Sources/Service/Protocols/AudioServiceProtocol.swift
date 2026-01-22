//
//  AudioServiceProtocol.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  音频服务协议 - 定义音频处理操作接口
//

import Foundation
import Combine

/// 音频服务协议
///
/// 定义了音频处理相关的操作接口，包括：
/// - 音频播放
/// - 音频录制
/// - 音频上传和下载
protocol AudioServiceProtocol {
    // MARK: - 播放状态

    /// 是否正在播放
    var isPlaying: AnyPublisher<Bool, Never> { get }

    /// 当前播放时间
    var currentTime: AnyPublisher<TimeInterval, Never> { get }

    /// 音频总时长
    var duration: AnyPublisher<TimeInterval, Never> { get }

    // MARK: - 播放操作

    /// 播放音频
    /// - Parameter url: 音频URL
    func play(url: String) async throws

    /// 暂停播放
    func pause()

    /// 停止播放
    func stop()

    /// 跳转到指定时间
    /// - Parameter time: 目标时间
    func seek(to time: TimeInterval)

    // MARK: - 录制操作

    /// 开始录制
    func startRecording() throws

    /// 停止录制
    /// - Returns: 录制的音频数据
    func stopRecording() throws -> Data

    /// 是否正在录制
    var isRecording: Bool { get }

    // MARK: - 上传下载

    /// 上传音频
    /// - Parameter data: 音频数据
    /// - Returns: 音频URL
    func uploadAudio(_ data: Data) async throws -> String

    /// 下载音频
    /// - Parameter url: 音频URL
    /// - Returns: 音频数据
    func downloadAudio(from url: String) async throws -> Data

    // MARK: - 缓存操作

    /// 获取缓存的音频
    /// - Parameter url: 音频URL
    /// - Returns: 音频数据，如果未缓存返回 nil
    func getCachedAudio(for url: String) -> Data?

    /// 缓存音频
    /// - Parameters:
    ///   - data: 音频数据
    ///   - url: 音频URL
    func cacheAudio(_ data: Data, for url: String)

    /// 清除音频缓存
    func clearAudioCache()
}
