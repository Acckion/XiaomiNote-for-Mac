import AppKit
import AVFoundation
import Combine
import Foundation

/// 音频录制服务
///
/// 负责音频录制功能，包括：
/// - 麦克风权限管理
/// - 录制控制（开始/暂停/继续/停止/取消）
/// - 录制状态管理
/// - 音量级别监控
/// - 最大时长限制
///
@MainActor
final class AudioRecorderService: NSObject, ObservableObject {

    // MARK: - 单例

    static let shared = AudioRecorderService()

    // MARK: - 录制状态枚举

    /// 录制状态
    enum RecordingState: Equatable {
        case idle // 空闲
        case preparing // 准备中
        case recording // 录制中
        case paused // 暂停
        case finished // 完成
        case error(String) // 错误

        static func == (lhs: RecordingState, rhs: RecordingState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.preparing, .preparing), (.recording, .recording),
                 (.paused, .paused), (.finished, .finished):
                true
            case let (.error(lhsMsg), .error(rhsMsg)):
                lhsMsg == rhsMsg
            default:
                false
            }
        }
    }

    // MARK: - 权限状态枚举

    /// 麦克风权限状态
    enum PermissionStatus: Equatable {
        case notDetermined // 未确定
        case granted // 已授权
        case denied // 已拒绝
        case restricted // 受限制
    }

    // MARK: - 发布属性（用于 SwiftUI 绑定）

    /// 当前录制状态
    @Published private(set) var state: RecordingState = .idle

    /// 录制时长（秒）
    @Published private(set) var recordingDuration: TimeInterval = 0

    /// 音量级别（0.0 - 1.0）
    @Published private(set) var audioLevel: Float = 0

    /// 麦克风权限状态
    @Published private(set) var permissionStatus: PermissionStatus = .notDetermined

    /// 错误信息
    @Published private(set) var errorMessage: String?

    /// 是否正在录制
    var isRecording: Bool {
        state == .recording
    }

    /// 是否已暂停
    var isPaused: Bool {
        state == .paused
    }

    /// 剩余可录制时长（秒）
    var remainingDuration: TimeInterval {
        max(0, maxDuration - recordingDuration)
    }

    // MARK: - 配置属性

    /// 最大录制时长（秒）- 5 分钟
    let maxDuration: TimeInterval = 300

    /// 录制的音频文件 URL
    private(set) var recordedFileURL: URL?

    // MARK: - 私有属性

    /// 音频录制器
    private var audioRecorder: AVAudioRecorder?

    /// 录制计时器
    private var recordingTimer: Timer?

    /// 音量监控计时器
    private var levelTimer: Timer?

    /// 计时器更新间隔（秒）
    private let timerInterval: TimeInterval = 0.1

    /// 临时录音文件目录
    private let tempDirectory: URL

    /// 录制开始时间
    private var recordingStartTime: Date?

    /// 暂停前的累计时长
    private var accumulatedDuration: TimeInterval = 0

    // MARK: - 录制设置

    /// 音频录制设置
    private let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44100.0,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        AVEncoderBitRateKey: 128_000,
    ]

    // MARK: - 音频输入设备诊断

    /// 获取当前音频输入设备信息
    func getAudioInputDeviceInfo() -> String {
        var result = "音频输入设备信息:\n"

        // 获取所有音频输入设备
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )

        let devices = discoverySession.devices
        result += "  - 发现 \(devices.count) 个音频输入设备\n"

        for (index, device) in devices.enumerated() {
            result += "  [\(index + 1)] \(device.localizedName)\n"
            result += "      - 唯一标识: \(device.uniqueID)\n"
            result += "      - 型号: \(device.modelID)\n"
            result += "      - 已连接: \(device.isConnected)\n"
            result += "      - 已暂停: \(device.isSuspended)\n"
        }

        // 获取默认音频输入设备
        if let defaultDevice = AVCaptureDevice.default(for: .audio) {
            result += "  默认设备: \(defaultDevice.localizedName)\n"
        } else {
            result += "  ⚠️ 没有默认音频输入设备\n"
        }

        return result
    }

    /// 检查音频输入是否正常工作
    func checkAudioInputHealth() -> (isHealthy: Bool, message: String) {
        // 检查权限
        let permissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        guard permissionStatus == .authorized else {
            return (false, "麦克风权限未授权")
        }

        // 检查是否有音频输入设备
        guard let defaultDevice = AVCaptureDevice.default(for: .audio) else {
            return (false, "没有可用的音频输入设备")
        }

        // 检查设备是否已连接
        guard defaultDevice.isConnected else {
            return (false, "音频输入设备未连接")
        }

        // 检查设备是否被暂停
        if defaultDevice.isSuspended {
            return (false, "音频输入设备已暂停")
        }

        return (true, "音频输入设备正常: \(defaultDevice.localizedName)")
    }

    // MARK: - 通知名称

    /// 录制状态变化通知
    nonisolated(unsafe) static let recordingStateDidChangeNotification = Notification.Name("AudioRecorderService.recordingStateDidChange")

    /// 录制时长变化通知
    nonisolated(unsafe) static let recordingDurationDidChangeNotification = Notification.Name("AudioRecorderService.recordingDurationDidChange")

    /// 录制完成通知
    nonisolated(unsafe) static let recordingDidFinishNotification = Notification.Name("AudioRecorderService.recordingDidFinish")

    /// 录制错误通知
    nonisolated(unsafe) static let recordingErrorNotification = Notification.Name("AudioRecorderService.recordingError")

    /// 权限状态变化通知
    nonisolated(unsafe) static let permissionStatusDidChangeNotification = Notification.Name("AudioRecorderService.permissionStatusDidChange")

    // MARK: - 初始化

    override private init() {
        // 配置临时录音文件目录
        self.tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("AudioRecordings")

        super.init()

        // 创建临时目录
        createTempDirectoryIfNeeded()

        // 检查初始权限状态
        updatePermissionStatus()

        LogService.shared.debug(.audio, "录制器初始化完成，临时目录: \(tempDirectory.path)")
    }

    // 单例不会被释放，无需 deinit

    /// 创建临时目录（如果不存在）
    private func createTempDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: tempDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                LogService.shared.error(.audio, "创建临时目录失败: \(error)")
            }
        }
    }

    // MARK: - 权限管理

    /// 请求麦克风权限
    ///
    /// - Returns: 是否获得授权
    @MainActor
    func requestPermission() async -> Bool {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        switch currentStatus {
        case .authorized:
            updatePermissionStatus(.granted)
            return true

        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if granted {
                updatePermissionStatus(.granted)
            } else {
                LogService.shared.warning(.audio, "用户拒绝麦克风权限")
                updatePermissionStatus(.denied)
            }
            return granted

        case .denied:
            LogService.shared.warning(.audio, "麦克风权限已被拒绝")
            updatePermissionStatus(.denied)
            return false

        case .restricted:
            LogService.shared.warning(.audio, "麦克风权限受限制")
            updatePermissionStatus(.restricted)
            return false

        @unknown default:
            updatePermissionStatus(.denied)
            return false
        }
    }

    /// 检查麦克风权限状态
    ///
    /// - Returns: 当前权限状态
    func checkPermissionStatus() -> PermissionStatus {
        updatePermissionStatus()
        return permissionStatus
    }

    /// 更新权限状态
    private func updatePermissionStatus() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        let newStatus: PermissionStatus = switch status {
        case .authorized:
            .granted
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .denied
        }

        updatePermissionStatus(newStatus)
    }

    /// 更新权限状态并发送通知
    private func updatePermissionStatus(_ newStatus: PermissionStatus) {
        let oldStatus = permissionStatus
        permissionStatus = newStatus

        if oldStatus != newStatus {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Self.permissionStatusDidChangeNotification,
                    object: self,
                    userInfo: [
                        "oldStatus": oldStatus,
                        "newStatus": newStatus,
                    ]
                )
            }
        }
    }

    /// 打开系统偏好设置（麦克风权限）
    ///
    func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 录制控制方法

    /// 开始录制
    ///
    /// - Throws: 录制失败时抛出错误
    func startRecording() throws {

        guard permissionStatus == .granted else {
            let errorMsg = "麦克风权限未授权"
            LogService.shared.error(.audio, errorMsg)
            updateStateInternal(.error(errorMsg))
            throw RecordingError.permissionDenied
        }

        let healthCheck = checkAudioInputHealth()
        if !healthCheck.isHealthy {
            LogService.shared.warning(.audio, "音频输入检查异常: \(healthCheck.message)")
        }

        if audioRecorder?.isRecording == true {
            audioRecorder?.stop()
        }

        recordingDuration = 0
        accumulatedDuration = 0
        audioLevel = 0
        errorMessage = nil

        let fileName = "recording_\(Date().timeIntervalSince1970).m4a"
        let fileURL = tempDirectory.appendingPathComponent(fileName)
        recordedFileURL = fileURL

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: recordingSettings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()

            let success = audioRecorder?.record() ?? false

            if success {
                recordingStartTime = Date()
                updateStateInternal(.recording)
                startTimers()
                LogService.shared.info(.audio, "录制开始: \(fileURL.lastPathComponent)")
            } else {
                let errorMsg = "录制启动失败"
                LogService.shared.error(.audio, errorMsg)
                updateStateInternal(.error(errorMsg))
                throw RecordingError.recordingFailed
            }
        } catch {
            let errorMsg = "创建录制器失败: \(error.localizedDescription)"
            LogService.shared.error(.audio, errorMsg)
            updateStateInternal(.error(errorMsg))
            throw error
        }
    }

    /// 暂停录制
    ///
    func pauseRecording() {

        guard state == .recording, let recorder = audioRecorder else {
            return
        }

        recorder.pause()

        if let startTime = recordingStartTime {
            accumulatedDuration += Date().timeIntervalSince(startTime)
        }
        recordingStartTime = nil

        stopTimers()
        updateStateInternal(.paused)
    }

    /// 继续录制
    ///
    func resumeRecording() {

        guard state == .paused, let recorder = audioRecorder else {
            return
        }

        if recordingDuration >= maxDuration {
            return
        }

        recorder.record()
        recordingStartTime = Date()

        startTimers()
        updateStateInternal(.recording)
    }

    /// 停止录制并返回文件 URL
    ///
    /// - Returns: 录制的音频文件 URL，如果录制失败则返回 nil
    @discardableResult
    func stopRecording() -> URL? {

        guard state == .recording || state == .paused else {
            return nil
        }

        // 停止录制
        audioRecorder?.stop()
        stopTimers()

        // 计算最终时长
        if let startTime = recordingStartTime {
            accumulatedDuration += Date().timeIntervalSince(startTime)
        }
        let finalDuration = accumulatedDuration
        let fileURL = recordedFileURL
        recordingStartTime = nil

        recordingDuration = finalDuration

        updateStateInternal(.finished)

        if let url = fileURL {
            LogService.shared.info(.audio, "录制完成: \(url.lastPathComponent), 时长: \(formatTime(finalDuration))")

            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int64,
               size < 1000
            {
                LogService.shared.warning(.audio, "录制文件过小(\(size)字节)，可能未录到声音")
            }
        }

        postFinishNotification()

        return fileURL
    }

    /// 取消录制
    ///
    func cancelRecording() {

        audioRecorder?.stop()
        stopTimers()

        if let fileURL = recordedFileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }

        resetInternal()
        updateStateInternal(.idle)
    }

    /// 重置录制器状态
    func reset() {

        resetInternal()
        updateStateInternal(.idle)
    }

    /// 内部重置方法（不加锁）
    private func resetInternal() {
        audioRecorder = nil
        recordedFileURL = nil
        recordingDuration = 0
        accumulatedDuration = 0
        audioLevel = 0
        recordingStartTime = nil
        errorMessage = nil
    }

    // MARK: - 录制状态管理

    /// 更新录制状态（内部版本，不加锁）
    private func updateStateInternal(_ newState: RecordingState) {
        let oldState = state
        state = newState

        // 更新错误信息
        if case let .error(message) = newState {
            errorMessage = message
        } else {
            errorMessage = nil
        }

        // 发送状态变化通知
        if oldState != newState {
            postStateNotification(oldState: oldState, newState: newState)
        }
    }

    // MARK: - 定时器管理

    /// 启动所有定时器
    private func startTimers() {
        stopTimers()

        // 录制时长计时器
        recordingTimer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [weak self] _ in
            self?.updateRecordingDuration()
        }

        // 音量监控计时器
        levelTimer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [weak self] _ in
            self?.updateAudioLevel()
        }

        // 确保定时器在 RunLoop 中运行
        if let timer = recordingTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        if let timer = levelTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    /// 停止所有定时器
    private func stopTimers() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil
    }

    /// 停止所有定时器（别名）
    private func stopAllTimers() {
        stopTimers()
    }

    /// 更新录制时长
    private func updateRecordingDuration() {
        guard state == .recording, let startTime = recordingStartTime else { return }

        let currentDuration = accumulatedDuration + Date().timeIntervalSince(startTime)

        // 检查是否达到最大时长
        if currentDuration >= maxDuration {
            DispatchQueue.main.async { [weak self] in
                _ = self?.stopRecording()
            }
            return
        }

        // 更新时长
        if abs(currentDuration - recordingDuration) > 0.01 {
            recordingDuration = currentDuration
            postDurationNotification()
        }
    }

    /// 更新音量级别
    private func updateAudioLevel() {
        guard let recorder = audioRecorder, recorder.isRecording else {
            audioLevel = 0
            return
        }

        // 更新音量计量
        recorder.updateMeters()

        // 获取平均音量（dB）
        let averagePower = recorder.averagePower(forChannel: 0)
        let peakPower = recorder.peakPower(forChannel: 0)

        // 将 dB 值转换为 0.0 - 1.0 的线性值
        // AVAudioRecorder 的 averagePower 范围通常是 -160 到 0 dB
        // 我们将 -60 dB 到 0 dB 映射到 0.0 到 1.0
        let minDb: Float = -60.0
        let maxDb: Float = 0.0

        let normalizedLevel: Float = if averagePower < minDb {
            0.0
        } else if averagePower > maxDb {
            1.0
        } else {
            (averagePower - minDb) / (maxDb - minDb)
        }

        // 平滑处理，避免跳动太大
        let smoothingFactor: Float = 0.3
        let newLevel = audioLevel * (1 - smoothingFactor) + normalizedLevel * smoothingFactor

        if newLevel < 0.01, recordingDuration > 1.0 {
            let seconds = Int(recordingDuration)
            if seconds % 30 == 0, seconds > 0 {
                LogService.shared.warning(.audio, "录制音量持续偏低，请检查麦克风")
            }
        }

        audioLevel = newLevel
    }

    // MARK: - 通知发送

    /// 发送状态变化通知
    private func postStateNotification(oldState: RecordingState, newState: RecordingState) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.recordingStateDidChangeNotification,
                object: self,
                userInfo: [
                    "oldState": oldState,
                    "newState": newState,
                ]
            )
        }
    }

    /// 发送时长变化通知
    private func postDurationNotification() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.recordingDurationDidChangeNotification,
                object: self,
                userInfo: [
                    "duration": self.recordingDuration,
                    "remainingDuration": self.remainingDuration,
                    "formattedDuration": self.formatTime(self.recordingDuration),
                ]
            )
        }
    }

    /// 发送录制完成通知
    private func postFinishNotification() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.recordingDidFinishNotification,
                object: self,
                userInfo: [
                    "fileURL": self.recordedFileURL as Any,
                    "duration": self.recordingDuration,
                ]
            )
        }
    }

    /// 发送录制错误通知
    private func postErrorNotification(_ error: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.recordingErrorNotification,
                object: self,
                userInfo: [
                    "error": error,
                ]
            )
        }
    }

    // MARK: - 辅助方法

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

    /// 格式化剩余时间
    ///
    /// - Returns: 格式化的剩余时间字符串
    func formatRemainingTime() -> String {
        formatTime(remainingDuration)
    }

    /// 获取录制信息
    ///
    /// - Returns: 录制信息字典
    func getRecordingInfo() -> [String: Any] {
        [
            "state": String(describing: state),
            "isRecording": isRecording,
            "isPaused": isPaused,
            "duration": recordingDuration,
            "formattedDuration": formatTime(recordingDuration),
            "remainingDuration": remainingDuration,
            "formattedRemainingDuration": formatRemainingTime(),
            "audioLevel": audioLevel,
            "maxDuration": maxDuration,
            "fileURL": recordedFileURL?.absoluteString as Any,
            "permissionStatus": String(describing: permissionStatus),
        ]
    }

    /// 获取录制的音频文件大小
    ///
    /// - Returns: 文件大小（字节），如果文件不存在则返回 nil
    func getRecordedFileSize() -> Int64? {
        guard let fileURL = recordedFileURL else { return nil }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            return attributes[.size] as? Int64
        } catch {
            return nil
        }
    }

    func cleanupTempFiles() {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
            for file in files {
                try FileManager.default.removeItem(at: file)
            }
        } catch {
            LogService.shared.error(.audio, "清理临时文件失败: \(error)")
        }
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecorderService: AVAudioRecorderDelegate {

    /// 录制完成回调
    nonisolated func audioRecorderDidFinishRecording(_: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            stopTimers()

            if !flag {
                let errorMsg = "录制异常结束"
                LogService.shared.error(.audio, errorMsg)
                updateStateInternal(.error(errorMsg))
                postErrorNotification(errorMsg)
            }
        }
    }

    /// 录制编码错误回调
    nonisolated func audioRecorderEncodeErrorDidOccur(_: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            stopTimers()

            let errorMsg = error?.localizedDescription ?? "音频编码错误"
            LogService.shared.error(.audio, "编码错误: \(errorMsg)")

            updateStateInternal(.error(errorMsg))
            postErrorNotification(errorMsg)
        }
    }
}

// MARK: - 录制错误类型

extension AudioRecorderService {

    /// 录制错误
    enum RecordingError: LocalizedError {
        case permissionDenied // 权限被拒绝
        case recordingFailed // 录制失败
        case encodingFailed // 编码失败
        case fileNotFound // 文件未找到
        case maxDurationReached // 达到最大时长

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                "麦克风权限未授权，请在系统偏好设置中允许访问麦克风"
            case .recordingFailed:
                "录制启动失败，请检查麦克风是否正常工作"
            case .encodingFailed:
                "音频编码失败"
            case .fileNotFound:
                "录音文件未找到"
            case .maxDurationReached:
                "已达到最大录制时长（5分钟）"
            }
        }
    }
}
