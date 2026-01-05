//
//  ToolbarItemProtocol.swift
//  MiNoteLibrary
//
//  Created by Acckion on 2026/1/5.
//  Copyright © 2026 Acckion. All rights reserved.
//

#if os(macOS)
import AppKit
import SwiftUI
import Combine
import os

/// 工具栏项协议
/// 定义所有工具栏项需要实现的基本功能
public protocol ToolbarItemProtocol {
    /// 工具栏项标识符
    var identifier: NSToolbarItem.Identifier { get }
    
    /// 创建工具栏项
    /// - Parameter target: 动作目标对象
    /// - Returns: 配置好的 NSToolbarItem
    func createToolbarItem(target: AnyObject?) -> NSToolbarItem?
    
    /// 验证工具栏项是否可用
    /// - Parameter validator: 验证器对象
    /// - Returns: 是否可用
    func validate(with validator: NSUserInterfaceValidations?) -> Bool
}

/// 基础工具栏项类
open class BaseToolbarItem: NSObject, ToolbarItemProtocol {
    public let identifier: NSToolbarItem.Identifier
    private let logger = Logger(subsystem: "com.minote.MiNoteMac", category: "BaseToolbarItem")
    
    /// 工具栏项标题
    public let title: String
    
    /// 工具栏项图标
    public let image: NSImage?
    
    /// 工具栏项动作
    public let action: Selector?
    
    /// 工具栏项提示
    public let toolTip: String?
    
    /// 初始化基础工具栏项
    /// - Parameters:
    ///   - identifier: 标识符
    ///   - title: 标题
    ///   - image: 图标
    ///   - action: 动作
    ///   - toolTip: 提示
    public init(identifier: NSToolbarItem.Identifier, 
                title: String, 
                image: NSImage? = nil, 
                action: Selector? = nil, 
                toolTip: String? = nil) {
        self.identifier = identifier
        self.title = title
        self.image = image
        self.action = action
        self.toolTip = toolTip
        super.init()
    }
    
    open func createToolbarItem(target: AnyObject?) -> NSToolbarItem? {
        let toolbarItem = MiNoteToolbarItem(itemIdentifier: identifier)
        toolbarItem.autovalidates = true
        
        let button = NSButton()
        button.bezelStyle = .texturedRounded
        button.image = image
        button.imageScaling = .scaleProportionallyDown
        
        if let action = action {
            button.action = action
            button.target = target
        }
        
        toolbarItem.view = button
        toolbarItem.toolTip = toolTip ?? title
        toolbarItem.label = title
        
        return toolbarItem
    }
    
    open func validate(with validator: NSUserInterfaceValidations?) -> Bool {
        // 默认实现：如果没有验证器，返回 true
        // 子类可以重写此方法提供自定义验证逻辑
        return true
    }
}

/// 菜单工具栏项协议
public protocol MenuToolbarItemProtocol: ToolbarItemProtocol {
    /// 创建菜单
    /// - Parameter target: 动作目标对象
    /// - Returns: 配置好的 NSMenu
    func createMenu(target: AnyObject?) -> NSMenu?
}

/// 搜索工具栏项协议
public protocol SearchToolbarItemProtocol: ToolbarItemProtocol {
    /// 创建搜索字段
    /// - Parameter target: 动作目标对象
    /// - Returns: 配置好的 NSSearchField
    func createSearchField(target: AnyObject?) -> NSSearchField?
}

/// 跟踪分隔符工具栏项协议
public protocol TrackingSeparatorToolbarItemProtocol: ToolbarItemProtocol {
    /// 创建跟踪分隔符
    /// - Parameters:
    ///   - splitView: 分割视图
    ///   - dividerIndex: 分隔符索引
    /// - Returns: 配置好的 NSTrackingSeparatorToolbarItem
    func createTrackingSeparator(splitView: NSSplitView, dividerIndex: Int) -> NSTrackingSeparatorToolbarItem?
}
#endif
