//
//  AttachmentProtocols.swift
//  MiNoteMac
//
//  附件基础协议定义
//

import AppKit

// MARK: - 可交互附件协议

/// 可交互附件协议
protocol InteractiveAttachment: AnyObject {
    /// 处理点击事件
    /// - Parameters:
    ///   - point: 点击位置
    ///   - textContainer: 文本容器
    ///   - characterIndex: 字符索引
    /// - Returns: 是否处理了点击
    func handleClick(at point: NSPoint, in textContainer: NSTextContainer?, characterIndex: Int) -> Bool
}

// MARK: - 主题感知附件协议

/// 主题感知附件协议
protocol ThemeAwareAttachment: AnyObject {
    /// 当前是否为深色模式
    var isDarkMode: Bool { get set }

    /// 更新主题
    func updateTheme()
}
