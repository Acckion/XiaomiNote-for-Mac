import AppKit
import Foundation

/// 剪贴板管理器
/// 负责处理剪贴板的多格式导入导出
///
/// **核心功能**:
/// - 导出多种格式到剪贴板（纯文本、RTF、HTML）
/// - 从剪贴板导入最合适的格式
/// - 支持"粘贴并匹配样式"功能
///
@MainActor
public class PasteboardManager {
    // MARK: - Singleton

    /// 共享实例
    public static let shared = PasteboardManager()

    // MARK: - Initialization

    private init() {
        #if DEBUG
        #endif
    }

    // MARK: - Public Methods - 导出

    /// 导出多种格式到剪贴板
    ///
    /// 将富文本内容导出为多种格式并写入剪贴板：
    /// 1. 纯文本格式（NSPasteboard.PasteboardType.string）
    /// 2. RTF 格式（NSPasteboard.PasteboardType.rtf）
    /// 3. HTML 格式（NSPasteboard.PasteboardType.html）
    ///
    /// 这样可以确保与各种应用的兼容性。
    ///
    ///
    /// - Parameters:
    ///   - attributedString: 要导出的富文本
    ///   - pasteboard: 目标剪贴板，默认为通用剪贴板
    public func exportMultipleFormats(
        _ attributedString: NSAttributedString,
        to pasteboard: NSPasteboard = .general
    ) {
        #if DEBUG
        #endif

        // 清空剪贴板
        pasteboard.clearContents()

        var items: [NSPasteboardItem] = []
        let item = NSPasteboardItem()

        // 1. 导出纯文本格式
        let plainText = attributedString.string
        item.setString(plainText, forType: .string)

        #if DEBUG
        #endif

        // 2. 导出 RTF 格式
        if let rtfData = try? attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) {
            item.setData(rtfData, forType: .rtf)

            #if DEBUG
            #endif
        }

        // 3. 导出 HTML 格式
        if let htmlData = try? attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ]
        ) {
            item.setData(htmlData, forType: .html)

            #if DEBUG
            #endif
        }

        items.append(item)

        // 写入剪贴板
        pasteboard.writeObjects(items)

        #if DEBUG
        #endif
    }

    // MARK: - Public Methods - 导入

    /// 从剪贴板导入最合适的格式
    ///
    /// 按优先级选择最丰富的可处理格式：
    /// 1. RTF 格式（最丰富）
    /// 2. HTML 格式
    /// 3. 纯文本格式（最基础）
    ///
    ///
    /// - Parameter pasteboard: 源剪贴板，默认为通用剪贴板
    /// - Returns: 导入的富文本，如果失败返回 nil
    public func importBestFormat(
        from pasteboard: NSPasteboard = .general
    ) -> NSAttributedString? {
        #if DEBUG
        #endif

        // 优先级 1: RTF 格式
        if let rtfData = pasteboard.data(forType: .rtf) {
            if let attributedString = try? NSAttributedString(
                data: rtfData,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ) {
                #if DEBUG
                #endif
                return attributedString
            }
        }

        // 优先级 2: HTML 格式
        if let htmlData = pasteboard.data(forType: .html) {
            if let attributedString = try? NSAttributedString(
                data: htmlData,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
            ) {
                #if DEBUG
                #endif
                return attributedString
            }
        }

        // 优先级 3: 纯文本格式
        if let plainText = pasteboard.string(forType: .string) {
            #if DEBUG
            #endif
            return NSAttributedString(string: plainText)
        }

        #if DEBUG
        #endif

        return nil
    }

    /// 粘贴并匹配样式
    ///
    /// 从剪贴板导入内容，但只保留纯文本，应用当前的打字属性。
    /// 这样可以确保粘贴的内容与周围文本的样式一致。
    ///
    ///
    /// - Parameters:
    ///   - pasteboard: 源剪贴板，默认为通用剪贴板
    ///   - typingAttributes: 当前的打字属性
    /// - Returns: 应用了打字属性的富文本，如果失败返回 nil
    public func pasteAndMatchStyle(
        from pasteboard: NSPasteboard = .general,
        typingAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString? {
        #if DEBUG
        #endif

        // 获取纯文本
        guard let plainText = pasteboard.string(forType: .string) else {
            #if DEBUG
            #endif
            return nil
        }

        // 应用打字属性
        let attributedString = NSAttributedString(
            string: plainText,
            attributes: typingAttributes
        )

        #if DEBUG
        #endif

        return attributedString
    }

    // MARK: - Public Methods - 便捷方法

    /// 复制纯文本到剪贴板
    ///
    /// - Parameters:
    ///   - text: 要复制的文本
    ///   - pasteboard: 目标剪贴板，默认为通用剪贴板
    public func copyPlainText(
        _ text: String,
        to pasteboard: NSPasteboard = .general
    ) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        #if DEBUG
        #endif
    }

    /// 获取剪贴板中的纯文本
    ///
    /// - Parameter pasteboard: 源剪贴板，默认为通用剪贴板
    /// - Returns: 纯文本，如果没有返回 nil
    public func getPlainText(
        from pasteboard: NSPasteboard = .general
    ) -> String? {
        pasteboard.string(forType: .string)
    }

    /// 检查剪贴板是否包含指定类型
    ///
    /// - Parameters:
    ///   - type: 要检查的类型
    ///   - pasteboard: 源剪贴板，默认为通用剪贴板
    /// - Returns: 如果包含返回 true，否则返回 false
    public func hasType(
        _ type: NSPasteboard.PasteboardType,
        in pasteboard: NSPasteboard = .general
    ) -> Bool {
        pasteboard.availableType(from: [type]) != nil
    }

    /// 获取剪贴板中可用的类型列表
    ///
    /// - Parameter pasteboard: 源剪贴板，默认为通用剪贴板
    /// - Returns: 可用类型的数组
    public func availableTypes(
        in pasteboard: NSPasteboard = .general
    ) -> [NSPasteboard.PasteboardType] {
        pasteboard.types ?? []
    }
}

// MARK: - Debug Support

public extension PasteboardManager {
    /// 获取调试信息
    ///
    /// - Parameter pasteboard: 要检查的剪贴板，默认为通用剪贴板
    /// - Returns: 包含剪贴板状态的字符串
    func debugDescription(
        for pasteboard: NSPasteboard = .general
    ) -> String {
        var info = "[PasteboardManager]\n"

        let types = availableTypes(in: pasteboard)
        info += "  可用类型数量: \(types.count)\n"

        for type in types {
            info += "  - \(type.rawValue)\n"

            // 显示每种类型的数据大小
            if let data = pasteboard.data(forType: type) {
                info += "    大小: \(data.count) 字节\n"
            }
        }

        // 显示纯文本预览
        if let plainText = getPlainText(from: pasteboard) {
            let preview = plainText.prefix(100)
            info += "  纯文本预览: \(preview)...\n"
        }

        return info
    }
}
