//
//  OfflineOperationsProgressToolbarDelegate.swift
//  MiNoteLibrary
//
//  Created by Acckion on 2026/1/5.
//  Copyright © 2026 Acckion. All rights reserved.
//

#if os(macOS)
import AppKit

/// 离线操作进度窗口工具栏代理
class OfflineOperationsProgressToolbarDelegate: NSObject, NSToolbarDelegate {
    
    /// 关闭回调
    var onClose: (() -> Void)?
    
    // MARK: - NSToolbarDelegate
    
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        
        switch itemIdentifier {
        case .close:
            return buildCloseToolbarButton()
            
        case .flexibleSpace:
            return NSToolbarItem(itemIdentifier: .flexibleSpace)
            
        default:
            return nil
        }
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .flexibleSpace,
            .close
        ]
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .flexibleSpace,
            .close
        ]
    }
    
    // MARK: - 工具栏项构建方法
    
    /// 构建关闭按钮
    private func buildCloseToolbarButton() -> NSToolbarItem {
        let toolbarItem = NSToolbarItem(itemIdentifier: .close)
        toolbarItem.autovalidates = true
        
        let button = NSButton()
        button.bezelStyle = .texturedRounded
        button.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
        button.imageScaling = .scaleProportionallyDown
        button.action = #selector(closeButtonClicked(_:))
        button.target = self
        
        toolbarItem.view = button
        toolbarItem.toolTip = "关闭"
        toolbarItem.label = "关闭"
        return toolbarItem
    }
    
    // MARK: - 动作方法
    
    @objc private func closeButtonClicked(_ sender: Any?) {
        onClose?()
    }
}

// MARK: - 工具栏项标识符扩展

extension NSToolbarItem.Identifier {
    /// 关闭按钮标识符
    static let close = NSToolbarItem.Identifier("com.minote.toolbar.close")
}

#endif
