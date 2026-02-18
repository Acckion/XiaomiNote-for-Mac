//
//  CustomRenderer.swift
//  MiNoteMac
//
//  自定义渲染器 - 统一管理所有特殊元素的渲染
//

import AppKit
import SwiftUI

// MARK: - 自定义渲染器

/// 自定义渲染器 - 负责创建和管理所有特殊元素的渲染
/// 包括复选框、分割线、项目符号、有序列表和引用块
@MainActor
class CustomRenderer {

    // MARK: - Singleton

    static let shared = CustomRenderer()

    // MARK: - Properties

    /// 引用块样式
    var quoteStyle = QuoteBlockStyle()

    /// 是否为深色模式
    private(set) var isDarkMode = false

    /// 附件缓存（使用优化的 LRU 策略）
    private var attachmentCache: [String: NSTextAttachment] = [:]

    /// 图像缓存
    private var imageCache: [String: NSImage] = [:]

    /// 缓存大小限制
    private let maxCacheSize = 200

    /// 缓存命中计数
    private var cacheHitCount = 0

    /// 缓存未命中计数
    private var cacheMissCount = 0

    /// 缓存命中率
    var cacheHitRate: Double {
        let total = cacheHitCount + cacheMissCount
        return total > 0 ? Double(cacheHitCount) / Double(total) : 0
    }

    // MARK: - Initialization

    private init() {
        updateTheme()

        // 监听主题变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Theme Management

    /// 更新主题
    func updateTheme() {
        // 安全获取当前外观，在测试环境中 NSApp 可能为 nil
        guard let currentAppearance = NSApp?.effectiveAppearance else {
            return
        }
        let newIsDarkMode = currentAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        if isDarkMode != newIsDarkMode {
            isDarkMode = newIsDarkMode
            clearCache()
        }
    }

    @objc private func handleAppearanceChange() {
        updateTheme()
    }

    // MARK: - Checkbox Creation

    /// 创建复选框附件
    /// - Parameters:
    ///   - checked: 是否选中
    ///   - level: 级别（对应 XML 中的 level 属性）
    ///   - indent: 缩进（对应 XML 中的 indent 属性）
    ///   - onToggle: 状态切换回调
    /// - Returns: 复选框附件
    func createCheckboxAttachment(
        checked: Bool = false,
        level: Int = 3,
        indent: Int = 1,
        onToggle: ((Bool) -> Void)? = nil
    ) -> InteractiveCheckboxAttachment {
        let attachment = InteractiveCheckboxAttachment(checked: checked, level: level, indent: indent)
        attachment.isDarkMode = isDarkMode
        attachment.onToggle = onToggle
        return attachment
    }

    /// 从缓存获取或创建复选框附件
    /// - Parameters:
    ///   - checked: 是否选中
    ///   - level: 级别
    ///   - indent: 缩进
    /// - Returns: 复选框附件
    func getCachedCheckboxAttachment(checked: Bool, level: Int, indent: Int) -> InteractiveCheckboxAttachment {
        let key = "checkbox_\(checked)_\(level)_\(indent)_\(isDarkMode)"

        if let cached = attachmentCache[key] as? InteractiveCheckboxAttachment {
            cached.isDarkMode = isDarkMode
            cacheHitCount += 1
            return cached
        }

        cacheMissCount += 1
        let attachment = createCheckboxAttachment(checked: checked, level: level, indent: indent)

        // 管理缓存大小（使用 LRU 策略）
        if attachmentCache.count >= maxCacheSize {
            // 移除一半的缓存条目
            let keysToRemove = Array(attachmentCache.keys.prefix(maxCacheSize / 2))
            for keyToRemove in keysToRemove {
                attachmentCache.removeValue(forKey: keyToRemove)
            }
        }

        attachmentCache[key] = attachment
        return attachment
    }

    // MARK: - Horizontal Rule Creation

    /// 创建分割线附件
    /// - Parameters:
    ///   - width: 宽度
    ///   - style: 线条样式
    /// - Returns: 分割线附件
    func createHorizontalRuleAttachment(
        width: CGFloat = 300,
        style: HorizontalRuleAttachment.LineStyle = .solid
    ) -> HorizontalRuleAttachment {
        let attachment = HorizontalRuleAttachment(width: width, style: style)
        attachment.isDarkMode = isDarkMode
        return attachment
    }

    /// 从缓存获取或创建分割线附件
    /// - Parameter width: 宽度
    /// - Returns: 分割线附件
    func getCachedHorizontalRuleAttachment(width: CGFloat) -> HorizontalRuleAttachment {
        let key = "hr_\(Int(width))_\(isDarkMode)"

        if let cached = attachmentCache[key] as? HorizontalRuleAttachment {
            cached.isDarkMode = isDarkMode
            cacheHitCount += 1
            return cached
        }

        cacheMissCount += 1
        let attachment = createHorizontalRuleAttachment(width: width)

        if attachmentCache.count >= maxCacheSize {
            let keysToRemove = Array(attachmentCache.keys.prefix(maxCacheSize / 2))
            for keyToRemove in keysToRemove {
                attachmentCache.removeValue(forKey: keyToRemove)
            }
        }

        attachmentCache[key] = attachment
        return attachment
    }

    // MARK: - Bullet Creation

    /// 创建项目符号附件
    /// - Parameter indent: 缩进级别
    /// - Returns: 项目符号附件
    func createBulletAttachment(indent: Int = 1) -> BulletAttachment {
        let attachment = BulletAttachment(indent: indent)
        attachment.isDarkMode = isDarkMode
        return attachment
    }

    /// 从缓存获取或创建项目符号附件
    /// - Parameter indent: 缩进级别
    /// - Returns: 项目符号附件
    func getCachedBulletAttachment(indent: Int) -> BulletAttachment {
        let key = "bullet_\(indent)_\(isDarkMode)"

        if let cached = attachmentCache[key] as? BulletAttachment {
            cached.isDarkMode = isDarkMode
            cacheHitCount += 1
            return cached
        }

        cacheMissCount += 1
        let attachment = createBulletAttachment(indent: indent)

        if attachmentCache.count >= maxCacheSize {
            let keysToRemove = Array(attachmentCache.keys.prefix(maxCacheSize / 2))
            for keyToRemove in keysToRemove {
                attachmentCache.removeValue(forKey: keyToRemove)
            }
        }

        attachmentCache[key] = attachment
        return attachment
    }

    // MARK: - Order List Creation

    /// 创建有序列表附件
    /// - Parameters:
    ///   - number: 编号
    ///   - inputNumber: 输入编号（对应 XML 中的 inputNumber 属性）
    ///   - indent: 缩进级别
    /// - Returns: 有序列表附件
    func createOrderAttachment(
        number: Int = 1,
        inputNumber: Int = 0,
        indent: Int = 1
    ) -> OrderAttachment {
        let attachment = OrderAttachment(number: number, inputNumber: inputNumber, indent: indent)
        attachment.isDarkMode = isDarkMode
        return attachment
    }

    /// 从缓存获取或创建有序列表附件
    /// - Parameters:
    ///   - number: 编号
    ///   - indent: 缩进级别
    /// - Returns: 有序列表附件
    func getCachedOrderAttachment(number: Int, indent: Int) -> OrderAttachment {
        let key = "order_\(number)_\(indent)_\(isDarkMode)"

        if let cached = attachmentCache[key] as? OrderAttachment {
            cached.isDarkMode = isDarkMode
            cacheHitCount += 1
            return cached
        }

        cacheMissCount += 1
        let attachment = createOrderAttachment(number: number, indent: indent)

        if attachmentCache.count >= maxCacheSize {
            let keysToRemove = Array(attachmentCache.keys.prefix(maxCacheSize / 2))
            for keyToRemove in keysToRemove {
                attachmentCache.removeValue(forKey: keyToRemove)
            }
        }

        attachmentCache[key] = attachment
        return attachment
    }

    // MARK: - Quote Block Creation

    /// 创建引用块布局管理器
    /// - Returns: 引用块布局管理器
    func createQuoteBlockLayoutManager() -> QuoteBlockLayoutManager {
        let layoutManager = QuoteBlockLayoutManager()
        layoutManager.quoteStyle = quoteStyle
        layoutManager.isDarkMode = isDarkMode
        return layoutManager
    }

    /// 创建引用块附件
    /// - Parameter indent: 缩进级别
    /// - Returns: 引用块附件
    func createQuoteBlockAttachment(indent: Int = 1) -> QuoteBlockAttachment {
        let attachment = QuoteBlockAttachment(indent: indent)
        attachment.isDarkMode = isDarkMode
        attachment.style = quoteStyle
        return attachment
    }

    // MARK: - Attributed String Helpers

    /// 创建包含复选框的 AttributedString
    /// - Parameters:
    ///   - checked: 是否选中
    ///   - content: 复选框后的内容
    ///   - level: 级别
    ///   - indent: 缩进
    /// - Returns: AttributedString
    func createCheckboxAttributedString(
        checked: Bool,
        content: String,
        level: Int = 3,
        indent: Int = 1
    ) -> NSAttributedString {
        let attachment = createCheckboxAttachment(checked: checked, level: level, indent: indent)
        let attachmentString = NSAttributedString(attachment: attachment)

        let result = NSMutableAttributedString(attributedString: attachmentString)
        result.append(NSAttributedString(string: " \(content)"))

        return result
    }

    /// 创建包含分割线的 AttributedString
    /// - Parameter width: 宽度
    /// - Returns: AttributedString
    func createHorizontalRuleAttributedString(width: CGFloat = 300) -> NSAttributedString {
        let attachment = createHorizontalRuleAttachment(width: width)
        return NSAttributedString(attachment: attachment)
    }

    /// 创建包含项目符号的 AttributedString
    /// - Parameters:
    ///   - content: 项目符号后的内容
    ///   - indent: 缩进级别
    /// - Returns: AttributedString
    func createBulletAttributedString(content: String, indent: Int = 1) -> NSAttributedString {
        let attachment = createBulletAttachment(indent: indent)
        let attachmentString = NSAttributedString(attachment: attachment)

        let result = NSMutableAttributedString(attributedString: attachmentString)
        result.append(NSAttributedString(string: content))

        return result
    }

    /// 创建包含有序列表编号的 AttributedString
    /// - Parameters:
    ///   - number: 编号
    ///   - content: 编号后的内容
    ///   - indent: 缩进级别
    /// - Returns: AttributedString
    func createOrderAttributedString(number: Int, content: String, indent: Int = 1) -> NSAttributedString {
        let attachment = createOrderAttachment(number: number, indent: indent)
        let attachmentString = NSAttributedString(attachment: attachment)

        let result = NSMutableAttributedString(attributedString: attachmentString)
        result.append(NSAttributedString(string: content))

        return result
    }

    /// 创建引用块 AttributedString
    /// - Parameters:
    ///   - content: 引用内容
    ///   - indent: 缩进级别
    /// - Returns: AttributedString
    func createQuoteAttributedString(content: String, indent: Int = 1) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: content)
        let fullRange = NSRange(location: 0, length: result.length)

        // 标记为引用块
        result.markAsQuoteBlock(range: fullRange, indent: indent)

        // 设置段落样式
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = CGFloat(indent - 1) * 20 + quoteStyle.leftPadding + quoteStyle.borderWidth
        paragraphStyle.headIndent = CGFloat(indent - 1) * 20 + quoteStyle.leftPadding + quoteStyle.borderWidth

        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)

        return result
    }

    // MARK: - Audio Attachment Creation

    /// 创建音频附件
    /// - Parameters:
    ///   - fileId: 语音文件 ID
    ///   - digest: 文件摘要（可选）
    ///   - mimeType: MIME 类型（可选）
    /// - Returns: 音频附件
    func createAudioAttachment(
        fileId: String,
        digest: String? = nil,
        mimeType: String? = nil
    ) -> AudioAttachment {
        let attachment = AudioAttachment(fileId: fileId, digest: digest, mimeType: mimeType)
        attachment.isDarkMode = isDarkMode
        return attachment
    }

    /// 从缓存获取或创建音频附件
    /// - Parameters:
    ///   - fileId: 语音文件 ID
    ///   - digest: 文件摘要（可选）
    ///   - mimeType: MIME 类型（可选）
    /// - Returns: 音频附件
    func getCachedAudioAttachment(
        fileId: String,
        digest: String? = nil,
        mimeType: String? = nil
    ) -> AudioAttachment {
        let key = "audio_\(fileId)_\(isDarkMode)"

        if let cached = attachmentCache[key] as? AudioAttachment {
            cached.isDarkMode = isDarkMode
            cacheHitCount += 1
            return cached
        }

        cacheMissCount += 1
        let attachment = createAudioAttachment(fileId: fileId, digest: digest, mimeType: mimeType)

        // 管理缓存大小（使用 LRU 策略）
        if attachmentCache.count >= maxCacheSize {
            let keysToRemove = Array(attachmentCache.keys.prefix(maxCacheSize / 2))
            for keyToRemove in keysToRemove {
                attachmentCache.removeValue(forKey: keyToRemove)
            }
        }

        attachmentCache[key] = attachment
        return attachment
    }

    /// 创建包含音频附件的 AttributedString
    /// - Parameters:
    ///   - fileId: 语音文件 ID
    ///   - digest: 文件摘要（可选）
    ///   - mimeType: MIME 类型（可选）
    /// - Returns: AttributedString
    func createAudioAttributedString(
        fileId: String,
        digest: String? = nil,
        mimeType: String? = nil
    ) -> NSAttributedString {
        let attachment = createAudioAttachment(fileId: fileId, digest: digest, mimeType: mimeType)
        return NSAttributedString(attachment: attachment)
    }

    // MARK: - Cache Management

    /// 清除所有缓存
    func clearCache() {
        attachmentCache.removeAll()
        imageCache.removeAll()
        cacheHitCount = 0
        cacheMissCount = 0
    }

    /// 获取缓存统计信息
    func getCacheStats() -> (attachments: Int, images: Int, hitRate: Double) {
        (attachmentCache.count, imageCache.count, cacheHitRate)
    }

    /// 预热缓存 - 预先创建常用的附件
    func warmUpCache() {
        // 预创建常用的复选框附件
        for checked in [true, false] {
            for indent in 1 ... 3 {
                _ = getCachedCheckboxAttachment(checked: checked, level: 3, indent: indent)
            }
        }

        // 预创建常用的项目符号附件
        for indent in 1 ... 3 {
            _ = getCachedBulletAttachment(indent: indent)
        }

        // 预创建常用的有序列表附件
        for number in 1 ... 10 {
            _ = getCachedOrderAttachment(number: number, indent: 1)
        }

        print("[CustomRenderer] 缓存预热完成，当前缓存数量: \(attachmentCache.count)")
    }

    /// 清除特定类型的缓存
    func clearCacheForType(_ type: String) {
        let keysToRemove = attachmentCache.keys.filter { $0.hasPrefix(type) }
        for key in keysToRemove {
            attachmentCache.removeValue(forKey: key)
        }
    }
}

// MARK: - 渲染器工厂扩展

extension CustomRenderer {

    /// 根据 XML 元素类型创建对应的附件
    /// - Parameters:
    ///   - elementType: 元素类型
    ///   - attributes: 元素属性
    /// - Returns: 对应的附件，如果不支持则返回 nil
    func createAttachment(
        forElementType elementType: String,
        attributes: [String: String]
    ) -> NSTextAttachment? {
        switch elementType {
        case "input":
            // 复选框
            let level = Int(attributes["level"] ?? "3") ?? 3
            let indent = Int(attributes["indent"] ?? "1") ?? 1
            return createCheckboxAttachment(checked: false, level: level, indent: indent)

        case "hr":
            // 分割线
            return createHorizontalRuleAttachment()

        case "bullet":
            // 项目符号
            let indent = Int(attributes["indent"] ?? "1") ?? 1
            return createBulletAttachment(indent: indent)

        case "order":
            // 有序列表
            let indent = Int(attributes["indent"] ?? "1") ?? 1
            let inputNumber = Int(attributes["inputNumber"] ?? "0") ?? 0
            // 注意：实际编号需要根据上下文计算
            return createOrderAttachment(number: inputNumber == 0 ? 1 : inputNumber + 1, inputNumber: inputNumber, indent: indent)

        case "img":
            // 图片
            let src = attributes["src"]
            let fileId = attributes["fileId"]
            let folderId = attributes["folderId"]
            return createImageAttachment(src: src, fileId: fileId, folderId: folderId)

        case "sound":
            // 语音文件
            guard let fileId = attributes["fileid"], !fileId.isEmpty else {
                print("[CustomRenderer] ⚠️ sound 元素缺少 fileid 属性")
                return nil
            }
            let digest = attributes["digest"]
            let mimeType = attributes["mimeType"]
            return createAudioAttachment(fileId: fileId, digest: digest, mimeType: mimeType)

        default:
            return nil
        }
    }

    // MARK: - Image Attachment Creation

    /// 创建图片附件
    /// - Parameters:
    ///   - src: 图片源 URL
    ///   - fileId: 文件 ID
    ///   - folderId: 文件夹 ID
    /// - Returns: 图片附件
    func createImageAttachment(src: String?, fileId: String?, folderId: String?) -> ImageAttachment {
        print("[CustomRenderer] 🖼️ createImageAttachment 被调用")
        print("[CustomRenderer]   - src: '\(src ?? "nil")'")
        print("[CustomRenderer]   - fileId: '\(fileId ?? "nil")'")
        print("[CustomRenderer]   - folderId: '\(folderId ?? "nil")'")

        if let src, !src.isEmpty {
            // 有 src URL，使用延迟加载
            print("[CustomRenderer] 🖼️ 使用 src URL 创建附件: \(src)")
            return ImageAttachment(src: src, fileId: fileId, folderId: folderId)
        } else if let fileId {
            // 没有 src，但有 fileId，创建一个延迟加载的附件
            // 使用 minote:// URL 格式，让 ImageAttachment 自己处理加载逻辑
            let minoteURL = "minote://image/\(fileId)"
            print("[CustomRenderer] 🖼️ 生成 minote URL: \(minoteURL)")
            return ImageAttachment(src: minoteURL, fileId: fileId, folderId: folderId)
        }

        // 创建占位符附件
        print("[CustomRenderer] 🖼️ 创建占位符附件（加载失败）")
        let attachment = ImageAttachment(src: "", fileId: fileId, folderId: folderId)
        attachment.loadFailed = true
        return attachment
    }

    /// 创建图片附件（从 NSImage）
    /// - Parameters:
    ///   - image: 图片
    ///   - fileId: 文件 ID
    ///   - folderId: 文件夹 ID
    /// - Returns: 图片附件
    func createImageAttachment(image: NSImage, fileId: String? = nil, folderId: String? = nil) -> ImageAttachment {
        ImageAttachment(image: image, fileId: fileId, folderId: folderId)
    }
}
