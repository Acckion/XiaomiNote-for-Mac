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
    @State private var showPrivateNotesTestAlert: Bool = false
    @State private var privateNotesTestResult: String = ""
    @State private var isTestingPrivateNotes: Bool = false
    @State private var showEncryptionInfoTestAlert: Bool = false
    @State private var encryptionInfoTestResult: String = ""
    @State private var isTestingEncryptionInfo: Bool = false
    @State private var showServiceStatusCheckAlert: Bool = false
    @State private var serviceStatusCheckResult: String = ""
    @State private var isTestingServiceStatus: Bool = false
    @State private var showSilentRefreshAlert: Bool = false
    @State private var silentRefreshResult: String = ""
    @State private var isTestingSilentRefresh: Bool = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                credentialsSection
                debugToolsSection
                apiInfoSection
                systemInfoSection
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
            .alert("私密笔记API测试结果", isPresented: $showPrivateNotesTestAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(privateNotesTestResult)
            }
            .alert("加密信息API测试结果", isPresented: $showEncryptionInfoTestAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(encryptionInfoTestResult)
            }
            .alert("服务状态检查API测试结果", isPresented: $showServiceStatusCheckAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(serviceStatusCheckResult)
            }
            .alert("静默刷新测试结果", isPresented: $showSilentRefreshAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(silentRefreshResult)
            }
            .onAppear {
                loadCredentials()
            }
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var credentialsSection: some View {
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
                                .border(Color.yellow.opacity(0.5), width: 1)
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
    }
    
    @ViewBuilder
    private var debugToolsSection: some View {
        Section("调试工具") {
            Button("测试网络连接") {
                testNetworkConnection()
            }
            
            Button("测试私密笔记API") {
                testPrivateNotesAPI()
            }
            .disabled(isTestingPrivateNotes)
            
            Button("测试加密信息API") {
                testEncryptionInfoAPI()
            }
            .disabled(isTestingEncryptionInfo)
            
            Button("测试服务状态检查API") {
                testServiceStatusCheckAPI()
            }
            .disabled(isTestingServiceStatus)
            
            Button("测试静默刷新Cookie") {
                testSilentCookieRefresh()
            }
            .disabled(isTestingSilentRefresh)
            
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
    }
    
    @ViewBuilder
    private var apiInfoSection: some View {
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
    }
    
    @ViewBuilder
    private var systemInfoSection: some View {
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
    
    private func testPrivateNotesAPI() {
        isTestingPrivateNotes = true
        Task {
            do {
                let response = try await MiNoteService.shared.fetchPrivateNotes(folderId: "2", limit: 200)
                
                // 解析响应
                var resultText = "✅ 私密笔记API测试成功！\n\n"
                
                // 检查响应结构
                if let code = response["code"] as? Int {
                    resultText += "响应代码: \(code)\n"
                }
                
                // 解析笔记列表
                var notesCount = 0
                if let data = response["data"] as? [String: Any] {
                    if let entries = data["entries"] as? [[String: Any]] {
                        notesCount = entries.count
                        resultText += "笔记数量: \(notesCount)\n\n"
                        
                        // 显示前5条笔记的标题
                        if !entries.isEmpty {
                            resultText += "笔记列表（前5条）：\n"
                            for (index, entry) in entries.prefix(5).enumerated() {
                                var title = "未命名笔记"
                                if let extraInfo = entry["extraInfo"] as? String,
                                   let extraData = extraInfo.data(using: .utf8),
                                   let extraJson = try? JSONSerialization.jsonObject(with: extraData) as? [String: Any],
                                   let entryTitle = extraJson["title"] as? String {
                                    title = entryTitle
                                } else if let entryTitle = entry["title"] as? String {
                                    title = entryTitle
                                }
                                resultText += "\(index + 1). \(title)\n"
                            }
                        }
                    } else {
                        resultText += "未找到笔记列表\n"
                    }
                } else {
                    resultText += "响应格式异常\n"
                }
                
                // 显示完整响应（JSON格式，用于调试）
                if let jsonData = try? JSONSerialization.data(withJSONObject: response, options: .prettyPrinted),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    resultText += "\n完整响应（前500字符）：\n"
                    resultText += String(jsonString.prefix(500))
                    if jsonString.count > 500 {
                        resultText += "\n... (已截断)"
                    }
                }
                
                privateNotesTestResult = resultText
                showPrivateNotesTestAlert = true
            } catch {
                privateNotesTestResult = "❌ 私密笔记API测试失败：\n\(error.localizedDescription)\n\n错误详情：\(error)"
                showPrivateNotesTestAlert = true
            }
            
            isTestingPrivateNotes = false
        }
    }
    
    private func testEncryptionInfoAPI() {
        isTestingEncryptionInfo = true
        Task {
            do {
                let response = try await MiNoteService.shared.getEncryptionInfo(hsid: 2, appId: "micloud")
                
                // 解析响应
                var resultText = "✅ 加密信息API测试成功！\n\n"
                
                // 解析各个字段
                if let zone = response["zone"] as? Int {
                    resultText += "区域标识 (zone): \(zone)\n"
                }
                
                if let e2eeStatus = response["e2eeStatus"] as? String {
                    resultText += "端到端加密状态 (e2eeStatus): \(e2eeStatus)\n"
                    if e2eeStatus == "close" {
                        resultText += "  → 当前未启用端到端加密，笔记数据未加密\n"
                    } else if e2eeStatus == "open" {
                        resultText += "  → 已启用端到端加密，需要解密才能读取\n"
                    }
                }
                
                if let serverSignZone = response["serverSignZone"] as? Int {
                    resultText += "服务器签名区域 (serverSignZone): \(serverSignZone)\n"
                }
                
                if let nonce = response["nonce"] as? String {
                    resultText += "随机数 (nonce): \(nonce.prefix(50))...\n"
                }
                
                // 解析应用密钥信息
                if let maxAppkey = response["maxAppkey"] as? [String: Any] {
                    resultText += "\n应用密钥信息:\n"
                    if let appKeyVersion = maxAppkey["appKeyVersion"] as? Int64 {
                        resultText += "  密钥版本: \(appKeyVersion)\n"
                    }
                    if let setEncryptAppKeys = maxAppkey["setEncryptAppKeys"] as? Bool {
                        resultText += "  已设置加密密钥: \(setEncryptAppKeys ? "是" : "否")\n"
                    }
                    if let encryptAppKeysSize = maxAppkey["encryptAppKeysSize"] as? Int {
                        resultText += "  加密密钥大小: \(encryptAppKeysSize)\n"
                    }
                    if let setAppKeyVersion = maxAppkey["setAppKeyVersion"] as? Bool {
                        resultText += "  已设置密钥版本: \(setAppKeyVersion ? "是" : "否")\n"
                    }
                }
                
                resultText += "\n📝 分析:\n"
                resultText += "此API用于检查端到端加密状态。\n"
                resultText += "在访问私密笔记或最近删除笔记时，系统会调用此API\n"
                resultText += "来确定是否需要解密数据。\n"
                resultText += "如果 e2eeStatus 为 'close'，说明数据未加密，可直接读取。\n"
                resultText += "如果 e2eeStatus 为 'open'，需要使用返回的加密信息解密数据。"
                
                await MainActor.run {
                    encryptionInfoTestResult = resultText
                    showEncryptionInfoTestAlert = true
                    isTestingEncryptionInfo = false
                }
            } catch {
                await MainActor.run {
                    encryptionInfoTestResult = "❌ 加密信息API测试失败：\(error.localizedDescription)"
                    showEncryptionInfoTestAlert = true
                    isTestingEncryptionInfo = false
                }
            }
        }
    }
    
    private func testServiceStatusCheckAPI() {
        isTestingServiceStatus = true
        Task {
            do {
                let response = try await MiNoteService.shared.checkServiceStatus()
                
                // 解析响应
                var resultText = "✅ 服务状态检查API测试成功！\n\n"
                
                // 解析各个字段
                if let result = response["result"] as? String {
                    resultText += "结果 (result): \(result)\n"
                }
                
                if let code = response["code"] as? Int {
                    resultText += "响应代码 (code): \(code)\n"
                }
                
                if let description = response["description"] as? String {
                    resultText += "描述 (description): \(description)\n"
                }
                
                if let reason = response["reason"] as? String, !reason.isEmpty {
                    resultText += "原因 (reason): \(reason)\n"
                }
                
                if let retriable = response["retriable"] as? Bool {
                    resultText += "可重试 (retriable): \(retriable ? "是" : "否")\n"
                }
                
                if let ts = response["ts"] as? Int64 {
                    let date = Date(timeIntervalSince1970: TimeInterval(ts) / 1000.0)
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                    resultText += "时间戳 (ts): \(formatter.string(from: date))\n"
                }
                
                resultText += "\n📝 分析:\n"
                resultText += "此API是一个通用的健康检查接口，用于：\n"
                resultText += "1. 验证服务器是否可访问\n"
                resultText += "2. 检查认证状态是否有效\n"
                resultText += "3. 验证网络连接是否正常\n"
                resultText += "4. 作为心跳检测使用\n\n"
                resultText += "通常在以下场景调用：\n"
                resultText += "- 登录后验证连接\n"
                resultText += "- 同步前检查服务可用性\n"
                resultText += "- 定期心跳检测\n"
                resultText += "- 在访问重要功能前验证服务状态"
                
                await MainActor.run {
                    serviceStatusCheckResult = resultText
                    showServiceStatusCheckAlert = true
                    isTestingServiceStatus = false
                }
            } catch {
                await MainActor.run {
                    serviceStatusCheckResult = "❌ 服务状态检查API测试失败：\(error.localizedDescription)"
                    showServiceStatusCheckAlert = true
                    isTestingServiceStatus = false
                }
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
    
    /// 测试静默刷新Cookie功能
    private func testSilentCookieRefresh() {
        isTestingSilentRefresh = true
        
        Task {
            var resultText = "🔧 静默刷新Cookie测试开始...\n\n"
            
            // 检查当前认证状态
            let isAuthenticatedBefore = MiNoteService.shared.isAuthenticated()
            resultText += "测试前认证状态: \(isAuthenticatedBefore ? "已认证" : "未认证")\n"
            
            // 获取当前Cookie
            let currentCookie = UserDefaults.standard.string(forKey: "minote_cookie") ?? ""
            resultText += "当前Cookie长度: \(currentCookie.count) 字符\n"
            
            if currentCookie.isEmpty {
                resultText += "\n⚠️ 警告：当前没有Cookie，无法测试静默刷新\n"
                resultText += "请先登录或手动设置Cookie"
                
                await MainActor.run {
                    silentRefreshResult = resultText
                    showSilentRefreshAlert = true
                    isTestingSilentRefresh = false
                }
                return
            }
            
            // 模拟Cookie失效（清除Cookie）
            resultText += "\n📝 模拟Cookie失效...\n"
            UserDefaults.standard.removeObject(forKey: "minote_cookie")
            MiNoteService.shared.setCookie("")
            
            // 验证Cookie已清除
            let isAuthenticatedAfterClear = MiNoteService.shared.isAuthenticated()
            resultText += "清除Cookie后认证状态: \(isAuthenticatedAfterClear ? "已认证" : "未认证")\n"
            
            if isAuthenticatedAfterClear {
                resultText += "❌ 错误：Cookie清除失败，无法继续测试\n"
                
                // 恢复原始Cookie
                UserDefaults.standard.set(currentCookie, forKey: "minote_cookie")
                MiNoteService.shared.setCookie(currentCookie)
                
                await MainActor.run {
                    silentRefreshResult = resultText
                    showSilentRefreshAlert = true
                    isTestingSilentRefresh = false
                }
                return
            }
            
            resultText += "✅ Cookie清除成功，开始静默刷新...\n\n"
            
            // 发送静默刷新通知（这会触发NotesViewModel中的静默刷新逻辑）
            resultText += "📢 发送静默刷新通知...\n"
            NotificationCenter.default.post(name: Notification.Name("performSilentCookieRefresh"), object: nil)
            
            // 等待一段时间让静默刷新完成
            resultText += "⏳ 等待静默刷新完成（5秒）...\n"
            
            // 等待5秒
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            
            // 检查刷新结果
            let isAuthenticatedAfterRefresh = MiNoteService.shared.isAuthenticated()
            let newCookie = UserDefaults.standard.string(forKey: "minote_cookie") ?? ""
            
            resultText += "\n📊 测试结果：\n"
            resultText += "刷新后认证状态: \(isAuthenticatedAfterRefresh ? "已认证" : "未认证")\n"
            resultText += "新Cookie长度: \(newCookie.count) 字符\n"
            
            if isAuthenticatedAfterRefresh && !newCookie.isEmpty {
                resultText += "\n✅ 静默刷新成功！\n"
                resultText += "系统已自动刷新Cookie并恢复认证状态\n\n"
                
                // 比较新旧Cookie
                if newCookie != currentCookie {
                    resultText += "📝 Cookie已更新：\n"
                    resultText += "- 旧Cookie长度: \(currentCookie.count) 字符\n"
                    resultText += "- 新Cookie长度: \(newCookie.count) 字符\n"
                    
                    // 检查关键字段
                    let hasServiceToken = newCookie.contains("serviceToken=")
                    let hasUserId = newCookie.contains("userId=")
                    
                    resultText += "\n🔍 新Cookie验证：\n"
                    resultText += "- 包含serviceToken: \(hasServiceToken ? "是" : "否")\n"
                    resultText += "- 包含userId: \(hasUserId ? "是" : "否")\n"
                    
                    if hasServiceToken && hasUserId {
                        resultText += "✅ 新Cookie格式正确\n"
                    } else {
                        resultText += "⚠️ 新Cookie可能缺少必要字段\n"
                    }
                } else {
                    resultText += "📝 Cookie未变化（可能使用了相同的Cookie）\n"
                }
            } else {
                resultText += "\n❌ 静默刷新失败！\n"
                resultText += "系统未能自动刷新Cookie\n\n"
                
                // 恢复原始Cookie
                resultText += "🔄 恢复原始Cookie...\n"
                UserDefaults.standard.set(currentCookie, forKey: "minote_cookie")
                MiNoteService.shared.setCookie(currentCookie)
                
                resultText += "✅ 原始Cookie已恢复\n"
                resultText += "\n💡 可能的原因：\n"
                resultText += "1. 网络连接问题\n"
                resultText += "2. 小米登录页面结构变化\n"
                resultText += "3. 需要手动登录\n"
                resultText += "4. 静默刷新逻辑未正确实现\n"
            }
            
            // 重新加载凭证以更新UI
            await MainActor.run {
                loadCredentials()
                silentRefreshResult = resultText
                showSilentRefreshAlert = true
                isTestingSilentRefresh = false
            }
        }
    }
}

#Preview {
    DebugSettingsView()
}
