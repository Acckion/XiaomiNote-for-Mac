//
//  MiNoteToolbarItem.swift
//  MiNoteLibrary
//
//  Created by Acckion on 2026/1/2.
//  Copyright © 2026 Acckion. All rights reserved.
//

#if os(macOS)
import AppKit

/// 自定义工具栏项，继承自 NSToolbarItem
/// 遵循 NetNewsWire 的 RSToolbarItem 模式，通过响应链验证工具栏项状态
public class MiNoteToolbarItem: NSToolbarItem {

    /// 验证工具栏项是否可用
    /// 通过响应链查找实现了 NSUserInterfaceValidations 的对象
    override public func validate() {
        guard let view = view, let _ = view.window else {
            isEnabled = false
            return
        }
        isEnabled = isValidAsUserInterfaceItem()
    }
}

private extension MiNoteToolbarItem {

    /// 检查工具栏项是否可以作为用户界面项使用
    /// 使用 NSValidatedUserInterfaceItem 协议而不是直接调用 validateToolbarItem:
    func isValidAsUserInterfaceItem() -> Bool {
        // 如果目标对象是响应者，首先尝试使用目标对象验证
        if let target = target as? NSResponder {
            return validateWithResponder(target) ?? false
        }

        // 从第一响应者开始，沿着响应链向上查找
        var responder = view?.window?.firstResponder
        if responder == nil {
            return false
        }

        while true {
            if let validated = validateWithResponder(responder!) {
                return validated
            }
            responder = responder?.nextResponder
            if responder == nil {
                break
            }
        }

        // 最后尝试应用委托
        if let appDelegate = NSApplication.shared.delegate {
            if let validated = validateWithResponder(appDelegate) {
                return validated
            }
        }

        return false
    }

    /// 使用特定的响应者验证工具栏项
    /// - Parameter responder: 要验证的响应者对象
    /// - Returns: 如果响应者可以处理该动作并验证通过，返回 true；否则返回 nil
    func validateWithResponder(_ responder: NSObjectProtocol) -> Bool? {
        guard responder.responds(to: action), let target = responder as? NSUserInterfaceValidations else {
            return nil
        }
        return target.validateUserInterfaceItem(self)
    }
}
#endif
