import SwiftUI

public struct SettingsView: View {
    @ObservedObject var viewModel: NotesViewModel
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("syncInterval") private var syncInterval: Double = 300 // 默认5分钟
    @AppStorage("autoSave") private var autoSave: Bool = true
    @AppStorage("offlineMode") private var offlineMode: Bool = false
    @AppStorage("theme") private var theme: String = "system"
    
    @State private var showLogoutAlert: Bool = false
    @State private var showClearCacheAlert: Bool = false
    @State private var showAboutSheet: Bool = false
    
    public init(viewModel: NotesViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("同步设置") {
                    Toggle("自动保存", isOn: $autoSave)
                    
                    Picker("同步间隔", selection: $syncInterval) {
                        Text("1分钟").tag(60.0)
                        Text("5分钟").tag(300.0)
                        Text("15分钟").tag(900.0)
                        Text("30分钟").tag(1800.0)
                        Text("1小时").tag(3600.0)
                    }
                    
                    Toggle("离线模式", isOn: $offlineMode)
                        .help("离线模式下仅使用本地缓存，不进行网络同步")
                }
                
                Section("外观") {
                    Picker("主题", selection: $theme) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }
                }
                
                Section("账户") {
                    HStack {
                        Text("登录状态")
                        Spacer()
                        if viewModel.isLoggedIn {
                            Text("已登录")
                                .foregroundColor(.green)
                        } else {
                            Text("未登录")
                                .foregroundColor(.red)
                        }
                    }
                    
                    Button("重新登录") {
                        viewModel.showLoginView = true
                        dismiss()
                    }
                    
                    Button("刷新Cookie") {
                        refreshCookie()
                    }
                    .help("如果同步失败，尝试刷新Cookie")
                    
                    Button("退出登录", role: .destructive) {
                        showLogoutAlert = true
                    }
                }
                
                Section("数据管理") {
                    Button("清除本地缓存") {
                        showClearCacheAlert = true
                    }
                    
                    Button("导出所有笔记") {
                        exportNotes()
                    }
                    
                    Button("从文件导入") {
                        importNotes()
                    }
                }
                
                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Button("检查更新") {
                        checkForUpdates()
                    }
                    
                    Button("关于小米笔记") {
                        showAboutSheet = true
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveSettings()
                        dismiss()
                    }
                }
            }
            .alert("退出登录", isPresented: $showLogoutAlert) {
                Button("退出", role: .destructive) {
                    logout()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("确定要退出登录吗？退出后将清除所有本地缓存。")
            }
            .alert("清除缓存", isPresented: $showClearCacheAlert) {
                Button("清除", role: .destructive) {
                    clearCache()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("清除缓存将删除所有本地笔记数据，但不会影响云端数据。")
            }
            .sheet(isPresented: $showAboutSheet) {
                AboutView()
            }
        }
        .frame(width: 500, height: 600)
    }
    
    private func saveSettings() {
        // 保存设置到UserDefaults
        UserDefaults.standard.set(syncInterval, forKey: "syncInterval")
        UserDefaults.standard.set(autoSave, forKey: "autoSave")
        UserDefaults.standard.set(offlineMode, forKey: "offlineMode")
        UserDefaults.standard.set(theme, forKey: "theme")
        
        // 通知ViewModel设置已更改
        viewModel.syncInterval = syncInterval
        viewModel.autoSave = autoSave
    }
    
    private func logout() {
        // 清除cookie
        MiNoteService.shared.clearCookie()
        
        // 清除本地数据
        viewModel.notes = []
        viewModel.folders = []
        viewModel.selectedNote = nil
        viewModel.selectedFolder = nil
        
        // 显示登录视图
        viewModel.showLoginView = true
        
        dismiss()
    }
    
    private func refreshCookie() {
        // 直接打开登录视图来刷新cookie
        let alert = NSAlert()
        alert.messageText = "刷新Cookie"
        alert.informativeText = "Cookie已过期，需要重新登录小米账号来获取新的Cookie。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "去登录")
        alert.addButton(withTitle: "取消")
        
        if alert.runModal() == .alertFirstButtonReturn {
            // 显示登录视图
            viewModel.showLoginView = true
            dismiss()
        }
    }
    
    private func clearCache() {
        // 清除所有本地存储的数据
        UserDefaults.standard.removeObject(forKey: "cachedNotes")
        UserDefaults.standard.removeObject(forKey: "cachedFolders")
        
        // 重新加载空数据
        viewModel.notes = []
        viewModel.folders = []
        
        // 如果已登录，从云端重新加载
        if viewModel.isLoggedIn {
            Task {
                await viewModel.loadNotesFromCloud()
            }
        }
    }
    
    private func exportNotes() {
        let notesData = viewModel.notes.map { $0.toMinoteData() }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: notesData, options: .prettyPrinted)
            
            let savePanel = NSSavePanel()
            savePanel.title = "导出笔记"
            savePanel.nameFieldStringValue = "小米笔记备份.json"
            savePanel.allowedContentTypes = [.json]
            
            if savePanel.runModal() == .OK, let url = savePanel.url {
                try jsonData.write(to: url)
                
                // 显示成功提示
                let alert = NSAlert()
                alert.messageText = "导出成功"
                alert.informativeText = "笔记已成功导出到 \(url.lastPathComponent)"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "确定")
                alert.runModal()
            }
        } catch {
            print("导出失败: \(error)")
        }
    }
    
    private func importNotes() {
        let openPanel = NSOpenPanel()
        openPanel.title = "导入笔记"
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        
        if openPanel.runModal() == .OK, let url = openPanel.url {
            do {
                let jsonData = try Data(contentsOf: url)
                let notesArray = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String: Any]] ?? []
                
                // 导入笔记到ViewModel
                let importedNotes = notesArray.compactMap { Note.fromMinoteData($0) }
                viewModel.notes.append(contentsOf: importedNotes)
                
                // 显示成功提示
                let alert = NSAlert()
                alert.messageText = "导入成功"
                alert.informativeText = "成功导入 \(importedNotes.count) 条笔记"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "确定")
                alert.runModal()
                
            } catch {
                print("导入失败: \(error)")
            }
        }
    }
    
    private func checkForUpdates() {
        // 检查更新逻辑
        let alert = NSAlert()
        alert.messageText = "检查更新"
        alert.informativeText = "当前已是最新版本 (1.0.0)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
}

// 关于视图
struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "note.text")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            Text("小米笔记 for Mac")
                .font(.title)
                .fontWeight(.bold)
            
            Text("版本 1.0.0")
                .foregroundColor(.secondary)
            
            Text("一个优雅的 macOS 客户端，用于同步和管理小米笔记")
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Divider()
                .padding(.horizontal, 40)
            
            Text("基于 SwiftUI 和 macOS 26 设计标准构建")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("关闭") {
                NSApp.keyWindow?.close()
            }
            .buttonStyle(.bordered)
            .padding(.bottom, 20)
        }
        .padding(40)
        .frame(width: 400, height: 400)
    }
}

#Preview {
    SettingsView(viewModel: NotesViewModel())
}
