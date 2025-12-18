import SwiftUI
import AppKit

public struct DebugSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var cookieString: String = ""
    @State private var serviceToken: String = ""
    @State private var showCopyAlert: Bool = false
    @State private var copyAlertMessage: String = ""
    @State private var showClearAlert: Bool = false
    @State private var showExportLogsAlert: Bool = false
    @State private var showNetworkTestAlert: Bool = false
    @State private var networkTestResult: String = ""
    @State private var showSaveAlert: Bool = false
    @State private var saveAlertMessage: String = ""
    @State private var isEditingCookie: Bool = false
    @State private var editedCookieString: String = ""
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("登录凭证") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Cookie")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            if isEditingCookie {
                                Button("取消") {
                                    isEditingCookie = false
                                    editedCookieString = cookieString
                                }
                                .buttonStyle(.borderless)
                            } else {
                                Button("编辑") {
                                    isEditingCookie = true
                                    editedCookieString = cookieString
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        
                        if isEditingCookie {
                            TextEditor(text: $editedCookieString)
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 120)
                                .border(Color.accentColor.opacity(0.5), width: 1)
                                .onChange(of: editedCookieString) { oldValue, newValue in
                                    // 实时解析 serviceToken
                                    parseServiceToken(from: newValue)
                                }
                            
                            Button("保存Cookie") {
                                saveCookie(editedCookieString)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(editedCookieString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        } else {
                            TextEditor(text: $cookieString)
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 120)
                                .border(Color.gray.opacity(0.3), width: 1)
                                .disabled(true)
                        }
                        
                        HStack {
                            Button("复制Cookie") {
                                copyToClipboard(isEditingCookie ? editedCookieString : cookieString)
                                copyAlertMessage = "Cookie已复制到剪贴板"
                                showCopyAlert = true
                            }
                            
                            Button("清除Cookie", role: .destructive) {
                                showClearAlert = true
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Service Token")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("", text: $serviceToken)
                            .font(.system(.body, design: .monospaced))
                            .disabled(true)
                        
                        Button("复制Service Token") {
                            copyToClipboard(serviceToken)
                            copyAlertMessage = "Service Token已复制到剪贴板"
                            showCopyAlert = true
                        }
                    }
                    
                    HStack {
                        Text("认证状态")
                        Spacer()
                        if MiNoteService.shared.isAuthenticated() {
                            Text("已认证")
                                .foregroundColor(.green)
                        } else {
                            Text("未认证")
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Section("调试工具") {
                    Button("测试网络连接") {
                        testNetworkConnection()
                    }
                    
                    Button("导出调试日志") {
                        exportDebugLogs()
                    }
                    
                    Button("清除所有本地数据") {
                        clearAllLocalData()
                    }
                    
                    Button("重置应用程序") {
                        resetApplication()
                    }
                }
                
                Section("API信息") {
                    HStack {
                        Text("Base URL")
                        Spacer()
                        Text("https://i.mi.com")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("User Agent")
                        Spacer()
                        Text("Chrome/120.0.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Cookie长度")
                        Spacer()
                        Text("\(cookieString.count) 字符")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Service Token长度")
                        Spacer()
                        Text("\(serviceToken.count) 字符")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("系统信息") {
                    HStack {
                        Text("应用程序版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("macOS版本")
                        Spacer()
                        Text("\(ProcessInfo.processInfo.operatingSystemVersionString)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("设备型号")
                        Spacer()
                        Text(getDeviceModel())
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("内存使用")
                        Spacer()
                        Text(getMemoryUsage())
                            .foregroundColor(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("调试设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("刷新") {
                        loadCredentials()
                    }
                }
            }
            .alert("复制成功", isPresented: $showCopyAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(copyAlertMessage)
            }
            .alert("清除Cookie", isPresented: $showClearAlert) {
                Button("清除", role: .destructive) {
                    clearCookie()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("确定要清除Cookie吗？清除后需要重新登录。")
            }
            .alert("网络测试结果", isPresented: $showNetworkTestAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(networkTestResult)
            }
            .alert("导出日志", isPresented: $showExportLogsAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text("调试日志已导出到桌面")
            }
            .alert("保存Cookie", isPresented: $showSaveAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(saveAlertMessage)
            }
            .onAppear {
                loadCredentials()
                editedCookieString = cookieString
            }
        }
        .frame(width: 600, height: 700)
    }
    
    private func loadCredentials() {
        // 从UserDefaults加载cookie
        if let savedCookie = UserDefaults.standard.string(forKey: "minote_cookie"), !savedCookie.isEmpty {
            cookieString = savedCookie
        } else {
            cookieString = "未找到Cookie"
        }
        
        // 从cookie中提取service token
        parseServiceToken(from: cookieString)
    }
    
    private func parseServiceToken(from cookieString: String) {
        let pattern = "serviceToken=([^;]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            serviceToken = "无法解析"
            return
        }
        
        let range = NSRange(location: 0, length: cookieString.utf16.count)
        if let match = regex.firstMatch(in: cookieString, options: [], range: range),
           let tokenRange = Range(match.range(at: 1), in: cookieString) {
            serviceToken = String(cookieString[tokenRange])
        } else {
            serviceToken = "未找到Service Token"
        }
    }
    
    private func saveCookie(_ newCookie: String) {
        let trimmedCookie = newCookie.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 验证 cookie 格式
        if trimmedCookie.isEmpty {
            saveAlertMessage = "Cookie 不能为空"
            showSaveAlert = true
            return
        }
        
        // 检查是否包含必要的字段
        let hasServiceToken = trimmedCookie.contains("serviceToken=")
        let hasUserId = trimmedCookie.contains("userId=")
        
        if !hasServiceToken {
            saveAlertMessage = "警告：Cookie 中未找到 serviceToken，可能无法正常使用"
            showSaveAlert = true
        } else if !hasUserId {
            saveAlertMessage = "警告：Cookie 中未找到 userId，可能无法正常使用"
            showSaveAlert = true
        }
        
        // 保存 cookie
        UserDefaults.standard.set(trimmedCookie, forKey: "minote_cookie")
        MiNoteService.shared.setCookie(trimmedCookie)
        
        // 更新显示
        cookieString = trimmedCookie
        isEditingCookie = false
        
        // 重新解析 serviceToken
        parseServiceToken(from: trimmedCookie)
        
        // 显示成功消息
        if hasServiceToken && hasUserId {
            saveAlertMessage = "Cookie 已保存并解析 Service Token 成功！"
        } else {
            saveAlertMessage = "Cookie 已保存，但可能缺少必要的字段"
        }
        showSaveAlert = true
    }
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    private func clearCookie() {
        UserDefaults.standard.removeObject(forKey: "minote_cookie")
        MiNoteService.shared.setCookie("")
        loadCredentials()
    }
    
    private func testNetworkConnection() {
        Task {
            do {
                let response = try await MiNoteService.shared.fetchPage()
                let notesCount = MiNoteService.shared.parseNotes(from: response).count
                let foldersCount = MiNoteService.shared.parseFolders(from: response).count
                
                networkTestResult = "网络连接成功！\n获取到 \(notesCount) 条笔记，\(foldersCount) 个文件夹"
                showNetworkTestAlert = true
            } catch {
                networkTestResult = "网络连接失败：\(error.localizedDescription)"
                showNetworkTestAlert = true
            }
        }
    }
    
    private func exportDebugLogs() {
        let logs = """
        小米笔记调试日志
        生成时间：\(Date())
        
        === 认证信息 ===
        Cookie: \(cookieString)
        Service Token: \(serviceToken)
        认证状态：\(MiNoteService.shared.isAuthenticated() ? "已认证" : "未认证")
        
        === 系统信息 ===
        应用程序版本：1.0.0
        macOS版本：\(ProcessInfo.processInfo.operatingSystemVersionString)
        设备型号：\(getDeviceModel())
        内存使用：\(getMemoryUsage())
        
        === 用户设置 ===
        同步间隔：\(UserDefaults.standard.double(forKey: "syncInterval")) 秒
        自动保存：\(UserDefaults.standard.bool(forKey: "autoSave"))
        离线模式：\(UserDefaults.standard.bool(forKey: "offlineMode"))
        主题：\(UserDefaults.standard.string(forKey: "theme") ?? "system")
        """
        
        let savePanel = NSSavePanel()
        savePanel.title = "导出调试日志"
        savePanel.nameFieldStringValue = "minote_debug_log_\(Date().timeIntervalSince1970).txt"
        savePanel.allowedContentTypes = [.plainText]
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try logs.write(to: url, atomically: true, encoding: .utf8)
                showExportLogsAlert = true
            } catch {
                print("导出日志失败: \(error)")
            }
        }
    }
    
    private func clearAllLocalData() {
        // 清除所有UserDefaults数据
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
        
        // 重新加载凭证
        loadCredentials()
    }
    
    private func resetApplication() {
        // 清除所有数据
        clearAllLocalData()
        
        // 退出应用程序
        NSApplication.shared.terminate(nil)
    }
    
    private func getDeviceModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
    
    private func getMemoryUsage() -> String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / 1024 / 1024
            return String(format: "%.1f MB", usedMB)
        } else {
            return "未知"
        }
    }
}

#Preview {
    DebugSettingsView()
}
