//
//  ImportContentConverter.swift
//  MiNoteMac
//
//  导入内容格式转换器
//  将纯文本、Markdown、RTF 转换为小米笔记 XML 格式
//

#if os(macOS)
    import AppKit
    import Foundation

    /// 导入内容格式转换器
    enum ImportContentConverter {

        // MARK: - 纯文本转 XML

        /// 将纯文本转换为小米笔记 XML
        ///
        /// 按行拆分，每行包装为 `<text indent="1">` 元素
        static func plainTextToXML(_ text: String) -> String {
            guard !text.isEmpty else {
                return "<text indent=\"1\"></text>"
            }

            let lines = text.components(separatedBy: "\n")
            let xmlLines = lines.map { line in
                let escaped = XMLEntityCodec.encode(line)
                return "<text indent=\"1\">\(escaped)</text>"
            }
            return xmlLines.joined(separator: "\n")
        }

        // MARK: - Markdown 转 XML

        /// 将 Markdown 转换为小米笔记 XML
        ///
        /// 支持标题、列表、待办、引用等块级语法，行内格式降级为纯文本
        static func markdownToXML(_ markdown: String) -> String {
            guard !markdown.isEmpty else {
                return "<text indent=\"1\"></text>"
            }

            let lines = markdown.components(separatedBy: "\n")
            let xmlLines = lines.map { parseMarkdownLine($0) }
            return xmlLines.joined(separator: "\n")
        }

        // MARK: - RTF 转 XML

        /// 将 RTF 数据转换为小米笔记 XML
        ///
        /// 通过 NSAttributedString 加载 RTF，提取纯文本后按行转换
        static func rtfToXML(_ rtfData: Data) -> String {
            guard let attrString = NSAttributedString(rtf: rtfData, documentAttributes: nil) else {
                LogService.shared.error(.app, "RTF 解析失败，降级为空内容")
                return "<text indent=\"1\"></text>"
            }
            return plainTextToXML(attrString.string)
        }

        // MARK: - Markdown 行解析

        /// 解析单行 Markdown 语法，返回对应的小米笔记 XML 元素
        private static func parseMarkdownLine(_ line: String) -> String {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 空行
            if trimmed.isEmpty {
                return "<text indent=\"1\"></text>"
            }

            // 待办事项：- [ ] 或 - [x]
            if let todoResult = parseTodo(trimmed) {
                return todoResult
            }

            // 标题：# ## ###
            if let headResult = parseHeading(trimmed) {
                return headResult
            }

            // 引用：> 文本
            if trimmed.hasPrefix(">") {
                let content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                let escaped = XMLEntityCodec.encode(content)
                return "<quote><text indent=\"1\">\(escaped)</text></quote>"
            }

            // 无序列表：- 或 * 开头
            if let ulResult = parseUnorderedList(trimmed) {
                return ulResult
            }

            // 有序列表：数字. 开头
            if let olResult = parseOrderedList(trimmed) {
                return olResult
            }

            // 普通文本
            let escaped = XMLEntityCodec.encode(trimmed)
            return "<text indent=\"1\">\(escaped)</text>"
        }

        /// 解析待办事项
        private static func parseTodo(_ line: String) -> String? {
            // 匹配 - [ ] 或 * [ ] 或 - [x] 或 * [x]
            let uncheckedPrefixes = ["- [ ] ", "* [ ] "]
            let checkedPrefixes = ["- [x] ", "* [x] ", "- [X] ", "* [X] "]

            for prefix in uncheckedPrefixes {
                if line.hasPrefix(prefix) {
                    let content = String(line.dropFirst(prefix.count))
                    let escaped = XMLEntityCodec.encode(content)
                    return "<todo checked=\"false\"><text indent=\"1\">\(escaped)</text></todo>"
                }
            }

            for prefix in checkedPrefixes {
                if line.hasPrefix(prefix) {
                    let content = String(line.dropFirst(prefix.count))
                    let escaped = XMLEntityCodec.encode(content)
                    return "<todo checked=\"true\"><text indent=\"1\">\(escaped)</text></todo>"
                }
            }

            return nil
        }

        /// 解析标题
        private static func parseHeading(_ line: String) -> String? {
            var level = 0
            for char in line {
                if char == "#" {
                    level += 1
                } else {
                    break
                }
            }

            guard level >= 1, level <= 3, line.count > level else { return nil }

            let afterHashes = line[line.index(line.startIndex, offsetBy: level)...]
            guard afterHashes.hasPrefix(" ") else { return nil }

            let content = afterHashes.dropFirst().trimmingCharacters(in: .whitespaces)
            let escaped = XMLEntityCodec.encode(content)
            return "<head level=\"\(level)\">\(escaped)</head>"
        }

        /// 解析无序列表
        private static func parseUnorderedList(_ line: String) -> String? {
            // 需要排除待办事项（已在前面处理）
            let prefixes = ["- ", "* "]
            for prefix in prefixes {
                if line.hasPrefix(prefix) {
                    // 排除待办事项
                    let rest = String(line.dropFirst(prefix.count))
                    if rest.hasPrefix("[ ] ") || rest.hasPrefix("[x] ") || rest.hasPrefix("[X] ") {
                        return nil
                    }
                    let escaped = XMLEntityCodec.encode(rest)
                    return "<list type=\"unordered\"><text indent=\"1\">\(escaped)</text></list>"
                }
            }
            return nil
        }

        /// 解析有序列表
        private static func parseOrderedList(_ line: String) -> String? {
            // 匹配 "数字. " 格式
            guard let dotIndex = line.firstIndex(of: ".") else { return nil }

            let numberPart = line[line.startIndex ..< dotIndex]
            guard !numberPart.isEmpty, numberPart.allSatisfy(\.isNumber) else { return nil }

            let afterDot = line[line.index(after: dotIndex)...]
            guard afterDot.hasPrefix(" ") else { return nil }

            let content = afterDot.dropFirst().trimmingCharacters(in: .whitespaces)
            let escaped = XMLEntityCodec.encode(content)
            return "<list type=\"ordered\"><text indent=\"1\">\(escaped)</text></list>"
        }
    }
#endif
