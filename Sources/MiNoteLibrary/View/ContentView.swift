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
    
    /// 是否显示同步菜单（已废弃，保留用于兼容）
    @State private var showingSyncMenu = false
    
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
            if viewModel.selectedFolder != nil {
                NotesListView(viewModel: viewModel)
            } else {
                // 如果没有选中文件夹，显示空状态
                ContentUnavailableView(
                    "选择文件夹",
                    systemImage: "folder",
                    description: Text("请从侧边栏选择一个文件夹")
                )
            }
        }
        .navigationTitle(viewModel.selectedFolder?.name ?? "所有笔记")
        .navigationSubtitle("\(viewModel.filteredNotes.count) 个备忘录")
        .navigationSplitViewColumnWidth(
            min: calculatedNotesListMinWidth,
            ideal: calculatedNotesListIdealWidth,
            max: notesListMaxWidth
        )
        .toolbar {
            // 自动位置：在线状态指示器（Cookie失效时可点击刷新）
            ToolbarItem(placement: .automatic) {
                onlineStatusIndicatorWithAction
            }
            
//            // 右侧：搜索框/搜索按钮
//            ToolbarItem(placement: .primaryAction) {
//                searchToolbarItem
//            }
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
    
    /// 状态指示器（可点击刷新Cookie）
    /// 
    /// Cookie失效时可以点击刷新，其他状态显示为普通文本
    private var onlineStatusIndicatorWithAction: some View {
        Group {
            if viewModel.isCookieExpired {
                // Cookie失效时，显示为可点击的按钮
                Button {
                    viewModel.showCookieRefreshView = true
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .font(.caption2)
                            .foregroundColor(statusColor)
                    }
                }
                .buttonStyle(.plain)
                .help(statusHelpText)
            } else {
                // 其他状态显示为普通文本
                onlineStatusIndicator
            }
        }
    }
    
    /// 搜索工具栏项 - 响应式搜索框/按钮
    /// 
    /// 位置：工具栏最右侧（.primaryAction）
    /// 
    /// 响应式行为：
    /// - 窗口宽度 > 800：显示搜索框（带放大镜图标和输入框）
    /// - 窗口宽度 ≤ 800：显示搜索按钮（点击后弹出搜索弹窗）
    /// 
    /// 搜索框样式：
    /// - 圆角背景
    /// - 宽度：150px
    /// - 字体大小：13pt
    private var searchToolbarItem: some View {
        Group {
            if windowWidth > 800 {
                // 宽度足够，显示搜索框
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    
                    TextField("搜索笔记", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 150)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: NSColor.controlBackgroundColor))
                )
            } else {
                // 宽度不够，显示搜索按钮
                Button {
                    showingSearchField.toggle()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                }
                .help("搜索笔记")
                .popover(isPresented: $showingSearchField, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("搜索笔记")
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            
                            TextField("输入搜索关键词", text: $viewModel.searchText)
                                .textFieldStyle(.plain)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: NSColor.controlBackgroundColor))
                        )
                        
                        if !viewModel.searchText.isEmpty {
                            Button("清除") {
                                viewModel.searchText = ""
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(12)
                    .frame(width: 250)
                }
            }
        }
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
    
    var body: some View {
        List(selection: $viewModel.selectedFolder) {
            // MARK: 小米笔记 Section
            Section {
                // 置顶文件夹
                if let starredFolder = viewModel.folders.first(where: { $0.id == "starred" }) {
                    SidebarFolderRow(folder: starredFolder)
                        .tag(starredFolder)
                        .contextMenu {
                            Button {
                                showSystemFolderRenameAlert(folder: starredFolder)
                            } label: {
                                Label("重命名文件夹", systemImage: "pencil.circle")
                            }
                        }
                }
                
                // 所有笔记文件夹
                if let allNotesFolder = viewModel.folders.first(where: { $0.id == "0" }) {
                    SidebarFolderRow(folder: allNotesFolder)
                        .tag(allNotesFolder)
                        .contextMenu {
                            Button {
                                showSystemFolderRenameAlert(folder: allNotesFolder)
                            } label: {
                                Label("重命名文件夹", systemImage: "pencil.circle")
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
            Section("我的文件夹") {
                // 未分类文件夹 - 现在 Folder 的 Equatable 只比较 id，所以可以正常保持选中状态
                SidebarFolderRow(folder: viewModel.uncategorizedFolder)
                    .tag(viewModel.uncategorizedFolder)
                    .contextMenu {
                        Button {
                            renameUncategorizedFolder()
                        } label: {
                            Label("重命名文件夹", systemImage: "pencil.circle")
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
                    SidebarFolderRow(folder: folder)
                        .tag(folder)
                        .contextMenu {
                            // 置顶/取消置顶文件夹
                            Button {
                                toggleFolderPin(folder)
                            } label: {
                                Label(folder.isPinned ? "取消置顶" : "置顶文件夹", systemImage: folder.isPinned ? "pin.slash" : "pin")
                            }
                            
                            Divider()
                            
                            // 重命名文件夹
                            Button {
                                renameFolder(folder)
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
            // Section 级别的右键菜单：新建文件夹
            .contextMenu {
                Button {
                    createNewFolder()
                } label: {
                    Label("新建文件夹", systemImage: "folder.badge.plus")
                }
            }
        }
        .listStyle(.sidebar)
        .accentColor(.yellow)  // 设置列表选择颜色为黄色
        .toolbar {
            // 工具栏：同步菜单按钮
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    // 新建文件夹
                    Button(action: createNewFolder) {
                        Label("新建文件夹", systemImage: "folder.badge.plus")
                    }
                    
                    Divider()
                    
                    // 完整同步
                    Button(action: performFullSync) {
                        Label("完整同步", systemImage: "arrow.down.circle")
                    }
                    .disabled(viewModel.isSyncing || !viewModel.isLoggedIn)
                    
                    // 增量同步
                    Button(action: performIncrementalSync) {
                        Label("增量同步", systemImage: "arrow.down.circle.dotted")
                    }
                    .disabled(viewModel.isSyncing || !viewModel.isLoggedIn)
                    
                    Divider()
                    
                    // 重置同步状态
                    Button(action: resetSyncStatus) {
                        Label("重置同步状态", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(viewModel.isSyncing)
                    
                    Divider()
                    
                    // 同步状态
                    Button(action: showSyncStatus) {
                        Label("同步状态", systemImage: "info.circle")
                    }
                } label: {
                    // 同步时显示加载图标，否则显示同步图标
                    if viewModel.isSyncing {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(viewModel.isSyncing)
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
    /// 显示输入对话框，让用户输入文件夹名称
    private func createNewFolder() {
        // 显示输入对话框
        let alert = NSAlert()
        alert.messageText = "新建文件夹"
        alert.informativeText = "请输入文件夹名称："
        alert.alertStyle = .informational
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")
        
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        inputField.placeholderString = "文件夹名称"
        alert.accessoryView = inputField
        alert.window.initialFirstResponder = inputField
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            let folderName = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !folderName.isEmpty {
                Task {
                    do {
                        try await viewModel.createFolder(name: folderName)
                    } catch {
                        print("[ContentView] 创建文件夹失败: \(error.localizedDescription)")
                    }
                }
            }
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
    /// 显示输入对话框，让用户输入新名称
    /// - Parameter folder: 要重命名的文件夹
    private func renameFolder(_ folder: Folder) {
        let alert = NSAlert()
        alert.messageText = "重命名文件夹"
        alert.informativeText = "请输入新的文件夹名称："
        alert.alertStyle = .informational
        alert.addButton(withTitle: "重命名")
        alert.addButton(withTitle: "取消")
        
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        inputField.placeholderString = "新文件夹名称"
        inputField.stringValue = folder.name
        alert.accessoryView = inputField
        alert.window.initialFirstResponder = inputField
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            let newName = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newName.isEmpty && newName != folder.name {
                Task {
                    do {
                        try await viewModel.renameFolder(folder, newName: newName)
                    } catch {
                        viewModel.errorMessage = "重命名文件夹失败: \(error.localizedDescription)"
                    }
                }
            } else if newName.isEmpty {
                viewModel.errorMessage = "文件夹名称不能为空"
            }
        }
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
}

// MARK: - 侧边栏文件夹行视图

/// 侧边栏文件夹行视图
/// 
/// 显示单个文件夹的信息：
/// - 文件夹图标（根据文件夹类型显示不同图标和颜色）
/// - 文件夹名称
/// - 笔记数量
struct SidebarFolderRow: View {
    /// 文件夹数据
    let folder: Folder
    
    /// 名称前缀（可选，用于特殊显示）
    var prefix: String = ""
    
    var body: some View {
        HStack {
            // 文件夹图标
            Image(systemName: folderIcon)
                .foregroundColor(folderColor)
                .font(.system(size: 16))  // 图标大小：16pt
                .frame(width: 24)  // 图标容器宽度：24px
            
            // 文件夹名称
            Text(prefix + folder.name)
                .lineLimit(1)
            
            Spacer()
            
            // 笔记数量
            Text("\(folder.count)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
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

@available(macOS 14.0, *)
#Preview {
    ContentView(viewModel: NotesViewModel())
}
