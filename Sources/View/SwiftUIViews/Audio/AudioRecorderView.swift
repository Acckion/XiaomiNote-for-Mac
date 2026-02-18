//
//  AudioRecorderView.swift
//  MiNoteMac
//
//  音频录制器视图 - 用于录制语音
//  需求: 8.1, 8.4, 8.6, 8.7
//

import AVFoundation
import SwiftUI

/// 音频录制器视图
///
/// 显示音频录制控件，包括：
/// - 录制时长显示
/// - 音量指示器
/// - 录制/停止/取消按钮
/// - 录制完成后的预览界面
///
struct AudioRecorderView: View {

    // MARK: - Properties

    /// 录制服务
    @ObservedObject private var recorderService: AudioRecorderService

    /// 播放服务（用于预览）
    @ObservedObject private var playerService: AudioPlayerService

    /// 录制完成回调
    let onComplete: (URL) -> Void

    /// 取消回调
    let onCancel: () -> Void

    /// 当前视图状态
    @State private var viewState: ViewState = .idle

    /// 录制完成的文件 URL
    @State private var recordedFileURL: URL?

    /// 错误信息
    @State private var errorMessage: String?

    /// 是否显示权限提示
    @State private var showPermissionAlert = false

    // MARK: - View State

    /// 视图状态枚举
    enum ViewState {
        case idle // 空闲，准备录制
        case recording // 录制中
        case paused // 暂停
        case preview // 预览录制结果
        case error // 错误状态
    }

    // MARK: - Initialization

    /// 初始化音频录制器视图
    /// - Parameters:
    ///   - recorderService: 录制服务（默认使用共享实例）
    ///   - playerService: 播放服务（默认使用共享实例）
    ///   - onComplete: 录制完成回调，传入录制的文件 URL
    ///   - onCancel: 取消回调
    init(
        recorderService: AudioRecorderService = .shared,
        playerService: AudioPlayerService = .shared,
        onComplete: @escaping (URL) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.recorderService = recorderService
        self.playerService = playerService
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 20) {
            // 标题栏
            titleBar

            // 根据状态显示不同内容
            switch viewState {
            case .idle:
                idleView
            case .recording, .paused:
                recordingView
            case .preview:
                previewView
            case .error:
                errorView
            }
        }
        .padding(24)
        .frame(width: 320)
        .background(backgroundView)
        .onAppear {
            checkPermission()
        }
        .onDisappear {
            cleanup()
        }
        .onChange(of: recorderService.state) { _, newState in
            handleRecorderStateChange(newState)
        }
        .alert("需要麦克风权限", isPresented: $showPermissionAlert) {
            Button("打开系统设置") {
                recorderService.openSystemPreferences()
            }
            Button("取消", role: .cancel) {
                onCancel()
            }
        } message: {
            Text("请在系统偏好设置中允许访问麦克风，以便录制语音。")
        }
    }

    // MARK: - Subviews

    /// 标题栏
    private var titleBar: some View {
        HStack {
            // 麦克风图标
            Image(systemName: "mic.fill")
                .foregroundColor(.red)
                .font(.title2)

            Text(titleText)
                .font(.headline)

            Spacer()

            // 关闭按钮
            Button(action: handleCancel) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
    }

    /// 标题文本
    private var titleText: String {
        switch viewState {
        case .idle:
            "录制语音"
        case .recording:
            "正在录制"
        case .paused:
            "已暂停"
        case .preview:
            "预览录音"
        case .error:
            "录制失败"
        }
    }

    /// 空闲状态视图
    private var idleView: some View {
        VStack(spacing: 24) {
            // 提示文字
            Text("点击下方按钮开始录制")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // 最大时长提示
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                Text("最长录制 \(formatTime(recorderService.maxDuration))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 录制按钮
            recordButton
        }
    }

    /// 录制中视图
    private var recordingView: some View {
        VStack(spacing: 20) {
            // 录制时长显示
            durationDisplay

            // 音量指示器
            audioLevelMeter

            // 剩余时间提示
            remainingTimeHint

            // 控制按钮
            recordingControlButtons
        }
    }

    /// 预览视图
    private var previewView: some View {
        VStack(spacing: 20) {
            // 录制时长显示
            VStack(spacing: 8) {
                Text("录制完成")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(formatTime(recorderService.recordingDuration))
                    .font(.system(size: 36, weight: .light, design: .monospaced))
            }

            // 播放控制
            previewPlaybackControls

            // 操作按钮
            previewActionButtons
        }
    }

    /// 错误视图
    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)

            Text(errorMessage ?? "录制失败")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("重试") {
                viewState = .idle
                errorMessage = nil
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// 背景视图
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(NSColor.controlBackgroundColor))
            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

    // MARK: - Recording Components

    /// 录制时长显示
    private var durationDisplay: some View {
        Text(formatTime(recorderService.recordingDuration))
            .font(.system(size: 48, weight: .light, design: .monospaced))
            .foregroundColor(viewState == .recording ? .red : .primary)
            .animation(.easeInOut(duration: 0.3), value: viewState)
    }

    /// 音量指示器
    private var audioLevelMeter: some View {
        AudioLevelMeterView(level: recorderService.audioLevel, isActive: viewState == .recording)
            .frame(height: 8)
            .padding(.horizontal, 20)
    }

    /// 剩余时间提示
    private var remainingTimeHint: some View {
        Group {
            if viewState == .recording || viewState == .paused {
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                    Text("剩余 \(recorderService.formatRemainingTime())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    /// 录制按钮
    private var recordButton: some View {
        Button(action: startRecording) {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 72, height: 72)

                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: 88, height: 88)

                Image(systemName: "mic.fill")
                    .font(.title)
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
    }

    /// 录制控制按钮
    private var recordingControlButtons: some View {
        HStack(spacing: 40) {
            // 取消按钮
            Button(action: handleCancel) {
                VStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("取消")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            // 暂停/继续按钮
            Button(action: togglePauseResume) {
                ZStack {
                    Circle()
                        .fill(viewState == .paused ? Color.orange : Color.orange.opacity(0.2))
                        .frame(width: 64, height: 64)

                    Image(systemName: viewState == .paused ? "play.fill" : "pause.fill")
                        .font(.title2)
                        .foregroundColor(viewState == .paused ? .white : .orange)
                }
            }
            .buttonStyle(.plain)

            // 停止按钮
            Button(action: stopRecording) {
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 64, height: 64)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white)
                            .frame(width: 24, height: 24)
                    }
                    Text("完成")
                        .font(.caption)
                        .foregroundColor(.primary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Preview Components

    /// 预览播放控制
    private var previewPlaybackControls: some View {
        HStack(spacing: 20) {
            // 播放/暂停按钮
            Button(action: togglePreviewPlayback) {
                ZStack {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 56, height: 56)

                    Image(systemName: playerService.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)

            // 进度条
            if let _ = recordedFileURL {
                VStack(spacing: 4) {
                    // 进度条
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.orange)
                                .frame(width: geometry.size.width * CGFloat(playerService.progress), height: 6)
                        }
                    }
                    .frame(height: 6)

                    // 时间显示
                    HStack {
                        Text(playerService.formatTime(playerService.currentTime))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(playerService.formatTime(playerService.duration))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 160)
            }
        }
        .padding(.horizontal, 20)
    }

    /// 预览操作按钮
    private var previewActionButtons: some View {
        HStack(spacing: 16) {
            // 重录按钮
            Button(action: reRecord) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("重录")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            // 确认按钮
            Button(action: confirmRecording) {
                HStack {
                    Image(systemName: "checkmark")
                    Text("确认")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Actions

    /// 检查麦克风权限
    private func checkPermission() {
        Task {
            let status = recorderService.checkPermissionStatus()
            if status == .notDetermined {
                let granted = await recorderService.requestPermission()
                if !granted {
                    await MainActor.run {
                        showPermissionAlert = true
                    }
                }
            } else if status == .denied || status == .restricted {
                await MainActor.run {
                    showPermissionAlert = true
                }
            }
        }
    }

    /// 开始录制
    private func startRecording() {
        do {
            try recorderService.startRecording()
            viewState = .recording
        } catch {
            errorMessage = error.localizedDescription
            viewState = .error
        }
    }

    /// 切换暂停/继续
    private func togglePauseResume() {
        if viewState == .recording {
            recorderService.pauseRecording()
            viewState = .paused
        } else if viewState == .paused {
            recorderService.resumeRecording()
            viewState = .recording
        }
    }

    /// 停止录制
    private func stopRecording() {
        if let fileURL = recorderService.stopRecording() {
            recordedFileURL = fileURL
            viewState = .preview

            // 加载音频用于预览
            loadAudioForPreview(fileURL)
        } else {
            errorMessage = "录制失败，请重试"
            viewState = .error
        }
    }

    /// 加载音频用于预览
    /// 不再自动播放然后暂停，只验证文件可以被加载
    private func loadAudioForPreview(_ url: URL) {
        // 只验证文件可以被加载，不自动播放
        if let duration = playerService.getDuration(for: url) {
            print("[AudioRecorderView] ✅ 预览音频加载成功，时长: \(formatTime(duration))")
        } else {
            print("[AudioRecorderView] ⚠️ 无法获取音频时长，文件可能无法播放")
        }
    }

    /// 切换预览播放
    /// 确保从头开始播放时正确初始化
    private func togglePreviewPlayback() {
        if playerService.isPlaying {
            // 正在播放，暂停
            playerService.pause()
        } else if let url = recordedFileURL {
            // 没有在播放，开始播放
            // 如果当前播放的不是预览文件，或者播放器处于空闲状态，需要重新加载
            if playerService.currentURL != url || playerService.playbackState == .idle {
                do {
                    try playerService.play(url: url)
                    print("[AudioRecorderView] ✅ 开始预览播放")
                } catch {
                    print("[AudioRecorderView] ❌ 播放预览失败: \(error)")
                }
            } else {
                // 已经加载了同一个文件，继续播放
                do {
                    try playerService.play(url: url)
                    print("[AudioRecorderView] ✅ 继续预览播放")
                } catch {
                    print("[AudioRecorderView] ❌ 继续播放失败: \(error)")
                }
            }
        }
    }

    /// 重新录制
    private func reRecord() {
        // 停止播放
        playerService.stop()

        // 删除已录制的文件
        if let url = recordedFileURL {
            try? FileManager.default.removeItem(at: url)
        }

        // 重置状态
        recordedFileURL = nil
        recorderService.reset()
        viewState = .idle
    }

    /// 确认录制
    private func confirmRecording() {
        print("[AudioRecorderView] 确认录制，准备停止播放并回调")

        // 停止播放
        playerService.stop()

        // 调用完成回调
        if let url = recordedFileURL {
            print("[AudioRecorderView] 调用完成回调: \(url.lastPathComponent)")
            onComplete(url)
        }
    }

    /// 处理取消
    private func handleCancel() {
        // 停止播放
        playerService.stop()

        // 取消录制
        recorderService.cancelRecording()

        // 删除已录制的文件
        if let url = recordedFileURL {
            try? FileManager.default.removeItem(at: url)
        }

        onCancel()
    }

    /// 清理资源
    private func cleanup() {
        print("[AudioRecorderView] cleanup() 被调用，停止播放")
        playerService.stop()

        // 如果还在录制中，取消录制
        if recorderService.isRecording || recorderService.isPaused {
            recorderService.cancelRecording()
        }
    }

    /// 处理录制器状态变化
    private func handleRecorderStateChange(_ newState: AudioRecorderService.RecordingState) {
        switch newState {
        case .idle:
            if viewState != .preview {
                viewState = .idle
            }
        case .recording:
            viewState = .recording
        case .paused:
            viewState = .paused
        case .finished:
            // 状态由 stopRecording() 处理
            break
        case let .error(message):
            errorMessage = message
            viewState = .error
        case .preparing:
            break
        }
    }

    // MARK: - Helper Methods

    /// 格式化时间
    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }

        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Audio Level Meter View

/// 音量指示器视图
struct AudioLevelMeterView: View {

    /// 音量级别（0.0 - 1.0）
    let level: Float

    /// 是否激活
    let isActive: Bool

    /// 条形数量
    private let barCount = 20

    /// 条形间距
    private let barSpacing: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: barSpacing) {
                ForEach(0 ..< barCount, id: \.self) { index in
                    barView(for: index, totalWidth: geometry.size.width)
                }
            }
        }
    }

    /// 单个条形视图
    private func barView(for index: Int, totalWidth: CGFloat) -> some View {
        let barWidth = (totalWidth - CGFloat(barCount - 1) * barSpacing) / CGFloat(barCount)
        let threshold = Float(index) / Float(barCount)
        let isLit = isActive && level > threshold

        return RoundedRectangle(cornerRadius: 2)
            .fill(barColor(for: index, isLit: isLit))
            .frame(width: barWidth)
            .animation(.easeOut(duration: 0.1), value: isLit)
    }

    /// 条形颜色
    private func barColor(for index: Int, isLit: Bool) -> Color {
        if !isLit {
            return Color.secondary.opacity(0.2)
        }

        let ratio = Float(index) / Float(barCount)

        if ratio < 0.6 {
            return .green
        } else if ratio < 0.8 {
            return .yellow
        } else {
            return .red
        }
    }
}

// MARK: - Audio Recorder Sheet View

/// 音频录制器 Sheet 视图（用于从其他视图弹出）
struct AudioRecorderSheetView: View {

    @Environment(\.dismiss) private var dismiss

    /// 录制完成回调
    let onComplete: (URL) -> Void

    var body: some View {
        AudioRecorderView(
            onComplete: { url in
                onComplete(url)
                dismiss()
            },
            onCancel: {
                dismiss()
            }
        )
    }
}

// MARK: - Audio Recorder Popover View

/// 音频录制器弹出视图
struct AudioRecorderPopoverView: View {

    /// 录制完成回调
    let onComplete: (URL) -> Void

    /// 关闭回调
    let onDismiss: () -> Void

    var body: some View {
        AudioRecorderView(
            onComplete: { url in
                onComplete(url)
                onDismiss()
            },
            onCancel: onDismiss
        )
    }
}

// MARK: - Preview

#Preview("Idle State") {
    AudioRecorderView(
        onComplete: { url in
            print("Recording completed: \(url)")
        },
        onCancel: {
            print("Recording cancelled")
        }
    )
    .padding()
}

#Preview("Audio Level Meter") {
    VStack(spacing: 20) {
        AudioLevelMeterView(level: 0.0, isActive: true)
            .frame(height: 8)

        AudioLevelMeterView(level: 0.3, isActive: true)
            .frame(height: 8)

        AudioLevelMeterView(level: 0.6, isActive: true)
            .frame(height: 8)

        AudioLevelMeterView(level: 0.9, isActive: true)
            .frame(height: 8)

        AudioLevelMeterView(level: 0.5, isActive: false)
            .frame(height: 8)
    }
    .padding()
    .frame(width: 300)
}
