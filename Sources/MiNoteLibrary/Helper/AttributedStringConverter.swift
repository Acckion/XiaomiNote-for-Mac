import Foundation
import SwiftUI

/// AttributedString 和 RTF Data 之间的转换工具
@available(macOS 14.0, *)
public struct AttributedStringConverter {
    
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
        
        // 将 NSAttributedString 转换为 AttributedString
        // 直接转换，不再使用 RTF 作为中间格式
        let attributedString = AttributedString(nsAttributedString)
        print("✅ [AttributedStringConverter] 直接转换为 AttributedString")
        
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

