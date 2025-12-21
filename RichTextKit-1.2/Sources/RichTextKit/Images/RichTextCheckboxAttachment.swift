//
//  RichTextCheckboxAttachment.swift
//  RichTextKit
//
//  Created for MiNote integration.
//  Copyright © 2024. All rights reserved.
//

#if iOS || os(tvOS) || os(visionOS)
import UIKit
#endif

#if macOS
import AppKit
#endif

#if iOS || macOS || os(tvOS) || os(visionOS)

/**
 A custom attachment type for interactive checkboxes in rich text.
 
 This attachment provides a clickable checkbox that can be toggled
 between checked and unchecked states. It uses platform-specific
 rendering to ensure proper display and interaction.
 */
@preconcurrency @MainActor
open class RichTextCheckboxAttachment: NSTextAttachment {
    
    /// Whether the checkbox is checked
    public var isChecked: Bool = false {
        didSet {
            updateImage()
        }
    }
    
    /**
     Create a checkbox attachment with an initial checked state.
     
     - Parameters:
       - isChecked: Whether the checkbox is initially checked
     */
    public convenience init(isChecked: Bool = false) {
        self.init(data: nil, ofType: nil)
        self.isChecked = isChecked
        setupCheckbox()
    }
    
    public override init(data contentData: Data?, ofType uti: String?) {
        super.init(data: contentData, ofType: uti)
        setupCheckbox()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        if coder.containsValue(forKey: "isChecked") {
            self.isChecked = coder.decodeBool(forKey: "isChecked")
        }
        setupCheckbox()
    }
    
    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(isChecked, forKey: "isChecked")
    }
    
    public override class var supportsSecureCoding: Bool { true }
    
    private func setupCheckbox() {
        updateImage()
        #if macOS
        bounds = NSRect(x: 0, y: -4, width: 16, height: 16)
        #else
        bounds = CGRect(x: 0, y: -4, width: 16, height: 16)
        #endif
    }
    
    private func updateImage() {
        let symbolName = isChecked ? "checkmark.square.fill" : "square"
        #if macOS
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "checkbox") {
            image.size = NSSize(width: 16, height: 16)
            // 在深色模式下，将图片模板化并设置为白色
            image.isTemplate = false
            self.image = image
        }
        #else
        if let image = UIImage(systemName: symbolName) {
            self.image = image
        }
        #endif
    }
    
    #if macOS
    public override var attachmentCell: NSTextAttachmentCellProtocol? {
        get {
            return CheckboxAttachmentCell(checkbox: self)
        }
        set {
            super.attachmentCell = newValue
        }
    }
    #endif
}

#if macOS
/// Custom cell for checkbox attachment that handles mouse interaction
class CheckboxAttachmentCell: NSTextAttachmentCell {
    weak var checkbox: RichTextCheckboxAttachment?
    
    init(checkbox: RichTextCheckboxAttachment) {
        self.checkbox = checkbox
        super.init(imageCell: checkbox.image)
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        if let checkbox = checkbox, let updatedImage = checkbox.image {
            image = updatedImage
        }
        
        guard let imageToDraw = image else { return }
        
        // 检查是否为深色模式
        var appearance: NSAppearance?
        if let controlView = controlView {
            appearance = controlView.effectiveAppearance
            if appearance == nil, let window = controlView.window {
                appearance = window.effectiveAppearance
            }
        }
        if appearance == nil {
            appearance = NSAppearance.current
        }
        
        let isDarkMode = appearance?.name == .darkAqua || appearance?.name == .vibrantDark
        
        if isDarkMode {
            // 深色模式：使用白色渲染
            // 使用模板图片模式，然后应用白色
            NSGraphicsContext.saveGraphicsState()
            let context = NSGraphicsContext.current
            context?.imageInterpolation = .high
            
            // 设置白色作为当前颜色
            NSColor.white.set()
            
            // 将图片作为模板绘制（模板图片会使用当前颜色）
            let templateImage = imageToDraw.copy() as! NSImage
            templateImage.isTemplate = true
            templateImage.draw(in: cellFrame)
            
            NSGraphicsContext.restoreGraphicsState()
        } else {
            // 浅色模式：正常渲染
            imageToDraw.draw(in: cellFrame)
        }
    }
    
    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect, glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        var rect = super.cellFrame(for: textContainer, proposedLineFragment: lineFrag, glyphPosition: position, characterIndex: charIndex)
        rect.origin.y -= 2
        return rect
    }
    
    // 注意：hitTest 方法可能在新版本的 macOS SDK 中已变更
    // 如果父类没有这个方法，可能需要通过 NSTextView 的鼠标事件处理来实现点击功能
    func hitTest(for point: NSPoint, in cellFrame: NSRect, of controlView: NSView?) -> NSCell.HitResult {
        if cellFrame.contains(point) {
            return .contentArea
        }
        // NSCell.HitResult 是一个选项集，使用空数组表示无命中
        return []
    }
    
    // trackMouse 方法存在于 NSCell 中，需要 override
    override func trackMouse(with theEvent: NSEvent, in cellFrame: NSRect, of controlView: NSView?, untilMouseUp flag: Bool) -> Bool {
        if let checkbox = checkbox {
            checkbox.isChecked.toggle()
            image = checkbox.image
            if let textView = controlView as? NSTextView {
                textView.setNeedsDisplay(cellFrame)
            }
            return true
        }
        return false
    }
}
#endif

#endif

