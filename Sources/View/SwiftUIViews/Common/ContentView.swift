import AppKit
import SwiftUI

/// 主内容视图 - 应用程序的核心UI容器
///
/// **已废弃**: 此视图已被新的多窗口架构替代。
/// 现在应该使用 `ContentAreaView` 配合 `coordinator` 和 `windowState`。
///
/// 保留此文件仅用于向后兼容和预览，但不应在新代码中使用。
///
/// UI布局说明：
/// - 左侧：侧边栏（文件夹列表）
/// - 中间：笔记列表（显示选中文件夹的笔记）
/// - 右侧：笔记编辑器（显示和编辑选中的笔记）
@available(macOS 14.0, *)
@available(*, deprecated, message: "使用 ContentAreaView 配合 coordinator 和 windowState 替代")
public struct ContentView: View {
    // MARK: - 数据绑定和状态管理

    /// 应用协调器
    let coordinator: AppCoordinator

    /// State 对象
    @ObservedObject var noteListState: NoteListState
    @ObservedObject var folderState: FolderState
    @ObservedObject var syncState: SyncState
    @ObservedObject var authState: AuthState
    @ObservedObject var searchState: SearchState
    @ObservedObject var noteEditorState: NoteEditorState

    /// 向后兼容：仍需要 viewModel 用于尚未迁移的子视图
    private var viewModel: NotesViewModel {
        coordinator.notesViewModel
    }

    /// 侧边栏可见性状态
    /// - `.all`: 显示所有列（侧边栏、列表、编辑区）
    /// - `.detailOnly`: 只显示列表和编辑区（隐藏侧边栏）
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    /// 是否显示新建笔记弹窗
    @State private var showingNewNote = false

    /// 是否显示设置弹窗
    @State private var showingSettings = false

    /// 是否显示登录弹窗
    @State private var showingLogin = false

    /// 是否显示Cookie失效弹窗
    @State private var showingCookieExpiredAlert = false

    @State private var showingSyncMenu = false

    /// 是否显示离线操作处理进度视图
    @State private var showingOfflineOperationsProgress = false

    /// 是否显示回收站视图
    @State private var showTrashView = false

    /// 当前窗口宽度 - 用于响应式布局计算
    @State private var windowWidth: CGFloat = 800

    /// 上次更新时间 - 用于防抖处理
    @State private var lastUpdateTime = Date()

    /// 是否显示搜索框弹窗（当窗口宽度不够时）
    @State private var showingSearchField = false

    /// 工具栏宽度 - 用于搜索框响应式显示（当前未使用，保留用于未来扩展）
    @State private var toolbarWidth: CGFloat = 0

    // MARK: - 列宽度常量定义

    /// 侧边栏最小宽度（像素）
    private let sidebarMinWidth: CGFloat = 180

    /// 侧边栏最大宽度（像素）
    private let sidebarMaxWidth: CGFloat = 300

    /// 侧边栏理想宽度（像素）
    private let sidebarIdealWidth: CGFloat = 250

    /// 笔记列表栏最小宽度（像素）
    private let notesListMinWidth: CGFloat = 200

    /// 笔记列表栏最大宽度（像素）
    private let notesListMaxWidth: CGFloat = 400

    /// 笔记列表栏理想宽度（像素）
    private let notesListIdealWidth: CGFloat = 300

    /// 编辑栏最小宽度（像素）
    private let detailMinWidth: CGFloat = 300

    /// 编辑栏绝对最小宽度（像素）- 当窗口非常小时，可以缩小到这个值
    private let detailAbsoluteMinWidth: CGFloat = 250

    /// 编辑栏理想宽度（像素）
    private let detailIdealWidth: CGFloat = 500

    /// 分隔线和边距宽度（像素）- 用于计算可用空间
    private let separatorWidth: CGFloat = 20

    // MARK: - 计算属性：窗口和布局相关

    /// 计算最小窗口宽度
    /// 公式：侧边栏最小 + 笔记列表最小 + 编辑栏绝对最小 + 分隔线
    /// 当前值：180 + 200 + 250 + 20 = 650
    private var minWindowWidth: CGFloat {
        sidebarMinWidth + notesListMinWidth + detailAbsoluteMinWidth + separatorWidth
    }

    /// 计算隐藏侧边栏的阈值
    /// 当窗口宽度小于这个值时，自动隐藏侧边栏
    /// 公式：笔记列表最小 + 编辑栏绝对最小 + 分隔线
    /// 当前值：200 + 250 + 20 = 470
    private var hideSidebarThreshold: CGFloat {
        notesListMinWidth + detailAbsoluteMinWidth + separatorWidth
    }

    // MARK: - 初始化方法

    /// 初始化方法
    /// - Parameter coordinator: 应用协调器
    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self._noteListState = ObservedObject(wrappedValue: coordinator.noteListState)
        self._folderState = ObservedObject(wrappedValue: coordinator.folderState)
        self._syncState = ObservedObject(wrappedValue: coordinator.syncState)
        self._authState = ObservedObject(wrappedValue: coordinator.authState)
        self._searchState = ObservedObject(wrappedValue: coordinator.searchState)
        self._noteEditorState = ObservedObject(wrappedValue: coordinator.noteEditorState)
    }

    // MARK: - 主视图

    /// 主视图body
    ///
    /// 布局结构：
    /// ```
    /// GeometryReader (监听窗口大小变化)
    ///   └─ NavigationSplitView (三栏布局)
    ///        ├─ sidebarContent (侧边栏)
    ///        ├─ notesListContent (笔记列表)
    ///        └─ detailContent (编辑区)
    /// ```
    public var body: some View {
        GeometryReader { geometry in
            mainNavigationView
                .onAppear {
                    // 初始化窗口宽度
                    windowWidth = geometry.size.width
                    updateColumnVisibility(for: geometry.size.width)
                }
                .onChange(of: geometry.size.width) { _, newValue in
                    // 防抖处理：避免频繁更新导致抖动
                    let now = Date()
                    if now.timeIntervalSince(lastUpdateTime) > 0.1 {
                        windowWidth = newValue
                        updateColumnVisibility(for: newValue)
                        lastUpdateTime = now
                    } else {
                        // 延迟更新
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            windowWidth = newValue
                            updateColumnVisibility(for: newValue)
                            lastUpdateTime = Date()
                        }
                    }
                }
        }
        .frame(minWidth: minWindowWidth, minHeight: 400)
        .sheet(isPresented: $showingNewNote) {
            NewNoteView(noteListState: noteListState, folderState: folderState)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(syncState: syncState, authState: authState)
        }
        .sheet(isPresented: $showingLogin) {
            LoginView(authState: authState)
        }
        .sheet(isPresented: $showingOfflineOperationsProgress) {
            OfflineOperationsProgressView(processor: OperationProcessor.shared)
        }
        .sheet(isPresented: $showTrashView) {
            TrashView(viewModel: viewModel)
        }
        .alert("Cookie已失效", isPresented: $showingCookieExpiredAlert) {
            Button("重新登录") {
                authState.handleCookieExpiredRefresh()
            }
            Button("取消", role: .cancel) {
                authState.showLoginView = true
            }
        } message: {
            Text("Cookie已失效，请重新登录以恢复同步功能。选择\"取消\"将保持离线模式。")
        }
        .onChange(of: authState.showCookieExpiredAlert) { _, newValue in
            if newValue {
                showingCookieExpiredAlert = true
                authState.showCookieExpiredAlert = false
            }
        }
        .onAppear(perform: handleAppear)
        .onChange(of: authState.showLoginView) { _, newValue in
            if newValue {
                showingLogin = true
                authState.showLoginView = false
            }
        }
        .onChange(of: authState.isLoggedIn) { oldValue, newValue in
            if newValue, !oldValue {
                Task {
                    await authState.handleLoginSuccess()
                }
            } else if !newValue, oldValue {
                authState.userProfile = nil
            }
        }
    }

    // MARK: - 导航视图组件

    /// 主导航视图 - 三栏布局容器
    ///
    /// 使用 NavigationSplitView 实现响应式三栏布局：
    /// - 第一栏：侧边栏（文件夹列表）
    /// - 第二栏：笔记列表
    /// - 第三栏：笔记编辑器
    ///
    /// 样式：`.balanced` - 平衡布局，自动调整各栏宽度
    private var mainNavigationView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
        } content: {
            notesListContent
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// 侧边栏内容视图
    ///
    /// 包含：
    /// - 文件夹列表（系统文件夹 + 用户文件夹）
    /// - 同步按钮菜单
    ///
    /// 宽度设置：
    /// - 最小：calculatedSidebarMinWidth（动态计算）
    /// - 理想：calculatedSidebarIdealWidth（动态计算）
    /// - 最大：sidebarMaxWidth（300）
    private var sidebarContent: some View {
        SidebarView(coordinator: coordinator)
            .navigationSplitViewColumnWidth(
                min: calculatedSidebarMinWidth,
                ideal: calculatedSidebarIdealWidth,
                max: sidebarMaxWidth
            )
            .animation(.easeInOut(duration: 0.3), value: calculatedSidebarMinWidth)
            .animation(.easeInOut(duration: 0.3), value: calculatedSidebarIdealWidth)
    }

    /// 笔记列表内容视图
    ///
    /// 显示选中文件夹的笔记列表，使用AppKit的NotesListViewController
    ///
    /// 宽度设置：
    /// - 最小：calculatedNotesListMinWidth（动态计算）
    /// - 理想：calculatedNotesListIdealWidth（动态计算）
    /// - 最大：notesListMaxWidth（400）
    private var notesListContent: some View {
        Group {
            if folderState.selectedFolder != nil || !searchState.searchText.isEmpty || searchState.hasSearchFilters {
                NotesListViewControllerWrapper(viewModel: viewModel)
            } else {
                ContentUnavailableView(
                    "选择文件夹",
                    systemImage: "folder",
                    description: Text("请从侧边栏选择一个文件夹")
                )
            }
        }
        .navigationTitle(searchState.searchText.isEmpty && !searchState.hasSearchFilters ? (folderState.selectedFolder?.name ?? "所有笔记") : "搜索")
        .navigationSubtitle(searchState.searchText.isEmpty && !searchState
            .hasSearchFilters ? "\(noteListState.filteredNotes.count) 个笔记" : "找到 \(noteListState.filteredNotes.count) 个结果")
        .navigationSplitViewColumnWidth(
            min: calculatedNotesListMinWidth,
            ideal: notesListMaxWidth,
            max: notesListMaxWidth
        )
        .searchable(
            text: $searchState.searchText,
            placement: .toolbar,
            prompt: searchState.filterTagsText.isEmpty ? "搜索笔记" : searchState.filterTagsText
        )
        .searchSuggestions {
            SearchFilterMenuContent(noteListState: noteListState)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                onlineStatusIndicatorWithAction
            }
        }
    }

    /// 编辑区内容视图
    ///
    /// 显示和编辑选中的笔记
    ///
    /// 宽度设置：
    /// - 最小：calculatedDetailMinWidth（动态计算）
    /// - 理想：calculatedDetailWidth.ideal（动态计算）
    ///
    /// **注意**: 此视图已废弃，使用临时兼容层
    private var detailContent: some View {
        // 临时兼容层：创建一个简单的占位视图
        // 由于 ContentView 已废弃，这里不需要完整实现
        Text("此视图已废弃")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationSplitViewColumnWidth(
                min: calculatedDetailMinWidth,
                ideal: calculatedDetailWidth.ideal
            )
    }

    // MARK: - 工具栏组件

    /// 新建笔记按钮
    ///
    /// 位置：工具栏左侧（.navigation）
    /// 图标：square.and.pencil
    /// 大小：12pt，中等粗细
    private var newNoteButton: some View {
        Button {
            Task { await noteListState.createNewNote(inFolder: folderState.selectedFolder?.id ?? "0") }
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 12, weight: .medium)) // 中等粗细
        }
        .help("新建笔记")
    }

    /// 在线状态指示器
    ///
    /// 显示当前网络连接状态
    /// 位置：工具栏自动位置（.automatic）
    ///
    /// 显示内容：
    /// - 绿色圆点 + "在线"（网络正常且cookie有效）
    /// - 红色圆点 + "Cookie失效"（网络正常但cookie失效）
    /// - 黄色圆点 + "离线"（网络断开）
    private var onlineStatusIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption2)
                .foregroundColor(statusColor)
        }
        .help(statusHelpText)
    }

    /// 状态颜色
    private var statusColor: Color {
        if authState.isOnline {
            .green
        } else if authState.isCookieExpired {
            .red
        } else {
            .yellow
        }
    }

    /// 状态文本
    private var statusText: String {
        if authState.isOnline {
            "在线"
        } else if authState.isCookieExpired {
            "Cookie失效"
        } else {
            "离线"
        }
    }

    /// 状态提示文本
    private var statusHelpText: String {
        if authState.isOnline {
            "已连接到小米笔记服务器"
        } else if authState.isCookieExpired {
            "Cookie已失效，请刷新Cookie或重新登录（点击可刷新）"
        } else {
            "离线模式：更改将在网络恢复后同步"
        }
    }

    /// 状态提示文本（包含待处理操作信息）
    private var statusHelpTextWithOperations: String {
        var helpText = statusHelpText
        if viewModel.pendingOperationsCount > 0 {
            helpText += "\n待处理操作: \(viewModel.pendingOperationsCount) 个"
        }
        return helpText
    }

    /// 状态指示器（合并了同步功能）
    ///
    /// 显示在线状态，点击可打开菜单，包含：
    /// - 同步选项（完整同步、增量同步）
    /// - Cookie刷新选项（如果失效）
    /// - 重置同步状态
    /// - 同步状态
    private var onlineStatusIndicatorWithAction: some View {
        Menu {
            Button {
                syncState.requestFullSync(mode: .normal)
            } label: {
                Label("完整同步", systemImage: "arrow.down.circle")
            }
            .disabled(syncState.isSyncing || !authState.isLoggedIn)

            Button {
                syncState.requestSync(mode: .full(.normal))
            } label: {
                Label("增量同步", systemImage: "arrow.down.circle.dotted")
            }
            .disabled(syncState.isSyncing || !authState.isLoggedIn)

            Divider()

            if authState.isCookieExpired {
                Button {
                    authState.showLoginView = true
                } label: {
                    Label("重新登录", systemImage: "person.crop.circle.badge.exclamationmark")
                }

                Divider()
            }

            Button {
                viewModel.resetSyncStatus()
            } label: {
                Label("重置同步状态", systemImage: "arrow.counterclockwise")
            }
            .disabled(syncState.isSyncing)

            Divider()

            // 笔记列表排序方式
            Menu {
                Button {
                    noteListState.notesListSortField = .createDate
                } label: {
                    Label("按创建时间排序", systemImage: noteListState.notesListSortField == .createDate ? "checkmark" : "circle")
                }

                Button {
                    noteListState.notesListSortField = .editDate
                } label: {
                    Label("按修改时间排序", systemImage: noteListState.notesListSortField == .editDate ? "checkmark" : "circle")
                }

                Button {
                    noteListState.notesListSortField = .title
                } label: {
                    Label("按名称排序", systemImage: noteListState.notesListSortField == .title ? "checkmark" : "circle")
                }

                Divider()

                Button {
                    noteListState.notesListSortDirection = .ascending
                } label: {
                    Label("升序", systemImage: noteListState.notesListSortDirection == .ascending ? "checkmark" : "circle")
                }

                Button {
                    noteListState.notesListSortDirection = .descending
                } label: {
                    Label("降序", systemImage: noteListState.notesListSortDirection == .descending ? "checkmark" : "circle")
                }
            } label: {
                Label("笔记列表排序", systemImage: "arrow.up.arrow.down")
            }

            Divider()

            // 离线操作处理（仍使用 viewModel，因为 State 对象尚未提供这些属性）
            if viewModel.pendingOperationsCount > 0 {
                Button {
                    showingOfflineOperationsProgress = true
                    Task {
                        await OperationProcessor.shared.processQueue()
                    }
                } label: {
                    Label("处理离线操作 (\(viewModel.pendingOperationsCount))", systemImage: "arrow.clockwise.circle")
                }
                .disabled(viewModel.isProcessingOfflineQueue || !authState.isOnline)

                if viewModel.offlineQueueFailedCount > 0 {
                    Button {
                        Task {
                            await OperationProcessor.shared.processRetries()
                        }
                    } label: {
                        Label("重试失败操作 (\(viewModel.offlineQueueFailedCount))", systemImage: "arrow.counterclockwise.circle")
                    }
                    .disabled(viewModel.isProcessingOfflineQueue || !authState.isOnline)
                }

                Divider()
            }

            Button {
                if let lastSync = syncState.lastSyncTime {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .short
                    formatter.timeStyle = .short

                    let alert = NSAlert()
                    alert.messageText = "同步状态"
                    var infoText = "上次同步时间: \(formatter.string(from: lastSync))"
                    if viewModel.pendingOperationsCount > 0 {
                        infoText += "\n待处理操作: \(viewModel.pendingOperationsCount) 个"
                    }
                    alert.informativeText = infoText
                    alert.addButton(withTitle: "确定")
                    alert.runModal()
                } else {
                    let alert = NSAlert()
                    alert.messageText = "同步状态"
                    var infoText = "从未同步"
                    if viewModel.pendingOperationsCount > 0 {
                        infoText += "\n待处理操作: \(viewModel.pendingOperationsCount) 个"
                    }
                    alert.informativeText = infoText
                    alert.addButton(withTitle: "确定")
                    alert.runModal()
                }
            } label: {
                Label("同步状态", systemImage: "info.circle")
            }
        } label: {
            HStack(spacing: 4) {
                if syncState.isSyncing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 8, height: 8)
                } else {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                }
                Text(statusText)
                    .font(.caption2)
                    .foregroundColor(statusColor)

                if viewModel.unifiedPendingUploadCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: 8))
                        Text("\(viewModel.unifiedPendingUploadCount)")
                            .font(.caption2)
                    }
                    .foregroundColor(.orange)
                } else if viewModel.temporaryIdNoteCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "doc.badge.clock")
                            .font(.system(size: 8))
                        Text("\(viewModel.temporaryIdNoteCount)")
                            .font(.caption2)
                    }
                    .foregroundColor(.purple)
                } else if viewModel.pendingOperationsCount > 0 {
                    Text("(\(viewModel.pendingOperationsCount))")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .help(statusHelpTextWithOperations)
    }

    // MARK: - 列宽度计算逻辑

    /// 计算各列宽度（统一计算，确保优先级正确）
    ///
    /// 优先级顺序（从高到低）：
    /// 1. 编辑栏（最先缩小）
    /// 2. 笔记列表栏（编辑栏达到最小时开始缩小）
    /// 3. 侧边栏（笔记列表栏达到最小时开始缩小）
    /// 4. 隐藏侧边栏（侧边栏达到最小时）
    ///
    /// 参数：
    /// - assumeSidebarVisible: 假设侧边栏是否可见（用于避免循环依赖）
    ///
    /// 返回：
    /// - detail: (min: 最小宽度, ideal: 理想宽度)
    /// - notesList: (min: 最小宽度, ideal: 理想宽度)
    /// - sidebar: (min: 最小宽度, ideal: 理想宽度)
    private func calculateColumnWidths(assumeSidebarVisible: Bool? = nil) -> (
        detail: (min: CGFloat, ideal: CGFloat),
        notesList: (min: CGFloat, ideal: CGFloat),
        sidebar: (min: CGFloat, ideal: CGFloat)
    ) {
        let availableWidth = windowWidth - separatorWidth

        // 使用传入的参数，如果没有则根据窗口宽度判断
        let sidebarVisible: Bool = if let assume = assumeSidebarVisible {
            assume
        } else {
            // 根据窗口宽度判断侧边栏是否应该可见（避免循环依赖）
            windowWidth >= hideSidebarThreshold + sidebarMinWidth
        }

        // 步骤1：先尝试给编辑栏分配空间（优先级最高，最先缩小）
        var detailWidth = detailMinWidth
        var notesListWidth = notesListMinWidth
        var sidebarWidth = sidebarVisible ? sidebarMinWidth : 0

        var totalUsed = detailWidth + notesListWidth + sidebarWidth

        // 如果空间不足，按优先级缩小
        if totalUsed > availableWidth {
            // 步骤2：缩小编辑栏到绝对最小
            detailWidth = detailAbsoluteMinWidth
            totalUsed = detailWidth + notesListWidth + sidebarWidth

            if totalUsed > availableWidth {
                // 步骤3：编辑栏已是最小，缩小笔记列表
                let remaining = availableWidth - detailWidth - sidebarWidth
                notesListWidth = max(150, remaining) // 笔记列表最小150
                totalUsed = detailWidth + notesListWidth + sidebarWidth

                if totalUsed > availableWidth, sidebarVisible {
                    // 步骤4：笔记列表已是最小，缩小侧边栏
                    let remaining = availableWidth - detailWidth - notesListWidth
                    sidebarWidth = max(0, remaining)
                    totalUsed = detailWidth + notesListWidth + sidebarWidth
                }
            }
        }

        // 计算理想宽度（在最小宽度基础上，如果有剩余空间则分配）
        let remainingSpace = availableWidth - totalUsed
        var idealDetailWidth = detailWidth
        var idealNotesListWidth = notesListWidth
        var idealSidebarWidth = sidebarWidth

        if remainingSpace > 0 {
            // 按比例分配剩余空间（编辑栏优先）
            idealDetailWidth = min(detailIdealWidth, detailWidth + remainingSpace * 0.5)
            let detailExtra = idealDetailWidth - detailWidth
            let remainingAfterDetail = remainingSpace - detailExtra

            idealNotesListWidth = min(notesListIdealWidth, notesListWidth + remainingAfterDetail * 0.5)
            let notesListExtra = idealNotesListWidth - notesListWidth
            let remainingAfterNotesList = remainingAfterDetail - notesListExtra

            if sidebarVisible {
                idealSidebarWidth = min(sidebarIdealWidth, sidebarWidth + remainingAfterNotesList)
            }
        }

        return (
            detail: (min: detailWidth, ideal: idealDetailWidth),
            notesList: (min: notesListWidth, ideal: idealNotesListWidth),
            sidebar: (min: sidebarWidth, ideal: idealSidebarWidth)
        )
    }

    /// 计算编辑栏宽度（优先级1：最先缩小）
    ///
    /// 返回：(min: 最小宽度, ideal: 理想宽度)
    private var calculatedDetailWidth: (min: CGFloat, ideal: CGFloat) {
        // 使用当前 columnVisibility 状态来计算
        calculateColumnWidths(assumeSidebarVisible: columnVisibility == .all).detail
    }

    /// 计算笔记列表宽度（优先级2：编辑栏达到最小时开始缩小）
    ///
    /// 返回：(min: 最小宽度, ideal: 理想宽度)
    private var calculatedNotesListWidth: (min: CGFloat, ideal: CGFloat) {
        calculateColumnWidths(assumeSidebarVisible: columnVisibility == .all).notesList
    }

    /// 计算侧边栏宽度（优先级3：笔记列表达到最小时开始缩小）
    ///
    /// 返回：(min: 最小宽度, ideal: 理想宽度)
    private var calculatedSidebarWidth: (min: CGFloat, ideal: CGFloat) {
        calculateColumnWidths(assumeSidebarVisible: columnVisibility == .all).sidebar
    }

    /// 计算侧边栏最小宽度
    private var calculatedSidebarMinWidth: CGFloat {
        calculatedSidebarWidth.min
    }

    /// 计算侧边栏理想宽度
    private var calculatedSidebarIdealWidth: CGFloat {
        calculatedSidebarWidth.ideal
    }

    /// 计算笔记列表最小宽度
    private var calculatedNotesListMinWidth: CGFloat {
        calculatedNotesListWidth.min
    }

    /// 计算笔记列表理想宽度
    private var calculatedNotesListIdealWidth: CGFloat {
        calculatedNotesListWidth.ideal
    }

    /// 计算编辑栏最小宽度
    private var calculatedDetailMinWidth: CGFloat {
        calculatedDetailWidth.min
    }

    // MARK: - 生命周期和事件处理

    /// 视图出现时的处理
    ///
    /// 主要功能：
    /// - 检查用户认证状态
    /// - 如果未认证，显示登录界面
    /// - 启动自动刷新Cookie定时器
    /// - 检查Cookie状态，如果失效则尝试静默刷新
    private func handleAppear() {
        let isAuthenticated = MiNoteService.shared.isAuthenticated()

        if !isAuthenticated {
            showingLogin = true
        } else {
            authState.startAutoRefreshCookieIfNeeded()
            checkCookieStatusAndRefreshIfNeeded()
        }
    }

    /// 检查Cookie状态，如果失效则尝试静默刷新
    private func checkCookieStatusAndRefreshIfNeeded() {
        let hasValidCookie = MiNoteService.shared.hasValidCookie()

        if !hasValidCookie {
            let silentRefreshOnFailure = UserDefaults.standard.bool(forKey: "silentRefreshOnFailure")

            if silentRefreshOnFailure {
                Task {
                    await authState.handleCookieExpiredSilently()
                }
            }
        }
    }

    /// 切换侧边栏显示/隐藏
    ///
    /// 用于手动切换侧边栏可见性
    private func toggleSidebar() {
        withAnimation {
            if columnVisibility == .all {
                columnVisibility = .detailOnly
            } else {
                columnVisibility = .all
            }
        }
    }

    /// 根据窗口宽度自动更新侧边栏可见性
    ///
    /// 使用滞后（hysteresis）阈值避免在阈值附近抖动：
    /// - 显示阈值：窗口宽度需要达到这个值才会显示侧边栏
    /// - 隐藏阈值：窗口宽度小于这个值才会隐藏侧边栏
    ///
    /// 阈值计算：
    /// - 显示阈值 = hideSidebarThreshold + sidebarMinWidth - 30
    /// - 隐藏阈值 = hideSidebarThreshold + sidebarMinWidth + 30
    ///
    /// 这样设计可以避免在临界值附近频繁切换
    /// - Parameter width: 当前窗口宽度
    private func updateColumnVisibility(for width: CGFloat) {
        let currentShowsSidebar = columnVisibility == .all

        // 使用滞后（hysteresis）阈值以避免在阈值附近抖动
        // 显示阈值：窗口宽度需要达到这个值才会显示侧边栏
        let showThreshold = hideSidebarThreshold + sidebarMinWidth - 30
        // 隐藏阈值：窗口宽度小于这个值才会隐藏侧边栏
        let hideThreshold = hideSidebarThreshold + sidebarMinWidth + 30

        let shouldShowSidebar: Bool = if currentShowsSidebar {
            // 当前显示侧边栏，只有当宽度小于隐藏阈值时才隐藏
            width >= hideThreshold
        } else {
            // 当前隐藏侧边栏，只有当宽度大于显示阈值时才显示
            width >= showThreshold
        }

        // 只有当状态需要改变时才更新
        if shouldShowSidebar != currentShowsSidebar {
            withAnimation(.easeInOut(duration: 0.3)) {
                columnVisibility = shouldShowSidebar ? .all : .detailOnly
            }
        }
    }
}

// MARK: - 账户行视图

/// 账户行视图（当前未使用，保留用于未来扩展）
struct AccountRow: View {
    let name: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)

            Text(name)
                .lineLimit(1)

            Spacer()
        }
    }
}

// MARK: - 同步状态覆盖层

struct SyncStatusOverlay: View {
    @ObservedObject var syncState: SyncState

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)

                Text(syncState.syncStatusMessage)
                    .font(.caption)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            )

            if syncState.syncProgress > 0 {
                ProgressView(value: syncState.syncProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
            }
        }
        .padding(.bottom, 20)
        .padding(.horizontal, 20)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - 自动聚焦文本字段

/// 自动聚焦的文本字段
///
/// 一个自定义的 TextField，在出现时自动聚焦并选中所有文本
struct AutoFocusTextField: View {
    @Binding var text: String
    let placeholder: String
    let onCommit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text, onCommit: onCommit)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .onAppear {
                // 延迟一点时间确保视图已经完全渲染
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isFocused = true
                    // 选中所有文本
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        if let textField = NSApp.keyWindow?.firstResponder as? NSTextView {
                            textField.selectAll(nil)
                        }
                    }
                }
            }
    }
}

// MARK: - NotesListViewControllerWrapper

/// NotesListViewController的SwiftUI包装器
///
/// 将AppKit的NotesListViewController包装成SwiftUI视图
/// 用于在ContentView中替换原来的SwiftUI NotesListView
struct NotesListViewControllerWrapper: NSViewControllerRepresentable {
    @ObservedObject var viewModel: NotesViewModel

    func makeNSViewController(context _: Context) -> NotesListViewController {
        NotesListViewController(viewModel: viewModel)
    }

    func updateNSViewController(_: NotesListViewController, context _: Context) {
        // 视图模型更新时，不需要额外操作
        // NotesListViewController内部已经通过Combine监听viewModel的变化
    }
}

@available(macOS 14.0, *)
#Preview {
    ContentView(coordinator: PreviewHelper.shared.createPreviewCoordinator())
}
