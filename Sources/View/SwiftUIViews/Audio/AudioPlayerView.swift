//
//  AudioPlayerView.swift
//  MiNoteMac
//
//  音频播放器视图 - 用于显示音频播放控件
//  需求: 7.2, 7.3, 7.4, 7.6
//

import SwiftUI
import Combine

/// 音频播放器视图
///
/// 显示音频播放控件，包括：
/// - 播放进度条
/// - 当前时间和总时长
/// - 播放/暂停/跳转控制按钮
/// 
struct AudioPlayerView: View {
    
    // MARK: - Properties
    
    /// 播放器服务
    @ObservedObject private var playerService: AudioPlayerService
    
    /// 文件 ID
    let fileId: String
    
    /// 关闭回调
    let onClose: (() -> Void)?
    
    /// 是否显示关闭按钮
    let showCloseButton: Bool
    
    /// 是否为紧凑模式
    let isCompact: Bool
    
    /// 是否正在拖动进度条
    @State private var isDragging: Bool = false
    
    /// 拖动时的临时进度值
    @State private var dragProgress: Double = 0
    
    // MARK: - Initialization
    
    /// 初始化音频播放器视图
    /// - Parameters:
    ///   - fileId: 文件 ID
    ///   - playerService: 播放器服务（默认使用共享实例）
    ///   - showCloseButton: 是否显示关闭按钮
    ///   - isCompact: 是否为紧凑模式
    ///   - onClose: 关闭回调
    init(
        fileId: String,
        playerService: AudioPlayerService = .shared,
        showCloseButton: Bool = true,
        isCompact: Bool = false,
        onClose: (() -> Void)? = nil
    ) {
        self.fileId = fileId
        self.playerService = playerService
        self.showCloseButton = showCloseButton
        self.isCompact = isCompact
        self.onClose = onClose
    }
    
    // MARK: - Body
    
    var body: some View {
        if isCompact {
            compactLayout
        } else {
            standardLayout
        }
    }
    
    // MARK: - Standard Layout
    
    /// 标准布局
    private var standardLayout: some View {
        VStack(spacing: 12) {
            // 标题栏（带关闭按钮）
            if showCloseButton {
                titleBar
            }
            
            // 播放进度条
            progressBar
            
            // 时间显示
            timeDisplay
            
            // 播放控制按钮
            controlButtons
        }
        .padding()
        .background(backgroundView)
    }
    
    // MARK: - Compact Layout
    
    /// 紧凑布局（用于内嵌显示）
    private var compactLayout: some View {
        HStack(spacing: 12) {
            // 播放/暂停按钮
            playPauseButton
                .frame(width: 32, height: 32)
            
            // 进度条和时间
            VStack(spacing: 4) {
                progressBar
                
                HStack {
                    Text(formattedCurrentTime)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formattedDuration)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(backgroundView)
    }
    
    // MARK: - Subviews
    
    /// 标题栏
    private var titleBar: some View {
        HStack {
            // 音频图标
            Image(systemName: "waveform")
                .foregroundColor(.orange)
            
            Text("语音录音")
                .font(.headline)
            
            Spacer()
            
            // 关闭按钮
            Button(action: { onClose?() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
    
    /// 播放进度条
    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 背景轨道
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 6)
                
                // 进度填充
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.orange)
                    .frame(width: progressWidth(for: geometry.size.width), height: 6)
                
                // 进度指示点
                Circle()
                    .fill(Color.orange)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                    .offset(x: indicatorOffset(for: geometry.size.width))
            }
            .frame(height: 14)
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
        .frame(height: 14)
    }
    
    /// 时间显示
    private var timeDisplay: some View {
        HStack {
            Text(formattedCurrentTime)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(formattedDuration)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
    
    /// 播放控制按钮
    private var controlButtons: some View {
        HStack(spacing: 24) {
            // 后退 15 秒
            Button(action: { playerService.skipBackward(15) }) {
                Image(systemName: "gobackward.15")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)
            .disabled(!isCurrentFile)
            
            // 播放/暂停按钮
            playPauseButton
                .frame(width: 48, height: 48)
            
            // 前进 15 秒
            Button(action: { playerService.skipForward(15) }) {
                Image(systemName: "goforward.15")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)
            .disabled(!isCurrentFile)
        }
    }
    
    /// 播放/暂停按钮
    private var playPauseButton: some View {
        Button(action: togglePlayPause) {
            ZStack {
                Circle()
                    .fill(Color.orange)
                
                if playerService.isLoading && isCurrentFile {
                    // 加载中显示进度指示器
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: playPauseIcon)
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(playerService.isLoading && isCurrentFile)
    }
    
    /// 背景视图
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(NSColor.controlBackgroundColor))
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
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
        if isCurrentFile && playerService.isPlaying {
            return "pause.fill"
        }
        return "play.fill"
    }
    
    // MARK: - Helper Methods
    
    /// 计算进度条宽度
    /// - Parameter totalWidth: 总宽度
    /// - Returns: 进度条宽度
    private func progressWidth(for totalWidth: CGFloat) -> CGFloat {
        return totalWidth * CGFloat(currentProgress)
    }
    
    /// 计算指示点偏移
    /// - Parameter totalWidth: 总宽度
    /// - Returns: 指示点偏移量
    private func indicatorOffset(for totalWidth: CGFloat) -> CGFloat {
        let progress = CGFloat(currentProgress)
        let indicatorRadius: CGFloat = 7
        return (totalWidth - indicatorRadius * 2) * progress
    }
    
    /// 切换播放/暂停状态
    private func togglePlayPause() {
        if isCurrentFile {
            playerService.togglePlayPause()
        } else {
            // 如果不是当前文件，需要先加载
            // 这里只是切换状态，实际加载由外部处理
            playerService.togglePlayPause()
        }
    }
}

// MARK: - Mini Audio Player View

/// 迷你音频播放器视图（用于工具栏或状态栏）
struct MiniAudioPlayerView: View {
    
    @ObservedObject private var playerService: AudioPlayerService
    
    init(playerService: AudioPlayerService = .shared) {
        self.playerService = playerService
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // 播放/暂停按钮
            Button(action: { playerService.togglePlayPause() }) {
                Image(systemName: playerService.isPlaying ? "pause.fill" : "play.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .disabled(playerService.currentURL == nil)
            
            // 进度指示
            if playerService.currentURL != nil {
                Text(playerService.formatTime(playerService.currentTime))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                
                // 简单进度条
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                        
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: geometry.size.width * CGFloat(playerService.progress))
                    }
                }
                .frame(width: 60, height: 4)
                .cornerRadius(2)
            }
            
            // 停止按钮
            Button(action: { playerService.stop() }) {
                Image(systemName: "stop.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .disabled(playerService.currentURL == nil)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - Audio Player Popover View

/// 音频播放器弹出视图（用于从附件弹出显示）
struct AudioPlayerPopoverView: View {
    
    @ObservedObject private var playerService: AudioPlayerService
    
    let fileId: String
    let onDismiss: () -> Void
    
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    
    init(
        fileId: String,
        playerService: AudioPlayerService = .shared,
        onDismiss: @escaping () -> Void
    ) {
        self.fileId = fileId
        self.playerService = playerService
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // 标题
            HStack {
                Image(systemName: "waveform")
                    .foregroundColor(.orange)
                Text("语音录音")
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // 错误提示
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }
            
            // 播放器控件
            AudioPlayerView(
                fileId: fileId,
                playerService: playerService,
                showCloseButton: false,
                isCompact: false,
                onClose: nil
            )
            
            // 文件信息
            HStack {
                Text("文件 ID:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(fileId)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding()
        .frame(width: 280)
    }
}

// MARK: - Preview

#Preview("Standard") {
    AudioPlayerView(
        fileId: "test-file-id",
        showCloseButton: true,
        isCompact: false
    ) {
        print("Close tapped")
    }
    .frame(width: 300)
    .padding()
}

#Preview("Compact") {
    AudioPlayerView(
        fileId: "test-file-id",
        showCloseButton: false,
        isCompact: true
    )
    .frame(width: 280)
    .padding()
}

#Preview("Mini") {
    MiniAudioPlayerView()
        .padding()
}

#Preview("Popover") {
    AudioPlayerPopoverView(
        fileId: "test-file-id"
    ) {
        print("Dismiss")
    }
}
