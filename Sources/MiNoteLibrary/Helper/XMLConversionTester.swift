import Foundation
import AppKit

/// XML转换可逆性测试工具
/// 
/// 用于验证小米笔记XML格式与NSAttributedString之间的转换是否可逆
/// 这是确保数据完整性的关键测试
class XMLConversionTester {
    
    // MARK: - 可逆性测试
    
    /// 测试XML到AttributedString再到XML的往返转换
    /// 
    /// 验证转换的可逆性：XML -> AttributedString -> XML 应该得到相同或等价的XML
    /// 
    /// - Parameters:
    ///   - originalXML: 原始XML内容
    ///   - noteRawData: 笔记原始数据（用于图片等）
    /// - Returns: 测试结果，包含是否成功、原始XML、转换后的XML等信息
    static func testRoundTripConversion(
        originalXML: String,
        noteRawData: [String: Any]? = nil
    ) -> RoundTripTestResult {
        print("🔄 [XMLConversionTester] 开始往返转换测试")
        print("🔄 [XMLConversionTester] 原始XML长度: \(originalXML.count)")
        print("🔄 [XMLConversionTester] 原始XML预览: \(String(originalXML.prefix(200)))")
        
        // 步骤1: XML -> NSAttributedString
        let attributedString = MiNoteContentParser.parseToAttributedString(originalXML, noteRawData: noteRawData)
        print("🔄 [XMLConversionTester] 转换为AttributedString，长度: \(attributedString.length)")
        
        // 步骤2: NSAttributedString -> XML
        let convertedXML = MiNoteContentParser.parseToXML(attributedString)
        print("🔄 [XMLConversionTester] 转换回XML，长度: \(convertedXML.count)")
        print("🔄 [XMLConversionTester] 转换后XML预览: \(String(convertedXML.prefix(200)))")
        
        // 步骤3: 比较结果
        let isEquivalent = areXMLEquivalent(originalXML, convertedXML)
        
        let result = RoundTripTestResult(
            success: isEquivalent,
            originalXML: originalXML,
            convertedXML: convertedXML,
            attributedStringLength: attributedString.length,
            differences: isEquivalent ? [] : findDifferences(originalXML, convertedXML)
        )
        
        if result.success {
            print("✅ [XMLConversionTester] 往返转换测试通过")
        } else {
            print("❌ [XMLConversionTester] 往返转换测试失败")
            print("❌ [XMLConversionTester] 差异数量: \(result.differences.count)")
            for (index, diff) in result.differences.enumerated() {
                print("❌ [XMLConversionTester] 差异 #\(index + 1): \(diff)")
            }
        }
        
        return result
    }
    
    /// 测试AttributedString到XML再到AttributedString的往返转换
    /// 
    /// 验证反向转换的可逆性：AttributedString -> XML -> AttributedString
    /// 
    /// - Parameters:
    ///   - originalAttributedString: 原始AttributedString
    ///   - noteRawData: 笔记原始数据
    /// - Returns: 测试结果
    static func testReverseRoundTripConversion(
        originalAttributedString: NSAttributedString,
        noteRawData: [String: Any]? = nil
    ) -> ReverseRoundTripTestResult {
        print("🔄 [XMLConversionTester] 开始反向往返转换测试")
        print("🔄 [XMLConversionTester] 原始AttributedString长度: \(originalAttributedString.length)")
        
        // 步骤1: NSAttributedString -> XML
        let xml = MiNoteContentParser.parseToXML(originalAttributedString)
        print("🔄 [XMLConversionTester] 转换为XML，长度: \(xml.count)")
        
        // 步骤2: XML -> NSAttributedString
        let convertedAttributedString = MiNoteContentParser.parseToAttributedString(xml, noteRawData: noteRawData)
        print("🔄 [XMLConversionTester] 转换回AttributedString，长度: \(convertedAttributedString.length)")
        
        // 步骤3: 比较结果（比较文本内容和主要属性）
        let isEquivalent = areAttributedStringsEquivalent(originalAttributedString, convertedAttributedString)
        
        let result = ReverseRoundTripTestResult(
            success: isEquivalent,
            originalAttributedString: originalAttributedString,
            convertedAttributedString: convertedAttributedString,
            intermediateXML: xml,
            differences: isEquivalent ? [] : findAttributedStringDifferences(originalAttributedString, convertedAttributedString)
        )
        
        if result.success {
            print("✅ [XMLConversionTester] 反向往返转换测试通过")
        } else {
            print("❌ [XMLConversionTester] 反向往返转换测试失败")
            print("❌ [XMLConversionTester] 差异数量: \(result.differences.count)")
            for (index, diff) in result.differences.enumerated() {
                print("❌ [XMLConversionTester] 差异 #\(index + 1): \(diff)")
            }
        }
        
        return result
    }
    
    // MARK: - 等价性检查
    
    /// 检查两个XML是否等价
    /// 
    /// 注意：由于XML格式可能略有不同（如属性顺序、空白字符等），
    /// 这里进行语义等价性检查，而不是严格的字符串比较
    private static func areXMLEquivalent(_ xml1: String, _ xml2: String) -> Bool {
        // 1. 规范化XML（移除多余空白、统一格式）
        let normalized1 = normalizeXML(xml1)
        let normalized2 = normalizeXML(xml2)
        
        // 2. 如果规范化后相同，则认为等价
        if normalized1 == normalized2 {
            return true
        }
        
        // 3. 解析并比较结构（更深入的检查）
        return compareXMLStructure(xml1, xml2)
    }
    
    /// 规范化XML（移除多余空白、统一格式）
    private static func normalizeXML(_ xml: String) -> String {
        var normalized = xml
        
        // 移除<new-format/>标签（如果存在）
        normalized = normalized.replacingOccurrences(of: "<new-format/>", with: "")
        
        // 规范化空白字符
        normalized = normalized.replacingOccurrences(of: "\n+", with: "\n", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return normalized
    }
    
    /// 比较XML结构（解析并比较内容）
    private static func compareXMLStructure(_ xml1: String, _ xml2: String) -> Bool {
        // 将XML转换为AttributedString，然后比较
        let attr1 = MiNoteContentParser.parseToAttributedString(xml1)
        let attr2 = MiNoteContentParser.parseToAttributedString(xml2)
        
        return areAttributedStringsEquivalent(attr1, attr2)
    }
    
    /// 检查两个AttributedString是否等价
    /// 
    /// 比较文本内容和主要格式属性
    private static func areAttributedStringsEquivalent(_ attr1: NSAttributedString, _ attr2: NSAttributedString) -> Bool {
        // 1. 文本内容必须相同
        if attr1.string != attr2.string {
            return false
        }
        
        // 2. 长度必须相同
        if attr1.length != attr2.length {
            return false
        }
        
        // 3. 比较主要属性（字体、颜色、样式等）
        let fullRange1 = NSRange(location: 0, length: attr1.length)
        let fullRange2 = NSRange(location: 0, length: attr2.length)
        
        // 比较每个字符的属性
        for i in 0..<min(attr1.length, attr2.length) {
            let range1 = NSRange(location: i, length: 1)
            let range2 = NSRange(location: i, length: 1)
            
            let attrs1 = attr1.attributes(at: i, effectiveRange: nil)
            let attrs2 = attr2.attributes(at: i, effectiveRange: nil)
            
            // 比较关键属性
            if !areAttributesEquivalent(attrs1, attrs2) {
                return false
            }
        }
        
        return true
    }
    
    /// 比较两个属性字典是否等价
    private static func areAttributesEquivalent(_ attrs1: [NSAttributedString.Key: Any], _ attrs2: [NSAttributedString.Key: Any]) -> Bool {
        // 比较字体
        let font1 = attrs1[.font] as? NSFont
        let font2 = attrs2[.font] as? NSFont
        if let f1 = font1, let f2 = font2 {
            if f1.pointSize != f2.pointSize {
                return false
            }
            let traits1 = f1.fontDescriptor.symbolicTraits
            let traits2 = f2.fontDescriptor.symbolicTraits
            if traits1.contains(.bold) != traits2.contains(.bold) {
                return false
            }
            if traits1.contains(.italic) != traits2.contains(.italic) {
                return false
            }
        } else if font1 != nil || font2 != nil {
            return false
        }
        
        // 比较下划线
        let underline1 = attrs1[.underlineStyle] as? Int ?? 0
        let underline2 = attrs2[.underlineStyle] as? Int ?? 0
        if underline1 != underline2 {
            return false
        }
        
        // 比较删除线
        let strikethrough1 = attrs1[.strikethroughStyle] as? Int ?? 0
        let strikethrough2 = attrs2[.strikethroughStyle] as? Int ?? 0
        if strikethrough1 != strikethrough2 {
            return false
        }
        
        // 比较背景色
        let bg1 = attrs1[.backgroundColor] as? NSColor
        let bg2 = attrs2[.backgroundColor] as? NSColor
        if let b1 = bg1, let b2 = bg2 {
            // 比较RGB和Alpha值（允许小的误差）
            let rgb1 = b1.usingColorSpace(.sRGB)
            let rgb2 = b2.usingColorSpace(.sRGB)
            if let r1 = rgb1, let r2 = rgb2 {
                if abs(r1.redComponent - r2.redComponent) > 0.01 ||
                   abs(r1.greenComponent - r2.greenComponent) > 0.01 ||
                   abs(r1.blueComponent - r2.blueComponent) > 0.01 ||
                   abs(r1.alphaComponent - r2.alphaComponent) > 0.01 {
                    return false
                }
            } else {
                return false
            }
        } else if bg1 != nil || bg2 != nil {
            return false
        }
        
        // 比较段落样式（对齐方式、缩进等）
        let para1 = attrs1[.paragraphStyle] as? NSParagraphStyle
        let para2 = attrs2[.paragraphStyle] as? NSParagraphStyle
        if let p1 = para1, let p2 = para2 {
            if p1.alignment != p2.alignment {
                return false
            }
            // 缩进比较（允许小的误差）
            if abs(p1.headIndent - p2.headIndent) > 1.0 {
                return false
            }
        } else if para1 != nil || para2 != nil {
            return false
        }
        
        return true
    }
    
    // MARK: - 差异查找
    
    /// 查找两个XML之间的差异
    private static func findDifferences(_ xml1: String, _ xml2: String) -> [String] {
        var differences: [String] = []
        
        // 1. 文本内容差异
        let attr1 = MiNoteContentParser.parseToAttributedString(xml1)
        let attr2 = MiNoteContentParser.parseToAttributedString(xml2)
        
        if attr1.string != attr2.string {
            differences.append("文本内容不同")
            // 找出第一个不同的字符位置
            let minLength = min(attr1.string.count, attr2.string.count)
            for i in 0..<minLength {
                let index1 = attr1.string.index(attr1.string.startIndex, offsetBy: i)
                let index2 = attr2.string.index(attr2.string.startIndex, offsetBy: i)
                if attr1.string[index1] != attr2.string[index2] {
                    differences.append("第一个不同字符位置: \(i)")
                    break
                }
            }
        }
        
        // 2. 属性差异
        let attrDiffs = findAttributedStringDifferences(attr1, attr2)
        differences.append(contentsOf: attrDiffs)
        
        return differences
    }
    
    /// 查找两个AttributedString之间的差异
    private static func findAttributedStringDifferences(_ attr1: NSAttributedString, _ attr2: NSAttributedString) -> [String] {
        var differences: [String] = []
        
        if attr1.length != attr2.length {
            differences.append("长度不同: \(attr1.length) vs \(attr2.length)")
        }
        
        let minLength = min(attr1.length, attr2.length)
        for i in 0..<minLength {
            let attrs1 = attr1.attributes(at: i, effectiveRange: nil)
            let attrs2 = attr2.attributes(at: i, effectiveRange: nil)
            
            if !areAttributesEquivalent(attrs1, attrs2) {
                differences.append("位置 \(i) 的属性不同")
                // 详细比较
                let font1 = attrs1[.font] as? NSFont
                let font2 = attrs2[.font] as? NSFont
                if let f1 = font1, let f2 = font2 {
                    if f1.pointSize != f2.pointSize {
                        differences.append("  字体大小: \(f1.pointSize) vs \(f2.pointSize)")
                    }
                    let bold1 = f1.fontDescriptor.symbolicTraits.contains(.bold)
                    let bold2 = f2.fontDescriptor.symbolicTraits.contains(.bold)
                    if bold1 != bold2 {
                        differences.append("  加粗: \(bold1) vs \(bold2)")
                    }
                    let italic1 = f1.fontDescriptor.symbolicTraits.contains(.italic)
                    let italic2 = f2.fontDescriptor.symbolicTraits.contains(.italic)
                    if italic1 != italic2 {
                        differences.append("  斜体: \(italic1) vs \(italic2)")
                    }
                }
            }
        }
        
        return differences
    }
    
    // MARK: - 测试结果模型
    
    /// 往返转换测试结果
    struct RoundTripTestResult {
        let success: Bool
        let originalXML: String
        let convertedXML: String
        let attributedStringLength: Int
        let differences: [String]
    }
    
    /// 反向往返转换测试结果
    struct ReverseRoundTripTestResult {
        let success: Bool
        let originalAttributedString: NSAttributedString
        let convertedAttributedString: NSAttributedString
        let intermediateXML: String
        let differences: [String]
    }
}

