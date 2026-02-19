import AppKit
import SwiftUI

/// 侧边栏视图 - 显示文件夹列表
///
/// 包含两个Section：
/// 1. "小米笔记" - 系统文件夹（置顶、所有笔记）
/// 2. "我的文件夹" - 用户文件夹（未分类 + 数据库中的文件夹，置顶的在前）
public struct SidebarView: View {
    @ObservedObject var viewModel: NotesViewModel
    @State private var showingSyncMenu = false

    // 行内编辑状态
    @State private var editingFolderId: String?
    @State private var editingFolderName = ""
    @State private var isCreatingNewFolder = false
    @State private var newFolderName = ""

    // 防止重复弹窗的状态
    @State private var lastDuplicateAlertFolderName: String?
    @State private var lastDuplicateAlertTime: Date?

    public init(viewModel: NotesViewModel) {
        self.viewModel = viewModel
    }

    /// 计算属性：根据文件夹ID返回对应的图标名称
    private func folderIconName(for folder: Folder) -> String {
        switch folder.id {
        case "0": "tray.full"
        case "starred": "pin.fill"
        case "uncategorized": "folder.badge.questionmark"
        case "new": "folder.badge.plus"
        default: folder.isPinned ? "pin.fill" : "folder"
        }
    }

    /// 计算属性：根据文件夹ID返回对应的图标颜色
    private func folderIconColor(for folder: Folder) -> Color {
        // 使用系统颜色，让图标看起来更原生
        switch folder.id {
        case "0": .blue // 所有笔记使用蓝色
        case "starred": .accentColor // 置顶使用强调色
        case "uncategorized": .gray // 未分类使用灰色
        default: .primary // 其他文件夹使用主要颜色
        }
    }

    public var body: some View {
        // 添加透明背景来捕获点击外部事件
        ZStack {
            // 透明背景，用于捕获点击外部事件
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    // 当用户点击侧边栏外部时，如果当前有文件夹正在编辑，触发名称检查
                    if let editingFolderId,
                       let editingFolder = viewModel.folders.first(where: { $0.id == editingFolderId })
                    {
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
                                        Label("编辑日期", systemImage: viewModel.getFolderSortOrder(allNotesFolder) == .editDate ? "checkmark" : "circle")
                                    }

                                    Button {
                                        viewModel.setFolderSortOrder(allNotesFolder, sortOrder: .createDate)
                                    } label: {
                                        Label(
                                            "创建日期",
                                            systemImage: viewModel.getFolderSortOrder(allNotesFolder) == .createDate ? "checkmark" : "circle"
                                        )
                                    }

                                    Button {
                                        viewModel.setFolderSortOrder(allNotesFolder, sortOrder: .title)
                                    } label: {
                                        Label("标题", systemImage: viewModel.getFolderSortOrder(allNotesFolder) == .title ? "checkmark" : "circle")
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
                                        Label("编辑日期", systemImage: viewModel.getFolderSortOrder(starredFolder) == .editDate ? "checkmark" : "circle")
                                    }

                                    Button {
                                        viewModel.setFolderSortOrder(starredFolder, sortOrder: .createDate)
                                    } label: {
                                        Label(
                                            "创建日期",
                                            systemImage: viewModel.getFolderSortOrder(starredFolder) == .createDate ? "checkmark" : "circle"
                                        )
                                    }

                                    Button {
                                        viewModel.setFolderSortOrder(starredFolder, sortOrder: .title)
                                    } label: {
                                        Label("标题", systemImage: viewModel.getFolderSortOrder(starredFolder) == .title ? "checkmark" : "circle")
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
                                .scaleEffect(0.4) // 缩小图标大小
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
                                    Label(
                                        "编辑日期",
                                        systemImage: viewModel.getFolderSortOrder(viewModel.uncategorizedFolder) == .editDate ? "checkmark" : "circle"
                                    )
                                }

                                Button {
                                    viewModel.setFolderSortOrder(viewModel.uncategorizedFolder, sortOrder: .createDate)
                                } label: {
                                    Label(
                                        "创建日期",
                                        systemImage: viewModel.getFolderSortOrder(viewModel.uncategorizedFolder) == .createDate ? "checkmark" : "circle"
                                    )
                                }

                                Button {
                                    viewModel.setFolderSortOrder(viewModel.uncategorizedFolder, sortOrder: .title)
                                } label: {
                                    Label(
                                        "标题",
                                        systemImage: viewModel.getFolderSortOrder(viewModel.uncategorizedFolder) == .title ? "checkmark" : "circle"
                                    )
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
                                            Label("编辑日期", systemImage: viewModel.getFolderSortOrder(folder) == .editDate ? "checkmark" : "circle")
                                        }

                                        Button {
                                            viewModel.setFolderSortOrder(folder, sortOrder: .createDate)
                                        } label: {
                                            Label("创建日期", systemImage: viewModel.getFolderSortOrder(folder) == .createDate ? "checkmark" : "circle")
                                        }

                                        Button {
                                            viewModel.setFolderSortOrder(folder, sortOrder: .title)
                                        } label: {
                                            Label("标题", systemImage: viewModel.getFolderSortOrder(folder) == .title ? "checkmark" : "circle")
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
            .onKeyPress(.return) {
                // 检查是否应该进入重命名模式
                if let selectedFolder = viewModel.selectedFolder,
                   !selectedFolder.isSystem,
                   selectedFolder.id != "uncategorized",
                   selectedFolder.id != "0",
                   selectedFolder.id != "starred",
                   selectedFolder.id != "2",
                   editingFolderId == nil,
                   !isCreatingNewFolder
                {
                    // 检查鼠标是否悬停在选中的文件夹上
                    // 这里需要检查鼠标位置，但由于 SwiftUI 的限制，我们暂时假设如果选中了文件夹就可以重命名
                    startRename(folder: selectedFolder)
                    return .handled
                }
                return .ignored
            }
            .onChange(of: viewModel.selectedFolder) { oldValue, newValue in
                // 当用户点击其他文件夹时，如果当前有文件夹正在编辑，触发名称检查
                if let editingFolderId,
                   let editingFolder = viewModel.folders.first(where: { $0.id == editingFolderId })
                {
                    // 延迟一小段时间，确保点击事件已经处理完成
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        // 标记这是通过点击其他文件夹退出的
                        saveRename(folder: editingFolder, isExitingByClickingOtherFolder: true)
                    }
                }

                // 确保切换文件夹时，编辑视图跟随更新
                // 使用 coordinator 进行状态管理，确保三个视图之间的状态同步
                // - 3.1: 选择新文件夹时立即显示该文件夹下的笔记列表
                // - 3.2: 选择新文件夹时清空编辑器或显示第一篇笔记
                // - 3.3: 选择新文件夹时清除之前的笔记选择状态
                if newValue != oldValue {
                    // 通过 coordinator 进行文件夹选择
                    // coordinator 会处理保存检查、状态更新和笔记选择清除
                    Task {
                        await viewModel.stateCoordinator.selectFolder(newValue)
                    }

                    // 调用原有的 selectFolder 方法处理私密笔记等特殊逻辑
                    viewModel.selectFolder(newValue)

                    // 延迟到当前渲染周期结束后再清除搜索状态，避免在视图更新中修改 @Published 属性
                    DispatchQueue.main.async {
                        viewModel.searchText = ""
                        viewModel.searchFilterHasTags = false
                        viewModel.searchFilterHasChecklist = false
                        viewModel.searchFilterHasImages = false
                        viewModel.searchFilterHasAudio = false
                        viewModel.searchFilterIsPrivate = false
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
                let newFolderId = try await viewModel.createFolder(name: folderName)
                LogService.shared.info(.window, "文件夹创建成功: \(newFolderId)")
                await selectAndRenameNewFolder(folderId: newFolderId, folderName: folderName)
            } catch {
                LogService.shared.error(.window, "创建文件夹失败: \(error.localizedDescription)")
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

                // 首先尝试使用返回的文件夹ID查找
                if let newFolder = nonSystemFolders.first(where: { $0.id == folderId }) {
                    viewModel.selectedFolder = newFolder
                    editingFolderId = newFolder.id
                    editingFolderName = newFolder.name
                    return
                } else {
                    // 如果通过ID找不到，尝试查找名称完全匹配的文件夹
                    let matchingFolders = nonSystemFolders.filter { $0.name == folderName }

                    if let newFolder = matchingFolders.first {
                        viewModel.selectedFolder = newFolder
                        editingFolderId = newFolder.id
                        editingFolderName = newFolder.name
                        return
                    } else {
                        // 如果还没有找到，尝试查找创建时间在创建操作之后的文件夹
                        let recentlyCreatedFolders = nonSystemFolders.filter { $0.createdAt > Date().addingTimeInterval(-10) }

                        if let newFolder = recentlyCreatedFolders.first {
                            viewModel.selectedFolder = newFolder
                            editingFolderId = newFolder.id
                            editingFolderName = newFolder.name
                            return
                        }
                    }
                }
            }
        }

        // 如果循环结束还没有找到，记录警告
        await MainActor.run {
            LogService.shared.warning(.window, "未找到新创建的文件夹 '\(folderName)' (ID: \(folderId))")
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
                LogService.shared.error(.window, "切换文件夹置顶状态失败: \(error.localizedDescription)")
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
               now.timeIntervalSince(lastTime) < 2.0
            { // 2秒内不重复显示
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
                LogService.shared.error(.window, "重命名文件夹失败: \(error.localizedDescription)")
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
/// - 笔记数量（可通过菜单切换显示/隐藏）
struct SidebarFolderRow: View {
    /// 文件夹数据
    let folder: Folder

    /// 名称前缀（可选，用于特殊显示）
    var prefix = ""

    /// 是否正在编辑
    var isEditing = false

    /// 编辑中的名称（绑定到父视图）
    @Binding var editingName: String

    /// 完成编辑的回调
    var onCommit: (() -> Void)?

    /// 取消编辑的回调
    var onCancel: (() -> Void)?

    /// 焦点状态
    @FocusState private var isFocused: Bool

    /// 鼠标是否悬停在该行上
    @State private var isHovering = false

    /// 视图选项管理器（用于获取笔记数量显示状态）
    @ObservedObject private var viewOptionsManager = ViewOptionsManager.shared

    /// 初始化器 - 用于正常模式（非编辑模式）
    init(folder: Folder, prefix: String = "") {
        self.folder = folder
        self.prefix = prefix
        self.isEditing = false
        _editingName = .constant("")
    }

    /// 初始化器 - 用于编辑模式
    init(folder: Folder, isEditing: Bool, editingName: Binding<String>, onCommit: (() -> Void)? = nil, onCancel: (() -> Void)? = nil) {
        self.folder = folder
        self.prefix = ""
        self.isEditing = isEditing
        _editingName = editingName
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    var body: some View {
        HStack {
            // 文件夹图标
            Image(systemName: folderIcon)
                .foregroundColor(folderColor)
                .font(.system(size: 16)) // 图标大小：16pt
                .frame(width: 24) // 图标容器宽度：24px

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
                .onChange(of: isEditing) { _, newValue in
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
                    if oldValue == true, newValue == false {
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

            // 笔记数量（编辑模式下不显示，根据设置可隐藏）
            if !isEditing, viewOptionsManager.showNoteCount {
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
        case "0": "tray.full"
        case "starred": "pin.fill"
        case "uncategorized": "folder.badge.questionmark"
        case "new": "folder.badge.plus"
        default: folder.isPinned ? "pin.fill" : "folder"
        }
    }

    /// 根据文件夹ID返回对应的图标颜色
    ///
    /// 使用系统颜色，让图标看起来更原生：
    /// - "0" (所有笔记): .blue
    /// - "starred" (置顶): .accentColor
    /// - "uncategorized" (未分类): .gray
    /// - "new" (新建): .green
    /// - 其他: .primary（如果置顶则使用 .accentColor）
    private var folderColor: Color {
        switch folder.id {
        case "0": .primary
        case "starred": .primary
        case "uncategorized": .primary
        case "new": .primary
        default: .primary
        }
    }
}
