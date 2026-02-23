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
    /// 支持以下格式：
    /// - 命名实体：`&lt;`, `&gt;`, `&amp;`, `&quot;`, `&apos;`
    /// - 十进制数字实体：`&#60;`, `&#62;`, `&#38;` 等
    /// - 十六进制数字实体：`&#x3C;`, `&#x3E;`, `&#x26;` 等
    ///
    /// - Parameter text: 包含 XML 实体的文本
    /// - Returns: 解码后的文本
    public static func decode(_ text: String) -> String {
        var result = text

        // 先解码数字实体（十进制和十六进制）
        result = decodeNumericEntities(result)

        // 然后替换标准 XML 命名实体
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        // 注意：必须最后替换 & 符号，否则会影响其他实体的解码
        result = result.replacingOccurrences(of: "&amp;", with: "&")

        return result
    }

    /// 解码数字实体（十进制和十六进制）
    ///
    /// - Parameter text: 包含数字实体的文本
    /// - Returns: 解码后的文本
    private static func decodeNumericEntities(_ text: String) -> String {
        var result = text

        // 使用正则表达式匹配数字实体
        // 十进制：&#数字;
        // 十六进制：&#x十六进制数字; 或 &#X十六进制数字;
        let pattern = "&#(x|X)?([0-9a-fA-F]+);"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return result
        }

        let nsString = result as NSString
        let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))

        // 从后往前替换，避免索引偏移问题
        for match in matches.reversed() {
            guard match.numberOfRanges == 3 else { continue }

            let fullRange = match.range(at: 0)
            let prefixRange = match.range(at: 1)
            let numberRange = match.range(at: 2)

            let numberString = nsString.substring(with: numberRange)

            // 判断是十进制还是十六进制
            let isHex = prefixRange.location != NSNotFound
            let radix = isHex ? 16 : 10

            // 解析数字并转换为字符
            if let codePoint = Int(numberString, radix: radix),
               let scalar = UnicodeScalar(codePoint)
            {
                let character = String(Character(scalar))
                result = (result as NSString).replacingCharacters(in: fullRange, with: character)
            }
        }

        return result
    }
}
