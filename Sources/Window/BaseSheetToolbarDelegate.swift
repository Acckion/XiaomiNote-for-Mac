//
//  BaseSheetToolbarDelegate.swift
//  MiNoteLibrary
//
//  Created by Acckion on 2026/1/6.
//  Copyright © 2026 Acckion. All rights reserved.
//

#if os(macOS)
import AppKit

/// 基础sheet窗口工具栏代理
/// 提供通用的关闭按钮和可选的保存按钮
class BaseSheetToolbarDelegate: NSObject, NSToolbarDelegate {
    
    // MARK: - 属性
    
    /// 关闭回调
    var onClose: (() -> Void)?
    
    /// 保存回调
    var onSave: (() -> Void)?
    
    /// 是否显示保存按钮
    var showSaveButton: Bool = false
    
    /// 关闭按钮标题（默认为"关闭"）
    var closeButtonTitle: String = "关闭"
    
    /// 保存按钮标题（默认为"保存"）
    var saveButtonTitle: String = "保存"
    
    // MARK: - NSToolbarDelegate
    
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        print("[BaseSheetToolbarDelegate] toolbar(_:itemForItemIdentifier:willBeInsertedIntoToolbar:) 被调用，itemIdentifier: \(itemIdentifier)")
        
        switch itemIdentifier {
        case .close:
            print("[BaseSheetToolbarDelegate] 请求创建关闭按钮")
            return buildCloseToolbarButton()
            
        case .save:
            print("[BaseSheetToolbarDelegate] 请求创建保存按钮，showSaveButton: \(showSaveButton)")
            return showSaveButton ? buildSaveToolbarButton() : nil
            
        case .flexibleSpace:
            print("[BaseSheetToolbarDelegate] 请求创建弹性空间")
            return NSToolbarItem(itemIdentifier: .flexibleSpace)
            
        default:
            print("[BaseSheetToolbarDelegate] 未知的itemIdentifier: \(itemIdentifier)")
            return nil
        }
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var identifiers: [NSToolbarItem.Identifier] = [
            .flexibleSpace
        ]
        
        if showSaveButton {
            identifiers.append(.save)
        }
        
        identifiers.append(.close)
        
        return identifiers
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var identifiers: [NSToolbarItem.Identifier] = [
            .flexibleSpace
        ]
        
        if showSaveButton {
            identifiers.append(.save)
        }
        
        identifiers.append(.close)
        
        return identifiers
    }
    
    // MARK: - 工具栏项构建方法
    
    /// 构建关闭按钮
    private func buildCloseToolbarButton() -> NSToolbarItem {
        print("[BaseSheetToolbarDelegate] 构建关闭工具栏按钮")
        let toolbarItem = NSToolbarItem(itemIdentifier: .close)
        toolbarItem.autovalidates = true
        
        let button = NSButton()
        button.bezelStyle = .circular // 使用圆形样式，确保是正圆形
        button.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        button.imageScaling = .scaleProportionallyDown
        button.action = #selector(closeButtonClicked(_:))
        button.target = self
        button.isEnabled = true // 确保按钮启用
        
        // 设置合适的frame，确保宽高相等
        button.frame = NSRect(x: 0, y: 0, width: 32, height: 32)
        
        print("[BaseSheetToolbarDelegate] 按钮创建完成，target: \(String(describing: button.target))，action: \(String(describing: button.action))，bezelStyle: \(button.bezelStyle.rawValue)，isEnabled: \(button.isEnabled)，frame: \(button.frame)")
        
        toolbarItem.view = button
        toolbarItem.toolTip = closeButtonTitle
        toolbarItem.label = closeButtonTitle
        
        // 设置工具栏项的最小和最大尺寸，确保是正方形
        toolbarItem.minSize = NSSize(width: 32, height: 32)
        toolbarItem.maxSize = NSSize(width: 32, height: 32)
        
        return toolbarItem
    }
    
    /// 构建保存按钮
    private func buildSaveToolbarButton() -> NSToolbarItem {
        let toolbarItem = NSToolbarItem(itemIdentifier: .save)
        toolbarItem.autovalidates = true
        
        let button = NSButton()
        button.bezelStyle = .texturedRounded
        button.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
        button.imageScaling = .scaleProportionallyDown
        button.action = #selector(saveButtonClicked(_:))
        button.target = self
        
        toolbarItem.view = button
        toolbarItem.toolTip = saveButtonTitle
        toolbarItem.label = saveButtonTitle
        return toolbarItem
    }
    
    // MARK: - 动作方法
    
    @objc private func closeButtonClicked(_ sender: Any?) {
        print("[BaseSheetToolbarDelegate] 关闭按钮被点击")
        onClose?()
    }
    
    @objc private func saveButtonClicked(_ sender: Any?) {
        onSave?()
    }
}

// MARK: - 工具栏项标识符扩展

extension NSToolbarItem.Identifier {
    /// 关闭按钮标识符（与OfflineOperationsProgressToolbarDelegate保持一致）
    static let close = NSToolbarItem.Identifier("com.minote.toolbar.close")
    
    /// 保存按钮标识符
    static let save = NSToolbarItem.Identifier("com.minote.toolbar.save")
}

#endif
