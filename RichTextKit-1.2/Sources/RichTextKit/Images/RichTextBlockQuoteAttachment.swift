//
//  RichTextBlockQuoteAttachment.swift
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
 A custom attachment type for block quote indicators in rich text.
 
 This attachment renders a vertical line on the left side of a block quote.
 The actual quote content should be in the paragraph following this attachment.
 */
@preconcurrency @MainActor
open class RichTextBlockQuoteAttachment: NSTextAttachment {
    
    /// The color of the block quote indicator line
    public var indicatorColor: ColorRepresentable? {
        didSet {
            updateImage()
        }
    }
    
    /**
     Create a block quote attachment.
     
     - Parameters:
       - indicatorColor: Optional color for the indicator line
     */
    public convenience init(indicatorColor: ColorRepresentable? = nil) {
        self.init(data: nil, ofType: nil)
        self.indicatorColor = indicatorColor
        setupBlockQuote()
    }
    
    public override init(data contentData: Data?, ofType uti: String?) {
        super.init(data: contentData, ofType: uti)
        setupBlockQuote()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupBlockQuote()
    }
    
    public override class var supportsSecureCoding: Bool { true }
    
    private func setupBlockQuote() {
        updateImage()
        #if macOS
        bounds = NSRect(x: 0, y: 0, width: 4, height: 20)
        #else
        bounds = CGRect(x: 0, y: 0, width: 4, height: 20)
        #endif
    }
    
    private func updateImage() {
        #if macOS
        let size = NSSize(width: 4, height: 20)
        let image = NSImage(size: size)
        image.lockFocus()
        
        let color = (indicatorColor as? NSColor) ?? NSColor.systemGray
        color.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 20).fill()
        
        image.unlockFocus()
        self.image = image
        #else
        let size = CGSize(width: 4, height: 20)
        let renderer = UIGraphicsImageRenderer(size: size)
        let color = (indicatorColor as? UIColor) ?? UIColor.systemGray
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 20))
        }
        self.image = image
        #endif
    }
    
    #if macOS
    public override var attachmentCell: NSTextAttachmentCellProtocol? {
        get {
            return BlockQuoteAttachmentCell(blockQuote: self)
        }
        set {
            super.attachmentCell = newValue
        }
    }
    #endif
}

#if macOS
/// Custom cell for block quote indicator
class BlockQuoteAttachmentCell: NSTextAttachmentCell {
    weak var blockQuote: RichTextBlockQuoteAttachment?
    
    init(blockQuote: RichTextBlockQuoteAttachment) {
        self.blockQuote = blockQuote
        super.init(imageCell: blockQuote.image)
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let color = (blockQuote?.indicatorColor as? NSColor) ?? NSColor.systemGray
        color.setFill()
        NSRect(x: cellFrame.origin.x, y: cellFrame.origin.y, width: 4, height: cellFrame.height).fill()
    }
}
#endif

#endif


