import Foundation
import AVFoundation
import Combine
import AppKit

/// 音频录制服务
///
/// 负责音频录制功能，包括：
/// - 麦克风权限管理
/// - 录制控制（开始/暂停/继续/停止/取消）
/// - 录制状态管理
/// - 音量级别监控
/// - 最大时长限制
///
/// Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6
final class AudioRecorderService: NSObject, ObservableObject, @unchecked Sendable {
    
    // MARK: - 单例
    
    static let shared = AudioRecorderService()
    
    // MARK: - 录制状态枚举
    
    /// 录制状态
    enum RecordingState: Equatable {
        case idle           // 空闲
        case preparing      // 准备中
        case recording      // 录制中
        case paused         // 暂停
        case finished       // 完成
        case error(String)  // 错误
        
        static func == (lhs: RecordingState, rhs: RecordingState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.preparing, .preparing), (.recording, .recording),
                 (.paused, .paused), (.finished, .finished):
                return true
            case (.error(let lhsMsg), .error(let rhsMsg)):
                return lhsMsg == rhsMsg
            default:
                return false
            }
        }
    }
    
    // MARK: - 权限状态枚举
    
    /// 麦克风权限状态
    enum PermissionStatus: Equatable {
        case notDetermined  // 未确定
        case granted        // 已授权
        case denied         // 已拒绝
        case restricted     // 受限制
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
        return state == .recording
    }
    
    /// 是否已暂停
    var isPaused: Bool {
        return state == .paused
    }
    
    /// 剩余可录制时长（秒）
    var remainingDuration: TimeInterval {
        return max(0, maxDuration - recordingDuration)
    }
    
    // MARK: - 配置属性
    
    /// 最大录制时长（秒）- 5 分钟
    /// Requirements: 8.5
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
    
    /// 状态访问锁
    private let stateLock = NSLock()
    
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
        AVEncoderBitRateKey: 128000
    ]
    
    // MARK: - 通知名称
    
    /// 录制状态变化通知
    static let recordingStateDidChangeNotification = Notification.Name("AudioRecorderService.recordingStateDidChange")
    
    /// 录制时长变化通知
    static let recordingDurationDidChangeNotification = Notification.Name("AudioRecorderService.recordingDurationDidChange")
    
    /// 录制完成通知
    static let recordingDidFinishNotification = Notification.Name("AudioRecorderService.recordingDidFinish")
    
    /// 录制错误通知
    static let recordingErrorNotification = Notification.Name("AudioRecorderService.recordingError")
    
    /// 权限状态变化通知
    static let permissionStatusDidChangeNotification = Notification.Name("AudioRecorderService.permissionStatusDidChange")

    
    // MARK: - 初始化
    
    private override init() {
        // 配置临时录音文件目录
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("AudioRecordings")
        
        super.init()
        
        // 创建临时目录
        createTempDirectoryIfNeeded()
        
        // 检查初始权限状态
        updatePermissionStatus()
        
        print("[AudioRecorder] 初始化完成")
        print("[AudioRecorder]   - 临时目录: \(tempDirectory.path)")
        print("[AudioRecorder]   - 最大录制时长: \(Int(maxDuration)) 秒")
        print("[AudioRecorder]   - 权限状态: \(permissionStatus)")
    }
    
    deinit {
        stopAllTimers()
        audioRecorder?.stop()
    }
    
    /// 创建临时目录（如果不存在）
    private func createTempDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: tempDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
                print("[AudioRecorder] 创建临时目录: \(tempDirectory.path)")
            } catch {
                print("[AudioRecorder] ❌ 创建临时目录失败: \(error)")
            }
        }
    }
    
    // MARK: - 权限管理
    // Requirements: 8.2, 8.3
    
    /// 请求麦克风权限
    ///
    /// - Returns: 是否获得授权
    /// - Requirements: 8.2
    @MainActor
    func requestPermission() async -> Bool {
        print("[AudioRecorder] 请求麦克风权限...")
        
        // 检查当前权限状态
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch currentStatus {
        case .authorized:
            print("[AudioRecorder] ✅ 麦克风权限已授权")
            updatePermissionStatus(.granted)
            return true
            
        case .notDetermined:
            // 请求权限
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if granted {
                print("[AudioRecorder] ✅ 用户授权麦克风权限")
                updatePermissionStatus(.granted)
            } else {
                print("[AudioRecorder] ❌ 用户拒绝麦克风权限")
                updatePermissionStatus(.denied)
            }
            return granted
            
        case .denied:
            print("[AudioRecorder] ❌ 麦克风权限已被拒绝")
            updatePermissionStatus(.denied)
            return false
            
        case .restricted:
            print("[AudioRecorder] ❌ 麦克风权限受限制")
            updatePermissionStatus(.restricted)
            return false
            
        @unknown default:
            print("[AudioRecorder] ❌ 未知的权限状态")
            updatePermissionStatus(.denied)
            return false
        }
    }
    
    /// 检查麦克风权限状态
    ///
    /// - Returns: 当前权限状态
    /// - Requirements: 8.3
    func checkPermissionStatus() -> PermissionStatus {
        updatePermissionStatus()
        return permissionStatus
    }
    
    /// 更新权限状态
    private func updatePermissionStatus() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        let newStatus: PermissionStatus
        
        switch status {
        case .authorized:
            newStatus = .granted
        case .notDetermined:
            newStatus = .notDetermined
        case .denied:
            newStatus = .denied
        case .restricted:
            newStatus = .restricted
        @unknown default:
            newStatus = .denied
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
                        "newStatus": newStatus
                    ]
                )
            }
        }
    }
    
    /// 打开系统偏好设置（麦克风权限）
    ///
    /// - Requirements: 8.3
    func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
            print("[AudioRecorder] 打开系统偏好设置 - 麦克风权限")
        }
    }

    
    // MARK: - 录制控制方法
    // Requirements: 8.1, 8.6
    
    /// 开始录制
    ///
    /// - Throws: 录制失败时抛出错误
    /// - Requirements: 8.1
    func startRecording() throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        print("[AudioRecorder] 开始录制...")
        
        // 检查权限
        guard permissionStatus == .granted else {
            let errorMsg = "麦克风权限未授权"
            print("[AudioRecorder] ❌ \(errorMsg)")
            updateStateInternal(.error(errorMsg))
            throw RecordingError.permissionDenied
        }
        
        // 如果已经在录制，先停止
        if audioRecorder?.isRecording == true {
            audioRecorder?.stop()
        }
        
        // 重置状态
        recordingDuration = 0
        accumulatedDuration = 0
        audioLevel = 0
        errorMessage = nil
        
        // 生成临时文件路径
        let fileName = "recording_\(Date().timeIntervalSince1970).m4a"
        let fileURL = tempDirectory.appendingPathComponent(fileName)
        recordedFileURL = fileURL
        
        // 创建录制器
        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: recordingSettings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true // 启用音量监控
            audioRecorder?.prepareToRecord()
            
            // 开始录制
            let success = audioRecorder?.record() ?? false
            
            if success {
                recordingStartTime = Date()
                updateStateInternal(.recording)
                startTimers()
                print("[AudioRecorder] ✅ 录制开始: \(fileURL.lastPathComponent)")
            } else {
                let errorMsg = "录制启动失败"
                print("[AudioRecorder] ❌ \(errorMsg)")
                updateStateInternal(.error(errorMsg))
                throw RecordingError.recordingFailed
            }
            
        } catch {
            let errorMsg = "创建录制器失败: \(error.localizedDescription)"
            print("[AudioRecorder] ❌ \(errorMsg)")
            updateStateInternal(.error(errorMsg))
            throw error
        }
    }
    
    /// 暂停录制
    ///
    /// - Requirements: 8.6
    func pauseRecording() {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        guard state == .recording, let recorder = audioRecorder else {
            print("[AudioRecorder] 无法暂停：没有正在进行的录制")
            return
        }
        
        recorder.pause()
        
        // 保存累计时长
        if let startTime = recordingStartTime {
            accumulatedDuration += Date().timeIntervalSince(startTime)
        }
        recordingStartTime = nil
        
        stopTimers()
        updateStateInternal(.paused)
        
        print("[AudioRecorder] 暂停录制，当前时长: \(formatTime(recordingDuration))")
    }
    
    /// 继续录制
    ///
    /// - Requirements: 8.6
    func resumeRecording() {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        guard state == .paused, let recorder = audioRecorder else {
            print("[AudioRecorder] 无法继续：没有暂停的录制")
            return
        }
        
        // 检查是否已达到最大时长
        if recordingDuration >= maxDuration {
            print("[AudioRecorder] 已达到最大录制时长，无法继续")
            return
        }
        
        recorder.record()
        recordingStartTime = Date()
        
        startTimers()
        updateStateInternal(.recording)
        
        print("[AudioRecorder] 继续录制")
    }
    
    /// 停止录制并返回文件 URL
    ///
    /// - Returns: 录制的音频文件 URL，如果录制失败则返回 nil
    /// - Requirements: 8.6
    @discardableResult
    func stopRecording() -> URL? {
        stateLock.lock()
        
        guard state == .recording || state == .paused else {
            print("[AudioRecorder] 无法停止：没有进行中的录制")
            stateLock.unlock()
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
        
        // 先解锁，再更新 @Published 属性（确保在主线程上触发 UI 更新）
        stateLock.unlock()
        
        // 在主线程上更新 @Published 属性
        DispatchQueue.main.async { [weak self] in
            self?.recordingDuration = finalDuration
        }
        
        updateStateInternal(.finished)
        
        print("[AudioRecorder] ✅ 录制完成")
        print("[AudioRecorder]   - 文件: \(fileURL?.lastPathComponent ?? "无")")
        print("[AudioRecorder]   - 时长: \(formatTime(finalDuration))")
        
        // 发送完成通知
        postFinishNotification()
        
        return fileURL
    }
    
    /// 取消录制
    ///
    /// - Requirements: 8.6
    func cancelRecording() {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        print("[AudioRecorder] 取消录制")
        
        // 停止录制
        audioRecorder?.stop()
        stopTimers()
        
        // 删除临时文件
        if let fileURL = recordedFileURL {
            try? FileManager.default.removeItem(at: fileURL)
            print("[AudioRecorder] 删除临时文件: \(fileURL.lastPathComponent)")
        }
        
        // 重置状态
        resetInternal()
        updateStateInternal(.idle)
    }
    
    /// 重置录制器状态
    func reset() {
        stateLock.lock()
        defer { stateLock.unlock() }
        
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
    // Requirements: 8.4, 8.5
    
    /// 更新录制状态（内部版本，不加锁）
    private func updateStateInternal(_ newState: RecordingState) {
        let oldState = state
        state = newState
        
        // 更新错误信息
        if case .error(let message) = newState {
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
    /// Requirements: 8.4
    private func updateRecordingDuration() {
        guard state == .recording, let startTime = recordingStartTime else { return }
        
        let currentDuration = accumulatedDuration + Date().timeIntervalSince(startTime)
        
        // 检查是否达到最大时长
        // Requirements: 8.5
        if currentDuration >= maxDuration {
            print("[AudioRecorder] ⚠️ 达到最大录制时长限制")
            
            // 在主线程上停止录制
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
    /// Requirements: 8.4
    private func updateAudioLevel() {
        guard let recorder = audioRecorder, recorder.isRecording else {
            audioLevel = 0
            return
        }
        
        // 更新音量计量
        recorder.updateMeters()
        
        // 获取平均音量（dB）
        let averagePower = recorder.averagePower(forChannel: 0)
        
        // 将 dB 值转换为 0.0 - 1.0 的线性值
        // AVAudioRecorder 的 averagePower 范围通常是 -160 到 0 dB
        // 我们将 -60 dB 到 0 dB 映射到 0.0 到 1.0
        let minDb: Float = -60.0
        let maxDb: Float = 0.0
        
        let normalizedLevel: Float
        if averagePower < minDb {
            normalizedLevel = 0.0
        } else if averagePower > maxDb {
            normalizedLevel = 1.0
        } else {
            normalizedLevel = (averagePower - minDb) / (maxDb - minDb)
        }
        
        // 平滑处理，避免跳动太大
        let smoothingFactor: Float = 0.3
        audioLevel = audioLevel * (1 - smoothingFactor) + normalizedLevel * smoothingFactor
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
                    "newState": newState
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
                    "formattedDuration": self.formatTime(self.recordingDuration)
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
                    "duration": self.recordingDuration
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
                    "error": error
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
        guard time.isFinite && time >= 0 else { return "0:00" }
        
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// 格式化剩余时间
    ///
    /// - Returns: 格式化的剩余时间字符串
    func formatRemainingTime() -> String {
        return formatTime(remainingDuration)
    }
    
    /// 获取录制信息
    ///
    /// - Returns: 录制信息字典
    func getRecordingInfo() -> [String: Any] {
        return [
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
            "permissionStatus": String(describing: permissionStatus)
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
            print("[AudioRecorder] 获取文件大小失败: \(error)")
            return nil
        }
    }
    
    /// 清理临时录音文件
    func cleanupTempFiles() {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
            for file in files {
                try FileManager.default.removeItem(at: file)
            }
            print("[AudioRecorder] ✅ 清理临时文件完成，共 \(files.count) 个文件")
        } catch {
            print("[AudioRecorder] ❌ 清理临时文件失败: \(error)")
        }
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecorderService: AVAudioRecorderDelegate {
    
    /// 录制完成回调
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        stopTimers()
        
        if flag {
            print("[AudioRecorder] ✅ 录制完成（委托回调）")
            // 状态已在 stopRecording() 中更新
        } else {
            let errorMsg = "录制异常结束"
            print("[AudioRecorder] ❌ \(errorMsg)")
            updateStateInternal(.error(errorMsg))
            postErrorNotification(errorMsg)
        }
    }
    
    /// 录制编码错误回调
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        stopTimers()
        
        let errorMsg = error?.localizedDescription ?? "音频编码错误"
        print("[AudioRecorder] ❌ 编码错误: \(errorMsg)")
        
        updateStateInternal(.error(errorMsg))
        postErrorNotification(errorMsg)
    }
}

// MARK: - 录制错误类型

extension AudioRecorderService {
    
    /// 录制错误
    enum RecordingError: LocalizedError {
        case permissionDenied       // 权限被拒绝
        case recordingFailed        // 录制失败
        case encodingFailed         // 编码失败
        case fileNotFound           // 文件未找到
        case maxDurationReached     // 达到最大时长
        
        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "麦克风权限未授权，请在系统偏好设置中允许访问麦克风"
            case .recordingFailed:
                return "录制启动失败，请检查麦克风是否正常工作"
            case .encodingFailed:
                return "音频编码失败"
            case .fileNotFound:
                return "录音文件未找到"
            case .maxDurationReached:
                return "已达到最大录制时长（5分钟）"
            }
        }
    }
}
