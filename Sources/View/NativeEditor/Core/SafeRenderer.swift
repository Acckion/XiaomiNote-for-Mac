//
//  SafeRenderer.swift
//  MiNoteMac
//
//  安全渲染器 - 提供渲染失败的回退机制

import AppKit
import Foundation

// MARK: - 安全渲染器

/// 安全渲染器
/// 在渲染失败时提供回退机制，确保内容始终可显示
@MainActor
final class SafeRenderer {

    // MARK: - Singleton

    static let shared = SafeRenderer()

    // MARK: - Properties

    /// 自定义渲染器
    private let customRenderer = CustomRenderer.shared

    /// 错误处理器
    private let errorHandler = NativeEditorErrorHandler.shared

    /// 日志记录器
    private let logger = NativeEditorLogger.shared

    /// 性能指标
    private let metrics = NativeEditorMetrics.shared

    /// 回退文本样式
    private var fallbackTextAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Safe Rendering Methods

    /// 安全创建复选框附件
    /// - Parameters:
    ///   - checked: 是否选中
    ///   - level: 级别
    ///   - indent: 缩进
    /// - Returns: 附件或回退文本
    func safeCreateCheckboxAttachment(
        checked: Bool,
        level: Int,
        indent: Int
    ) -> NSAttributedString {
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let attachment = try createCheckboxAttachmentWithValidation(
                checked: checked,
                level: level,
                indent: indent
            )

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metrics.recordRendering("checkbox", duration: duration)
            logger.logRendering(element: "checkbox", duration: duration, cached: false, success: true)

            return NSAttributedString(attachment: attachment)
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            logger.logRendering(element: "checkbox", duration: duration, cached: false, success: false)

            errorHandler.handleError(
                .attachmentCreationFailed(type: "checkbox"),
                context: "checked=\(checked), level=\(level), indent=\(indent)"
            )

            return createFallbackCheckbox(checked: checked)
        }
    }

    /// 安全创建分割线附件
    /// - Parameter width: 宽度
    /// - Returns: 附件或回退文本
    func safeCreateHorizontalRuleAttachment(width: CGFloat = 300) -> NSAttributedString {
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let attachment = try createHorizontalRuleAttachmentWithValidation(width: width)

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metrics.recordRendering("horizontalRule", duration: duration)
            logger.logRendering(element: "horizontalRule", duration: duration, cached: false, success: true)

            return NSAttributedString(attachment: attachment)
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            logger.logRendering(element: "horizontalRule", duration: duration, cached: false, success: false)

            errorHandler.handleError(
                .attachmentCreationFailed(type: "horizontalRule"),
                context: "width=\(width)"
            )

            return createFallbackHorizontalRule()
        }
    }

    /// 安全创建项目符号附件
    /// - Parameter indent: 缩进
    /// - Returns: 附件或回退文本
    func safeCreateBulletAttachment(indent: Int) -> NSAttributedString {
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let attachment = try createBulletAttachmentWithValidation(indent: indent)

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metrics.recordRendering("bullet", duration: duration)
            logger.logRendering(element: "bullet", duration: duration, cached: false, success: true)

            return NSAttributedString(attachment: attachment)
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            logger.logRendering(element: "bullet", duration: duration, cached: false, success: false)

            errorHandler.handleError(
                .attachmentCreationFailed(type: "bullet"),
                context: "indent=\(indent)"
            )

            return createFallbackBullet(indent: indent)
        }
    }

    /// 安全创建有序列表附件
    /// - Parameters:
    ///   - number: 编号
    ///   - indent: 缩进
    /// - Returns: 附件或回退文本
    func safeCreateOrderAttachment(number: Int, indent: Int) -> NSAttributedString {
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let attachment = try createOrderAttachmentWithValidation(number: number, indent: indent)

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metrics.recordRendering("order", duration: duration)
            logger.logRendering(element: "order", duration: duration, cached: false, success: true)

            return NSAttributedString(attachment: attachment)
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            logger.logRendering(element: "order", duration: duration, cached: false, success: false)

            errorHandler.handleError(
                .attachmentCreationFailed(type: "order"),
                context: "number=\(number), indent=\(indent)"
            )

            return createFallbackOrder(number: number, indent: indent)
        }
    }

    /// 安全创建图片附件
    /// - Parameters:
    ///   - src: 图片源
    ///   - fileId: 文件 ID
    ///   - folderId: 文件夹 ID
    /// - Returns: 附件或回退文本
    func safeCreateImageAttachment(
        src: String?,
        fileId: String?,
        folderId: String?
    ) -> NSAttributedString {
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let attachment = try createImageAttachmentWithValidation(
                src: src,
                fileId: fileId,
                folderId: folderId
            )

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metrics.recordRendering("image", duration: duration)
            logger.logRendering(element: "image", duration: duration, cached: false, success: true)

            return NSAttributedString(attachment: attachment)
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            logger.logRendering(element: "image", duration: duration, cached: false, success: false)

            errorHandler.handleError(
                .imageLoadFailed(fileId: fileId, reason: error.localizedDescription),
                context: "src=\(src ?? "nil"), fileId=\(fileId ?? "nil")"
            )

            return createFallbackImage()
        }
    }

    // MARK: - Validation Methods

    /// 创建复选框附件（带验证）
    private func createCheckboxAttachmentWithValidation(
        checked: Bool,
        level: Int,
        indent: Int
    ) throws -> InteractiveCheckboxAttachment {
        // 验证参数
        guard level >= 1, level <= 10 else {
            throw NativeEditorError.renderingFailed(element: "checkbox", reason: "无效的级别: \(level)")
        }

        guard indent >= 1, indent <= 10 else {
            throw NativeEditorError.renderingFailed(element: "checkbox", reason: "无效的缩进: \(indent)")
        }

        return customRenderer.createCheckboxAttachment(checked: checked, level: level, indent: indent)
    }

    /// 创建分割线附件（带验证）
    private func createHorizontalRuleAttachmentWithValidation(width: CGFloat) throws -> HorizontalRuleAttachment {
        guard width > 0, width < 10000 else {
            throw NativeEditorError.renderingFailed(element: "horizontalRule", reason: "无效的宽度: \(width)")
        }

        return customRenderer.createHorizontalRuleAttachment(width: width)
    }

    /// 创建项目符号附件（带验证）
    private func createBulletAttachmentWithValidation(indent: Int) throws -> BulletAttachment {
        guard indent >= 1, indent <= 10 else {
            throw NativeEditorError.renderingFailed(element: "bullet", reason: "无效的缩进: \(indent)")
        }

        return customRenderer.createBulletAttachment(indent: indent)
    }

    /// 创建有序列表附件（带验证）
    private func createOrderAttachmentWithValidation(number: Int, indent: Int) throws -> OrderAttachment {
        guard number >= 0, number < 10000 else {
            throw NativeEditorError.renderingFailed(element: "order", reason: "无效的编号: \(number)")
        }

        guard indent >= 1, indent <= 10 else {
            throw NativeEditorError.renderingFailed(element: "order", reason: "无效的缩进: \(indent)")
        }

        return customRenderer.createOrderAttachment(number: number, indent: indent)
    }

    /// 创建图片附件（带验证）
    private func createImageAttachmentWithValidation(
        src: String?,
        fileId: String?,
        folderId: String?
    ) throws -> ImageAttachment {
        // 至少需要 src 或 fileId
        guard src != nil || fileId != nil else {
            throw NativeEditorError.renderingFailed(element: "image", reason: "缺少图片源或文件 ID")
        }

        return customRenderer.createImageAttachment(src: src, fileId: fileId, folderId: folderId)
    }

    // MARK: - Fallback Methods

    /// 创建回退复选框
    private func createFallbackCheckbox(checked: Bool) -> NSAttributedString {
        let symbol = checked ? "☑" : "☐"
        return NSAttributedString(string: "\(symbol) ", attributes: fallbackTextAttributes)
    }

    /// 创建回退分割线
    private func createFallbackHorizontalRule() -> NSAttributedString {
        let line = "───────────────────────────────────────"
        var attributes = fallbackTextAttributes
        attributes[.foregroundColor] = NSColor.separatorColor
        return NSAttributedString(string: "\n\(line)\n", attributes: attributes)
    }

    /// 创建回退项目符号
    private func createFallbackBullet(indent: Int) -> NSAttributedString {
        let indentString = String(repeating: "  ", count: max(0, indent - 1))
        return NSAttributedString(string: "\(indentString)• ", attributes: fallbackTextAttributes)
    }

    /// 创建回退有序列表
    private func createFallbackOrder(number: Int, indent: Int) -> NSAttributedString {
        let indentString = String(repeating: "  ", count: max(0, indent - 1))
        return NSAttributedString(string: "\(indentString)\(number). ", attributes: fallbackTextAttributes)
    }

    /// 创建回退图片
    private func createFallbackImage() -> NSAttributedString {
        var attributes = fallbackTextAttributes
        attributes[.foregroundColor] = NSColor.placeholderTextColor
        return NSAttributedString(string: "[图片加载失败]", attributes: attributes)
    }

    // MARK: - Batch Safe Rendering

    /// 安全渲染 XML 元素
    /// - Parameters:
    ///   - elementType: 元素类型
    ///   - attributes: 元素属性
    /// - Returns: 渲染结果
    func safeRenderElement(
        elementType: String,
        attributes: [String: String]
    ) -> NSAttributedString {
        switch elementType {
        case "input":
            let level = Int(attributes["level"] ?? "3") ?? 3
            let indent = Int(attributes["indent"] ?? "1") ?? 1
            return safeCreateCheckboxAttachment(checked: false, level: level, indent: indent)

        case "hr":
            return safeCreateHorizontalRuleAttachment()

        case "bullet":
            let indent = Int(attributes["indent"] ?? "1") ?? 1
            return safeCreateBulletAttachment(indent: indent)

        case "order":
            let indent = Int(attributes["indent"] ?? "1") ?? 1
            let inputNumber = Int(attributes["inputNumber"] ?? "0") ?? 0
            let number = inputNumber == 0 ? 1 : inputNumber + 1
            return safeCreateOrderAttachment(number: number, indent: indent)

        case "img":
            return safeCreateImageAttachment(
                src: attributes["src"],
                fileId: attributes["fileId"],
                folderId: attributes["folderId"]
            )

        default:
            logger.logWarning("未知的元素类型: \(elementType)", category: "SafeRenderer")
            return NSAttributedString(string: "[\(elementType)]", attributes: fallbackTextAttributes)
        }
    }
}

// MARK: - 安全格式转换器扩展

extension XiaoMiFormatConverter {

    /// 安全转换 XML 到 AttributedString
    /// - Parameters:
    ///   - xml: XML 字符串
    ///   - folderId: 文件夹 ID（用于图片加载）
    /// - Returns: 转换结果
    @MainActor
    func safeXMLToAttributedString(_ xml: String, folderId: String? = nil) -> Result<AttributedString, NativeEditorError> {
        let startTime = CFAbsoluteTimeGetCurrent()
        let logger = NativeEditorLogger.shared
        let metrics = NativeEditorMetrics.shared

        do {
            let result = try xmlToAttributedString(xml, folderId: folderId)

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metrics.recordFormatConversion("xmlToAttributedString", duration: duration, success: true)
            logger.logFormatConversion(
                direction: "XML -> AttributedString",
                inputPreview: xml,
                outputPreview: String(result.characters),
                duration: duration,
                success: true
            )

            return .success(result)
        } catch let error as ConversionError {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metrics.recordFormatConversion("xmlToAttributedString", duration: duration, success: false)
            logger.logFormatConversion(
                direction: "XML -> AttributedString",
                inputPreview: xml,
                outputPreview: "",
                duration: duration,
                success: false
            )

            switch error {
            case let .invalidXML(message):
                return .failure(.invalidXMLStructure(details: message))
            case let .unsupportedElement(element):
                return .failure(.unsupportedXMLElement(element: element))
            default:
                return .failure(.xmlParsingFailed(xml: xml, reason: error.localizedDescription))
            }
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metrics.recordFormatConversion("xmlToAttributedString", duration: duration, success: false)

            return .failure(.xmlParsingFailed(xml: xml, reason: error.localizedDescription))
        }
    }

    /// 安全转换 AttributedString 到 XML
    /// - Parameter attributedString: AttributedString
    /// - Returns: 转换结果
    @MainActor
    func safeAttributedStringToXML(_ attributedString: AttributedString) -> Result<String, NativeEditorError> {
        let startTime = CFAbsoluteTimeGetCurrent()
        let logger = NativeEditorLogger.shared
        let metrics = NativeEditorMetrics.shared

        do {
            let result = try attributedStringToXML(attributedString)

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metrics.recordFormatConversion("attributedStringToXML", duration: duration, success: true)
            logger.logFormatConversion(
                direction: "AttributedString -> XML",
                inputPreview: String(attributedString.characters),
                outputPreview: result,
                duration: duration,
                success: true
            )

            return .success(result)
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metrics.recordFormatConversion("attributedStringToXML", duration: duration, success: false)
            logger.logFormatConversion(
                direction: "AttributedString -> XML",
                inputPreview: String(attributedString.characters),
                outputPreview: "",
                duration: duration,
                success: false
            )

            return .failure(.attributedStringConversionFailed(reason: error.localizedDescription))
        }
    }
}
