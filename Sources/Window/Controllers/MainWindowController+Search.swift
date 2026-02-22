//
//  MainWindowController+Search.swift
//  MiNoteLibrary
//
//  Created by Acckion on 2026/1/2.
//  Copyright © 2026 Acckion. All rights reserved.
//

#if os(macOS)
    import AppKit
    import SwiftUI

    // MARK: - NSSearchFieldDelegate

    extension MainWindowController: NSSearchFieldDelegate {

        public func searchFieldDidStartSearching(_ sender: NSSearchField) {
            coordinator.noteListState.searchText = sender.stringValue
        }

        public func searchFieldDidEndSearching(_: NSSearchField) {
            coordinator.noteListState.searchText = ""
        }

        @objc func performSearch(_ sender: NSSearchField) {
            coordinator.noteListState.searchText = sender.stringValue
        }

        public func controlTextDidBeginEditing(_ obj: Notification) {
            LogService.shared.debug(.window, "controlTextDidBeginEditing被调用")

            // 当搜索框开始编辑（获得焦点）时，显示筛选菜单
            if let searchField = obj.object as? NSSearchField {
                LogService.shared.debug(.window, "搜索框开始编辑")

                if searchField == currentSearchField {
                    // 检查popover是否已经显示
                    if let popover = searchFilterMenuPopover, popover.isShown {
                        LogService.shared.debug(.window, "popover已经显示，跳过重复调用")
                        return
                    }

                    LogService.shared.debug(.window, "是当前搜索框，立即显示筛选菜单")

                    // 只要光标在搜索框中就弹出菜单，不需要检查搜索框内容
                    LogService.shared.debug(.window, "光标在搜索框中，立即显示筛选菜单")
                    showSearchFilterMenu(searchField)
                } else {
                    LogService.shared.debug(.window, "不是当前搜索框，忽略")
                }
            } else {
                LogService.shared.debug(.window, "通知对象不是搜索框")
            }
        }

        public func controlTextDidEndEditing(_ obj: Notification) {
            LogService.shared.debug(.window, "controlTextDidEndEditing被调用")

            // 当搜索框结束编辑（失去焦点）时，收回筛选菜单
            if let searchField = obj.object as? NSSearchField {
                LogService.shared.debug(.window, "搜索框结束编辑")

                if searchField == currentSearchField {
                    LogService.shared.debug(.window, "是当前搜索框，收回筛选菜单")

                    // 如果popover正在显示，关闭它
                    if let popover = searchFilterMenuPopover, popover.isShown {
                        LogService.shared.debug(.window, "popover正在显示，关闭它")
                        popover.performClose(nil)
                        searchFilterMenuPopover = nil
                    }
                }
            }
        }
    }

    // MARK: - 搜索筛选菜单

    extension MainWindowController {

        /// 为搜索框设置下拉菜单（使用SwiftUI popover）
        func setupSearchFieldMenu(for searchField: NSSearchField) {

            // 设置搜索框属性以确保菜单正确工作
            searchField.sendsSearchStringImmediately = false
            searchField.sendsWholeSearchString = true

            // 移除旧的NSMenu设置，因为我们使用popover
            searchField.menu = nil

            // 设置搜索框的点击事件处理 - 按Enter时执行搜索，而不是弹出菜单
            searchField.target = self
            searchField.action = #selector(performSearch(_:))

            // 重要：确保搜索框有正确的行为设置
            searchField.bezelStyle = .roundedBezel
            searchField.controlSize = .regular

            // 添加调试日志
        }

        @objc func showSearchFilterMenu(_ sender: Any?) {

            // 如果popover已经显示，则关闭它
            if let popover = searchFilterMenuPopover, popover.isShown {
                popover.performClose(sender)
                searchFilterMenuPopover = nil
                return
            }

            // 创建SwiftUI搜索筛选菜单视图
            let searchFilterMenuView = SearchFilterMenuContent(noteListState: coordinator.noteListState)

            // 创建托管控制器
            let hostingController = NSHostingController(rootView: searchFilterMenuView)
            hostingController.view.frame = NSRect(x: 0, y: 0, width: 200, height: 190)

            // 创建popover
            let popover = NSPopover()
            popover.contentSize = NSSize(width: 200, height: 190)
            // 使用.semitransient行为，这样用户与搜索框交互时不会自动关闭
            popover.behavior = .semitransient
            popover.animates = true
            popover.contentViewController = hostingController

            // 存储popover引用
            searchFilterMenuPopover = popover

            // 显示popover
            if let searchField = sender as? NSSearchField {

                // 方案三：参考格式菜单的实现，使用.maxY并调整positioningRect
                // 格式菜单使用.maxY显示在按钮上方，搜索框也应该类似

                // 获取搜索框的bounds
                let bounds = searchField.bounds

                // 创建一个positioningRect，使用搜索框的bounds
                let positioningRect = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)

                // 使用.maxY（显示在搜索框上方），与格式菜单保持一致
                popover.show(relativeTo: positioningRect, of: searchField, preferredEdge: .maxY)
            } else if let window, let contentView = window.contentView {
                // 如果没有搜索框，显示在窗口中央
                popover.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .maxY)
            } else {
                LogService.shared.error(.window, "无法显示搜索筛选菜单：没有搜索框或窗口")
            }
        }

        /// 检查是否有任何筛选选项被启用
        func hasAnySearchFilter() -> Bool {
            let state = coordinator.noteListState
            return state.filterHasTags ||
                state.filterHasChecklist ||
                state.filterHasImages ||
                state.filterHasAudio ||
                state.filterIsPrivate
        }

        /// 清除所有筛选选项
        func clearAllSearchFilters() {
            coordinator.noteListState.filterHasTags = false
            coordinator.noteListState.filterHasChecklist = false
            coordinator.noteListState.filterHasImages = false
            coordinator.noteListState.filterHasAudio = false
            coordinator.noteListState.filterIsPrivate = false
        }
    }
#endif
