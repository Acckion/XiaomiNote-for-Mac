import Foundation
import SwiftUI

/// AttributedString 和 RTF Data 之间的转换工具
@available(macOS 14.0, *)
public struct AttributedStringConverter {
    
    /// 将 archivedData 转换为 AttributedString
    /// 只支持 archivedData 格式（RichTextKit 的标准格式）
    public static func rtfDataToAttributedString(_ rtfData: Data?) -> AttributedString? {
        guard let rtfData = rtfData else {
            print("![[debug]] [AttributedStringConverter] archivedData 为 nil")
            return nil
        }
        
        print("![[debug]] [AttributedStringConverter] 开始转换 archivedData，长度: \(rtfData.count) 字节")
        
        // 使用 RichTextKit 的 archivedData 格式
        do {
            let nsAttributedString = try NSAttributedString(data: rtfData, format: .archivedData)
            print("![[debug]] [AttributedStringConverter] ✅ 使用 archivedData 格式成功，长度: \(nsAttributedString.length)")
            return AttributedString(nsAttributedString)
        } catch {
            print("![[debug]] [AttributedStringConverter] ❌ archivedData 格式失败: \(error)")
            return nil
        }
    }
    
    /// 将 AttributedString 转换为 archivedData
    /// 使用 RichTextKit 的 archivedData 格式（支持所有附件类型）
    public static func attributedStringToRTFData(_ attributedString: AttributedString) -> Data? {
        // 将 AttributedString 转换为 NSAttributedString
        let nsAttributedString = NSAttributedString(attributedString)
        
        // 使用 archivedData 格式（RichTextKit 标准格式）
        return try? nsAttributedString.richTextData(for: .archivedData)
    }
    
    /// 将 XML 内容转换为 AttributedString（用于向后兼容）
    public static func xmlToAttributedString(_ xmlContent: String, noteRawData: [String: Any]?) -> AttributedString? {
        guard !xmlContent.isEmpty else { return nil }
        
        // 确保正文以 <new-format/> 开头
        var bodyContent = xmlContent
        if !bodyContent.hasPrefix("<new-format/>") {
            bodyContent = "<new-format/>" + bodyContent
        }
        
        // 将 XML 转换为 NSAttributedString
        let nsAttributedString = MiNoteContentParser.parseToAttributedString(bodyContent, noteRawData: noteRawData)
        
        // 调试：检查 NSAttributedString 的属性
        print("🔍 [AttributedStringConverter] NSAttributedString 长度: \(nsAttributedString.length)")
        if nsAttributedString.length > 0 {
            let attrs = nsAttributedString.attributes(at: 0, effectiveRange: nil)
            print("🔍 [AttributedStringConverter] 第一个字符的属性:")
            if let font = attrs[.font] as? NSFont {
                print("  - 字体: \(font.fontName), 大小: \(font.pointSize), 加粗: \(font.fontDescriptor.symbolicTraits.contains(.bold)), 斜体: \(font.fontDescriptor.symbolicTraits.contains(.italic))")
            }
            if let underlineStyle = attrs[.underlineStyle] as? Int {
                print("  - 下划线: \(underlineStyle)")
            }
            if let strikethroughStyle = attrs[.strikethroughStyle] as? Int {
                print("  - 删除线: \(strikethroughStyle)")
            }
            if let backgroundColor = attrs[.backgroundColor] as? NSColor {
                print("  - 背景色: \(backgroundColor)")
            }
        }
        
        // 将 NSAttributedString 转换为 AttributedString
        // 直接转换，不再使用 RTF 作为中间格式
        let attributedString = AttributedString(nsAttributedString)
        print("✅ [AttributedStringConverter] 直接转换为 AttributedString")
        
        // 调试：检查转换后的 AttributedString 的属性
        print("🔍 [AttributedStringConverter] AttributedString 字符数: \(attributedString.characters.count)")
        if !attributedString.characters.isEmpty {
            let firstRun = attributedString.runs.first
            print("🔍 [AttributedStringConverter] 第一个 run 的属性:")
            if let font = firstRun?.font {
                print("  - 字体: \(font)")
            }
            if let underlineStyle = firstRun?.underlineStyle {
                print("  - 下划线: \(underlineStyle)")
            }
            if let strikethroughStyle = firstRun?.strikethroughStyle {
                print("  - 删除线: \(strikethroughStyle)")
            }
            if let backgroundColor = firstRun?.backgroundColor {
                print("  - 背景色: \(backgroundColor)")
            }
        }
        
        return attributedString
    }
    
    /// 将 AttributedString 转换为 XML（用于同步到云端）
    public static func attributedStringToXML(_ attributedString: AttributedString) -> String {
        print("[[调试]]步骤12 [AttributedStringConverter] 开始AttributedString到XML转换，输入AttributedString长度: \(attributedString.characters.count)")
        // 将 AttributedString 转换为 NSAttributedString
        let nsAttributedString = NSAttributedString(attributedString)
        print("[[调试]]步骤13 [AttributedStringConverter] 转换为NSAttributedString，长度: \(nsAttributedString.length)")
        
        // 将 NSAttributedString 转换为 XML
        print("[[调试]]步骤14 [AttributedStringConverter] 调用MiNoteContentParser.parseToXML，输入NSAttributedString长度: \(nsAttributedString.length)")
        var xmlContent = MiNoteContentParser.parseToXML(nsAttributedString)
        
        // 清理内容：移除开头的空段落
        xmlContent = xmlContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if xmlContent.isEmpty {
            xmlContent = "<new-format/><text indent=\"1\"></text>"
        }
        
        print("[[调试]]步骤15 [AttributedStringConverter] XML转换完成，XML内容长度: \(xmlContent.count), 内容预览: \(xmlContent.prefix(100))")
        return xmlContent
    }
    
    /// 创建带有默认属性的空 AttributedString（用于新建笔记）
    /// 确保文本颜色等属性正确设置，适配深色模式
    public static func createEmptyAttributedString() -> AttributedString {
        // 创建一个带有默认属性的 NSAttributedString
        let defaultAttributes = MiNoteContentParser.defaultAttributes()
        let nsAttributedString = NSAttributedString(string: "", attributes: defaultAttributes)
        
        // 转换为 AttributedString
        return AttributedString(nsAttributedString)
    }
}

