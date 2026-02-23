import SwiftUI

public struct SettingsView: View {
    @ObservedObject var syncState: SyncState
    @ObservedObject var authState: AuthState
    let noteStore: NoteStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage("syncInterval") private var syncInterval: Double = 300
    @AppStorage("autoSave") private var autoSave = true
    @AppStorage("offlineMode") private var offlineMode = false
    @AppStorage("theme") private var theme = "system"
    @AppStorage("autoRefreshCookie") private var autoRefreshCookie = false
    @AppStorage("autoRefreshInterval") private var autoRefreshInterval: Double = 86400
    @AppStorage("silentRefreshOnFailure") private var silentRefreshOnFailure = true

    @AppStorage("editorFontSize") private var editorFontSize = 14.0
    @AppStorage("editorLineHeight") private var editorLineHeight = 1.5

    @State private var showLogoutAlert = false
    @State private var showClearCacheAlert = false

    init(syncState: SyncState, authState: AuthState, noteStore: NoteStore) {
        self.syncState = syncState
        self.authState = authState
        self.noteStore = noteStore
    }

    public var body: some View {
        NavigationStack {
            Form {
                syncSection
                editorSection
                debugSection
                appearanceSection
                privateNotesSection
                accountSection
                dataManagementSection
            }
            .formStyle(.grouped)
            .navigationTitle("设置")
            .toolbarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
            .toolbarBackgroundVisibility(.automatic, for: .windowToolbar)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Color.clear.frame(width: 0, height: 0)
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
        }
        .background(.ultraThickMaterial)
        .frame(minWidth: 550, idealWidth: 650, minHeight: 500, idealHeight: 600)
    }

    // MARK: - 各 Section

    private var syncSection: some View {
        Section("同步设置") {
            Toggle("自动保存", isOn: $autoSave)

            Picker("同步间隔", selection: $syncInterval) {
                Text("10秒").tag(10.0)
                Text("30秒").tag(30.0)
                Text("1分钟").tag(60.0)
                Text("5分钟").tag(300.0)
                Text("15分钟").tag(900.0)
                Text("30分钟").tag(1800.0)
                Text("1小时").tag(3600.0)
            }
            .onChange(of: syncInterval) { newValue in
                syncState.updateSyncInterval(newValue)
            }

            Toggle("离线模式", isOn: $offlineMode)
                .help("离线模式下仅使用本地缓存，不进行网络同步")

            Toggle("自动刷新Cookie", isOn: $autoRefreshCookie)
                .help("启用后，系统会自动定期刷新Cookie，避免Cookie过期导致同步失败")

            if autoRefreshCookie {
                Picker("刷新频率", selection: $autoRefreshInterval) {
                    Text("每天").tag(86400.0)
                    Text("每周").tag(604_800.0)
                    Text("每月").tag(2_592_000.0)
                }
                .help("自动刷新Cookie的时间间隔")
            }

            Toggle("Cookie失效时静默刷新", isOn: $silentRefreshOnFailure)
                .help("启用后，当Cookie失效时会自动尝试静默刷新，刷新失败才会弹窗提示")
        }
    }

    private var editorSection: some View {
        Section("编辑器") {
            NavigationLink("编辑器设置") {
                EditorSettingsView()
            }
            .help("配置原生编辑器")
        }
    }

    private var debugSection: some View {
        Section("调试") {
            NavigationLink("操作队列调试") {
                OperationQueueDebugView(noteStore: noteStore)
            }
            .help("查看和管理待上传注册表、离线操作队列等")

            NavigationLink("XML 往返一致性检测") {
                XMLRoundtripDebugView()
            }
            .help("检测所有笔记的 XML 转换往返一致性")

            NavigationLink("调试设置") {
                DebugSettingsView()
            }
            .help("Cookie 管理、API 测试等调试功能")
        }
    }

    private var appearanceSection: some View {
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

                VStack(alignment: .leading, spacing: 8) {
                    Slider(value: $editorFontSize, in: 12 ... 24, step: 1) {
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
                    .onChange(of: editorFontSize) { _ in
                        applyEditorSettings()
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Slider(value: $editorLineHeight, in: 1.0 ... 2.5, step: 0.1) {
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
                    .onChange(of: editorLineHeight) { _ in
                        applyEditorSettings()
                    }
                }

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
    }

    private var privateNotesSection: some View {
        Section("私密笔记") {
            PrivateNotesPasswordSettingsView()
        }
    }

    private var accountSection: some View {
        Section("账户") {
            if let profile = authState.userProfile {
                HStack {
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
                    if authState.isLoggedIn {
                        Text("已登录")
                            .foregroundColor(.green)
                    } else {
                        Text("未登录")
                            .foregroundColor(.red)
                    }
                }
            }

            Button("重新登录") {
                Task { await EventBus.shared.publish(SettingsEvent.showLoginRequested) }
                dismiss()
            }

            Button("退出登录", role: .destructive) {
                showLogoutAlert = true
            }
        }
    }

    private var dataManagementSection: some View {
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
    }

    // MARK: - 操作方法

    private func saveSettings() {
        UserDefaults.standard.set(syncInterval, forKey: "syncInterval")
        UserDefaults.standard.set(autoSave, forKey: "autoSave")
        UserDefaults.standard.set(offlineMode, forKey: "offlineMode")
        UserDefaults.standard.set(theme, forKey: "theme")
        UserDefaults.standard.set(autoRefreshCookie, forKey: "autoRefreshCookie")
        UserDefaults.standard.set(autoRefreshInterval, forKey: "autoRefreshInterval")
        UserDefaults.standard.set(silentRefreshOnFailure, forKey: "silentRefreshOnFailure")
        UserDefaults.standard.set(editorFontSize, forKey: "editorFontSize")
        UserDefaults.standard.set(editorLineHeight, forKey: "editorLineHeight")

        syncState.updateSyncInterval(syncInterval)

        if autoRefreshCookie {
            authState.startAutoRefreshCookieIfNeeded()
        } else {
            authState.stopAutoRefreshCookie()
        }

        applyEditorSettings()
    }

    private func applyEditorSettings() {
        Task { await EventBus.shared.publish(SettingsEvent.editorSettingsChanged) }
        LogService.shared.debug(.app, "编辑器设置已更新: 字体大小=\(editorFontSize)px, 行间距=\(editorLineHeight)")
    }

    private func logout() {
        APIClient.shared.clearCookie()
        authState.handleLogout()
        dismiss()
    }

    private func clearCache() {
        UserDefaults.standard.removeObject(forKey: "cachedNotes")
        UserDefaults.standard.removeObject(forKey: "cachedFolders")

        if authState.isLoggedIn {
            syncState.requestFullSync(mode: .normal)
        }
    }

    private func exportNotes() {
        Task {
            let notes = await noteStore.notes
            let notesData = notes.map { NoteMapper.toUploadPayload($0) }

            do {
                let jsonData = try JSONSerialization.data(withJSONObject: notesData, options: .prettyPrinted)

                let savePanel = NSSavePanel()
                savePanel.title = "导出笔记"
                savePanel.nameFieldStringValue = "小米笔记备份.json"
                savePanel.allowedContentTypes = [.json]

                if savePanel.runModal() == .OK, let url = savePanel.url {
                    try jsonData.write(to: url)

                    let alert = NSAlert()
                    alert.messageText = "导出成功"
                    alert.informativeText = "笔记已成功导出到 \(url.lastPathComponent)"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "确定")
                    alert.runModal()
                }
            } catch {
                LogService.shared.error(.app, "导出笔记失败: \(error)")
            }
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

                let importedNotes = notesArray.compactMap { NoteMapper.fromMinoteListData($0) }
                // TODO: 导入功能需要通过 NoteStore 或 EventBus 处理，后续任务实现
                LogService.shared.info(.app, "导入了 \(importedNotes.count) 条笔记，待后续处理")

                let alert = NSAlert()
                alert.messageText = "导入成功"
                alert.informativeText = "成功导入 \(importedNotes.count) 条笔记"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "确定")
                alert.runModal()
            } catch {
                LogService.shared.error(.app, "导入笔记失败: \(error)")
            }
        }
    }
}

/// 私密笔记密码设置视图
struct PrivateNotesPasswordSettingsView: View {
    @State private var showSetPasswordDialog = false
    @State private var showChangePasswordDialog = false
    @State private var showDeletePasswordAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showSuccessAlert = false
    @State private var successMessage = ""
    @State private var touchIDEnabled = false

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

/// 设置密码对话框
struct SetPasswordDialogView: View {
    @Binding var isPresented: Bool
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showError = false
    @State private var errorMessage = ""

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

/// 修改密码对话框
struct ChangePasswordDialogView: View {
    @Binding var isPresented: Bool
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showError = false
    @State private var errorMessage = ""

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

#Preview {
    SettingsView(syncState: SyncState(), authState: AuthState(), noteStore: NoteStore(db: .shared, eventBus: .shared))
}
