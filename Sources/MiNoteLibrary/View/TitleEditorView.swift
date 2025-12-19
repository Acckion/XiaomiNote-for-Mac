import SwiftUI
import AppKit

/// 标题编辑器（独立的编辑区域）
@available(macOS 14.0, *)
struct TitleEditorView: NSViewRepresentable {
    @Binding var title: String
    @Binding var isEditable: Bool
    
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
        
        return containerView
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        
        guard let textView = context.coordinator.textView else { return }
        
        // 如果内容从外部改变，更新文本视图
        let cleanTitle = title.isEmpty ? "" : title
        if textView.string != cleanTitle {
            context.coordinator.isUpdatingFromExternal = true
            textView.string = cleanTitle
            // 确保文本颜色正确（适配深色模式）
            textView.textColor = NSColor.labelColor
            context.coordinator.isUpdatingFromExternal = false
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
        context.coordinator.updatePlaceholder()
        
        textView.isEditable = isEditable
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    @MainActor class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TitleEditorView?
        var textView: NSTextView?
        var isUpdatingFromExternal: Bool = false
        private let placeholderText = "标题"
        
        /// 处理外观变化（深色/浅色模式切换）
        @objc func appearanceChanged() {
            guard let textView = textView else { return }
            // 确保文本颜色适配当前外观
            textView.textColor = NSColor.labelColor
            // 更新占位符颜色
            updatePlaceholder()
        }
        
        func updatePlaceholder() {
            guard let textView = textView,
                  let textStorage = textView.textStorage else { return }
            
            // 如果文本为空，显示占位符
            if textStorage.string.isEmpty {
                // 设置占位符的行高
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.minimumLineHeight = 50  // 适配40pt字体
                paragraphStyle.maximumLineHeight = 50  // 适配40pt字体
                
                let placeholderAttr = NSAttributedString(
                    string: placeholderText,
                    attributes: [
                        .foregroundColor: NSColor.placeholderTextColor,
                        .font: NSFont.systemFont(ofSize: 40, weight: .bold),  // 增大占位符字体
                        .paragraphStyle: paragraphStyle
                    ]
                )
                isUpdatingFromExternal = true
                textStorage.setAttributedString(placeholderAttr)
                isUpdatingFromExternal = false
            } else {
                // 如果当前显示的是占位符，清除它
                if textStorage.string == placeholderText {
                    let currentColor = textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
                    if currentColor == NSColor.placeholderTextColor {
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
            
            // 如果输入的是占位符文本，清空
            if newTitle == placeholderText {
                isUpdatingFromExternal = true
                textView.string = ""
                textView.textColor = NSColor.labelColor  // 确保文本颜色正确
                isUpdatingFromExternal = false
                updatePlaceholder()
                return
            }
            
            // 更新标题（如果不是占位符）
            if newTitle != parent.title && newTitle != placeholderText {
                parent.title = newTitle
                // 确保文本颜色正确（适配深色模式）
                textView.textColor = NSColor.labelColor
            }
        }
        
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = textView,
                  let textStorage = textView.textStorage else { return }
            
            // 如果当前显示的是占位符，且用户点击了，清除占位符
            if textStorage.string == placeholderText {
                let currentColor = textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
                if currentColor == NSColor.placeholderTextColor {
                    isUpdatingFromExternal = true
                    textStorage.setAttributedString(NSAttributedString(string: ""))
                    isUpdatingFromExternal = false
                }
            }
        }
    }
}

