//
//  AudioPanelView.swift
//  MiNoteMac
//
//  音频面板视图 - 显示在主窗口第四栏，提供录制和播放功能
//

import SwiftUI

/// 音频面板视图
///
/// 显示在主窗口第四栏，根据模式显示录制或播放界面。
/// 支持深色背景和橙色主题色，与 Apple Notes 风格一致。
///
struct AudioPanelView: View {

    // MARK: - Properties

    /// 状态管理器
    @ObservedObject var stateManager: AudioPanelStateManager

    /// 录制服务
    @ObservedObject var recorderService: AudioRecorderService

    /// 播放服务
    @ObservedObject var playerService: AudioPlayerService

    /// 录制完成回调
    let onRecordingComplete: (URL) -> Void

    /// 关闭回调
    let onClose: () -> Void

    /// 是否显示更多选项菜单
    @State private var showMoreOptions = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            panelHeader

            Divider()
                .background(Color.secondary.opacity(0.3))

            // 内容区域（根据模式切换）
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 280, maxWidth: 400)
        .background(panelBackground)
    }

    // MARK: - 标题栏

    /// 面板标题栏
    private var panelHeader: some View {
        HStack(spacing: 12) {
            // 关闭按钮
            Button(action: handleClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("关闭面板")

            // 标题
            VStack(alignment: .leading, spacing: 2) {
                Text(panelTitle)
                    .font(.headline)
                    .foregroundColor(.primary)

                if let subtitle = panelSubtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // 更多选项按钮
            Menu {
                moreOptionsMenu
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28, height: 28)
            .help("更多选项")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    /// 面板标题
    private var panelTitle: String {
        switch stateManager.mode {
        case .recording:
            "录制语音"
        case .playback:
            "语音录音"
        }
    }

    /// 面板副标题
    private var panelSubtitle: String? {
        switch stateManager.mode {
        case .recording:
            switch recorderService.state {
            case .recording:
                return "正在录制..."
            case .paused:
                return "已暂停"
            case .finished:
                return "录制完成"
            default:
                return nil
            }
        case .playback:
            if playerService.isPlaying {
                return "正在播放"
            } else if playerService.currentURL != nil {
                return "已暂停"
            }
            return nil
        }
    }

    /// 更多选项菜单
    @ViewBuilder
    private var moreOptionsMenu: some View {
        if stateManager.mode == .recording {
            Button("重置录制") {
                recorderService.reset()
            }
            .disabled(recorderService.state == .recording || recorderService.state == .paused)
        } else {
            Button("停止播放") {
                playerService.stop()
            }
            .disabled(!playerService.isPlaying)
        }

        Divider()

        Button("关闭面板") {
            handleClose()
        }
    }

    // MARK: - 内容区域

    /// 内容区域（根据模式切换）
    @ViewBuilder
    private var contentArea: some View {
        switch stateManager.mode {
        case .recording:
            AudioPanelRecordingContent(
                recorderService: recorderService,
                playerService: playerService,
                onComplete: onRecordingComplete,
                onCancel: handleClose
            )
        case .playback:
            AudioPanelPlaybackContent(
                playerService: playerService,
                fileId: stateManager.currentFileId ?? "",
                onClose: handleClose
            )
        }
    }

    // MARK: - 背景

    /// 面板背景
    private var panelBackground: some View {
        Color(NSColor.controlBackgroundColor)
    }

    // MARK: - Actions

    /// 处理关闭
    private func handleClose() {
        // 检查是否可以安全关闭
        if stateManager.canClose() {
            // 停止播放
            if playerService.isPlaying {
                playerService.stop()
            }
            onClose()
        } else {
            // 需要确认对话框（由外部处理）
            NotificationCenter.default.post(
                name: AudioPanelStateManager.needsConfirmationNotification,
                object: stateManager
            )
        }
    }
}

// MARK: - Preview

#Preview("Recording Mode") {
    AudioPanelView(
        stateManager: AudioPanelStateManager.shared,
        recorderService: .shared,
        playerService: .shared,
        onRecordingComplete: { _ in },
        onClose: {}
    )
    .frame(width: 320, height: 500)
}

// MARK: - 录制模式内容

/// 音频面板录制模式内容
///
/// 显示录制控件，包括：
/// - 录制时长显示
/// - 音量指示器
/// - 录制/暂停/停止按钮
/// - 预览和确认界面
///
struct AudioPanelRecordingContent: View {

    // MARK: - Properties

    /// 录制服务
    @ObservedObject var recorderService: AudioRecorderService

    /// 播放服务（用于预览）
    @ObservedObject var playerService: AudioPlayerService

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

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

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

            Spacer()
        }
        .padding(24)
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

    // MARK: - 空闲状态视图

    private var idleView: some View {
        VStack(spacing: 32) {
            // 麦克风图标
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "mic.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.red)
            }

            // 提示文字
            VStack(spacing: 8) {
                Text("点击下方按钮开始录制")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // 最大时长提示
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text("最长录制 \(formatTime(recorderService.maxDuration))")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }

            // 录制按钮
            recordButton
        }
    }

    // MARK: - 录制中视图

    private var recordingView: some View {
        VStack(spacing: 24) {
            // 录制指示器
            if viewState == .recording {
                recordingIndicator
            }

            // 录制时长显示
            durationDisplay

            // 音量指示器
            audioLevelMeter

            // 剩余时间提示
            remainingTimeHint

            Spacer()
                .frame(height: 20)

            // 控制按钮
            recordingControlButtons
        }
    }

    /// 录制指示器（红色闪烁点）
    private var recordingIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
                .opacity(viewState == .recording ? 1.0 : 0.3)
                .animation(
                    viewState == .recording ?
                        .easeInOut(duration: 0.8).repeatForever(autoreverses: true) :
                        .default,
                    value: viewState
                )

            Text("正在录制")
                .font(.caption)
                .foregroundColor(.red)
        }
    }

    /// 录制时长显示
    private var durationDisplay: some View {
        Text(formatTime(recorderService.recordingDuration))
            .font(.system(size: 56, weight: .light, design: .monospaced))
            .foregroundColor(viewState == .recording ? .red : .primary)
            .animation(.easeInOut(duration: 0.3), value: viewState)
    }

    /// 音量指示器
    private var audioLevelMeter: some View {
        AudioLevelMeterView(
            level: recorderService.audioLevel,
            isActive: viewState == .recording
        )
        .frame(height: 8)
        .padding(.horizontal, 20)
    }

    /// 剩余时间提示
    private var remainingTimeHint: some View {
        Group {
            if viewState == .recording || viewState == .paused {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text("剩余 \(recorderService.formatRemainingTime())")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
        }
    }

    /// 录制按钮
    private var recordButton: some View {
        Button(action: startRecording) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: 88, height: 88)

                Circle()
                    .fill(Color.red)
                    .frame(width: 72, height: 72)

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
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 56, height: 56)

                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    Text("取消")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            // 暂停/继续按钮
            Button(action: togglePauseResume) {
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(viewState == .paused ? Color.orange : Color.orange.opacity(0.2))
                            .frame(width: 64, height: 64)

                        Image(systemName: viewState == .paused ? "play.fill" : "pause.fill")
                            .font(.title2)
                            .foregroundColor(viewState == .paused ? .white : .orange)
                    }
                    Text(viewState == .paused ? "继续" : "暂停")
                        .font(.caption)
                        .foregroundColor(.primary)
                }
            }
            .buttonStyle(.plain)

            // 停止按钮
            Button(action: stopRecording) {
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 56, height: 56)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white)
                            .frame(width: 22, height: 22)
                    }
                    Text("完成")
                        .font(.caption)
                        .foregroundColor(.primary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 预览视图

    private var previewView: some View {
        VStack(spacing: 24) {
            // 完成图标
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.green)
            }

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

            Spacer()
                .frame(height: 20)

            // 操作按钮
            previewActionButtons
        }
    }

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
            if recordedFileURL != nil {
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
                .frame(width: 140)
            }
        }
        .padding(.horizontal, 20)
    }

    /// 预览操作按钮
    private var previewActionButtons: some View {
        HStack(spacing: 16) {
            // 重录按钮
            Button(action: reRecord) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("重录")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)

            // 确认按钮
            Button(action: confirmRecording) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                    Text("确认")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - 错误视图

    private var errorView: some View {
        VStack(spacing: 20) {
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
            .tint(.orange)
        }
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
            loadAudioForPreview(fileURL)
        } else {
            errorMessage = "录制失败，请重试"
            viewState = .error
        }
    }

    /// 加载音频用于预览
    private func loadAudioForPreview(_ url: URL) {
        if playerService.getDuration(for: url) == nil {
            LogService.shared.warning(.audio, "无法获取音频时长")
        }
    }

    /// 切换预览播放
    private func togglePreviewPlayback() {
        if playerService.isPlaying {
            playerService.pause()
        } else if let url = recordedFileURL {
            if playerService.currentURL != url || playerService.playbackState == .idle {
                do {
                    try playerService.play(url: url)
                } catch {
                    LogService.shared.error(.audio, "播放预览失败: \(error)")
                }
            } else {
                do {
                    try playerService.play(url: url)
                } catch {
                    LogService.shared.error(.audio, "继续播放失败: \(error)")
                }
            }
        }
    }

    /// 重新录制
    private func reRecord() {
        playerService.stop()

        if let url = recordedFileURL {
            try? FileManager.default.removeItem(at: url)
        }

        recordedFileURL = nil
        recorderService.reset()
        viewState = .idle
    }

    /// 确认录制
    private func confirmRecording() {
        playerService.stop()

        if let url = recordedFileURL {
            onComplete(url)
        }
    }

    /// 处理取消
    private func handleCancel() {
        playerService.stop()
        recorderService.cancelRecording()

        if let url = recordedFileURL {
            try? FileManager.default.removeItem(at: url)
        }

        onCancel()
    }

    /// 清理资源
    private func cleanup() {
        playerService.stop()

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

// MARK: - 播放模式内容

/// 音频面板播放模式内容
///
/// 显示播放控件，包括：
/// - 播放进度条
/// - 当前时间和总时长
/// - 播放/暂停/跳转控制按钮
///
struct AudioPanelPlaybackContent: View {

    // MARK: - Properties

    /// 播放服务
    @ObservedObject var playerService: AudioPlayerService

    /// 文件 ID
    let fileId: String

    /// 关闭回调
    let onClose: () -> Void

    /// 是否正在拖动进度条
    @State private var isDragging = false

    /// 拖动时的临时进度值
    @State private var dragProgress: Double = 0

    /// 是否正在加载
    @State private var isLoading = false

    /// 错误信息
    @State private var errorMessage: String?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if let error = errorMessage {
                errorView(message: error)
            } else if isLoading {
                loadingView
            } else {
                playbackContent
            }

            Spacer()
        }
        .padding(24)
    }

    // MARK: - 播放内容

    private var playbackContent: some View {
        VStack(spacing: 32) {
            // 波形图标
            waveformIcon

            // 时间显示
            timeDisplay

            // 进度条
            progressBar

            // 控制按钮
            controlButtons
        }
    }

    /// 波形图标
    private var waveformIcon: some View {
        ZStack {
            Circle()
                .fill(Color.orange.opacity(0.1))
                .frame(width: 100, height: 100)

            // 波形动画
            HStack(spacing: 4) {
                ForEach(0 ..< 5, id: \.self) { index in
                    waveformBar(index: index)
                }
            }
        }
    }

    /// 波形条
    private func waveformBar(index: Int) -> some View {
        let isPlaying = playerService.isPlaying && isCurrentFile
        let baseHeight: CGFloat = 20
        let maxHeight: CGFloat = 40

        return RoundedRectangle(cornerRadius: 2)
            .fill(Color.orange)
            .frame(width: 6, height: isPlaying ? maxHeight : baseHeight)
            .animation(
                isPlaying ?
                    .easeInOut(duration: 0.3)
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.1) :
                    .default,
                value: isPlaying
            )
    }

    /// 时间显示
    private var timeDisplay: some View {
        VStack(spacing: 8) {
            // 当前时间
            Text(formattedCurrentTime)
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundColor(.primary)

            // 总时长
            Text("/ \(formattedDuration)")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    /// 进度条
    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 背景轨道
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 8)

                // 进度填充
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.orange)
                    .frame(width: progressWidth(for: geometry.size.width), height: 8)

                // 进度指示点
                Circle()
                    .fill(Color.orange)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                    .offset(x: indicatorOffset(for: geometry.size.width))
            }
            .frame(height: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let progress = max(0, min(1, value.location.x / geometry.size.width))
                        dragProgress = progress
                    }
                    .onEnded { value in
                        let progress = max(0, min(1, value.location.x / geometry.size.width))
                        playerService.seek(to: progress)
                        isDragging = false
                    }
            )
        }
        .frame(height: 18)
        .padding(.horizontal, 20)
    }

    /// 控制按钮
    private var controlButtons: some View {
        HStack(spacing: 32) {
            // 后退 15 秒
            Button(action: { playerService.skipBackward(15) }) {
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 52, height: 52)

                    Image(systemName: "gobackward.15")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
            }
            .buttonStyle(.plain)
            .disabled(!isCurrentFile)

            // 播放/暂停按钮
            Button(action: togglePlayPause) {
                ZStack {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 72, height: 72)

                    if playerService.isLoading, isCurrentFile {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: playPauseIcon)
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(playerService.isLoading && isCurrentFile)

            // 前进 15 秒
            Button(action: { playerService.skipForward(15) }) {
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 52, height: 52)

                    Image(systemName: "goforward.15")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
            }
            .buttonStyle(.plain)
            .disabled(!isCurrentFile)
        }
    }

    // MARK: - 加载视图

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("加载中...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 错误视图

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("关闭") {
                onClose()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
    }

    // MARK: - Computed Properties

    /// 是否为当前播放的文件
    private var isCurrentFile: Bool {
        playerService.currentFileId == fileId
    }

    /// 当前进度（考虑拖动状态）
    private var currentProgress: Double {
        if isDragging {
            return dragProgress
        }
        return isCurrentFile ? playerService.progress : 0
    }

    /// 格式化的当前时间
    private var formattedCurrentTime: String {
        if isDragging {
            let time = playerService.duration * dragProgress
            return playerService.formatTime(time)
        }
        return isCurrentFile ? playerService.formatTime(playerService.currentTime) : "0:00"
    }

    /// 格式化的总时长
    private var formattedDuration: String {
        isCurrentFile ? playerService.formatTime(playerService.duration) : "0:00"
    }

    /// 播放/暂停图标
    private var playPauseIcon: String {
        if isCurrentFile, playerService.isPlaying {
            return "pause.fill"
        }
        return "play.fill"
    }

    // MARK: - Helper Methods

    /// 计算进度条宽度
    private func progressWidth(for totalWidth: CGFloat) -> CGFloat {
        totalWidth * CGFloat(currentProgress)
    }

    /// 计算指示点偏移
    private func indicatorOffset(for totalWidth: CGFloat) -> CGFloat {
        let progress = CGFloat(currentProgress)
        let indicatorRadius: CGFloat = 9
        return (totalWidth - indicatorRadius * 2) * progress
    }

    /// 切换播放/暂停状态
    private func togglePlayPause() {
        if isCurrentFile {
            playerService.togglePlayPause()
        } else {
            // 如果不是当前文件，需要先加载
            playerService.togglePlayPause()
        }
    }
}

// MARK: - Preview

#Preview("Playback Mode") {
    AudioPanelPlaybackContent(
        playerService: .shared,
        fileId: "test-file-id",
        onClose: {}
    )
    .frame(width: 320, height: 500)
    .background(Color(NSColor.controlBackgroundColor))
}
