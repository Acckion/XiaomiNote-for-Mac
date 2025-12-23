import SwiftUI
import AppKit

/// 标题编辑器（独立的编辑区域）
@available(macOS 14.0, *)
struct TitleEditorView: NSViewRepresentable {
    @Binding var title: String
    @Binding var isEditable: Bool
    var hasRealTitle: Bool = true  // 是否有真正的标题（不是从内容中提取的）
    
    func makeNSView(context: Context) -> NSView {
        // 创建一个容器视图
        let containerView = NSView()
        
        // 创建文本视图（不使用滚动视图）
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: 8)  // 增加上下内边距，确保字体完整显示
        textView.font = NSFont.systemFont(ofSize: 40, weight: .bold)  // 增大标题字体
        textView.textColor = NSColor.labelColor  // 使用 labelColor 自动适配深色模式
        textView.backgroundColor = NSColor.clear
        textView.allowsUndo = true
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.heightTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        
        // 设置行高，确保40pt字体完整显示
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = 50  // 设置最小行高，适配40pt字体
        paragraphStyle.maximumLineHeight = 50  // 设置最大行高，适配40pt字体
        textView.defaultParagraphStyle = paragraphStyle
        
        // 设置初始内容
        textView.string = title.isEmpty ? "" : title
        textView.isEditable = isEditable
        
        // 将文本视图添加到容器
        containerView.addSubview(textView)
        textView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: containerView.topAnchor),
            textView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60) // 最小高度，确保40pt字体完整显示
        ])
        
        context.coordinator.textView = textView
        context.coordinator.parent = self
        
        // 设置占位符
        context.coordinator.updatePlaceholder()
        
        // 监听外观变化，确保深色模式下颜色正确
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.appearanceChanged),
            name: NSNotification.Name("NSApplicationDidChangeEffectiveAppearanceNotification"),
            object: nil
        )
        
        // 监听窗口成为主窗口，用于检测焦点变化
        // 延迟设置，因为此时 textView.window 可能还是 nil
        DispatchQueue.main.async {
            if let window = textView.window {
                NotificationCenter.default.addObserver(
                    context.coordinator,
                    selector: #selector(Coordinator.windowDidBecomeKey),
                    name: NSWindow.didBecomeKeyNotification,
                    object: window
                )
            }
        }
        
        return containerView
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        
        guard let textView = context.coordinator.textView else { return }
        
        // 防止在更新过程中递归调用
        guard !context.coordinator.isUpdatingFromExternal else { return }
        
        // 确保在主线程上执行
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.updateNSView(nsView, context: context)
            }
            return
        }
        
        // 检查当前显示的是否是占位符
        // 根据是否有真正的标题确定占位符文本
        let currentPlaceholder = hasRealTitle == false ? "无标题" : "标题"
        let currentString = textView.string
        let isShowingPlaceholder = currentString == currentPlaceholder || currentString == "标题" || currentString == "无标题"
        
        // 安全地检查颜色
        var isPlaceholderColor = false
        if let textStorage = textView.textStorage, textStorage.length > 0 {
            let currentColor = textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
            isPlaceholderColor = currentColor == NSColor.placeholderTextColor || currentColor == NSColor.secondaryLabelColor
        }
        
        // 如果内容从外部改变，且当前不是占位符，更新文本视图
        let cleanTitle = title.isEmpty ? "" : title
        
        // 如果当前显示的是占位符，不要更新文本视图（让 updatePlaceholder 处理）
        if isShowingPlaceholder && isPlaceholderColor {
            // 如果标题从外部变为非空，需要清除占位符并显示标题
            if !cleanTitle.isEmpty {
                context.coordinator.isUpdatingFromExternal = true
                textView.string = cleanTitle
                textView.textColor = NSColor.labelColor
                context.coordinator.isUpdatingFromExternal = false
            }
        } else {
            // 当前不是占位符，正常更新
            if currentString != cleanTitle {
                context.coordinator.isUpdatingFromExternal = true
                textView.string = cleanTitle
                textView.textColor = NSColor.labelColor
                context.coordinator.isUpdatingFromExternal = false
            }
        }
        
        // 确保文本颜色始终正确（适配深色模式）
        // 使用 appearance-based 的颜色，确保在深色模式下正确显示
        let effectiveAppearance = textView.effectiveAppearance
        if effectiveAppearance.name == .darkAqua || effectiveAppearance.name == .vibrantDark {
            // 深色模式：确保使用浅色文本
            if textView.textColor == NSColor.black || textView.textColor == NSColor.textColor {
                textView.textColor = NSColor.labelColor
            }
        } else {
            // 浅色模式：使用 labelColor（会自动适配）
            textView.textColor = NSColor.labelColor
        }
        
        // 更新占位符
        // 如果标题为空，立即更新占位符（不需要延迟）
        if title.isEmpty {
            context.coordinator.updatePlaceholder()
        } else {
            // 如果标题不为空，延迟更新占位符（避免在更新过程中触发）
            let coordinator = context.coordinator
            DispatchQueue.main.async { [weak coordinator] in
                guard let coordinator = coordinator else { return }
                coordinator.updatePlaceholder()
            }
        }
        
        textView.isEditable = isEditable
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    @MainActor class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TitleEditorView?
        var textView: NSTextView?
        var isUpdatingFromExternal: Bool = false
        private var placeholderText: String {
            // 根据是否有真正的标题显示不同的占位符
            return parent?.hasRealTitle == false ? "无标题" : "标题"
        }
        
        /// 处理外观变化（深色/浅色模式切换）
        @objc func appearanceChanged() {
            guard let textView = textView else { return }
            // 确保文本颜色适配当前外观
            textView.textColor = NSColor.labelColor
            // 更新占位符颜色
            updatePlaceholder()
        }
        
        func updatePlaceholder() {
            // 确保在主线程上执行
            guard Thread.isMainThread else {
                DispatchQueue.main.async { [weak self] in
                    self?.updatePlaceholder()
                }
                return
            }
            
            guard let textView = textView,
                  let textStorage = textView.textStorage,
                  let parent = parent else { return }
            
            // 防止递归调用
            guard !isUpdatingFromExternal else { return }
            
            let currentPlaceholder = placeholderText
            let currentString = textStorage.string
            
            // 如果文本为空或者是占位符文本，显示占位符
            if currentString.isEmpty || currentString == currentPlaceholder || currentString == "标题" || currentString == "无标题" {
                // 检查当前显示的是否已经是正确的占位符
                var currentColor: NSColor? = nil
                if textStorage.length > 0 {
                    currentColor = textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
                }
                
                let expectedColor = parent.hasRealTitle == false ? NSColor.secondaryLabelColor : NSColor.placeholderTextColor
                if currentString == currentPlaceholder && currentColor == expectedColor {
                    // 已经是正确的占位符，不需要更新
                    return
                }
                
                // 设置占位符的行高
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.minimumLineHeight = 50  // 适配40pt字体
                paragraphStyle.maximumLineHeight = 50  // 适配40pt字体
                
                // 使用灰色显示"无标题"占位符
                let placeholderColor = parent.hasRealTitle == false ? NSColor.secondaryLabelColor : NSColor.placeholderTextColor
                
                let placeholderAttr = NSAttributedString(
                    string: currentPlaceholder,
                    attributes: [
                        .foregroundColor: placeholderColor,
                        .font: NSFont.systemFont(ofSize: 40, weight: .bold),  // 增大占位符字体
                        .paragraphStyle: paragraphStyle
                    ]
                )
                isUpdatingFromExternal = true
                textStorage.setAttributedString(placeholderAttr)
                // 确保 textView 是可编辑的，即使显示占位符
                textView.isEditable = true
                isUpdatingFromExternal = false
            } else {
                // 如果当前显示的是占位符，清除它
                if currentString == currentPlaceholder || currentString == "标题" || currentString == "无标题" {
                    var currentColor: NSColor? = nil
                    if textStorage.length > 0 {
                        currentColor = textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
                    }
                    if currentColor == NSColor.placeholderTextColor || currentColor == NSColor.secondaryLabelColor {
                        isUpdatingFromExternal = true
                        textStorage.setAttributedString(NSAttributedString(string: ""))
                        isUpdatingFromExternal = false
                    }
                }
            }
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = textView,
                  let parent = parent,
                  !isUpdatingFromExternal else { return }
            
            let newTitle = textView.string
            let currentPlaceholder = placeholderText
            
            // 如果输入的是占位符文本，清空
            if newTitle == currentPlaceholder || newTitle == "标题" || newTitle == "无标题" {
                isUpdatingFromExternal = true
                textView.string = ""
                textView.textColor = NSColor.labelColor  // 确保文本颜色正确
                isUpdatingFromExternal = false
                updatePlaceholder()
                return
            }
            
            // 更新标题（如果不是占位符）
            // 即使 newTitle 是空字符串，也要更新 parent.title，以便触发保存
            if newTitle != currentPlaceholder && newTitle != "标题" && newTitle != "无标题" {
                // 总是更新 parent.title，即使它和当前值相同（空字符串的情况）
                parent.title = newTitle
                // 确保文本颜色正确（适配深色模式）
                textView.textColor = NSColor.labelColor
            }
        }
        
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = textView,
                  let textStorage = textView.textStorage,
                  !isUpdatingFromExternal else { return }
            
            let currentPlaceholder = placeholderText
            let currentString = textStorage.string
            
            // 如果当前显示的是占位符，且用户点击了，清除占位符
            if currentString == currentPlaceholder || currentString == "标题" || currentString == "无标题" {
                var currentColor: NSColor? = nil
                if textStorage.length > 0 {
                    currentColor = textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
                }
                if currentColor == NSColor.placeholderTextColor || currentColor == NSColor.secondaryLabelColor {
                    isUpdatingFromExternal = true
                    textStorage.setAttributedString(NSAttributedString(string: ""))
                    textView.textColor = NSColor.labelColor  // 确保文本颜色正确
                    // 更新 parent.title 为空字符串，触发保存
                    if let parent = parent {
                        parent.title = ""
                    }
                    isUpdatingFromExternal = false
                }
            }
        }
        
        // 处理文本视图获得焦点时清除占位符
        func textViewDidBecomeFirstResponder(_ textView: NSTextView) {
            guard let textStorage = textView.textStorage,
                  !isUpdatingFromExternal else { return }
            
            let currentPlaceholder = placeholderText
            let currentString = textStorage.string
            
            // 如果当前显示的是占位符，清除它
            if currentString == currentPlaceholder || currentString == "标题" || currentString == "无标题" {
                var currentColor: NSColor? = nil
                if textStorage.length > 0 {
                    currentColor = textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
                }
                if currentColor == NSColor.placeholderTextColor || currentColor == NSColor.secondaryLabelColor {
                    isUpdatingFromExternal = true
                    textStorage.setAttributedString(NSAttributedString(string: ""))
                    textView.textColor = NSColor.labelColor  // 确保文本颜色正确
                    // 更新 parent.title 为空字符串，触发保存
                    if let parent = parent {
                        parent.title = ""
                    }
                    isUpdatingFromExternal = false
                }
            }
        }
        
        /// 处理窗口成为主窗口时，检查文本视图是否获得焦点
        @objc func windowDidBecomeKey(_ notification: Notification) {
            guard let textView = textView,
                  let window = notification.object as? NSWindow,
                  window === textView.window else { return }
            
            // 延迟检查，确保焦点已经设置
            DispatchQueue.main.async { [weak self] in
                guard let self = self,
                      let textView = self.textView,
                      window.firstResponder === textView else { return }
                self.textViewDidBecomeFirstResponder(textView)
            }
        }
    }
}

