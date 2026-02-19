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
        var showSaveButton = false

        /// 关闭按钮标题（默认为"关闭"）
        var closeButtonTitle = "关闭"

        /// 保存按钮标题（默认为"保存"）
        var saveButtonTitle = "保存"

        // MARK: - NSToolbarDelegate

        func toolbar(
            _: NSToolbar,
            itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
            willBeInsertedIntoToolbar _: Bool
        ) -> NSToolbarItem? {
            switch itemIdentifier {
            case .close:
                buildCloseToolbarButton()

            case .save:
                showSaveButton ? buildSaveToolbarButton() : nil

            case .flexibleSpace:
                NSToolbarItem(itemIdentifier: .flexibleSpace)

            default:
                nil
            }
        }

        func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
            var identifiers: [NSToolbarItem.Identifier] = [
                .flexibleSpace,
            ]

            if showSaveButton {
                identifiers.append(.save)
            }

            identifiers.append(.close)

            return identifiers
        }

        func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
            var identifiers: [NSToolbarItem.Identifier] = [
                .flexibleSpace,
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
            let toolbarItem = NSToolbarItem(itemIdentifier: .close)
            toolbarItem.autovalidates = true

            let button = NSButton()
            button.bezelStyle = .texturedRounded
            button.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
            button.imageScaling = .scaleProportionallyDown
            button.action = #selector(closeButtonClicked(_:))
            button.target = self

            toolbarItem.view = button
            toolbarItem.toolTip = "关闭"
            toolbarItem.label = "关闭"
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

        @objc private func closeButtonClicked(_: Any?) {
            onClose?()
        }

        @objc private func saveButtonClicked(_: Any?) {
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
