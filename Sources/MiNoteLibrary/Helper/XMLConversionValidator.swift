import Foundation
import AppKit

/// XML转换验证器
/// 
/// 用于验证小米笔记XML格式转换的正确性和可逆性
/// 提供详细的验证报告和问题诊断
class XMLConversionValidator {
    
    // MARK: - 验证方法
    
    /// 验证XML转换的可逆性
    /// 
    /// 执行完整的往返转换测试，验证：
    /// 1. XML -> AttributedString 转换是否正确
    /// 2. AttributedString -> XML 转换是否正确
    /// 3. 往返转换是否可逆（XML -> AttributedString -> XML 应该得到等价的XML）
    /// 
    /// - Parameters:
    ///   - xml: 要测试的XML内容
    ///   - noteRawData: 笔记原始数据（用于图片等）
    /// - Returns: 验证结果，包含详细的验证信息
    static func validateReversibility(
        xml: String,
        noteRawData: [String: Any]? = nil
    ) -> ValidationResult {
        print("🔍 [XMLConversionValidator] 开始验证XML转换可逆性")
        print("🔍 [XMLConversionValidator] 输入XML长度: \(xml.count)")
        
        var issues: [ValidationIssue] = []
        
        // 步骤1: XML -> AttributedString
        let attributedString = MiNoteContentParser.parseToAttributedString(xml, noteRawData: noteRawData)
        if attributedString.length == 0 && !xml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(
                type: .conversionError,
                severity: .error,
                message: "XML转换为AttributedString失败：结果为空",
                location: "XML -> AttributedString"
            ))
        }
        
        // 步骤2: AttributedString -> XML
        let convertedXML = MiNoteContentParser.parseToXML(attributedString)
        if convertedXML.isEmpty {
            issues.append(.init(
                type: .conversionError,
                severity: .error,
                message: "AttributedString转换为XML失败：结果为空",
                location: "AttributedString -> XML"
            ))
        }
        
        // 步骤3: 验证可逆性
        let reversibilityResult = XMLConversionTester.testRoundTripConversion(
            originalXML: xml,
            noteRawData: noteRawData
        )
        
        if !reversibilityResult.success {
            issues.append(.init(
                type: .reversibilityError,
                severity: .error,
                message: "往返转换不可逆：转换后的XML与原始XML不等价",
                location: "往返转换",
                details: reversibilityResult.differences
            ))
        }
        
        // 步骤4: 验证文本内容一致性
        let originalText = extractPlainText(from: xml)
        let convertedText = attributedString.string
        if originalText != convertedText {
            issues.append(.init(
                type: .contentMismatch,
                severity: .warning,
                message: "文本内容不一致",
                location: "文本提取",
                details: ["原始文本: \(originalText.prefix(50))", "转换后文本: \(convertedText.prefix(50))"]
            ))
        }
        
        // 步骤5: 验证格式属性
        let formatIssues = validateFormatAttributes(xml: xml, attributedString: attributedString)
        issues.append(contentsOf: formatIssues)
        
        let result = ValidationResult(
            isValid: issues.isEmpty || issues.allSatisfy { $0.severity != .error },
            originalXML: xml,
            convertedXML: convertedXML,
            attributedString: attributedString,
            issues: issues
        )
        
        print("🔍 [XMLConversionValidator] 验证完成")
        if result.isValid {
            print("✅ [XMLConversionValidator] 验证通过：XML转换可逆")
        } else {
            print("❌ [XMLConversionValidator] 验证失败：发现 \(issues.count) 个问题")
            for issue in issues {
                print("   - [\(issue.severity)] \(issue.message)")
            }
        }
        
        return result
    }
    
    /// 验证格式属性
    private static func validateFormatAttributes(xml: String, attributedString: NSAttributedString) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        
        // 检查加粗
        if xml.contains("<b>") {
            let hasBold = attributedString.string.unicodeScalars.enumerated().contains { (index, _) in
                if let font = attributedString.attribute(.font, at: index, effectiveRange: nil) as? NSFont {
                    return font.fontDescriptor.symbolicTraits.contains(.bold)
                }
                return false
            }
            if !hasBold {
                issues.append(.init(
                    type: .formatMissing,
                    severity: .warning,
                    message: "XML中包含<b>标签，但AttributedString中未检测到加粗格式",
                    location: "格式验证"
                ))
            }
        }
        
        // 检查斜体
        if xml.contains("<i>") {
            let hasItalic = attributedString.string.unicodeScalars.enumerated().contains { (index, _) in
                if let font = attributedString.attribute(.font, at: index, effectiveRange: nil) as? NSFont {
                    return font.fontDescriptor.symbolicTraits.contains(.italic)
                }
                return false
            }
            if !hasItalic {
                issues.append(.init(
                    type: .formatMissing,
                    severity: .warning,
                    message: "XML中包含<i>标签，但AttributedString中未检测到斜体格式",
                    location: "格式验证"
                ))
            }
        }
        
        // 检查标题
        if xml.contains("<size>") || xml.contains("<mid-size>") || xml.contains("<h3-size>") {
            let hasHeading = attributedString.string.unicodeScalars.enumerated().contains { (index, _) in
                if let font = attributedString.attribute(.font, at: index, effectiveRange: nil) as? NSFont {
                    return font.pointSize >= 14.0 // h3FontSize
                }
                return false
            }
            if !hasHeading {
                issues.append(.init(
                    type: .formatMissing,
                    severity: .warning,
                    message: "XML中包含标题标签，但AttributedString中未检测到标题格式",
                    location: "格式验证"
                ))
            }
        }
        
        return issues
    }
    
    /// 从XML中提取纯文本（用于比较）
    private static func extractPlainText(from xml: String) -> String {
        // 移除所有XML标签
        var text = xml
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<new-format/>", with: "")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }
    
    // MARK: - 验证结果模型
    
    /// 验证结果
    struct ValidationResult {
        /// 是否有效（没有错误）
        let isValid: Bool
        
        /// 原始XML
        let originalXML: String
        
        /// 转换后的XML
        let convertedXML: String
        
        /// 中间AttributedString
        let attributedString: NSAttributedString
        
        /// 发现的问题
        let issues: [ValidationIssue]
    }
    
    /// 验证问题
    struct ValidationIssue {
        enum IssueType {
            case conversionError      // 转换错误
            case reversibilityError   // 可逆性错误
            case contentMismatch      // 内容不匹配
            case formatMissing        // 格式缺失
        }
        
        enum Severity {
            case error
            case warning
        }
        
        let type: IssueType
        let severity: Severity
        let message: String
        let location: String
        let details: [String]
        
        init(type: IssueType, severity: Severity, message: String, location: String, details: [String] = []) {
            self.type = type
            self.severity = severity
            self.message = message
            self.location = location
            self.details = details
        }
    }
}

