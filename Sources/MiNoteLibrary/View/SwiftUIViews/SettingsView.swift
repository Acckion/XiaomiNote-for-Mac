import SwiftUI

public struct SettingsView: View {
    @ObservedObject var viewModel: NotesViewModel
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("syncInterval") private var syncInterval: Double = 300 // 默认5分钟
    @AppStorage("autoSave") private var autoSave: Bool = true
    @AppStorage("offlineMode") private var offlineMode: Bool = false
    @AppStorage("theme") private var theme: String = "system"
    @AppStorage("autoRefreshCookie") private var autoRefreshCookie: Bool = false
    @AppStorage("autoRefreshInterval") private var autoRefreshInterval: Double = 86400 // 默认每天（24小时）
    @AppStorage("silentRefreshOnFailure") private var silentRefreshOnFailure: Bool = true // 默认启用静默刷新
    
    // 编辑器显示设置
    @AppStorage("editorFontSize") private var editorFontSize: Double = 14.0 // 默认字体大小 14px
    @AppStorage("editorLineHeight") private var editorLineHeight: Double = 1.5 // 默认行间距 1.5
    
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
                    
                    Toggle("自动刷新Cookie", isOn: $autoRefreshCookie)
                        .help("启用后，系统会自动定期刷新Cookie，避免Cookie过期导致同步失败")
                    
                    if autoRefreshCookie {
                        Picker("刷新频率", selection: $autoRefreshInterval) {
                            Text("每天").tag(86400.0)
                            Text("每周").tag(604800.0)
                            Text("每月").tag(2592000.0)
                        }
                        .help("自动刷新Cookie的时间间隔")
                    }
                    
                    Toggle("Cookie失效时静默刷新", isOn: $silentRefreshOnFailure)
                        .help("启用后，当Cookie失效时会自动尝试静默刷新，刷新失败才会弹窗提示")
                }
                
                Section("外观") {
                    Picker("主题", selection: $theme) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("编辑器显示")
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        // 字体大小设置
                        VStack(alignment: .leading, spacing: 8) {    
                            Slider(value: $editorFontSize, in: 12...24, step: 1) {
                                Text("字体大小")
                            } minimumValueLabel: {
                                Text("12")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } maximumValueLabel: {
                                Text("24")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .onChange(of: editorFontSize) { newValue in
                                // 立即应用字体大小更改
                                applyEditorSettings()
                            }
                        }
                        
                        // 行间距设置
                        VStack(alignment: .leading, spacing: 8) {
                            Slider(value: $editorLineHeight, in: 1.0...2.5, step: 0.1) {
                                Text("行间距")
                            } minimumValueLabel: {
                                Text("1.0")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } maximumValueLabel: {
                                Text("2.5")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .onChange(of: editorLineHeight) { newValue in
                                // 立即应用行间距更改
                                applyEditorSettings()
                            }
                        }
                        
                        // 预设按钮
                        HStack {                    
                            Spacer()
                            Button("重置为默认") {
                                editorFontSize = 14.0
                                editorLineHeight = 1.5
                                applyEditorSettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.vertical, 8)
                }
                
                Section("私密笔记") {
                    PrivateNotesPasswordSettingsView()
                }
                
                Section("账户") {
                    // 用户信息显示
                    if let profile = viewModel.userProfile {
                        HStack {
                            // 头像
                            AsyncImage(url: URL(string: profile.icon)) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Image(systemName: "person.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                            
                            // 用户名
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.nickname)
                                    .font(.headline)
                                Text("已登录")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    } else {
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
        UserDefaults.standard.set(autoRefreshCookie, forKey: "autoRefreshCookie")
        UserDefaults.standard.set(autoRefreshInterval, forKey: "autoRefreshInterval")
        UserDefaults.standard.set(silentRefreshOnFailure, forKey: "silentRefreshOnFailure")
        UserDefaults.standard.set(editorFontSize, forKey: "editorFontSize")
        UserDefaults.standard.set(editorLineHeight, forKey: "editorLineHeight")
        
        // 通知ViewModel设置已更改
        viewModel.syncInterval = syncInterval
        viewModel.autoSave = autoSave
        
        // 启动或停止自动刷新Cookie定时器
        if autoRefreshCookie {
            viewModel.startAutoRefreshCookieIfNeeded()
        } else {
            viewModel.stopAutoRefreshCookie()
        }
        
        // 应用编辑器设置
        applyEditorSettings()
    }
    
    /// 应用编辑器显示设置（字体大小和行间距）
    private func applyEditorSettings() {
        // 通知所有活动的 WebEditorView 更新显示设置
        NotificationCenter.default.post(
            name: NSNotification.Name("EditorSettingsChanged"),
            object: nil,
            userInfo: [
                "fontSize": editorFontSize,
                "lineHeight": editorLineHeight
            ]
        )
        
        print("[SettingsView] 编辑器设置已更新: 字体大小=\(editorFontSize)px, 行间距=\(editorLineHeight)")
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
        // 参考 Obsidian 插件：打开Cookie刷新视图
        // 显示Cookie刷新视图（而不是登录视图）
        viewModel.showCookieRefreshView = true
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

// 私密笔记密码设置视图
struct PrivateNotesPasswordSettingsView: View {
    @State private var showSetPasswordDialog: Bool = false
    @State private var showChangePasswordDialog: Bool = false
    @State private var showDeletePasswordAlert: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    @State private var showSuccessAlert: Bool = false
    @State private var successMessage: String = ""
    @State private var touchIDEnabled: Bool = false
    
    private let passwordManager = PrivateNotesPasswordManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if passwordManager.hasPassword() {
                HStack {
                    Text("密码状态")
                    Spacer()
                    Text("已设置")
                        .foregroundColor(.green)
                }
                
                Button("修改密码") {
                    showChangePasswordDialog = true
                }
                
                Button("删除密码", role: .destructive) {
                    showDeletePasswordAlert = true
                }
                
                Divider()
                
                // Touch ID 设置
                if passwordManager.isBiometricAvailable() {
                    Toggle("使用 \(passwordManager.getBiometricType() ?? "Touch ID")", isOn: $touchIDEnabled)
                        .onChange(of: touchIDEnabled) { newValue in
                            passwordManager.setTouchIDEnabled(newValue)
                        }
                        .help("启用后，访问私密笔记时可以使用 \(passwordManager.getBiometricType() ?? "Touch ID") 验证")
                } else {
                    HStack {
                        Text("\(passwordManager.getBiometricType() ?? "Touch ID") 不可用")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .help("设备不支持生物识别或未设置生物识别")
                }
            } else {
                HStack {
                    Text("密码状态")
                    Spacer()
                    Text("未设置")
                        .foregroundColor(.secondary)
                }
                
                Button("设置密码") {
                    showSetPasswordDialog = true
                }
            }
        }
        .onAppear {
            touchIDEnabled = passwordManager.isTouchIDEnabled()
        }
        .sheet(isPresented: $showSetPasswordDialog) {
            SetPasswordDialogView(
                isPresented: $showSetPasswordDialog,
                onSuccess: {
                    successMessage = "密码设置成功"
                    showSuccessAlert = true
                },
                onError: { error in
                    errorMessage = error
                    showErrorAlert = true
                }
            )
        }
        .sheet(isPresented: $showChangePasswordDialog) {
            ChangePasswordDialogView(
                isPresented: $showChangePasswordDialog,
                onSuccess: {
                    successMessage = "密码修改成功"
                    showSuccessAlert = true
                },
                onError: { error in
                    errorMessage = error
                    showErrorAlert = true
                }
            )
        }
        .alert("删除密码", isPresented: $showDeletePasswordAlert) {
            Button("删除", role: .destructive) {
                if passwordManager.deletePassword() {
                    successMessage = "密码已删除"
                    showSuccessAlert = true
                } else {
                    errorMessage = "删除密码失败"
                    showErrorAlert = true
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定要删除私密笔记密码吗？删除后访问私密笔记将不再需要密码。")
        }
        .alert("错误", isPresented: $showErrorAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("成功", isPresented: $showSuccessAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(successMessage)
        }
    }
}

// 设置密码对话框
struct SetPasswordDialogView: View {
    @Binding var isPresented: Bool
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    let onSuccess: () -> Void
    let onError: (String) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("设置私密笔记密码")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("密码")
                    .font(.caption)
                    .foregroundColor(.secondary)
                SecureField("请输入密码", text: $password)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("确认密码")
                    .font(.caption)
                    .foregroundColor(.secondary)
                SecureField("请再次输入密码", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
            }
            
            if showError {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            HStack {
                Button("取消") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("确定") {
                    if password.isEmpty {
                        errorMessage = "密码不能为空"
                        showError = true
                    } else if password != confirmPassword {
                        errorMessage = "两次输入的密码不一致"
                        showError = true
                    } else if password.count < 4 {
                        errorMessage = "密码长度至少为4位"
                        showError = true
                    } else {
                        do {
                            try PrivateNotesPasswordManager.shared.setPassword(password)
                            isPresented = false
                            onSuccess()
                        } catch {
                            onError(error.localizedDescription)
                            isPresented = false
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

// 修改密码对话框
struct ChangePasswordDialogView: View {
    @Binding var isPresented: Bool
    @State private var currentPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    let onSuccess: () -> Void
    let onError: (String) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("修改私密笔记密码")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("当前密码")
                    .font(.caption)
                    .foregroundColor(.secondary)
                SecureField("请输入当前密码", text: $currentPassword)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("新密码")
                    .font(.caption)
                    .foregroundColor(.secondary)
                SecureField("请输入新密码", text: $newPassword)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("确认新密码")
                    .font(.caption)
                    .foregroundColor(.secondary)
                SecureField("请再次输入新密码", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
            }
            
            if showError {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            HStack {
                Button("取消") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("确定") {
                    if !PrivateNotesPasswordManager.shared.verifyPassword(currentPassword) {
                        errorMessage = "当前密码不正确"
                        showError = true
                    } else if newPassword.isEmpty {
                        errorMessage = "新密码不能为空"
                        showError = true
                    } else if newPassword != confirmPassword {
                        errorMessage = "两次输入的新密码不一致"
                        showError = true
                    } else if newPassword.count < 4 {
                        errorMessage = "密码长度至少为4位"
                        showError = true
                    } else {
                        do {
                            try PrivateNotesPasswordManager.shared.setPassword(newPassword)
                            isPresented = false
                            onSuccess()
                        } catch {
                            onError(error.localizedDescription)
                            isPresented = false
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
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
