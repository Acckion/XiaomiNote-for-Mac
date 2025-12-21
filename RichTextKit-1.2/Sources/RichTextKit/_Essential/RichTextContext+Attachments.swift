//
//  RichTextContext+Attachments.swift
//  RichTextKit
//
//  Created for MiNote integration.
//  Copyright © 2024. All rights reserved.
//

import Foundation
import AppKit

public extension RichTextContext {
    
    /// Insert a checkbox at the current selection or cursor position.
    ///
    /// - Parameters:
    ///   - isChecked: Whether the checkbox is initially checked
    ///   - withSpace: Whether to add a space after the checkbox
    func insertCheckbox(isChecked: Bool = false, withSpace: Bool = true) {
        let checkbox = RichTextCheckboxAttachment(isChecked: isChecked)
        let checkboxString = NSAttributedString(attachment: checkbox)
        let content = NSMutableAttributedString(attributedString: checkboxString)
        
        if withSpace {
            content.append(NSAttributedString(string: " "))
        }
        
        if hasSelectedRange {
            handle(.replaceSelectedText(with: content))
        } else {
            let insertLocation = selectedRange.location < attributedString.length 
                ? selectedRange.location 
                : attributedString.length
            handle(.replaceText(in: NSRange(location: insertLocation, length: 0), with: content))
        }
    }
    
    /// Insert a horizontal rule (divider) at the current selection or cursor position.
    ///
    /// - Parameters:
    ///   - withNewlines: Whether to add newlines before and after the rule
    func insertHorizontalRule(withNewlines: Bool = true) {
        let hr = RichTextHorizontalRuleAttachment()
        let hrString = NSAttributedString(attachment: hr)
        let content = NSMutableAttributedString()
        
        if withNewlines {
            content.append(NSAttributedString(string: "\n"))
        }
        content.append(hrString)
        if withNewlines {
            content.append(NSAttributedString(string: "\n"))
        }
        
        if hasSelectedRange {
            handle(.replaceSelectedText(with: content))
        } else {
            let insertLocation = selectedRange.location < attributedString.length 
                ? selectedRange.location 
                : attributedString.length
            handle(.replaceText(in: NSRange(location: insertLocation, length: 0), with: content))
        }
    }
    
    /// Insert a block quote indicator at the current selection or cursor position.
    ///
    /// - Parameters:
    ///   - indicatorColor: Optional color for the indicator line
    ///   - withSpace: Whether to add a space after the indicator
    func insertBlockQuote(indicatorColor: ColorRepresentable? = nil, withSpace: Bool = true) {
        let blockQuote = RichTextBlockQuoteAttachment(indicatorColor: indicatorColor)
        let blockQuoteString = NSAttributedString(attachment: blockQuote)
        let content = NSMutableAttributedString(attributedString: blockQuoteString)
        
        if withSpace {
            content.append(NSAttributedString(string: " "))
        }
        
        if hasSelectedRange {
            handle(.replaceSelectedText(with: content))
        } else {
            let insertLocation = selectedRange.location < attributedString.length 
                ? selectedRange.location 
                : attributedString.length
            handle(.replaceText(in: NSRange(location: insertLocation, length: 0), with: content))
        }
    }
    
    /// Apply block quote styling to the selected range or current paragraph.
    ///
    /// This adds left indentation and a visual indicator to create a block quote effect.
    func applyBlockQuoteStyling() {
        let range = hasSelectedRange ? selectedRange : NSRange(location: 0, length: attributedString.length)
        
        // Create paragraph style with left indent
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = 20
        paragraphStyle.headIndent = 20
        
        // Apply paragraph style
        var mutableString = NSMutableAttributedString(attributedString: attributedString)
        mutableString.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        
        // Insert block quote indicator at the start if not already present
        if range.location > 0 {
            let charBefore = mutableString.attributedSubstring(from: NSRange(location: range.location - 1, length: 1))
            if !charBefore.string.hasPrefix("\u{FFFC}") {
                let blockQuote = RichTextBlockQuoteAttachment()
                let blockQuoteString = NSAttributedString(attachment: blockQuote)
                mutableString.insert(blockQuoteString, at: range.location)
            }
        }
        
        handle(.setAttributedString(mutableString))
    }
}

