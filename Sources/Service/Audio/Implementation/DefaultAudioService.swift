import Foundation
import AVFoundation
import Combine

/// 默认音频服务实现
final class DefaultAudioService: AudioServiceProtocol {
    // MARK: - Properties
    private let cacheService: CacheServiceProtocol
    private var audioPlayer: AVAudioPlayer?
    private var audioRecorder: AVAudioRecorder?
    private let playbackStateSubject = CurrentValueSubject<PlaybackState, Never>(.stopped)

    var playbackState: AnyPublisher<PlaybackState, Never> {
        playbackStateSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization
    init(cacheService: CacheServiceProtocol) {
        self.cacheService = cacheService
    }

    // MARK: - Playback Methods
    func play(url: String) async throws {
        guard let audioURL = URL(string: url) else {
            throw AudioError.invalidURL
        }

        // 检查缓存
        let audioData: Data
        if let cachedData: Data = try? await cacheService.get(key: url) {
            audioData = cachedData
        } else {
            let (data, _) = try await URLSession.shared.data(from: audioURL)
            audioData = data
            try? await cacheService.set(key: url, value: data, policy: .default)
        }

        audioPlayer = try AVAudioPlayer(data: audioData)
        audioPlayer?.play()
        playbackStateSubject.send(.playing)
    }

    func pause() {
        audioPlayer?.pause()
        playbackStateSubject.send(.paused)
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        playbackStateSubject.send(.stopped)
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
    }

    func getCurrentTime() -> TimeInterval {
        return audioPlayer?.currentTime ?? 0
    }

    func getDuration() -> TimeInterval {
        return audioPlayer?.duration ?? 0
    }

    // MARK: - Recording Methods
    func startRecording(outputURL: URL) async throws {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: outputURL, settings: settings)
        audioRecorder?.record()
    }

    func stopRecording() async throws -> URL {
        guard let recorder = audioRecorder else {
            throw AudioError.noActiveRecording
        }

        recorder.stop()
        let url = recorder.url
        audioRecorder = nil

        return url
    }

    func deleteRecording(url: URL) async throws {
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Cache Methods
    func cacheAudio(url: String) async throws {
        guard let audioURL = URL(string: url) else {
            throw AudioError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: audioURL)
        try await cacheService.set(key: url, value: data, policy: .default)
    }

    func clearAudioCache() async throws {
        try await cacheService.clear()
    }
}

// MARK: - Supporting Types
enum AudioError: Error {
    case invalidURL
    case noActiveRecording
}
