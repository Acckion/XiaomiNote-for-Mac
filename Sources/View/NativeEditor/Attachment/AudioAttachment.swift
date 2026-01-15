//
//  AudioAttachment.swift
//  MiNoteMac
//
//  语音文件附件 - 用于在原生编辑器中显示语音文件占位符和播放控件

import AppKit
import SwiftUI
import Combine

// MARK: - 播放状态枚举

/// 音频播放状态
enum AudioPlaybackState: Equatable {
    case idle           // 空闲（未播放）
    case loading        // 加载中（下载/缓存）
    case playing        // 播放中
    case paused         // 暂停
    case error(String)  // 错误
    
    static func == (lhs: AudioPlaybackState, rhs: AudioPlaybackState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.playing, .playing), (.paused, .paused):
            return true
        case (.error(let lhsMsg), .error(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
    
    /// 是否可以播放
    var canPlay: Bool {
        switch self {
        case .idle, .paused:
            return true
        default:
            return false
        }
    }
    
    /// 是否正在播放
    var isPlaying: Bool {
        if case .playing = self {
            return true
        }
        return false
    }
    
    /// 是否正在加载
    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }
    
    /// 错误信息（如果有）
    var errorMessage: String? {
        if case .error(let message) = self {
            return message
        }
        return nil
    }
}

// MARK: - 语音文件附件

/// 语音文件附件 - 用于在 NSTextView 中显示语音文件占位符和播放控件
/// 支持播放控制、进度显示和状态管理
final class AudioAttachment: NSTextAttachment, ThemeAwareAttachment {
    
    // MARK: - 基础属性
    
    /// 语音文件 ID（对应 XML 中的 fileid 属性）
    var fileId: String?
    
    /// 文件摘要（digest）
    var digest: String?
    
    /// MIME 类型
    var mimeType: String?
    
    /// 是否为临时占位符（录音中）
    /// 临时占位符的 fileId 以 "temp_" 开头，导出时会添加 des="temp" 属性
    var isTemporaryPlaceholder: Bool = false
    
    /// 是否为深色模式
    var isDarkMode: Bool = false {
        didSet {
            if oldValue != isDarkMode {
                invalidateCache()
            }
        }
    }
    
    /// 占位符尺寸（带播放控件时更大）
    var placeholderSize: NSSize = NSSize(width: 240, height: 56)
    
    /// 缓存的图像
    private var cachedImage: NSImage? 
    
    /// 当前播放状态
    private(set) var playbackState: AudioPlaybackState = .idle {
        didSet {
            if oldValue != playbackState {
                invalidateCache()
                notifyStateChange()
            }
        }
    }
    
    /// 播放进度（0.0 - 1.0）
    private(set) var playbackProgress: Double = 0.0 {
        didSet {
            if abs(oldValue - playbackProgress) > 0.01 {
                invalidateCache()
            }
        }
    }
    
    /// 当前播放时间（秒）
    private(set) var currentTime: TimeInterval = 0 {
        didSet {
            if abs(oldValue - currentTime) > 0.1 {
                invalidateCache()
            }
        }
    }
    
    /// 总时长（秒）
    private(set) var duration: TimeInterval = 0 {
        didSet {
            if abs(oldValue - duration) > 0.1 {
                invalidateCache()
            }
        }
    }
    
    /// 本地缓存文件 URL
    private var cachedFileURL: URL?
    
    /// 通知订阅
    private var cancellables = Set<AnyCancellable>()
    
    /// 状态变化通知名称
    static let playbackStateDidChangeNotification = Notification.Name("AudioAttachment.playbackStateDidChange")
    
    // MARK: - Initialization
    
    override init(data contentData: Data?, ofType uti: String?) {
        super.init(data: contentData, ofType: uti)
        setupAttachment()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupAttachment()
    }
    
    /// 便捷初始化方法
    /// - Parameters:
    ///   - fileId: 语音文件 ID
    ///   - digest: 文件摘要（可选）
    ///   - mimeType: MIME 类型（可选）
    convenience init(fileId: String, digest: String? = nil, mimeType: String? = nil) {
        self.init(data: nil, ofType: nil)
        self.fileId = fileId
        self.digest = digest
        self.mimeType = mimeType
        print("[AudioAttachment] 🎤 初始化语音附件")
        print("[AudioAttachment]   - fileId: '\(fileId)'")
        print("[AudioAttachment]   - digest: '\(digest ?? "nil")'")
        print("[AudioAttachment]   - mimeType: '\(mimeType ?? "nil")'")
    }
    
    private func setupAttachment() {
        updateTheme()
        self.bounds = CGRect(origin: .zero, size: placeholderSize)
        // 预先创建占位符图像
        self.image = createPlaceholderImage()
        // 订阅播放器状态变化
        subscribeToPlayerNotifications()
    }
    
    deinit {
        // 如果当前正在播放此附件的音频，停止播放
        if let fileId = fileId, AudioPlayerService.shared.currentFileId == fileId {
            AudioPlayerService.shared.stop()
        }
        cancellables.removeAll()
    }
    
    // MARK: - 播放器通知订阅
    
    /// 订阅播放器状态变化通知
    private func subscribeToPlayerNotifications() {
        // 订阅播放状态变化
        NotificationCenter.default.publisher(for: AudioPlayerService.playbackStateDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handlePlaybackStateChange(notification)
            }
            .store(in: &cancellables)
        
        // 订阅播放进度变化
        NotificationCenter.default.publisher(for: AudioPlayerService.playbackProgressDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handlePlaybackProgressChange(notification)
            }
            .store(in: &cancellables)
        
        // 订阅播放完成
        NotificationCenter.default.publisher(for: AudioPlayerService.playbackDidFinishNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handlePlaybackFinished(notification)
            }
            .store(in: &cancellables)
        
        // 订阅播放错误
        NotificationCenter.default.publisher(for: AudioPlayerService.playbackErrorNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handlePlaybackError(notification)
            }
            .store(in: &cancellables)
    }
    
    /// 处理播放状态变化
    private func handlePlaybackStateChange(_ notification: Notification) {
        guard let notificationFileId = notification.userInfo?["fileId"] as? String,
              notificationFileId == fileId else {
            return
        }
        
        if let newState = notification.userInfo?["newState"] as? AudioPlayerService.PlaybackState {
            // 转换播放器状态到附件状态
            switch newState {
            case .idle:
                playbackState = .idle
            case .loading:
                playbackState = .loading
            case .playing:
                playbackState = .playing
            case .paused:
                playbackState = .paused
            case .error(let message):
                playbackState = .error(message)
            }
        }
    }
    
    /// 处理播放进度变化
    private func handlePlaybackProgressChange(_ notification: Notification) {
        guard let notificationFileId = notification.userInfo?["fileId"] as? String,
              notificationFileId == fileId else {
            return
        }
        
        if let progress = notification.userInfo?["progress"] as? Double {
            playbackProgress = progress
        }
        if let time = notification.userInfo?["currentTime"] as? TimeInterval {
            currentTime = time
        }
        if let dur = notification.userInfo?["duration"] as? TimeInterval {
            duration = dur
        }
    }
    
    /// 处理播放完成
    private func handlePlaybackFinished(_ notification: Notification) {
        guard let notificationFileId = notification.userInfo?["fileId"] as? String,
              notificationFileId == fileId else {
            return
        }
        
        playbackState = .idle
        playbackProgress = 0
        currentTime = 0
    }
    
    /// 处理播放错误
    private func handlePlaybackError(_ notification: Notification) {
        guard let notificationFileId = notification.userInfo?["fileId"] as? String,
              notificationFileId == fileId else {
            return
        }
        
        if let error = notification.userInfo?["error"] as? String {
            playbackState = .error(error)
        }
    }
    
    /// 通知状态变化
    private func notifyStateChange() {
        NotificationCenter.default.post(
            name: Self.playbackStateDidChangeNotification,
            object: self,
            userInfo: [
                "fileId": fileId as Any,
                "state": playbackState
            ]
        )
    } 
    
    /// 开始播放（自动下载和缓存）
    ///
    /// - Throws: 播放失败时抛出错误 
    func play() async throws {
        guard let fileId = fileId else {
            let error = "无法播放：缺少文件 ID"
            playbackState = .error(error)
            throw NSError(domain: "AudioAttachment", code: -1, userInfo: [NSLocalizedDescriptionKey: error])
        }
        
        print("[AudioAttachment] ▶️ 开始播放: \(fileId)")
        
        // 设置加载状态
        playbackState = .loading
        
        do {
            // 检查缓存
            let audioURL: URL
            if let cachedURL = AudioCacheService.shared.getCachedFile(for: fileId) {
                print("[AudioAttachment] 使用缓存文件: \(cachedURL.lastPathComponent)")
                audioURL = cachedURL
                cachedFileURL = cachedURL
            } else {
                // 需要下载
                print("[AudioAttachment] 开始下载音频文件...")
                let audioData = try await MiNoteService.shared.downloadAudio(fileId: fileId)
                
                // 缓存文件
                let mimeType = self.mimeType ?? "audio/mpeg"
                audioURL = try AudioCacheService.shared.cacheFile(data: audioData, fileId: fileId, mimeType: mimeType)
                cachedFileURL = audioURL
                print("[AudioAttachment] ✅ 下载并缓存完成: \(audioURL.lastPathComponent)")
            }
            
            // 播放音频
            try AudioPlayerService.shared.play(url: audioURL, fileId: fileId)
            
            // 更新时长
            if let dur = AudioPlayerService.shared.getDuration(for: audioURL) {
                duration = dur
            }
            
            playbackState = .playing
            print("[AudioAttachment] ✅ 播放开始")
            
        } catch {
            let errorMsg = "播放失败: \(error.localizedDescription)"
            print("[AudioAttachment] ❌ \(errorMsg)")
            playbackState = .error(errorMsg)
            throw error
        }
    }
    
    /// 暂停播放
    /// 
    func pause() {
        guard let fileId = fileId,
              AudioPlayerService.shared.currentFileId == fileId else {
            return
        }
        
        print("[AudioAttachment] ⏸️ 暂停播放")
        AudioPlayerService.shared.pause()
        playbackState = .paused
    }
    
    /// 停止播放
    func stop() {
        guard let fileId = fileId,
              AudioPlayerService.shared.currentFileId == fileId else {
            return
        }
        
        print("[AudioAttachment] ⏹️ 停止播放")
        AudioPlayerService.shared.stop()
        playbackState = .idle
        playbackProgress = 0
        currentTime = 0
    }
    
    /// 跳转到指定位置
    ///
    /// - Parameter progress: 进度值（0.0 - 1.0） 
    func seek(to progress: Double) {
        guard let fileId = fileId,
              AudioPlayerService.shared.currentFileId == fileId else {
            return
        }
        
        let clampedProgress = max(0, min(1, progress))
        print("[AudioAttachment] ⏩ 跳转到: \(Int(clampedProgress * 100))%")
        AudioPlayerService.shared.seek(to: clampedProgress)
        playbackProgress = clampedProgress
        currentTime = duration * clampedProgress
    }
    
    /// 切换播放/暂停状态
    func togglePlayPause() async throws {
        switch playbackState {
        case .idle, .paused:
            try await play()
        case .playing:
            pause()
        case .loading:
            // 加载中，忽略
            break
        case .error:
            // 出错后重试
            try await play()
        }
    }
    
    // MARK: - 辅助方法
    
    /// 格式化时间为 mm:ss 格式
    func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && time >= 0 else { return "0:00" }
        
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// 获取当前时间的格式化字符串
    var formattedCurrentTime: String {
        formatTime(currentTime)
    }
    
    /// 获取总时长的格式化字符串
    var formattedDuration: String {
        formatTime(duration)
    }
    
    /// 获取播放信息
    func getPlaybackInfo() -> [String: Any] {
        return [
            "fileId": fileId as Any,
            "state": String(describing: playbackState),
            "progress": playbackProgress,
            "currentTime": currentTime,
            "duration": duration,
            "formattedCurrentTime": formattedCurrentTime,
            "formattedDuration": formattedDuration
        ]
    }
    
    // MARK: - NSTextAttachment Override
    
    override func image(forBounds imageBounds: CGRect,
                       textContainer: NSTextContainer?,
                       characterIndex charIndex: Int) -> NSImage? {
        // 检查主题变化
        updateTheme()
        
        // 如果有缓存的图像，直接返回
        if let cached = cachedImage {
            return cached
        }
        
        // 创建新图像
        let image = createPlaceholderImage()
        cachedImage = image
        return image
    }
    
    override func attachmentBounds(for textContainer: NSTextContainer?,
                                  proposedLineFragment lineFrag: CGRect,
                                  glyphPosition position: CGPoint,
                                  characterIndex charIndex: Int) -> CGRect {
        // 检查容器宽度，确保不超出
        if let container = textContainer {
            let containerWidth = container.size.width - container.lineFragmentPadding * 2
            if containerWidth > 0 && placeholderSize.width > containerWidth {
                // 如果占位符宽度超过容器宽度，调整尺寸
                let ratio = containerWidth / placeholderSize.width
                return CGRect(
                    origin: .zero,
                    size: NSSize(
                        width: containerWidth,
                        height: placeholderSize.height * ratio
                    )
                )
            }
        }
        
        return CGRect(origin: .zero, size: placeholderSize)
    }
    
    // MARK: - ThemeAwareAttachment
    
    func updateTheme() {
        guard let currentAppearance = NSApp?.effectiveAppearance else {
            return
        }
        let newIsDarkMode = currentAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        
        if isDarkMode != newIsDarkMode {
            isDarkMode = newIsDarkMode
        }
    }
    
    // MARK: - Cache Management
    
    /// 清除缓存的图像
    func invalidateCache() {
        cachedImage = nil
        // 重新创建图像
        self.image = createPlaceholderImage()
    }

    
    // MARK: - Placeholder Image Creation
    
    /// 创建占位符图像（带播放控件）
    /// - Returns: 语音文件占位符图像
    private func createPlaceholderImage() -> NSImage {
        let size = placeholderSize
        
        let image = NSImage(size: size, flipped: false) { [weak self] rect in
            guard let self = self else { return false }
            
            // 获取主题相关颜色
            let backgroundColor: NSColor
            let borderColor: NSColor
            let iconColor: NSColor
            let textColor: NSColor
            let progressBackgroundColor: NSColor
            let progressFillColor: NSColor
            
            if self.isDarkMode {
                backgroundColor = NSColor.white.withAlphaComponent(0.08)
                borderColor = NSColor.white.withAlphaComponent(0.15)
                iconColor = NSColor.systemOrange.withAlphaComponent(0.9)
                textColor = NSColor.white.withAlphaComponent(0.7)
                progressBackgroundColor = NSColor.white.withAlphaComponent(0.15)
                progressFillColor = NSColor.systemOrange.withAlphaComponent(0.8)
            } else {
                backgroundColor = NSColor.black.withAlphaComponent(0.04)
                borderColor = NSColor.black.withAlphaComponent(0.12)
                iconColor = NSColor.systemOrange
                textColor = NSColor.black.withAlphaComponent(0.6)
                progressBackgroundColor = NSColor.black.withAlphaComponent(0.1)
                progressFillColor = NSColor.systemOrange.withAlphaComponent(0.9)
            }
            
            // 绘制圆角矩形背景
            let backgroundPath = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
            backgroundColor.setFill()
            backgroundPath.fill()
            
            // 绘制边框
            borderColor.setStroke()
            backgroundPath.lineWidth = 1
            backgroundPath.stroke()
            
            // 绘制播放/暂停按钮
            let buttonSize: CGFloat = 28
            let buttonRect = CGRect(
                x: 12,
                y: (rect.height - buttonSize) / 2,
                width: buttonSize,
                height: buttonSize
            )
            self.drawPlayPauseButton(in: buttonRect, color: iconColor)
            
            // 绘制进度条
            let progressBarX = buttonRect.maxX + 10
            let progressBarWidth = rect.width - progressBarX - 60 // 留出时间显示空间
            let progressBarHeight: CGFloat = 6
            let progressBarY = rect.height / 2 + 4
            
            let progressBarRect = CGRect(
                x: progressBarX,
                y: progressBarY,
                width: progressBarWidth,
                height: progressBarHeight
            )
            self.drawProgressBar(in: progressBarRect, backgroundColor: progressBackgroundColor, fillColor: progressFillColor)
            
            // 绘制时间信息
            let timeText: String
            if self.duration > 0 {
                timeText = "\(self.formattedCurrentTime) / \(self.formattedDuration)"
            } else {
                timeText = "语音录音"
            }
            
            let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            let timeAttributes: [NSAttributedString.Key: Any] = [
                .font: timeFont,
                .foregroundColor: textColor
            ]
            
            let timeSize = (timeText as NSString).size(withAttributes: timeAttributes)
            let timePoint = NSPoint(
                x: rect.width - timeSize.width - 12,
                y: (rect.height - timeSize.height) / 2
            )
            
            (timeText as NSString).draw(at: timePoint, withAttributes: timeAttributes)
            
            // 如果正在加载，显示加载指示
            if self.playbackState.isLoading {
                self.drawLoadingIndicator(in: buttonRect, color: iconColor)
            }
            
            // 如果有错误，显示错误图标
            if let _ = self.playbackState.errorMessage {
                self.drawErrorIndicator(in: buttonRect, color: NSColor.systemRed)
            }
            
            return true
        }
        
        return image
    }
    
    /// 绘制播放/暂停按钮
    /// - Parameters:
    ///   - rect: 绘制区域
    ///   - color: 按钮颜色
    private func drawPlayPauseButton(in rect: CGRect, color: NSColor) {
        // 绘制圆形背景
        let circlePath = NSBezierPath(ovalIn: rect)
        color.withAlphaComponent(0.15).setFill()
        circlePath.fill()
        
        color.setFill()
        
        let centerX = rect.midX
        let centerY = rect.midY
        let iconSize: CGFloat = 10
        
        if playbackState.isPlaying {
            // 绘制暂停图标（两条竖线）
            let barWidth: CGFloat = 3
            let barHeight: CGFloat = iconSize
            let barSpacing: CGFloat = 4
            
            let leftBarRect = CGRect(
                x: centerX - barSpacing / 2 - barWidth,
                y: centerY - barHeight / 2,
                width: barWidth,
                height: barHeight
            )
            let rightBarRect = CGRect(
                x: centerX + barSpacing / 2,
                y: centerY - barHeight / 2,
                width: barWidth,
                height: barHeight
            )
            
            let leftBar = NSBezierPath(roundedRect: leftBarRect, xRadius: 1, yRadius: 1)
            let rightBar = NSBezierPath(roundedRect: rightBarRect, xRadius: 1, yRadius: 1)
            
            leftBar.fill()
            rightBar.fill()
        } else {
            // 绘制播放图标（三角形）
            let trianglePath = NSBezierPath()
            let triangleWidth: CGFloat = iconSize
            let triangleHeight: CGFloat = iconSize * 1.2
            
            // 三角形顶点（稍微向右偏移以视觉居中）
            let offsetX: CGFloat = 2
            trianglePath.move(to: NSPoint(x: centerX - triangleWidth / 2 + offsetX, y: centerY + triangleHeight / 2))
            trianglePath.line(to: NSPoint(x: centerX - triangleWidth / 2 + offsetX, y: centerY - triangleHeight / 2))
            trianglePath.line(to: NSPoint(x: centerX + triangleWidth / 2 + offsetX, y: centerY))
            trianglePath.close()
            
            trianglePath.fill()
        }
    }
    
    /// 绘制进度条
    /// - Parameters:
    ///   - rect: 绘制区域
    ///   - backgroundColor: 背景颜色
    ///   - fillColor: 填充颜色
    private func drawProgressBar(in rect: CGRect, backgroundColor: NSColor, fillColor: NSColor) {
        // 绘制背景
        let backgroundPath = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        backgroundColor.setFill()
        backgroundPath.fill()
        
        // 绘制进度
        if playbackProgress > 0 {
            let progressWidth = rect.width * CGFloat(playbackProgress)
            let progressRect = CGRect(
                x: rect.origin.x,
                y: rect.origin.y,
                width: max(rect.height, progressWidth), // 至少显示一个圆形
                height: rect.height
            )
            let progressPath = NSBezierPath(roundedRect: progressRect, xRadius: rect.height / 2, yRadius: rect.height / 2)
            fillColor.setFill()
            progressPath.fill()
            
            // 绘制进度指示点
            let indicatorSize: CGFloat = rect.height + 4
            let indicatorRect = CGRect(
                x: rect.origin.x + progressWidth - indicatorSize / 2,
                y: rect.origin.y - 2,
                width: indicatorSize,
                height: indicatorSize
            )
            let indicatorPath = NSBezierPath(ovalIn: indicatorRect)
            fillColor.setFill()
            indicatorPath.fill()
            
            // 绘制指示点边框
            NSColor.white.withAlphaComponent(0.8).setStroke()
            indicatorPath.lineWidth = 1.5
            indicatorPath.stroke()
        }
    }
    
    /// 绘制加载指示器
    /// - Parameters:
    ///   - rect: 绘制区域
    ///   - color: 颜色
    private func drawLoadingIndicator(in rect: CGRect, color: NSColor) {
        // 绘制简单的加载圆环
        let centerX = rect.midX
        let centerY = rect.midY
        let radius: CGFloat = 8
        
        let arcPath = NSBezierPath()
        arcPath.appendArc(
            withCenter: NSPoint(x: centerX, y: centerY),
            radius: radius,
            startAngle: 0,
            endAngle: 270,
            clockwise: false
        )
        
        color.setStroke()
        arcPath.lineWidth = 2
        arcPath.lineCapStyle = .round
        arcPath.stroke()
    }
    
    /// 绘制错误指示器
    /// - Parameters:
    ///   - rect: 绘制区域
    ///   - color: 颜色
    private func drawErrorIndicator(in rect: CGRect, color: NSColor) {
        let centerX = rect.midX
        let centerY = rect.midY
        let size: CGFloat = 12
        
        // 绘制感叹号
        color.setFill()
        
        // 感叹号主体
        let bodyRect = CGRect(
            x: centerX - 1.5,
            y: centerY - 2,
            width: 3,
            height: 8
        )
        let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 1.5, yRadius: 1.5)
        bodyPath.fill()
        
        // 感叹号点
        let dotRect = CGRect(
            x: centerX - 1.5,
            y: centerY - size / 2,
            width: 3,
            height: 3
        )
        let dotPath = NSBezierPath(ovalIn: dotRect)
        dotPath.fill()
    }
    
    /// 绘制音频图标（麦克风样式）- 保留用于无播放控件时
    /// - Parameters:
    ///   - rect: 绘制区域
    ///   - color: 图标颜色
    private func drawAudioIcon(in rect: CGRect, color: NSColor) {
        color.setStroke()
        color.setFill()
        
        let centerX = rect.midX
        let centerY = rect.midY
        
        // 绘制麦克风主体（椭圆形）
        let micWidth: CGFloat = 8
        let micHeight: CGFloat = 12
        let micRect = CGRect(
            x: centerX - micWidth / 2,
            y: centerY - 2,
            width: micWidth,
            height: micHeight
        )
        let micPath = NSBezierPath(roundedRect: micRect, xRadius: micWidth / 2, yRadius: micWidth / 2)
        micPath.fill()
        
        // 绘制麦克风支架（U 形）
        let standPath = NSBezierPath()
        let standWidth: CGFloat = 12
        let standHeight: CGFloat = 8
        let standY = centerY - 4
        
        standPath.move(to: NSPoint(x: centerX - standWidth / 2, y: standY))
        standPath.appendArc(
            withCenter: NSPoint(x: centerX, y: standY),
            radius: standWidth / 2,
            startAngle: 180,
            endAngle: 0,
            clockwise: true
        )
        
        standPath.lineWidth = 2
        standPath.lineCapStyle = .round
        standPath.stroke()
        
        // 绘制麦克风底座（竖线 + 横线）
        let basePath = NSBezierPath()
        let baseY = standY - standHeight
        
        // 竖线
        basePath.move(to: NSPoint(x: centerX, y: standY - standWidth / 2))
        basePath.line(to: NSPoint(x: centerX, y: baseY))
        
        // 横线
        let baseWidth: CGFloat = 8
        basePath.move(to: NSPoint(x: centerX - baseWidth / 2, y: baseY))
        basePath.line(to: NSPoint(x: centerX + baseWidth / 2, y: baseY))
        
        basePath.lineWidth = 2
        basePath.lineCapStyle = .round
        basePath.stroke()
    }
}
