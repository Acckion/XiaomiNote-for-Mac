//
//  AudioAttachment+Rendering.swift
//  MiNoteMac
//
//  AudioAttachment 的 UI 渲染逻辑 - 绘制波形、播放控件、进度条等

import AppKit

// MARK: - UI 渲染

extension AudioAttachment {

    // MARK: - NSTextAttachment Override

    override nonisolated func image(
        forBounds _: CGRect,
        textContainer _: NSTextContainer?,
        characterIndex _: Int
    ) -> NSImage? {
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

    override nonisolated func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment _: CGRect,
        glyphPosition _: CGPoint,
        characterIndex _: Int
    ) -> CGRect {
        // 检查容器宽度，确保不超出
        if let container = textContainer {
            let containerWidth = container.size.width - container.lineFragmentPadding * 2
            if containerWidth > 0, placeholderSize.width > containerWidth {
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

    // MARK: - 占位符图像创建

    /// 创建占位符图像（带播放控件）
    /// - Returns: 语音文件占位符图像
    func createPlaceholderImage() -> NSImage {
        let size = placeholderSize

        return NSImage(size: size, flipped: false) { [weak self] rect in
            guard let self else { return false }

            // 获取主题相关颜色
            let backgroundColor: NSColor
            let borderColor: NSColor
            let iconColor: NSColor
            let textColor: NSColor
            let progressBackgroundColor: NSColor
            let progressFillColor: NSColor

            if isDarkMode {
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
            drawPlayPauseButton(in: buttonRect, color: iconColor)

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
            drawProgressBar(in: progressBarRect, backgroundColor: progressBackgroundColor, fillColor: progressFillColor)

            // 绘制时间信息
            let timeText = if duration > 0 {
                "\(formattedCurrentTime) / \(formattedDuration)"
            } else {
                "语音录音"
            }

            let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            let timeAttributes: [NSAttributedString.Key: Any] = [
                .font: timeFont,
                .foregroundColor: textColor,
            ]

            let timeSize = (timeText as NSString).size(withAttributes: timeAttributes)
            let timePoint = NSPoint(
                x: rect.width - timeSize.width - 12,
                y: (rect.height - timeSize.height) / 2
            )

            (timeText as NSString).draw(at: timePoint, withAttributes: timeAttributes)

            // 如果正在加载，显示加载指示
            if playbackState.isLoading {
                drawLoadingIndicator(in: buttonRect, color: iconColor)
            }

            // 如果有错误，显示错误图标
            if let _ = playbackState.errorMessage {
                drawErrorIndicator(in: buttonRect, color: NSColor.systemRed)
            }

            return true
        }
    }

    /// 绘制播放/暂停按钮
    /// - Parameters:
    ///   - rect: 绘制区域
    ///   - color: 按钮颜色
    func drawPlayPauseButton(in rect: CGRect, color: NSColor) {
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
    func drawProgressBar(in rect: CGRect, backgroundColor: NSColor, fillColor: NSColor) {
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
    func drawLoadingIndicator(in rect: CGRect, color: NSColor) {
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
    func drawErrorIndicator(in rect: CGRect, color: NSColor) {
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
    func drawAudioIcon(in rect: CGRect, color: NSColor) {
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
