import AVFoundation
import Combine
import Foundation

/// 默认音频服务实现
final class DefaultAudioService: AudioServiceProtocol {
    // MARK: - Properties

    private let cacheService: CacheServiceProtocol
    private var audioPlayer: AVAudioPlayer?
    private var audioRecorder: AVAudioRecorder?

    private let isPlayingSubject = CurrentValueSubject<Bool, Never>(false)
    private let currentTimeSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private let durationSubject = CurrentValueSubject<TimeInterval, Never>(0)

    var isPlaying: AnyPublisher<Bool, Never> {
        isPlayingSubject.eraseToAnyPublisher()
    }

    var currentTime: AnyPublisher<TimeInterval, Never> {
        currentTimeSubject.eraseToAnyPublisher()
    }

    var duration: AnyPublisher<TimeInterval, Never> {
        durationSubject.eraseToAnyPublisher()
    }

    var isRecording: Bool {
        audioRecorder?.isRecording ?? false
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

        isPlayingSubject.send(true)
        durationSubject.send(audioPlayer?.duration ?? 0)
    }

    func pause() {
        audioPlayer?.pause()
        isPlayingSubject.send(false)
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingSubject.send(false)
        currentTimeSubject.send(0)
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTimeSubject.send(time)
    }

    // MARK: - Recording Methods

    func startRecording() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        audioRecorder = try AVAudioRecorder(url: tempURL, settings: settings)
        audioRecorder?.record()
    }

    func stopRecording() throws -> Data {
        guard let recorder = audioRecorder else {
            throw AudioError.noActiveRecording
        }

        recorder.stop()
        let url = recorder.url
        audioRecorder = nil

        let data = try Data(contentsOf: url)
        try? FileManager.default.removeItem(at: url)

        return data
    }

    // MARK: - Upload/Download Methods

    func uploadAudio(_: Data) async throws -> String {
        // 暂时返回占位 URL
        // 实际应用中应该上传到服务器
        throw AudioError.notImplemented
    }

    func downloadAudio(from url: String) async throws -> Data {
        guard let audioURL = URL(string: url) else {
            throw AudioError.invalidURL
        }

        // 检查缓存
        if let cachedData: Data = try? await cacheService.get(key: url) {
            return cachedData
        }

        let (data, _) = try await URLSession.shared.data(from: audioURL)
        try? await cacheService.set(key: url, value: data, policy: .default)

        return data
    }

    // MARK: - Cache Methods

    func getCachedAudio(for _: String) -> Data? {
        // 同步方法，暂时返回 nil
        nil
    }

    func cacheAudio(_: Data, for _: String) {
        // 异步缓存,不等待结果
        // 实际应用中可以使用后台队列
    }

    func clearAudioCache() {
        // 异步清理,不等待结果
        // 实际应用中可以使用后台队列
    }
}

// MARK: - Supporting Types

enum AudioError: Error {
    case invalidURL
    case noActiveRecording
    case notImplemented
}
