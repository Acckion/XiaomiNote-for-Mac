import SwiftUI
import AppKit

/// 编辑器格式工具栏
struct EditorToolbar: View {
    @State private var textView: NSTextView?
    @State private var isBold: Bool = false
    @State private var isItalic: Bool = false
    @State private var fontSize: CGFloat = NSFont.systemFontSize
    @State private var hasSelection: Bool = false
    
    init() {
        // 通过 NotificationCenter 获取 textView
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 标题按钮组
            Group {
                Button(action: { applyHeading(level: 1) }) {
                    Text("大标题")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("一级标题")
                
                Button(action: { applyHeading(level: 2) }) {
                    Text("标题")
                        .font(.system(size: 12, weight: .regular))
                }
                .buttonStyle(.plain)
                .help("二级标题")
                
                Button(action: { applyHeading(level: 3) }) {
                    Text("副标题")
                        .font(.system(size: 12, weight: .regular))
                }
                .buttonStyle(.plain)
                .help("三级标题")
            }
            
            Divider()
                .frame(height: 20)
            
            // 格式按钮组
            Group {
                Button(action: { toggleBold() }) {
                    Image(systemName: "bold")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("加粗 (⌘B)")
                .disabled(!hasSelection)
                .keyboardShortcut("b", modifiers: .command)
                
                Button(action: { toggleItalic() }) {
                    Image(systemName: "italic")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("斜体 (⌘I)")
                .disabled(!hasSelection)
                .keyboardShortcut("i", modifiers: .command)
            }
            
            Divider()
                .frame(height: 20)
            
            // 高亮按钮
            Button(action: { applyHighlight() }) {
                Image(systemName: "highlighter")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .help("高亮文本")
            .disabled(!hasSelection)
            
            Divider()
                .frame(height: 20)
            
            // 字体大小选择
            Menu {
                Button("小 (12pt)") { setFontSize(12) }
                Button("标准 (14pt)") { setFontSize(NSFont.systemFontSize) }
                Button("大 (18pt)") { setFontSize(18) }
                Button("超大 (24pt)") { setFontSize(24) }
            } label: {
                Image(systemName: "textformat.size")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .help("字体大小")
            .disabled(!hasSelection)
            
            Spacer()
            
            // 状态指示
            if hasSelection {
                Text("已选择文本")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: NSColor.windowBackgroundColor).opacity(0.85))
                .background(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: NSColor.separatorColor).opacity(0.2), lineWidth: 0.5)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MiNoteEditorTextViewCreated"))) { notification in
            if let tv = notification.object as? NSTextView {
                self.textView = tv
                updateSelectionState()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSTextView.didChangeSelectionNotification)) { notification in
            if let tv = notification.object as? NSTextView, tv === textView {
                updateSelectionState()
            }
        }
        .onAppear {
            updateSelectionState()
        }
    }
    
    // MARK: - Actions
    
    private func updateSelectionState() {
        guard let textView = textView else {
            hasSelection = false
            return
        }
        let range = textView.selectedRange()
        hasSelection = range.length > 0
        
        if hasSelection && range.location < textView.string.count {
            let attributes = textView.textStorage?.attributes(at: range.location, effectiveRange: nil) ?? [:]
            if let font = attributes[.font] as? NSFont {
                fontSize = font.pointSize
                isBold = font.fontDescriptor.symbolicTraits.contains(.bold)
                isItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
            }
        }
    }
    
    private func applyHeading(level: Int) {
        guard let textView = textView,
              let textStorage = textView.textStorage else { return }
        
        let range = textView.selectedRange()
        var targetRange = range
        
        if range.length == 0 {
            // 如果没有选择，选择当前段落
            let paragraphRange = (textView.string as NSString).paragraphRange(for: range)
            if paragraphRange.length > 0 {
                targetRange = paragraphRange
                textView.setSelectedRange(targetRange)
            } else {
                // 如果段落为空，插入一个标题文本
                return
            }
        }
        
        applyHeadingToRange(level: level, range: targetRange)
    }
    
    private func applyHeadingToRange(level: Int, range: NSRange) {
        guard let textView = textView,
              let textStorage = textView.textStorage else { return }
        
        var fontSize: CGFloat
        var isBold = true
        
        switch level {
        case 1:
            fontSize = 24
        case 2:
            fontSize = 18
        case 3:
            fontSize = 14
        default:
            fontSize = NSFont.systemFontSize
            isBold = false
        }
        
        let font = isBold 
            ? NSFont.boldSystemFont(ofSize: fontSize)
            : NSFont.systemFont(ofSize: fontSize)
        
        textStorage.addAttribute(.font, value: font, range: range)
        textView.didChangeText()
    }
    
    private func toggleBold() {
        guard let textView = textView,
              let textStorage = textView.textStorage else { return }
        
        let range = textView.selectedRange()
        guard range.length > 0 && range.location < textView.string.count else { return }
        
        // 检查当前是否加粗（检查选中范围的第一个字符）
        var shouldBold = true
        if range.location < textStorage.length {
            if let font = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont {
                if font.fontDescriptor.symbolicTraits.contains(.bold) {
                    shouldBold = false
                }
            }
        }
        
        // 应用或移除加粗
        textStorage.beginEditing()
        textStorage.enumerateAttribute(.font, in: range, options: []) { (value, subrange, _) in
            if let oldFont = value as? NSFont {
                let fontSize = oldFont.pointSize
                let newFont: NSFont
                if shouldBold {
                    // 添加加粗
                    newFont = NSFont.boldSystemFont(ofSize: fontSize)
                } else {
                    // 移除加粗，保持其他特性
                    var fontDescriptor = oldFont.fontDescriptor
                    var traits = fontDescriptor.symbolicTraits
                    traits.remove(.bold)
                    fontDescriptor = fontDescriptor.withSymbolicTraits(traits)
                    newFont = NSFont(descriptor: fontDescriptor, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
                }
                textStorage.addAttribute(.font, value: newFont, range: subrange)
            } else {
                let baseFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
                let newFont = shouldBold 
                    ? NSFont.boldSystemFont(ofSize: baseFont.pointSize)
                    : baseFont
                textStorage.addAttribute(.font, value: newFont, range: subrange)
            }
        }
        textStorage.endEditing()
        
        textView.didChangeText()
        updateSelectionState()
    }
    
    private func toggleItalic() {
        guard let textView = textView,
              let textStorage = textView.textStorage else { return }
        
        let range = textView.selectedRange()
        guard range.length > 0 && range.location < textView.string.count else { return }
        
        // 检查当前是否斜体（检查选中范围的第一个字符）
        var shouldItalic = true
        if range.location < textStorage.length {
            if let font = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont {
                if font.fontDescriptor.symbolicTraits.contains(.italic) {
                    shouldItalic = false
                }
            }
        }
        
        // 应用或移除斜体
        textStorage.beginEditing()
        textStorage.enumerateAttribute(.font, in: range, options: []) { (value, subrange, _) in
            if let oldFont = value as? NSFont {
                let fontSize = oldFont.pointSize
                var fontDescriptor = oldFont.fontDescriptor
                var traits = fontDescriptor.symbolicTraits
                
                if shouldItalic {
                    // 添加斜体
                    traits.insert(.italic)
                } else {
                    // 移除斜体
                    traits.remove(.italic)
                }
                
                fontDescriptor = fontDescriptor.withSymbolicTraits(traits)
                let newFont = NSFont(descriptor: fontDescriptor, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
                textStorage.addAttribute(.font, value: newFont, range: subrange)
            } else {
                let baseFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
                var fontDescriptor = baseFont.fontDescriptor
                if shouldItalic {
                    fontDescriptor = fontDescriptor.withSymbolicTraits([.italic])
                }
                let newFont = NSFont(descriptor: fontDescriptor, size: baseFont.pointSize) ?? baseFont
                textStorage.addAttribute(.font, value: newFont, range: subrange)
            }
        }
        textStorage.endEditing()
        
        textView.didChangeText()
        updateSelectionState()
    }
    
    private func applyHighlight() {
        guard let textView = textView,
              let textStorage = textView.textStorage else { return }
        
        let range = textView.selectedRange()
        guard range.length > 0 else { return }
        
        // 使用小米笔记的高亮颜色 #9affe8af
        let highlightColor = NSColor(hex: "9affe8af") ?? NSColor.yellow.withAlphaComponent(0.5)
        
        // 检查是否已经有高亮
        var hasHighlight = false
        textStorage.enumerateAttribute(.backgroundColor, in: range, options: []) { (value, _, _) in
            if value != nil {
                hasHighlight = true
            }
        }
        
        if hasHighlight {
            // 移除高亮
            textStorage.removeAttribute(.backgroundColor, range: range)
        } else {
            // 添加高亮
            textStorage.addAttribute(.backgroundColor, value: highlightColor, range: range)
        }
        
        textView.didChangeText()
    }
    
    private func setFontSize(_ size: CGFloat) {
        guard let textView = textView,
              let textStorage = textView.textStorage else { return }
        
        let range = textView.selectedRange()
        guard range.length > 0 else { return }
        
        textStorage.enumerateAttribute(.font, in: range, options: []) { (value, subrange, _) in
            if let oldFont = value as? NSFont {
                let newFont = NSFont(descriptor: oldFont.fontDescriptor, size: size) ?? NSFont.systemFont(ofSize: size)
                textStorage.addAttribute(.font, value: newFont, range: subrange)
            } else {
                let newFont = NSFont.systemFont(ofSize: size)
                textStorage.addAttribute(.font, value: newFont, range: subrange)
            }
        }
        
        textView.didChangeText()
    }
}

