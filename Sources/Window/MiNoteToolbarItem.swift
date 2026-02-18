//
//  MiNoteToolbarItem.swift
//  MiNoteLibrary
//
//  Created by Acckion on 2026/1/2.
//  Copyright © 2026 Acckion. All rights reserved.
//

#if os(macOS)
    import AppKit
    import os

    /// 自定义工具栏项，继承自 NSToolbarItem
    /// 遵循 NetNewsWire 的 RSToolbarItem 模式，通过响应链验证工具栏项状态
    public class MiNoteToolbarItem: NSToolbarItem {

        private let logger = Logger(subsystem: "com.minote.MiNoteMac", category: "MiNoteToolbarItem")

        /// 验证工具栏项是否可用
        /// 通过响应链查找实现了 NSUserInterfaceValidations 的对象
        ///
        /// - 2.2: 当选中笔记时，编辑器项应该启用
        /// - 2.3: 当没有选中笔记时，编辑器项应该可见但禁用
        /// - 隐藏状态优先于启用状态：隐藏的工具栏项不会被错误地启用
        override public func validate() {
            // 隐藏状态优先于启用状态
            // 如果工具栏项被隐藏，则不应该启用
            if isHidden {
                isEnabled = false
                return
            }

            // 即使没有视图或窗口，也尝试验证
            // 被收纳的工具栏项可能没有有效的view或window
            let isValid = isValidAsUserInterfaceItem()
            isEnabled = isValid
        }
    }

    private extension MiNoteToolbarItem {

        /// 检查工具栏项是否可以作为用户界面项使用
        /// 使用 NSValidatedUserInterfaceItem 协议而不是直接调用 validateToolbarItem:
        func isValidAsUserInterfaceItem() -> Bool {
            // 如果目标对象是响应者，首先尝试使用目标对象验证
            if let target = target as? NSResponder {
                if let result = validateWithResponder(target) {
                    return result
                }
            }

            // 尝试从视图的窗口获取第一响应者
            var responder: NSResponder?

            // 首先尝试从视图的窗口获取
            if let view, let window = view.window {
                responder = window.firstResponder
            } else {
                // 如果没有视图或窗口，尝试从主窗口获取
                responder = NSApplication.shared.mainWindow?.firstResponder
                if responder == nil {
                    // 最后尝试应用的关键窗口
                    responder = NSApplication.shared.keyWindow?.firstResponder
                }
            }

            // 如果找到了响应者，沿着响应链向上查找
            if let currentResponder = responder {
                var chainResponder: NSResponder? = currentResponder

                while let r = chainResponder {
                    if let validated = validateWithResponder(r) {
                        return validated
                    }
                    chainResponder = r.nextResponder
                }
            }

            // 尝试窗口控制器
            if let window = view?.window ?? NSApplication.shared.mainWindow ?? NSApplication.shared.keyWindow {
                if let windowController = window.windowController {
                    if let validated = validateWithResponder(windowController) {
                        return validated
                    }
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
            guard let action else {
                return nil
            }

            guard responder.responds(to: action) else {
                return nil
            }

            guard let target = responder as? NSUserInterfaceValidations else {
                return nil
            }

            return target.validateUserInterfaceItem(self)
        }
    }
#endif
