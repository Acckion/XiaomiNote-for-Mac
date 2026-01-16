//
//  AttachmentHighlightView.swift
//  MiNoteMac
//
//  Created by Kiro AI
//

import AppKit

/// 附件高亮视图
/// 负责渲染描边效果、主题适配、动画效果
class AttachmentHighlightView: NSView {
    // MARK: - Properties
    
    /// 高亮样式
    enum HighlightStyle {
        case border         // 描边样式(用于图片、音频等)
        case thickLine      // 加粗线条样式(用于分割线)
    }
    
    /// 当前高亮样式
    var highlightStyle: HighlightStyle = .border {
        didSet {
            needsDisplay = true
        }
    }
    
    /// 描边宽度
    var borderWidth: CGFloat = 2.5 {
        didSet {
            needsDisplay = true
        }
    }
    
    /// 描边颜色
    var borderColor: NSColor = .controlAccentColor {
        didSet {
            needsDisplay = true
        }
    }
    
    /// 圆角半径
    var cornerRadius: CGFloat = 4 {
        didSet {
            needsDisplay = true
        }
    }
    
    /// 是否启用动画
    var animationEnabled: Bool = true
    
    /// 动画时长
    var animationDuration: TimeInterval = 0.15
    
    // MARK: - Initialization
    
    /// 初始化高亮视图
    /// - Parameter frame: 视图区域
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        // 设置视图为透明背景
        wantsLayer = true
        layer?.backgroundColor = .clear
        
        // 初始时隐藏
        alphaValue = 0
        
        // 更新主题
        updateTheme()
        
        // 监听系统外观变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemAppearanceDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Display
    
    /// 更新高亮区域
    /// - Parameters:
    ///   - rect: 新的区域
    ///   - animated: 是否使用动画
    func updateFrame(_ rect: CGRect, animated: Bool) {
        if animated && animationEnabled {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().frame = rect
            }
        } else {
            frame = rect
        }
    }
    
    /// 显示高亮(带动画)
    func show() {
        if animationEnabled {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                animator().alphaValue = 1.0
            }
        } else {
            alphaValue = 1.0
        }
    }
    
    /// 隐藏高亮(带动画)
    func hide() {
        if animationEnabled {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 0.0
            }
        } else {
            alphaValue = 0.0
        }
    }
    
    // MARK: - Theme
    
    /// 更新主题
    func updateTheme() {
        borderColor = getBorderColor()
        needsDisplay = true
    }
    
    /// 获取当前主题的描边颜色
    /// - Returns: 描边颜色
    func getBorderColor() -> NSColor {
        // 使用系统强调色
        return .controlAccentColor
    }
    
    @objc private func systemAppearanceDidChange() {
        updateTheme()
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        
        switch highlightStyle {
        case .border:
            // 绘制描边样式(用于图片、音频等)
            let insetRect = bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
            let path = NSBezierPath(roundedRect: insetRect, xRadius: cornerRadius, yRadius: cornerRadius)
            
            borderColor.setStroke()
            path.lineWidth = borderWidth
            path.stroke()
            
        case .thickLine:
            // 绘制加粗线条样式(用于分割线)
            // 使用更粗的线条(4pt)和圆角矩形
            let lineHeight: CGFloat = 4
            let lineY = (bounds.height - lineHeight) / 2
            let lineRect = CGRect(x: 0, y: lineY, width: bounds.width, height: lineHeight)
            
            borderColor.setFill()
            NSBezierPath(roundedRect: lineRect, xRadius: 2, yRadius: 2).fill()
        }
    }
}
