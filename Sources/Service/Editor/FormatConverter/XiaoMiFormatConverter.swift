//
//  XiaoMiFormatConverter.swift
//  MiNoteMac
//
//  小米笔记格式转换器
//  XML <-> NSAttributedString 双向转换的门面层
//  内部委托 AST 管道：MiNoteXMLParser / ASTToAttributedStringConverter / AttributedStringToASTConverter / XMLGenerator
//

import AppKit
import Foundation

/// 小米笔记格式转换器
@MainActor
class XiaoMiFormatConverter {

    // MARK: - Singleton

    static let shared = XiaoMiFormatConverter()

    private init() {}

    // MARK: - XML -> NSAttributedString

    /// 将小米笔记 XML 转换为 NSAttributedString
    ///
    /// 转换管道：XML -> Tokens -> AST -> NSAttributedString
    ///
    /// - Parameters:
    ///   - xml: 小米笔记 XML 格式字符串
    ///   - folderId: 文件夹 ID（用于图片加载）
    /// - Returns: 转换后的 NSAttributedString
    /// - Throws: ConversionError
    func xmlToNSAttributedString(_ xml: String, folderId: String? = nil) throws -> NSAttributedString {
        guard !xml.isEmpty else {
            return NSAttributedString()
        }

        let parser = MiNoteXMLParser()
        let parseResult = try parser.parse(xml)

        for warning in parseResult.warnings {
            LogService.shared.warning(.editor, "XML 解析警告: \(warning.message)")
        }

        let astConverter = ASTToAttributedStringConverter(folderId: folderId)
        return astConverter.convert(parseResult.value)
    }

    // MARK: - NSAttributedString -> XML

    /// 将 NSAttributedString 转换为小米笔记 XML 格式
    ///
    /// 转换管道：NSAttributedString -> AST -> XML
    ///
    /// - Parameter nsAttributedString: 要转换的 NSAttributedString
    /// - Returns: 小米笔记 XML 格式字符串
    /// - Throws: ConversionError
    func nsAttributedStringToXML(_ nsAttributedString: NSAttributedString) throws -> String {
        let astConverter = AttributedStringToASTConverter()
        let document = astConverter.convert(nsAttributedString)
        let xmlGenerator = XMLGenerator()
        return xmlGenerator.generate(document)
    }

    /// 安全转换 NSAttributedString 到 XML（带错误回退）
    ///
    /// 转换失败时回退为纯文本 XML，保证不丢失内容
    ///
    /// - Parameter nsAttributedString: 要转换的 NSAttributedString
    /// - Returns: 小米笔记 XML 格式字符串（保证不为空，除非输入为空）
    func safeNSAttributedStringToXML(_ nsAttributedString: NSAttributedString) -> String {
        guard nsAttributedString.length > 0 else {
            return ""
        }

        do {
            return try nsAttributedStringToXML(nsAttributedString)
        } catch {
            LogService.shared.error(.editor, "XML 转换失败，使用纯文本回退: \(error.localizedDescription)")

            let plainText = nsAttributedString.string
            let lines = plainText.components(separatedBy: "\n")
            var xmlElements: [String] = []

            for line in lines {
                guard !line.isEmpty else { continue }
                let escapedText = XMLEntityCodec.encode(line)
                xmlElements.append("<text indent=\"1\">\(escapedText)</text>")
            }

            return xmlElements.joined(separator: "\n")
        }
    }

    // MARK: - 验证

    /// 验证 XML 往返转换的一致性
    ///
    /// - Parameter xml: 原始 XML
    /// - Returns: 往返转换后是否一致
    func validateConversion(_ xml: String) -> Bool {
        do {
            let nsAttributedString = try xmlToNSAttributedString(xml)
            let backConverted = try nsAttributedStringToXML(nsAttributedString)
            return XMLNormalizer.shared.normalize(xml) == XMLNormalizer.shared.normalize(backConverted)
        } catch {
            LogService.shared.error(.editor, "验证转换失败: \(error)")
            return false
        }
    }
}
