import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var viewModel: NotesViewModel
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showingNewNote = false
    @State private var showingSettings = false
    @State private var showingLogin = false
    @State private var showingSyncMenu = false
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // 侧边栏 - 文件夹列表
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } content: {
            // 中间栏 - 笔记列表
            NotesListView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
                .toolbar {
                    // 左侧：文件夹名称 + 笔记数目（不需要圆圈包裹）
                    ToolbarItem(placement: .navigation) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(viewModel.selectedFolder?.name ?? "所有备忘录")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                
                                Text("\(viewModel.filteredNotes.count) 个备忘录")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            // 在线/离线状态指示器
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(viewModel.isOnline ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)
                                Text(viewModel.isOnline ? "在线" : "离线")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .help(viewModel.isOnline ? "已连接到小米笔记服务器" : "离线模式：更改将在网络恢复后同步")
                        }
                    }
                }
        } detail: {
            // 详情栏 - 笔记编辑器（带预览功能）
            NoteDetailView(viewModel: viewModel)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 800, minHeight: 600)
        .sheet(isPresented: $showingNewNote) {
            NewNoteView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingLogin) {
            LoginView(viewModel: viewModel)
        }
        .onAppear {
            // 检查是否需要登录
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
        .onChange(of: viewModel.showLoginView) { oldValue, newValue in
            if newValue {
                showingLogin = true
                viewModel.showLoginView = false
            }
        }
        // 同步状态覆盖层
        .overlay(alignment: .bottom) {
            if viewModel.isSyncing {
                SyncStatusOverlay(viewModel: viewModel)
            }
        }
    }
    
    private func toggleSidebar() {
        withAnimation {
            if columnVisibility == .all {
                columnVisibility = .detailOnly
            } else {
                columnVisibility = .all
            }
        }
    }
}

struct SidebarView: View {
    @ObservedObject var viewModel: NotesViewModel
    @State private var showingSyncMenu = false
    
    var body: some View {
        List(selection: $viewModel.selectedFolder) {
            Section("小米笔记") {
                ForEach(viewModel.folders.filter { $0.isSystem }) { folder in
                    SidebarFolderRow(folder: folder)
                        .tag(folder)
                }
            }
            
            Section("我的文件夹") {
                // 添加"未分类"文件夹
                SidebarFolderRow(folder: viewModel.uncategorizedFolder)
                    .tag(viewModel.uncategorizedFolder)
                
                ForEach(viewModel.folders.filter { !$0.isSystem }) { folder in
                    SidebarFolderRow(folder: folder)
                        .tag(folder)
                        .contextMenu {
                            Button {
                                renameFolder(folder)
                            } label: {
                                Label("重命名文件夹", systemImage: "pencil.circle")
                            }
                            Button(role: .destructive) {
                                deleteFolder(folder)
                            } label: {
                                Label("删除文件夹", systemImage: "trash")
                            }
                        }
                }
            }
            .contextMenu {
                Button {
                    createNewFolder()
                } label: {
                    Label("新建文件夹", systemImage: "folder.badge.plus")
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(action: createNewFolder) {
                        Label("新建文件夹", systemImage: "folder.badge.plus")
                    }
                    
                    Divider()
                    
                    Button(action: performFullSync) {
                        Label("完整同步", systemImage: "arrow.down.circle")
                    }
                    .disabled(viewModel.isSyncing || !viewModel.isLoggedIn)
                    
                    Button(action: performIncrementalSync) {
                        Label("增量同步", systemImage: "arrow.down.circle.dotted")
                    }
                    .disabled(viewModel.isSyncing || !viewModel.isLoggedIn)
                    
                    Divider()
                    
                    Button(action: resetSyncStatus) {
                        Label("重置同步状态", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(viewModel.isSyncing)
                    
                    Divider()
                    
                    Button(action: showSyncStatus) {
                        Label("同步状态", systemImage: "info.circle")
                    }
                } label: {
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
    
    private func performFullSync() {
        Task {
            await viewModel.performFullSync()
        }
    }
    
    private func performIncrementalSync() {
        Task {
            await viewModel.performIncrementalSync()
        }
    }
    
    private func resetSyncStatus() {
        viewModel.resetSyncStatus()
    }
    
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

struct SidebarFolderRow: View {
    let folder: Folder
    
    var body: some View {
        HStack {
            Image(systemName: folderIcon)
                .foregroundColor(folderColor)
                .frame(width: 20)
            
            Text(folder.name)
                .lineLimit(1)
            
            Spacer()
            
            Text("\(folder.count)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var folderIcon: String {
        switch folder.id {
        case "0": return "tray.full"
        case "starred": return "star"
        case "uncategorized": return "folder.badge.questionmark"
        default: return "folder"
        }
    }
    
    private var folderColor: Color {
        switch folder.id {
        case "0": return .blue
        case "starred": return .yellow
        case "uncategorized": return .gray
        default: return .orange
        }
    }
}

// MARK: - 同步状态覆盖层

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

#Preview {
    ContentView(viewModel: NotesViewModel())
}
