//
//  XMLEntityCodec.swift
//  MiNoteMac
//
//  XML 实体编解码工具
//  用于处理 XML 特殊字符的编码和解码
//

import Foundation

/// XML 实体编解码工具
///
/// 支持标准 XML 实体的编码和解码：
/// - `<` ↔ `&lt;`
/// - `>` ↔ `&gt;`
/// - `&` ↔ `&amp;`
/// - `"` ↔ `&quot;`
/// - `'` ↔ `&apos;`
public enum XMLEntityCodec {
    
    // MARK: - 编码
    
    /// 将文本中的特殊字符编码为 XML 实体
    ///
    /// - Parameter text: 原始文本
    /// - Returns: 编码后的文本
    public static func encode(_ text: String) -> String {
        var result = text
        
        // 注意：必须先替换 & 符号，否则会影响其他实体
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&apos;")
        
        return result
    }
    
    // MARK: - 解码
    
    /// 将 XML 实体解码为原始字符
    ///
    /// - Parameter text: 包含 XML 实体的文本
    /// - Returns: 解码后的文本
    public static func decode(_ text: String) -> String {
        var result = text
        
        // 替换标准 XML 实体
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        // 注意：必须最后替换 & 符号，否则会影响其他实体的解码
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        
        return result
    }
}
