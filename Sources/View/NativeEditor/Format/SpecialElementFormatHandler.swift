//
//  SpecialElementFormatHandler.swift
//  MiNoteMac
//
//  特殊元素格式处理器 - 处理复选框、分割线、图片等特殊元素的格式应用逻辑

import AppKit
import SwiftUI

// MARK: - 特殊元素格式决策

/// 特殊元素格式应用决策
enum SpecialElementFormatDecision {
    /// 允许应用格式
    case allow
    /// 禁止应用格式
    case deny
    /// 跳过特殊元素，只应用到普通文本
    case skipElement
}

// MARK: - 特殊元素检测结果

/// 特殊元素检测结果
struct SpecialElementDetectionResult {
    /// 检测到的特殊元素类型
    let elementType: SpecialElement?
    /// 元素范围
    let range: NSRange
    /// 是否在特殊元素内部
    let isInsideElement: Bool
    /// 是否在特殊元素附近（前后 1 个字符）
    let isNearElement: Bool
}

// MARK: - 特殊元素格式处理器

/// 特殊元素格式处理器
/// 
/// 负责处理复选框、分割线、图片等特殊元素的格式应用逻辑。
/// 需求: 7.1, 7.2, 7.3, 7.4
@MainActor
class SpecialElementFormatHandler {
    
    // MARK: - Singleton
    
    static let shared = SpecialElementFormatHandler()
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// 检测指定位置的特殊元素
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 特殊元素检测结果
    /// 需求: 7.1, 7.2, 7.3
    func detectSpecialElement(
        in textStorage: NSAttributedString,
        at position: Int
    ) -> SpecialElementDetectionResult {
        guard position >= 0 && position < textStorage.length else {
            return SpecialElementDetectionResult(
                elementType: nil,
                range: NSRange(location: position, length: 0),
                isInsideElement: false,
                isNearElement: false
            )
        }
        
        let attributes = textStorage.attributes(at: position, effectiveRange: nil)
        
        // 检查是否有附件
        if let attachment = attributes[.attachment] as? NSTextAttachment {
            let elementType = identifyAttachmentType(attachment)
            return SpecialElementDetectionResult(
                elementType: elementType,
                range: NSRange(location: position, length: 1),
                isInsideElement: true,
                isNearElement: true
            )
        }
        
        // 检查附近是否有特殊元素
        let nearbyResult = checkNearbySpecialElements(in: textStorage, at: position)
        return nearbyResult
    }
    
    /// 检测选中范围内的特殊元素
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 选中范围
    /// - Returns: 特殊元素检测结果数组
    func detectSpecialElements(
        in textStorage: NSAttributedString,
        range: NSRange
    ) -> [SpecialElementDetectionResult] {
        var results: [SpecialElementDetectionResult] = []
        
        textStorage.enumerateAttribute(.attachment, in: range, options: []) { value, attrRange, _ in
            if let attachment = value as? NSTextAttachment {
                let elementType = identifyAttachmentType(attachment)
                let result = SpecialElementDetectionResult(
                    elementType: elementType,
                    range: attrRange,
                    isInsideElement: true,
                    isNearElement: true
                )
                results.append(result)
            }
        }
        
        return results
    }
    
    /// 决定是否应该应用格式到特殊元素
    /// - Parameters:
    ///   - format: 格式类型
    ///   - elementType: 特殊元素类型
    /// - Returns: 格式应用决策
    /// 需求: 7.4
    func shouldApplyFormat(
        _ format: TextFormat,
        to elementType: SpecialElement
    ) -> SpecialElementFormatDecision {
        switch elementType {
        case .checkbox:
            // 复选框：允许应用内联格式到复选框后的文本
            return format.isInlineFormat ? .skipElement : .deny
            
        case .horizontalRule:
            // 分割线：禁止应用任何格式
            return .deny
            
        case .image:
            // 图片：禁止应用文本格式
            return .deny
            
        case .audio:
            // 语音录音：禁止应用文本格式
            return .deny
            
        case .bulletPoint, .numberedItem:
            // 列表项：允许应用内联格式到列表项后的文本
            return format.isInlineFormat ? .skipElement : .deny
            
        case .quote:
            // 引用块：允许应用内联格式
            return format.isInlineFormat ? .allow : .deny
        }
    }
    
    /// 应用格式到包含特殊元素的范围
    /// - Parameters:
    ///   - format: 格式类型
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    /// - Returns: 实际应用格式的范围数组
    /// 需求: 7.4
    func applyFormatWithSpecialElements(
        _ format: TextFormat,
        to textStorage: NSTextStorage,
        range: NSRange
    ) -> [NSRange] {
        let specialElements = detectSpecialElements(in: textStorage, range: range)
        
        print("[SpecialElementFormat] 应用格式: \(format.displayName)")
        print("[SpecialElementFormat]   - 范围: \(range)")
        print("[SpecialElementFormat]   - 特殊元素数量: \(specialElements.count)")
        
        // 如果没有特殊元素，直接应用格式
        if specialElements.isEmpty {
            return [range]
        }
        
        // 计算需要应用格式的范围（排除特殊元素）
        var applicableRanges: [NSRange] = []
        var currentLocation = range.location
        
        for element in specialElements.sorted(by: { $0.range.location < $1.range.location }) {
            guard let elementType = element.elementType else { continue }
            
            let decision = shouldApplyFormat(format, to: elementType)
            
            print("[SpecialElementFormat]   - 元素: \(elementType.displayName), 决策: \(decision)")
            
            switch decision {
            case .allow:
                // 允许应用，不需要特殊处理
                break
                
            case .deny, .skipElement:
                // 添加元素之前的范围
                if currentLocation < element.range.location {
                    let beforeRange = NSRange(
                        location: currentLocation,
                        length: element.range.location - currentLocation
                    )
                    if beforeRange.length > 0 {
                        applicableRanges.append(beforeRange)
                    }
                }
                currentLocation = element.range.location + element.range.length
            }
        }
        
        // 添加最后一个元素之后的范围
        let endLocation = range.location + range.length
        if currentLocation < endLocation {
            let afterRange = NSRange(
                location: currentLocation,
                length: endLocation - currentLocation
            )
            if afterRange.length > 0 {
                applicableRanges.append(afterRange)
            }
        }
        
        // 如果没有需要排除的元素，返回原始范围
        if applicableRanges.isEmpty && specialElements.allSatisfy({ element in
            guard let elementType = element.elementType else { return true }
            return shouldApplyFormat(format, to: elementType) == .allow
        }) {
            return [range]
        }
        
        print("[SpecialElementFormat]   - 实际应用范围: \(applicableRanges)")
        return applicableRanges
    }
    
    /// 获取特殊元素附近应该禁用的格式按钮
    /// - Parameter elementType: 特殊元素类型
    /// - Returns: 应该禁用的格式类型数组
    /// 需求: 7.2
    func getDisabledFormats(for elementType: SpecialElement) -> [TextFormat] {
        switch elementType {
        case .horizontalRule:
            // 分割线附近禁用所有格式
            return TextFormat.allCases
            
        case .image:
            // 图片附近禁用所有文本格式
            return TextFormat.allCases.filter { $0.isInlineFormat }
            
        case .audio:
            // 语音录音附近禁用所有文本格式
            return TextFormat.allCases.filter { $0.isInlineFormat }
            
        case .checkbox, .bulletPoint, .numberedItem:
            // 列表项附近禁用块级格式
            return TextFormat.allCases.filter { $0.isBlockFormat }
            
        case .quote:
            // 引用块附近禁用其他块级格式
            return [.heading1, .heading2, .heading3, .bulletList, .numberedList, .checkbox]
        }
    }
    
    // MARK: - Private Methods
    
    /// 识别附件类型
    private func identifyAttachmentType(_ attachment: NSTextAttachment) -> SpecialElement? {
        if let checkboxAttachment = attachment as? InteractiveCheckboxAttachment {
            return .checkbox(checked: checkboxAttachment.isChecked, level: checkboxAttachment.level)
        } else if attachment is HorizontalRuleAttachment {
            return .horizontalRule
        } else if let bulletAttachment = attachment as? BulletAttachment {
            return .bulletPoint(indent: bulletAttachment.indent)
        } else if let orderAttachment = attachment as? OrderAttachment {
            return .numberedItem(number: orderAttachment.number, indent: orderAttachment.indent)
        } else if let imageAttachment = attachment as? ImageAttachment {
            return .image(fileId: imageAttachment.fileId, src: imageAttachment.src)
        }
        return nil
    }
    
    /// 检查附近是否有特殊元素
    private func checkNearbySpecialElements(
        in textStorage: NSAttributedString,
        at position: Int
    ) -> SpecialElementDetectionResult {
        // 检查前一个位置
        if position > 0 {
            let prevAttributes = textStorage.attributes(at: position - 1, effectiveRange: nil)
            if let attachment = prevAttributes[.attachment] as? NSTextAttachment {
                let elementType = identifyAttachmentType(attachment)
                return SpecialElementDetectionResult(
                    elementType: elementType,
                    range: NSRange(location: position - 1, length: 1),
                    isInsideElement: false,
                    isNearElement: true
                )
            }
        }
        
        // 检查后一个位置
        if position < textStorage.length - 1 {
            let nextAttributes = textStorage.attributes(at: position + 1, effectiveRange: nil)
            if let attachment = nextAttributes[.attachment] as? NSTextAttachment {
                let elementType = identifyAttachmentType(attachment)
                return SpecialElementDetectionResult(
                    elementType: elementType,
                    range: NSRange(location: position + 1, length: 1),
                    isInsideElement: false,
                    isNearElement: true
                )
            }
        }
        
        return SpecialElementDetectionResult(
            elementType: nil,
            range: NSRange(location: position, length: 0),
            isInsideElement: false,
            isNearElement: false
        )
    }
}

// MARK: - NativeEditorContext Extension

extension NativeEditorContext {
    
    /// 检测当前光标位置的特殊元素
    /// - Returns: 特殊元素检测结果
    func detectSpecialElementAtCursorPosition() -> SpecialElementDetectionResult {
        return SpecialElementFormatHandler.shared.detectSpecialElement(
            in: nsAttributedText,
            at: cursorPosition
        )
    }
    
    /// 获取当前位置应该禁用的格式按钮
    /// - Returns: 应该禁用的格式类型数组
    func getDisabledFormatsAtCursor() -> [TextFormat] {
        let detection = detectSpecialElementAtCursorPosition()
        guard let elementType = detection.elementType else {
            return []
        }
        return SpecialElementFormatHandler.shared.getDisabledFormats(for: elementType)
    }
    
    /// 检查指定格式在当前位置是否可用
    /// - Parameter format: 格式类型
    /// - Returns: 是否可用
    func isFormatAvailableAtCursor(_ format: TextFormat) -> Bool {
        let disabledFormats = getDisabledFormatsAtCursor()
        return !disabledFormats.contains(format)
    }
}
