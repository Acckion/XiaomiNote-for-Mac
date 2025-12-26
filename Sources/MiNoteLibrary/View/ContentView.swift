import SwiftUI
import AppKit

/// 主内容视图 - 应用程序的核心UI容器
/// 
/// 这个视图负责：
/// - 管理三栏布局（侧边栏、笔记列表、编辑区）
/// - 响应式窗口大小调整
/// - 工具栏和搜索功能
/// - 窗口标题设置
///
/// UI布局说明：
/// - 左侧：侧边栏（文件夹列表）
/// - 中间：笔记列表（显示选中文件夹的笔记）
/// - 右侧：笔记编辑器（显示和编辑选中的笔记）
@available(macOS 14.0, *)
public struct ContentView: View {
    // MARK: - 数据绑定和状态管理
    
    /// 视图模型 - 管理笔记、文件夹、同步等业务逻辑
    @ObservedObject var viewModel: NotesViewModel
    
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
    
    /// 是否显示Cookie刷新弹窗
    @State private var showingCookieRefresh = false
    
    /// 是否显示Cookie失效弹窗
    @State private var showingCookieExpiredAlert = false
    
    /// 是否显示同步菜单（已废弃，保留用于兼容）
    @State private var showingSyncMenu = false
    
    /// 是否显示离线操作处理进度视图
    @State private var showingOfflineOperationsProgress = false
    
    /// 当前窗口宽度 - 用于响应式布局计算
    @State private var windowWidth: CGFloat = 800
    
    /// 上次更新时间 - 用于防抖处理
    @State private var lastUpdateTime: Date = Date()
    
    /// 是否显示搜索框弹窗（当窗口宽度不够时）
    @State private var showingSearchField: Bool = false
    
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
    /// - Parameter viewModel: 笔记视图模型实例
    public init(viewModel: NotesViewModel) {
        self.viewModel = viewModel
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
                .onChange(of: geometry.size.width) { oldValue, newValue in
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
            NewNoteView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingLogin) {
            LoginView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingCookieRefresh) {
            CookieRefreshView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingOfflineOperationsProgress) {
            OfflineOperationsProgressView(processor: OfflineOperationProcessor.shared)
        }
        .sheet(isPresented: $viewModel.showPrivateNotesPasswordDialog) {
            PrivateNotesPasswordInputDialogView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showTrashView) {
            TrashView(viewModel: viewModel)
        }
        .alert("Cookie已失效", isPresented: $showingCookieExpiredAlert) {
            Button("刷新Cookie") {
                viewModel.handleCookieExpiredRefresh()
            }
            Button("取消", role: .cancel) {
                viewModel.handleCookieExpiredCancel()
            }
        } message: {
            Text("Cookie已失效，请刷新Cookie以恢复同步功能。选择\"取消\"将保持离线模式。")
        }
        .onChange(of: viewModel.showCookieExpiredAlert) { oldValue, newValue in
            if newValue {
                showingCookieExpiredAlert = true
                viewModel.showCookieExpiredAlert = false
            }
        }
        .onAppear(perform: handleAppear)
        .onChange(of: viewModel.showLoginView) { oldValue, newValue in
            if newValue {
                showingLogin = true
                viewModel.showLoginView = false
            }
        }
        .onChange(of: viewModel.showCookieRefreshView) { oldValue, newValue in
            if newValue {
                showingCookieRefresh = true
                viewModel.showCookieRefreshView = false
            }
        }
        .onChange(of: viewModel.isLoggedIn) { oldValue, newValue in
            if newValue {
                // 登录成功后获取用户信息
                Task {
                    await viewModel.fetchUserProfile()
                }
            } else {
                // 登出后清空用户信息
                viewModel.userProfile = nil
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
        SidebarView(viewModel: viewModel)
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
    /// 显示选中文件夹的笔记列表，包含：
    /// - 笔记列表（NotesListView）
    /// - 工具栏（在线状态、搜索框）
    /// 
    /// 宽度设置：
    /// - 最小：calculatedNotesListMinWidth（动态计算）
    /// - 理想：calculatedNotesListIdealWidth（动态计算）
    /// - 最大：notesListMaxWidth（400）
    private var notesListContent: some View {
        Group {
            if viewModel.selectedFolder != nil || !viewModel.searchText.isEmpty || viewModel.hasSearchFilters {
                NotesListView(viewModel: viewModel)
            } else {
                // 如果没有选中文件夹且没有搜索且没有筛选，显示空状态
                ContentUnavailableView(
                    "选择文件夹",
                    systemImage: "folder",
                    description: Text("请从侧边栏选择一个文件夹")
                )
            }
        }
        .navigationTitle(viewModel.searchText.isEmpty && !viewModel.hasSearchFilters ? (viewModel.selectedFolder?.name ?? "所有笔记") : "搜索")
        .navigationSubtitle(viewModel.searchText.isEmpty && !viewModel.hasSearchFilters ? "\(viewModel.filteredNotes.count) 个备忘录" : "找到 \(viewModel.filteredNotes.count) 个结果")
        .navigationSplitViewColumnWidth(
            min: calculatedNotesListMinWidth,
            ideal: notesListMaxWidth,
            max: notesListMaxWidth
        )
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: viewModel.filterTagsText.isEmpty ? "搜索笔记" : viewModel.filterTagsText)
        .searchToolbarBehavior(.automatic)
        .searchSuggestions {
            SearchFilterMenuContent(viewModel: viewModel)
        }
        .toolbar {
            // 自动位置：在线状态指示器（Cookie失效时可点击刷新）
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
    private var detailContent: some View {
        NoteDetailView(viewModel: viewModel)
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
            viewModel.createNewNote()
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 12, weight: .medium))  // 中等粗细
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
        if viewModel.isOnline {
            return .green
        } else if viewModel.isCookieExpired {
            return .red
        } else {
            return .yellow
        }
    }
    
    /// 状态文本
    private var statusText: String {
        if viewModel.isOnline {
            return "在线"
        } else if viewModel.isCookieExpired {
            return "Cookie失效"
        } else {
            return "离线"
        }
    }
    
    /// 状态提示文本
    private var statusHelpText: String {
        if viewModel.isOnline {
            return "已连接到小米笔记服务器"
        } else if viewModel.isCookieExpired {
            return "Cookie已失效，请刷新Cookie或重新登录（点击可刷新）"
        } else {
            return "离线模式：更改将在网络恢复后同步"
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
            // 同步选项
            Button {
                Task {
                    await viewModel.performFullSync()
                }
            } label: {
                Label("完整同步", systemImage: "arrow.down.circle")
            }
            .disabled(viewModel.isSyncing || !viewModel.isLoggedIn)
            
            Button {
                Task {
                    await viewModel.performIncrementalSync()
                }
            } label: {
                Label("增量同步", systemImage: "arrow.down.circle.dotted")
            }
            .disabled(viewModel.isSyncing || !viewModel.isLoggedIn)
            
            Divider()
            
            // Cookie刷新（如果失效）
            if viewModel.isCookieExpired {
                Button {
                    viewModel.showCookieRefreshView = true
                } label: {
                    Label("刷新Cookie", systemImage: "arrow.clockwise")
                }
                
                Divider()
            }
            
            // 重置同步状态
            Button {
                viewModel.resetSyncStatus()
            } label: {
                Label("重置同步状态", systemImage: "arrow.counterclockwise")
            }
            .disabled(viewModel.isSyncing)
            
            Divider()
            
            // 笔记列表排序方式
            Menu {
                // 排序字段
                Button {
                    viewModel.setNotesListSortField(.createDate)
                } label: {
                    Label("按创建时间排序", systemImage: viewModel.notesListSortField == .createDate ? "checkmark" : "")
                }
                
                Button {
                    viewModel.setNotesListSortField(.editDate)
                } label: {
                    Label("按修改时间排序", systemImage: viewModel.notesListSortField == .editDate ? "checkmark" : "")
                }
                
                Button {
                    viewModel.setNotesListSortField(.title)
                } label: {
                    Label("按名称排序", systemImage: viewModel.notesListSortField == .title ? "checkmark" : "")
                }
                
                Divider()
                
                // 排序方向
                Button {
                    viewModel.setNotesListSortDirection(.ascending)
                } label: {
                    Label("升序", systemImage: viewModel.notesListSortDirection == .ascending ? "checkmark" : "")
                }
                
                Button {
                    viewModel.setNotesListSortDirection(.descending)
                } label: {
                    Label("降序", systemImage: viewModel.notesListSortDirection == .descending ? "checkmark" : "")
                }
            } label: {
                Label("笔记列表排序", systemImage: "arrow.up.arrow.down")
            }
            
            Divider()
            
            // 离线操作处理
            if viewModel.pendingOperationsCount > 0 {
                Button {
                    showingOfflineOperationsProgress = true
                    Task {
                        await OfflineOperationProcessor.shared.processOperations()
                    }
                } label: {
                    Label("处理离线操作 (\(viewModel.pendingOperationsCount))", systemImage: "arrow.clockwise.circle")
                }
                .disabled(viewModel.isProcessingOfflineOperations || !viewModel.isOnline)
                
                if viewModel.failedOperationsCount > 0 {
                    Button {
                        Task {
                            await OfflineOperationProcessor.shared.retryFailedOperations()
                        }
                    } label: {
                        Label("重试失败操作 (\(viewModel.failedOperationsCount))", systemImage: "arrow.counterclockwise.circle")
                    }
                    .disabled(viewModel.isProcessingOfflineOperations || !viewModel.isOnline)
                }
                
                Divider()
            }
            
            // 同步状态
            Button {
                // 显示同步状态信息
                if let lastSync = viewModel.lastSyncTime {
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
                // 同步时显示加载图标，否则显示状态圆点
                if viewModel.isSyncing {
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
                
                // 显示待处理操作数量（如果有）
                if viewModel.pendingOperationsCount > 0 {
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
    private func calculateColumnWidths(assumeSidebarVisible: Bool? = nil) -> (detail: (min: CGFloat, ideal: CGFloat), 
                                             notesList: (min: CGFloat, ideal: CGFloat),
                                             sidebar: (min: CGFloat, ideal: CGFloat)) {
        let availableWidth = windowWidth - separatorWidth
        
        // 使用传入的参数，如果没有则根据窗口宽度判断
        let sidebarVisible: Bool
        if let assume = assumeSidebarVisible {
            sidebarVisible = assume
        } else {
            // 根据窗口宽度判断侧边栏是否应该可见（避免循环依赖）
            sidebarVisible = windowWidth >= hideSidebarThreshold + sidebarMinWidth
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
                
                if totalUsed > availableWidth && sidebarVisible {
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
    private func handleAppear() {
            print("ContentView onAppear - 检查认证状态")
            let isAuthenticated = MiNoteService.shared.isAuthenticated()
            print("isAuthenticated: \(isAuthenticated)")
            
            if !isAuthenticated {
                print("显示登录界面")
                showingLogin = true
            } else {
                print("已认证，不显示登录界面")
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
        
        let shouldShowSidebar: Bool
        if currentShowsSidebar {
            // 当前显示侧边栏，只有当宽度小于隐藏阈值时才隐藏
            shouldShowSidebar = width >= hideThreshold
        } else {
            // 当前隐藏侧边栏，只有当宽度大于显示阈值时才显示
            shouldShowSidebar = width >= showThreshold
        }
        
        // 只有当状态需要改变时才更新
        if shouldShowSidebar != currentShowsSidebar {
            withAnimation(.easeInOut(duration: 0.3)) {
                columnVisibility = shouldShowSidebar ? .all : .detailOnly
            }
        }
    }
}

// MARK: - 侧边栏视图

/// 侧边栏视图 - 显示文件夹列表
/// 
/// 包含两个Section：
/// 1. "小米笔记" - 系统文件夹（置顶、所有笔记）
/// 2. "我的文件夹" - 用户文件夹（未分类 + 数据库中的文件夹，置顶的在前）
struct SidebarView: View {
    @ObservedObject var viewModel: NotesViewModel
    @State private var showingSyncMenu = false
    
    // 行内编辑状态
    @State private var editingFolderId: String? = nil
    @State private var editingFolderName: String = ""
    @State private var isCreatingNewFolder: Bool = false
    @State private var newFolderName: String = ""
    
    // 防止重复弹窗的状态
    @State private var lastDuplicateAlertFolderName: String? = nil
    @State private var lastDuplicateAlertTime: Date? = nil
    
    var body: some View {
        // 添加透明背景来捕获点击外部事件
        ZStack {
            // 透明背景，用于捕获点击外部事件
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    // 当用户点击侧边栏外部时，如果当前有文件夹正在编辑，触发名称检查
                    if let editingFolderId = editingFolderId,
                       let editingFolder = viewModel.folders.first(where: { $0.id == editingFolderId }) {
                        // 延迟一小段时间，确保点击事件已经处理完成
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            saveRename(folder: editingFolder)
                        }
                    }
                }
            
            List(selection: $viewModel.selectedFolder) {
            // MARK: 小米笔记 Section
            Section {
                // 所有笔记文件夹
                if let allNotesFolder = viewModel.folders.first(where: { $0.id == "0" }) {
                    SidebarFolderRow(folder: allNotesFolder)
                        .tag(allNotesFolder)
                        .contextMenu {
                            Button {
                                createNewFolder()
                            } label: {
                                Label("新建文件夹", systemImage: "folder.badge.plus")
                            }
                            
                            Divider()
                            
                            // 排序方式
                            Menu {
                                Button {
                                    viewModel.setFolderSortOrder(allNotesFolder, sortOrder: .editDate)
                                } label: {
                                    Label("编辑日期", systemImage: viewModel.getFolderSortOrder(allNotesFolder) == .editDate ? "checkmark" : "")
                                }
                                
                                Button {
                                    viewModel.setFolderSortOrder(allNotesFolder, sortOrder: .createDate)
                                } label: {
                                    Label("创建日期", systemImage: viewModel.getFolderSortOrder(allNotesFolder) == .createDate ? "checkmark" : "")
                                }
                                
                                Button {
                                    viewModel.setFolderSortOrder(allNotesFolder, sortOrder: .title)
                                } label: {
                                    Label("标题", systemImage: viewModel.getFolderSortOrder(allNotesFolder) == .title ? "checkmark" : "")
                                }
                            } label: {
                                Label("排序方式", systemImage: "arrow.up.arrow.down")
                            }
                        }
                }
                // 置顶文件夹
                if let starredFolder = viewModel.folders.first(where: { $0.id == "starred" }) {
                    SidebarFolderRow(folder: starredFolder)
                        .tag(starredFolder)
                        .contextMenu {
                            Button {
                                createNewFolder()
                            } label: {
                                Label("新建文件夹", systemImage: "folder.badge.plus")
                            }
                            
                            Divider()
                            
                            // 排序方式
                            Menu {
                                Button {
                                    viewModel.setFolderSortOrder(starredFolder, sortOrder: .editDate)
                                } label: {
                                    Label("编辑日期", systemImage: viewModel.getFolderSortOrder(starredFolder) == .editDate ? "checkmark" : "")
                                }
                                
                                Button {
                                    viewModel.setFolderSortOrder(starredFolder, sortOrder: .createDate)
                                } label: {
                                    Label("创建日期", systemImage: viewModel.getFolderSortOrder(starredFolder) == .createDate ? "checkmark" : "")
                                }
                                
                                Button {
                                    viewModel.setFolderSortOrder(starredFolder, sortOrder: .title)
                                } label: {
                                    Label("标题", systemImage: viewModel.getFolderSortOrder(starredFolder) == .title ? "checkmark" : "")
                                }
                            } label: {
                                Label("排序方式", systemImage: "arrow.up.arrow.down")
                            }
                        }
                }
                // 私密笔记文件夹
                if let privateNotesFolder = viewModel.folders.first(where: { $0.id == "2" }) {
                    SidebarFolderRow(folder: privateNotesFolder)
                        .tag(privateNotesFolder)
                        .contextMenu {
                            Button {
                                createNewFolder()
                            } label: {
                                Label("新建文件夹", systemImage: "folder.badge.plus")
                            }
                        }
                }
            } header: {
                // Section 标题：显示"小米笔记"和同步加载图标
                HStack(spacing: 6) {
                    Text("小米笔记")
                    // 同步时显示加载图标
                    if viewModel.isSyncing {
                        ProgressView()
                            .scaleEffect(0.4)  // 缩小图标大小
                            .frame(width: 10, height: 10)
                    }
                }
            }
            
            // MARK: 我的文件夹 Section
            Section {
                // 未分类文件夹 - 现在 Folder 的 Equatable 只比较 id，所以可以正常保持选中状态
                SidebarFolderRow(folder: viewModel.uncategorizedFolder)
                    .tag(viewModel.uncategorizedFolder)
                    .contextMenu {
                        Button {
                            createNewFolder()
                        } label: {
                            Label("新建文件夹", systemImage: "folder.badge.plus")
                        }
                        
                        Divider()
                        
                        // 排序方式
                        Menu {
                            Button {
                                viewModel.setFolderSortOrder(viewModel.uncategorizedFolder, sortOrder: .editDate)
                            } label: {
                                Label("编辑日期", systemImage: viewModel.getFolderSortOrder(viewModel.uncategorizedFolder) == .editDate ? "checkmark" : "")
                            }
                            
                            Button {
                                viewModel.setFolderSortOrder(viewModel.uncategorizedFolder, sortOrder: .createDate)
                            } label: {
                                Label("创建日期", systemImage: viewModel.getFolderSortOrder(viewModel.uncategorizedFolder) == .createDate ? "checkmark" : "")
                            }
                            
                            Button {
                                viewModel.setFolderSortOrder(viewModel.uncategorizedFolder, sortOrder: .title)
                            } label: {
                                Label("标题", systemImage: viewModel.getFolderSortOrder(viewModel.uncategorizedFolder) == .title ? "checkmark" : "")
                            }
                        } label: {
                            Label("排序方式", systemImage: "arrow.up.arrow.down")
                        }
                    }
                
                // 显示所有非系统文件夹（从数据库加载）
                // 排除系统文件夹（id == "0" 或 "starred"）和未分类文件夹（id == "uncategorized"）
                // 按置顶状态排序：置顶的在前
                ForEach(viewModel.folders.filter { folder in
                    !folder.isSystem && 
                    folder.id != "0" && 
                    folder.id != "starred" && 
                    folder.id != "uncategorized" &&
                    folder.id != "new"
                }.sorted { folder1, folder2 in
                    // 置顶的在前
                    if folder1.isPinned != folder2.isPinned {
                        return folder1.isPinned
                    }
                    // 否则按名称排序
                    return folder1.name < folder2.name
                }) { folder in
                    if editingFolderId == folder.id {
                        // 编辑模式
                        SidebarFolderRow(
                            folder: folder,
                            isEditing: true,
                            editingName: $editingFolderName,
                            onCommit: {
                                saveRename(folder: folder)
                            },
                            onCancel: {
                                cancelRename()
                            }
                        )
                        .tag(folder)
                    } else {
                        // 正常模式
                        SidebarFolderRow(folder: folder)
                            .tag(folder)
                        .contextMenu {
                            // 新建文件夹
                            Button {
                                createNewFolder()
                            } label: {
                                Label("新建文件夹", systemImage: "folder.badge.plus")
                            }
                            
                            Divider()
                            
                            // 排序方式
                            Menu {
                                Button {
                                    viewModel.setFolderSortOrder(folder, sortOrder: .editDate)
                                } label: {
                                    Label("编辑日期", systemImage: viewModel.getFolderSortOrder(folder) == .editDate ? "checkmark" : "")
                                }
                                
                                Button {
                                    viewModel.setFolderSortOrder(folder, sortOrder: .createDate)
                                } label: {
                                    Label("创建日期", systemImage: viewModel.getFolderSortOrder(folder) == .createDate ? "checkmark" : "")
                                }
                                
                                Button {
                                    viewModel.setFolderSortOrder(folder, sortOrder: .title)
                                } label: {
                                    Label("标题", systemImage: viewModel.getFolderSortOrder(folder) == .title ? "checkmark" : "")
                                }
                            } label: {
                                Label("排序方式", systemImage: "arrow.up.arrow.down")
                            }
                            
                            Divider()
                            
                            // 重命名文件夹
                            Button {
                                startRename(folder: folder)
                            } label: {
                                Label("重命名文件夹", systemImage: "pencil.circle")
                            }
                            
                            // 删除文件夹
                            Button(role: .destructive) {
                                deleteFolder(folder)
                            } label: {
                                Label("删除文件夹", systemImage: "trash")
                            }
                        }
                    }
                }
                
                // 新建文件夹行（只在创建时显示）
                if isCreatingNewFolder {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                            .foregroundColor(.white)
                            .font(.system(size: 16))
                            .frame(width: 24)
                        
                        AutoFocusTextField(
                            text: $newFolderName,
                            placeholder: "输入文件夹名称",
                            onCommit: {
                                // 直接调用 createNewFolder 方法
                                createNewFolder()
                            }
                        )
                        .onSubmit {
                            // 直接调用 createNewFolder 方法
                            createNewFolder()
                        }
                    }
                    .tag(Folder(id: "new", name: "新建文件夹", count: 0, isSystem: false, isPinned: false))
                }
            } header: {
                HStack {
                    Text("我的文件夹")
                }
                .contextMenu {
                    Button {
                        createNewFolder()
                    } label: {
                        Label("新建文件夹", systemImage: "folder.badge.plus")
                    }
                }
            }
            }
            .listStyle(.sidebar)
            .accentColor(.yellow)  // 设置列表选择颜色为黄色
            .onKeyPress(.return) {
                // 检查是否应该进入重命名模式
                if let selectedFolder = viewModel.selectedFolder,
                   !selectedFolder.isSystem,
                   selectedFolder.id != "uncategorized",
                   selectedFolder.id != "0",
                   selectedFolder.id != "starred",
                   selectedFolder.id != "2",
                   editingFolderId == nil,
                   !isCreatingNewFolder {
                    // 检查鼠标是否悬停在选中的文件夹上
                    // 这里需要检查鼠标位置，但由于 SwiftUI 的限制，我们暂时假设如果选中了文件夹就可以重命名
                    startRename(folder: selectedFolder)
                    return .handled
                }
                return .ignored
            }
            .onChange(of: viewModel.selectedFolder) { oldValue, newValue in
                // 当用户点击其他文件夹时，如果当前有文件夹正在编辑，触发名称检查
                if let editingFolderId = editingFolderId,
                   let editingFolder = viewModel.folders.first(where: { $0.id == editingFolderId }) {
                    // 延迟一小段时间，确保点击事件已经处理完成
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        // 标记这是通过点击其他文件夹退出的
                        saveRename(folder: editingFolder, isExitingByClickingOtherFolder: true)
                    }
                }
            }
        }
    }
    
    // MARK: - 侧边栏操作函数
    
    /// 执行完整同步
    private func performFullSync() {
        Task {
            await viewModel.performFullSync()
        }
    }
    
    /// 执行增量同步
    private func performIncrementalSync() {
        Task {
            await viewModel.performIncrementalSync()
        }
    }
    
    /// 重置同步状态
    private func resetSyncStatus() {
        viewModel.resetSyncStatus()
    }
    
    /// 创建新文件夹
    /// 
    /// 自动生成文件夹名称（"新建文件夹x"，如果已存在则递增）
    /// 然后立即创建并选中，进入重命名模式
    private func createNewFolder() {
        // 生成文件夹名称
        let folderName = generateNewFolderName()
        
        // 立即执行创建，而不是进入编辑模式
        Task {
            do {
                // 调用 createFolder 方法，它会返回新创建的文件夹ID
                let newFolderId = try await viewModel.createFolder(name: folderName)
                print("[ContentView] ✅ 文件夹创建成功，返回的文件夹ID: \(newFolderId)")
                
                // 创建成功后，立即选中并进入重命名模式
                await selectAndRenameNewFolder(folderId: newFolderId, folderName: folderName)
            } catch {
                print("[ContentView] 创建文件夹失败: \(error.localizedDescription)")
            }
        }
    }
    
    /// 生成新的文件夹名称
    /// 
    /// 格式："新建文件夹x"，如果已存在则递增
    /// 例如：如果已有"新建文件夹1"、"新建文件夹2"，则生成"新建文件夹3"
    private func generateNewFolderName() -> String {
        let baseName = "新建文件夹"
        var maxNumber = 0
        
        // 查找所有以"新建文件夹"开头的文件夹
        for folder in viewModel.folders {
            if folder.name.hasPrefix(baseName) {
                let suffix = String(folder.name.dropFirst(baseName.count))
                if let number = Int(suffix) {
                    maxNumber = max(maxNumber, number)
                }
            }
        }
        
        // 生成下一个数字
        let nextNumber = maxNumber + 1
        return "\(baseName)\(nextNumber)"
    }
    
    
    
    /// 取消新建文件夹
    private func cancelNewFolder() {
        isCreatingNewFolder = false
        newFolderName = ""
    }
    
    /// 选中并重命名新创建的文件夹
    private func selectAndRenameNewFolder(folderId: String, folderName: String) async {
        // 等待文件夹列表更新（最多尝试5次，每次间隔0.2秒）
        var attempts = 0
        let maxAttempts = 5
        
        while attempts < maxAttempts {
            attempts += 1
            
            // 在主线程刷新文件夹列表
            await MainActor.run {
                viewModel.loadFolders()
            }
            
            // 等待一小段时间
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
            
            // 检查文件夹是否已更新
            await MainActor.run {
                let nonSystemFolders = viewModel.folders.filter { !$0.isSystem }
                print("[ContentView] 等待文件夹更新，尝试 \(attempts)/\(maxAttempts)，文件夹名称: '\(folderName)', 返回的文件夹ID: '\(folderId)'")
                print("[ContentView] 非系统文件夹数量: \(nonSystemFolders.count)")
                print("[ContentView] 非系统文件夹列表: \(nonSystemFolders.map { "\($0.id):'\($0.name)' (创建于: \($0.createdAt))" }.joined(separator: ", "))")
                
                // 首先尝试使用返回的文件夹ID查找
                if let newFolder = nonSystemFolders.first(where: { $0.id == folderId }) {
                    print("[ContentView] ✅ 通过返回的ID找到新创建的文件夹: \(newFolder.id) - '\(newFolder.name)' (创建于: \(newFolder.createdAt))")
                    
                    // 选中文件夹（在侧边栏中高亮显示）
                    viewModel.selectedFolder = newFolder
                    print("[ContentView] ✅ 已设置 selectedFolder: '\(viewModel.selectedFolder?.name ?? "nil")' (ID: \(viewModel.selectedFolder?.id ?? "nil"))")
                    
                    // 进入编辑状态（光标在文件夹名称处，可以立即修改）
                    editingFolderId = newFolder.id
                    editingFolderName = newFolder.name
                    print("[ContentView] ✅ 已进入编辑状态，editingFolderId: \(editingFolderId ?? "nil")")
                    
                    // 成功找到并选中，退出循环
                    return
                } else {
                    // 如果通过ID找不到，尝试查找名称完全匹配的文件夹
                    let matchingFolders = nonSystemFolders.filter { $0.name == folderName }
                    print("[ContentView] 名称匹配的文件夹数量: \(matchingFolders.count)")
                    
                    if let newFolder = matchingFolders.first {
                        print("[ContentView] ⚠️ 通过ID未找到，但通过名称找到文件夹: \(newFolder.id) - '\(newFolder.name)'")
                        viewModel.selectedFolder = newFolder
                        editingFolderId = newFolder.id
                        editingFolderName = newFolder.name
                        return
                    } else {
                        // 如果还没有找到，尝试查找创建时间在创建操作之后的文件夹
                        let recentlyCreatedFolders = nonSystemFolders.filter { $0.createdAt > Date().addingTimeInterval(-10) } // 最近10秒内创建的
                        print("[ContentView] 最近创建的文件夹数量: \(recentlyCreatedFolders.count)")
                        
                        if let newFolder = recentlyCreatedFolders.first {
                            print("[ContentView] ⚠️ 通过名称未找到，但找到最近创建的文件夹: \(newFolder.id) - '\(newFolder.name)'")
                            viewModel.selectedFolder = newFolder
                            editingFolderId = newFolder.id
                            editingFolderName = newFolder.name
                            return
                        }
                    }
                }
            }
        }
        
        // 如果循环结束还没有找到，打印警告
        await MainActor.run {
            print("[ContentView] ❌ 警告：未找到新创建的文件夹 '\(folderName)' (ID: \(folderId))")
            print("[ContentView] 所有文件夹列表: \(viewModel.folders.map { "\($0.id):'\($0.name)' (系统: \($0.isSystem), 创建于: \($0.createdAt))" }.joined(separator: ", "))")
        }
    }
    
    /// 切换文件夹置顶状态
    /// 
    /// - Parameter folder: 要切换置顶状态的文件夹
    private func toggleFolderPin(_ folder: Folder) {
        Task {
            do {
                try await viewModel.toggleFolderPin(folder)
            } catch {
                print("[ContentView] 切换文件夹置顶状态失败: \(error.localizedDescription)")
            }
        }
    }
    
    /// 显示系统文件夹重命名提示
    /// 
    /// 系统文件夹（置顶、所有笔记）不能重命名
    /// - Parameter folder: 要提示的文件夹
    private func showSystemFolderRenameAlert(folder: Folder) {
        // 系统文件夹不能重命名
        let alert = NSAlert()
        alert.messageText = "提示"
        alert.informativeText = "\"\(folder.name)\"是系统文件夹，不能重命名。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    /// 重命名未分类文件夹
    /// 
    /// 未分类文件夹是系统文件夹，不能重命名
    private func renameUncategorizedFolder() {
        // 未分类文件夹是系统文件夹，不能重命名
        showSystemFolderRenameAlert(folder: viewModel.uncategorizedFolder)
    }
    
    /// 重命名文件夹
    /// 
    /// 使用内联编辑方式，直接在文件夹名称处进行修改
    /// - Parameter folder: 要重命名的文件夹
    private func renameFolder(_ folder: Folder) {
        // 使用内联编辑方式，直接进入编辑状态
        startRename(folder: folder)
    }
    
    /// 删除文件夹
    /// 
    /// 显示确认对话框，确认后删除文件夹
    /// 删除后，文件夹内的所有笔记将移动到"未分类"
    /// - Parameter folder: 要删除的文件夹
    private func deleteFolder(_ folder: Folder) {
        let alert = NSAlert()
        alert.messageText = "删除文件夹"
        alert.informativeText = "确定要删除文件夹 \"\(folder.name)\" 吗？此操作无法撤销，并且文件夹内的所有笔记将移动到\"未分类\"。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            Task {
                do {
                    try await viewModel.deleteFolder(folder)
                } catch {
                    viewModel.errorMessage = "删除文件夹失败: \(error.localizedDescription)"
                }
            }
        }
    }
    
    /// 显示同步状态
    /// 
    /// 显示上次同步时间或"从未同步"提示
    private func showSyncStatus() {
        // 显示同步状态信息
        if let lastSync = viewModel.lastSyncTime {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            
            let alert = NSAlert()
            alert.messageText = "同步状态"
            alert.informativeText = "上次同步时间: \(formatter.string(from: lastSync))"
            alert.addButton(withTitle: "确定")
            alert.runModal()
        } else {
            let alert = NSAlert()
            alert.messageText = "同步状态"
            alert.informativeText = "从未同步"
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }
    
    // MARK: - 行内编辑方法
    
    /// 开始重命名文件夹
    /// - Parameter folder: 要重命名的文件夹
    private func startRename(folder: Folder) {
        editingFolderId = folder.id
        editingFolderName = folder.name
    }
    
    /// 保存重命名
    /// - Parameter folder: 要重命名的文件夹
    /// - Parameter isExitingByClickingOtherFolder: 是否通过点击其他文件夹退出编辑状态
    private func saveRename(folder: Folder, isExitingByClickingOtherFolder: Bool = false) {
        let newName = editingFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 验证新名称
        if newName.isEmpty {
            // 名称不能为空，恢复原名称
            editingFolderId = nil
            editingFolderName = ""
            return
        }
        
        if newName == folder.name {
            // 名称未改变，无需操作
            editingFolderId = nil
            editingFolderName = ""
            return
        }
        
        // 检查是否有同名文件夹
        if viewModel.folders.contains(where: { $0.name == newName && $0.id != folder.id }) {
            // 如果通过点击其他文件夹退出，总是显示弹窗（不检查防重复逻辑）
            if isExitingByClickingOtherFolder {
                // 名称已存在，显示弹窗提示
                // 注意：在显示弹窗前，需要先恢复编辑状态，因为用户已经点击了其他文件夹
                // 但我们需要阻止文件夹切换，直到用户处理完重复名称的问题
                showDuplicateNameAlertOnExit(isNewFolder: false, folderName: newName, folder: folder)
                return
            }
            
            // 检查是否刚刚显示过相同的重复名称弹窗（防止重复弹窗）
            let now = Date()
            if let lastTime = lastDuplicateAlertTime,
               let lastName = lastDuplicateAlertFolderName,
               lastName == newName,
               now.timeIntervalSince(lastTime) < 2.0 { // 2秒内不重复显示
                // 刚刚显示过相同的弹窗，保持编辑状态但不显示弹窗
                return
            }
            
            // 名称已存在，显示弹窗提示
            showDuplicateNameAlert(isNewFolder: false, folderName: newName)
            return
        }
        
        // 执行重命名
        Task {
            do {
                try await viewModel.renameFolder(folder, newName: newName)
                editingFolderId = nil
                editingFolderName = ""
            } catch {
                // 重命名失败，恢复原名称
                editingFolderId = nil
                editingFolderName = ""
                print("[ContentView] 重命名文件夹失败: \(error.localizedDescription)")
            }
        }
    }
    
    /// 取消重命名
    private func cancelRename() {
        editingFolderId = nil
        editingFolderName = ""
    }
    
    /// 显示名称重复弹窗
    /// - Parameters:
    ///   - isNewFolder: 是否是新建文件夹（true）还是重命名（false）
    ///   - folderName: 重复的文件夹名称
    private func showDuplicateNameAlert(isNewFolder: Bool, folderName: String) {
        // 记录弹窗显示的时间和名称
        lastDuplicateAlertFolderName = folderName
        lastDuplicateAlertTime = Date()
        
        let alert = NSAlert()
        alert.messageText = "名称已被使用"
        alert.informativeText = "已存在名为 \"\(folderName)\" 的文件夹。请选取一个不同的名称。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "放弃更改")
        alert.addButton(withTitle: "好")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // 放弃更改
            if isNewFolder {
                // 对于新建文件夹，取消创建
                isCreatingNewFolder = false
                newFolderName = ""
            } else {
                // 对于重命名，取消编辑
                editingFolderId = nil
                editingFolderName = ""
            }
        } else {
            // 点击"好"，保持编辑状态
            // 对于新建文件夹，保持创建状态
            // 对于重命名，保持编辑状态
            // 不需要做任何操作，用户会继续编辑
            
            // 重要：保持编辑状态，让用户可以继续修改名称
            // 对于重命名，editingFolderId 和 editingFolderName 保持不变
            // 对于新建文件夹，isCreatingNewFolder 和 newFolderName 保持不变
            
            // 注意：不需要在这里聚焦文本字段，因为 SidebarFolderRow 的 onAppear 会自动处理
        }
    }
    
    /// 显示名称重复弹窗（当通过点击其他文件夹退出时）
    /// - Parameters:
    ///   - isNewFolder: 是否是新建文件夹（true）还是重命名（false）
    ///   - folderName: 重复的文件夹名称
    ///   - folder: 正在编辑的文件夹（用于恢复选中状态）
    private func showDuplicateNameAlertOnExit(isNewFolder: Bool, folderName: String, folder: Folder) {
        // 记录弹窗显示的时间和名称
        lastDuplicateAlertFolderName = folderName
        lastDuplicateAlertTime = Date()
        
        let alert = NSAlert()
        alert.messageText = "名称已被使用"
        alert.informativeText = "已存在名为 \"\(folderName)\" 的文件夹。请选取一个不同的名称。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "放弃更改")
        alert.addButton(withTitle: "好")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // 放弃更改
            if isNewFolder {
                // 对于新建文件夹，取消创建
                isCreatingNewFolder = false
                newFolderName = ""
            } else {
                // 对于重命名，取消编辑
                editingFolderId = nil
                editingFolderName = ""
            }
        } else {
            // 点击"好"，恢复编辑状态并重新选中该文件夹
            if isNewFolder {
                // 对于新建文件夹，保持创建状态
                // 不需要做任何操作
            } else {
                // 对于重命名，恢复编辑状态并重新选中该文件夹
                editingFolderId = folder.id
                editingFolderName = folderName
                // 重新选中该文件夹，确保用户可以继续编辑
                viewModel.selectedFolder = folder
            }
        }
    }
}

// MARK: - 侧边栏文件夹行视图

/// 侧边栏文件夹行视图
/// 
/// 显示单个文件夹的信息：
/// - 文件夹图标（根据文件夹类型显示不同图标和颜色）
/// - 文件夹名称（支持编辑模式）
/// - 笔记数量
struct SidebarFolderRow: View {
    /// 文件夹数据
    let folder: Folder
    
    /// 名称前缀（可选，用于特殊显示）
    var prefix: String = ""
    
    /// 是否正在编辑
    var isEditing: Bool = false
    
    /// 编辑中的名称（绑定到父视图）
    @Binding var editingName: String
    
    /// 完成编辑的回调
    var onCommit: (() -> Void)? = nil
    
    /// 取消编辑的回调
    var onCancel: (() -> Void)? = nil
    
    /// 焦点状态
    @FocusState private var isFocused: Bool
    
    /// 鼠标是否悬停在该行上
    @State private var isHovering: Bool = false
    
    /// 初始化器 - 用于正常模式（非编辑模式）
    init(folder: Folder, prefix: String = "") {
        self.folder = folder
        self.prefix = prefix
        self.isEditing = false
        self._editingName = .constant("")
    }
    
    /// 初始化器 - 用于编辑模式
    init(folder: Folder, isEditing: Bool, editingName: Binding<String>, onCommit: (() -> Void)? = nil, onCancel: (() -> Void)? = nil) {
        self.folder = folder
        self.prefix = ""
        self.isEditing = isEditing
        self._editingName = editingName
        self.onCommit = onCommit
        self.onCancel = onCancel
    }
    
    var body: some View {
        HStack {
            // 文件夹图标
            Image(systemName: folderIcon)
                .foregroundColor(folderColor)
                .font(.system(size: 16))  // 图标大小：16pt
                .frame(width: 24)  // 图标容器宽度：24px
            
            if isEditing {
                // 编辑模式：显示 TextField
                TextField("文件夹名称", text: $editingName, onCommit: {
                    onCommit?()
                })
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit {
                    onCommit?()
                }
                .onAppear {
                    // 自动聚焦并选中所有文本
                    DispatchQueue.main.async {
                        isFocused = true
                        // 延迟一点时间确保 TextField 已经准备好
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            // 尝试选中所有文本
                            if let textField = NSApp.keyWindow?.firstResponder as? NSTextView {
                                textField.selectAll(nil)
                            }
                        }
                    }
                }
                .onChange(of: isEditing) { oldValue, newValue in
                    if newValue {
                        // 进入编辑模式时自动聚焦
                        DispatchQueue.main.async {
                            isFocused = true
                            // 延迟一点时间确保 TextField 已经准备好
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                // 尝试选中所有文本
                                if let textField = NSApp.keyWindow?.firstResponder as? NSTextView {
                                    textField.selectAll(nil)
                                }
                            }
                        }
                    } else {
                        // 退出编辑模式时移除焦点
                        isFocused = false
                    }
                }
                .onChange(of: isFocused) { oldValue, newValue in
                    // 当焦点离开输入框时，触发名称检查
                    if oldValue == true && newValue == false {
                        // 延迟一小段时间，确保焦点变化已经完成
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            onCommit?()
                        }
                    }
                }
            } else {
                // 正常模式：显示文件夹名称
                Text(prefix + folder.name)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // 笔记数量（编辑模式下不显示）
            if !isEditing {
                Text("\(folder.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .background(
            // 透明背景用于捕获键盘事件
            Color.clear
                .contentShape(Rectangle())
        )
    }
    
    /// 根据文件夹ID返回对应的图标
    /// 
    /// 图标映射：
    /// - "0" (所有笔记): tray.full
    /// - "starred" (置顶): pin.fill
    /// - "uncategorized" (未分类): folder.badge.questionmark
    /// - "new" (新建): folder.badge.plus
    /// - 其他: folder（如果置顶则显示 pin.fill）
    private var folderIcon: String {
        switch folder.id {
        case "0": return "tray.full"
        case "starred": return "pin.fill"
        case "uncategorized": return "folder.badge.questionmark"
        case "new": return "folder.badge.plus"
        default: return folder.isPinned ? "pin.fill" : "folder"
        }
    }
    
    /// 根据文件夹ID返回对应的颜色
    /// 
    /// 颜色映射（统一使用白色）：
    /// - "0" (所有笔记): 白色
    /// - "starred" (置顶): 白色
    /// - "uncategorized" (未分类): 白色
    /// - "new" (新建): 白色
    /// - 其他: 白色
    private var folderColor: Color {
        return .white
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

/// 同步状态覆盖层（已废弃，保留用于兼容）
/// 
/// 注意：当前已移除底部同步状态显示，只保留按钮的旋转动画
struct SyncStatusOverlay: View {
    @ObservedObject var viewModel: NotesViewModel
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                
                Text(viewModel.syncStatusMessage)
                    .font(.caption)
                    .lineLimit(1)
                
                Spacer()
                
                Button("取消") {
                    viewModel.cancelSync()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            )
            
            if viewModel.syncProgress > 0 {
                ProgressView(value: viewModel.syncProgress)
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

@available(macOS 14.0, *)
#Preview {
    ContentView(viewModel: NotesViewModel())
}
