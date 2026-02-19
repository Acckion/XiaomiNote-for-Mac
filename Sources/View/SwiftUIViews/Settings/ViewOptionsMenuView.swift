//
//  ViewOptionsMenuView.swift
//  MiNoteMac
//
//  视图选项菜单视图 - 提供排序方式、排序方向、日期分组和视图模式选项
//

#if os(macOS)
    import AppKit
    import SwiftUI

    // MARK: - 菜单项按钮组件

    /// 可复用的菜单项按钮组件
    ///
    /// 支持标题、图标、选中状态显示
    /// _Requirements: 2.4, 2.8, 3.5, 4.6_
    struct MenuItemButton: View {

        // MARK: - Properties

        /// 菜单项标题
        let title: String

        /// 菜单项图标（可选）
        let icon: String?

        /// 是否选中
        let isSelected: Bool

        /// 点击回调
        let action: () -> Void

        // MARK: - Initializers

        /// 初始化方法
        /// - Parameters:
        ///   - title: 菜单项标题
        ///   - icon: 菜单项图标（可选）
        ///   - isSelected: 是否选中
        ///   - action: 点击回调
        init(
            title: String,
            icon: String? = nil,
            isSelected: Bool = false,
            action: @escaping () -> Void
        ) {
            self.title = title
            self.icon = icon
            self.isSelected = isSelected
            self.action = action
        }

        // MARK: - Body

        var body: some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    // 选中标记
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.accentColor)
                            .frame(width: 16, alignment: .center)
                    } else {
                        Color.clear
                            .frame(width: 16)
                    }

                    // 图标（如果有）
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                            .frame(width: 16, alignment: .center)
                    }

                    // 标题
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 分隔线组件

    /// 菜单分隔线组件
    struct MenuDivider: View {
        var body: some View {
            Divider()
                .padding(.vertical, 4)
        }
    }

    // MARK: - 菜单标题组件

    /// 菜单标题组件
    struct MenuSectionTitle: View {
        let title: String

        var body: some View {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
        }
    }

    // MARK: - 视图选项菜单视图

    /// 视图选项菜单视图
    ///
    /// 显示排序方式、排序方向、日期分组和视图模式选项
    /// _Requirements: 1.2, 2.1, 2.2, 2.6, 3.2, 4.2_
    struct ViewOptionsMenuView: View {

        // MARK: - Properties

        /// 视图选项管理器
        @ObservedObject var optionsManager: ViewOptionsManager

        /// 菜单是否显示（用于关闭菜单）
        @Binding var isPresented: Bool

        // MARK: - Body

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                // 排序方式部分
                sortOrderSection

                MenuDivider()

                // 排序方向部分
                sortDirectionSection

                MenuDivider()

                // 日期分组部分
                dateGroupingSection

                MenuDivider()

                // 视图模式部分
                viewModeSection
            }
            .frame(width: 180)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        }

        // MARK: - 排序方式部分

        /// 排序方式选项
        /// _Requirements: 2.1, 2.2, 2.4_
        private var sortOrderSection: some View {
            VStack(alignment: .leading, spacing: 0) {
                MenuSectionTitle(title: "排序方式")

                ForEach([NoteSortOrder.editDate, .createDate, .title], id: \.self) { order in
                    MenuItemButton(
                        title: order.displayName,
                        icon: order.icon,
                        isSelected: optionsManager.state.sortOrder == order
                    ) {
                        optionsManager.setSortOrder(order)
                    }
                }
            }
        }

        // MARK: - 排序方向部分

        /// 排序方向选项
        /// _Requirements: 2.6, 2.8_
        private var sortDirectionSection: some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach([SortDirection.descending, .ascending], id: \.self) { direction in
                    MenuItemButton(
                        title: direction.displayName,
                        icon: direction.icon,
                        isSelected: optionsManager.state.sortDirection == direction
                    ) {
                        optionsManager.setSortDirection(direction)
                    }
                }
            }
        }

        // MARK: - 日期分组部分

        /// 日期分组选项
        /// _Requirements: 3.2, 3.5_
        private var dateGroupingSection: some View {
            MenuItemButton(
                title: "按日期分组",
                icon: "calendar",
                isSelected: optionsManager.state.isDateGroupingEnabled
            ) {
                optionsManager.toggleDateGrouping()
            }
        }

        // MARK: - 视图模式部分

        /// 视图模式选项
        /// _Requirements: 4.2, 4.6_
        private var viewModeSection: some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    MenuItemButton(
                        title: mode.displayName,
                        icon: mode.icon,
                        isSelected: optionsManager.state.viewMode == mode
                    ) {
                        optionsManager.setViewMode(mode)
                        // 切换视图模式后关闭菜单
                        isPresented = false
                    }
                }
            }
        }
    }

    // MARK: - Preview

    #Preview("视图选项菜单") {
        ViewOptionsMenuView(
            optionsManager: ViewOptionsManager.shared,
            isPresented: .constant(true)
        )
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }

    #Preview("菜单项按钮 - 选中") {
        MenuItemButton(
            title: "编辑时间",
            icon: "pencil",
            isSelected: true
        ) {
        }
        .frame(width: 180)
        .padding()
    }

    #Preview("菜单项按钮 - 未选中") {
        MenuItemButton(
            title: "创建时间",
            icon: "calendar.badge.plus",
            isSelected: false
        ) {
        }
        .frame(width: 180)
        .padding()
    }

#endif
