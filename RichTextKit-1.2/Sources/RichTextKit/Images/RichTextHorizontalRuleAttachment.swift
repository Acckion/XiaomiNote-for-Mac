//
//  RichTextHorizontalRuleAttachment.swift
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
 A custom attachment type for horizontal rules (dividers) in rich text.
 
 This attachment renders a horizontal line that spans the full width
 of the text container. It adapts to light and dark appearance modes.
 */
@preconcurrency @MainActor
open class RichTextHorizontalRuleAttachment: NSTextAttachment {
    
    /**
     Create a horizontal rule attachment.
     */
    public convenience init() {
        self.init(data: nil, ofType: nil)
        setupHorizontalRule()
    }
    
    public override init(data contentData: Data?, ofType uti: String?) {
        super.init(data: contentData, ofType: uti)
        setupHorizontalRule()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupHorizontalRule()
    }
    
    public override class var supportsSecureCoding: Bool { true }
    
    private func setupHorizontalRule() {
        #if macOS
        bounds = NSRect(x: 0, y: 0, width: 10000, height: 1)
        #else
        bounds = CGRect(x: 0, y: 0, width: 10000, height: 1)
        #endif
    }
    
    #if macOS
    public override var attachmentCell: NSTextAttachmentCellProtocol? {
        get {
            return HorizontalRuleAttachmentCell()
        }
        set {
            super.attachmentCell = newValue
        }
    }
    #endif
}

#if macOS
/// Custom cell for horizontal rule that draws a full-width line
class HorizontalRuleAttachmentCell: NSTextAttachmentCell {
    
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        // Determine separator color based on appearance
        var separatorColor: NSColor
        
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
        
        if let appearance = appearance,
           appearance.name == .darkAqua || appearance.name == .vibrantDark {
            separatorColor = NSColor.white
        } else {
            separatorColor = NSColor.separatorColor
        }
        
        separatorColor.setFill()
        
        // 绘制分割线，高度为1，垂直居中
        let lineRect = NSRect(
            x: cellFrame.origin.x,
            y: cellFrame.midY - 0.5,
            width: cellFrame.width,
            height: 1.0
        )
        lineRect.fill()
    }
    
    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect, glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        var availableWidth = lineFrag.width
        
        if let textView = textContainer.layoutManager?.firstTextView {
            let textViewWidth = textView.bounds.width
            let padding = textContainer.lineFragmentPadding * 2
            let actualWidth = textViewWidth - padding
            
            if actualWidth > 0 && actualWidth > lineFrag.width {
                availableWidth = actualWidth
            }
        } else {
            let containerWidth = textContainer.containerSize.width
            if containerWidth < CGFloat.greatestFiniteMagnitude && containerWidth > lineFrag.width {
                let padding = textContainer.lineFragmentPadding * 2
                availableWidth = max(containerWidth - padding, lineFrag.width)
            }
        }
        
        availableWidth = max(availableWidth, lineFrag.width)
        
        // 使用行片段的高度作为分割线的高度，确保与正文高度相同
        let lineHeight = lineFrag.height
        
        return NSRect(
            x: lineFrag.origin.x,
            y: lineFrag.origin.y,
            width: availableWidth,
            height: lineHeight
        )
    }
    
    override var cellSize: NSSize {
        // 返回一个非常宽的尺寸，高度由 cellFrame 动态决定
        return NSSize(width: 10000, height: 1.0)
    }
}
#endif

#if iOS || os(tvOS) || os(visionOS)
extension RichTextHorizontalRuleAttachment {
    public override var image: UIImage? {
        get {
            // Create a 1-pixel wide image that will be stretched
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
            return renderer.image { context in
                UIColor.separator.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
            }
        }
        set {
            super.image = newValue
        }
    }
}
#endif

#endif

