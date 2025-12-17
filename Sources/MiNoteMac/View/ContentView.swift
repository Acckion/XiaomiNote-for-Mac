import SwiftUI

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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.selectedFolder?.name ?? "所有备忘录")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("\(viewModel.filteredNotes.count) 个备忘录")
                                .font(.caption)
                                .foregroundColor(.secondary)
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
            Section("iCloud") {
                ForEach(viewModel.folders.filter { $0.isSystem }) { folder in
                    SidebarFolderRow(folder: folder)
                        .tag(folder)
                }
            }
            
            Section("我的文件夹") {
                ForEach(viewModel.folders.filter { !$0.isSystem }) { folder in
                    SidebarFolderRow(folder: folder)
                        .tag(folder)
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
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
        default: return "folder"
        }
    }
    
    private var folderColor: Color {
        switch folder.id {
        case "0": return .blue
        case "starred": return .yellow
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
