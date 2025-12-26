# Implementation Plan

## 概述
修复小米笔记Mac客户端的在线状态管理和cookie刷新逻辑问题，确保cookie静默刷新功能正常工作，避免应用启动后cookie失效但显示在线的状态不一致问题。

## 类型系统变更
无新的类型定义，主要修改现有类的实现逻辑。

## 文件修改

### 1. Sources/MiNoteLibrary/View/ContentView.swift
**修改内容**：
- 在`handleAppear()`方法中添加启动自动刷新Cookie定时器的调用
- 添加启动时Cookie有效性检查逻辑
- 确保应用启动时根据用户设置自动启动定时器

**具体修改**：
```swift
private func handleAppear() {
    print("ContentView onAppear - 检查认证状态")
    let isAuthenticated = MiNoteService.shared.isAuthenticated()
    print("isAuthenticated: \(isAuthenticated)")
    
    if !isAuthenticated {
        print("显示登录界面")
        showingLogin = true
    } else {
        print("已认证，不显示登录界面")
        // 启动自动刷新Cookie定时器（如果需要）
        viewModel.startAutoRefreshCookieIfNeeded()
        
        // 检查Cookie有效性
        Task {
            await checkCookieValidityOnStartup()
        }
    }
}

private func checkCookieValidityOnStartup() async {
    print("[ContentView] 启动时检查Cookie有效性")
    let hasValidCookie = MiNoteService.shared.hasValidCookie()
    
    if !hasValidCookie {
        print("[ContentView] ⚠️ Cookie已失效，触发静默刷新")
        // 触发静默刷新逻辑
        await viewModel.handleCookieExpiredSilently()
    } else {
        print("[ContentView] ✅ Cookie有效")
    }
}
```

### 2. Sources/MiNoteLibrary/Service/AuthenticationStateManager.swift
**修改内容**：
- 在`handleCookieExpired()`方法中实现静默刷新逻辑
- 添加静默刷新重试机制（最多3次）
- 添加静默刷新失败后的弹窗显示逻辑

**具体修改**：
```swift
/// 处理Cookie失效（支持静默刷新）
@MainActor
func handleCookieExpired() {
    print("[AuthStateManager] 处理Cookie失效，silentRefreshOnFailure: \(silentRefreshOnFailure)")
    
    if silentRefreshOnFailure {
        // 尝试静默刷新
        Task {
            await attemptSilentRefresh()
        }
    } else {
        // 直接显示弹窗
        showCookieExpiredAlert = true
        isCookieExpired = true
        isOnline = false
    }
}

/// 尝试静默刷新Cookie（最多3次）
private func attemptSilentRefresh() async {
    print("[AuthStateManager] 开始静默刷新Cookie")
    
    var attempt = 0
    let maxAttempts = 3
    var success = false
    
    while attempt < maxAttempts && !success {
        attempt += 1
        print("[AuthStateManager] 静默刷新尝试 \(attempt)/\(maxAttempts)")
        
        do {
            // 尝试刷新Cookie
            let refreshSuccess = try await MiNoteService.shared.refreshCookie()
            if refreshSuccess {
                print("[AuthStateManager] ✅ 静默刷新成功")
                success = true
                
                // 恢复在线状态
                await MainActor.run {
                    isCookieExpired = false
                    isOnline = true
                    cookieExpiredShown = false
                    showCookieExpiredAlert = false
                }
                
                // 通知ViewModel处理待同步操作
                await NotesViewModel.shared?.processPendingOperations()
                break
            }
        } catch {
            print("[AuthStateManager] ❌ 静默刷新失败 (尝试 \(attempt)): \(error)")
        }
        
        // 如果不是最后一次尝试，等待一段时间再重试
        if attempt < maxAttempts {
            let delaySeconds = TimeInterval(attempt * 5) // 指数退避：5, 10, 15秒
            print("[AuthStateManager] 等待 \(delaySeconds) 秒后重试...")
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
        }
    }
    
    if !success {
        print("[AuthStateManager] ❌ 所有静默刷新尝试都失败，显示弹窗")
        await MainActor.run {
            showCookieExpiredAlert = true
            isCookieExpired = true
            isOnline = false
        }
    }
}

/// 静默处理Cookie失效（由ContentView调用）
@MainActor
func handleCookieExpiredSilently() async {
    print("[AuthStateManager] 静默处理Cookie失效")
    await attemptSilentRefresh()
}
```

### 3. Sources/MiNoteLibrary/Service/MiNoteService.swift
**修改内容**：
- 在`refreshCookie()`方法中添加重试逻辑
- 添加Cookie有效性检查，避免不必要的刷新
- 改进错误处理和日志记录

**具体修改**：
```swift
/// 刷新Cookie（带重试机制）
func refreshCookie() async throws -> Bool {
    print("[MiNoteService] 刷新Cookie（带重试机制）")
    
    // 先检查Cookie是否仍然有效，避免不必要的刷新
    if hasValidCookie() {
        print("[MiNoteService] ✅ Cookie仍然有效，跳过刷新")
        return true
    }
    
    var attempt = 0
    let maxAttempts = 3
    var lastError: Error?
    
    while attempt < maxAttempts {
        attempt += 1
        print("[MiNoteService] 刷新Cookie尝试 \(attempt)/\(maxAttempts)")
        
        do {
            let success = try await performCookieRefresh()
            if success {
                print("[MiNoteService] ✅ Cookie刷新成功")
                return true
            }
        } catch {
            print("[MiNoteService] ❌ Cookie刷新失败 (尝试 \(attempt)): \(error)")
            lastError = error
            
            // 如果不是最后一次尝试，等待一段时间再重试
            if attempt < maxAttempts {
                let delaySeconds = TimeInterval(attempt * 2) // 指数退避：2, 4, 6秒
                print("[MiNoteService] 等待 \(delaySeconds) 秒后重试...")
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            }
        }
    }
    
    print("[MiNoteService] ❌ 所有刷新尝试都失败")
    throw lastError ?? MiNoteError.networkError(URLError(.cannotConnectToHost))
}

/// 执行实际的Cookie刷新逻辑
private func performCookieRefresh() async throws -> Bool {
    // 原有的刷新逻辑...
    // 保持原有实现，但添加更详细的日志
    print("[MiNoteService] 执行Cookie刷新请求")
    
    // 原有的网络请求代码...
    // ...
    
    return true
}

/// 检查Cookie是否有效（更严格的检查）
func hasValidCookie() -> Bool {
    // 原有的检查逻辑...
    // 添加额外的检查：Cookie是否即将过期（例如1小时内）
    
    guard let cookie = UserDefaults.standard.string(forKey: "minote_cookie"),
          !cookie.isEmpty else {
        print("[MiNoteService] Cookie检查：无Cookie或Cookie为空")
        return false
    }
    
    // 检查Cookie是否包含必要的字段
    let hasUserId = cookie.contains("userId=")
    let hasServiceToken = cookie.contains("serviceToken=")
    
    if !hasUserId || !hasServiceToken {
        print("[MiNoteService] Cookie检查：缺少必要字段")
        return false
    }
    
    print("[MiNoteService] Cookie检查：Cookie有效")
    return true
}
```

### 4. Sources/MiNoteLibrary/ViewModel/NotesViewModel.swift
**修改内容**：
- 添加`handleCookieExpiredSilently()`方法供ContentView调用
- 改进自动刷新Cookie定时器的启动逻辑
- 添加启动时状态同步优化

**具体修改**：
```swift
/// 静默处理Cookie失效（由ContentView调用）
@MainActor
func handleCookieExpiredSilently() async {
    print("[VIEWMODEL] 静默处理Cookie失效")
    await authStateManager.handleCookieExpiredSilently()
}

/// 启动自动刷新Cookie定时器（改进版）
func startAutoRefreshCookieIfNeeded() {
    // 检查是否已登录
    guard service.isAuthenticated() else {
        print("[VIEWMODEL] 未登录，不启动自动刷新Cookie定时器")
        return
    }
    
    // 检查Cookie是否有效，避免不必要的定时器
    guard service.hasValidCookie() else {
        print("[VIEWMODEL] Cookie无效，不启动自动刷新Cookie定时器")
        return
    }
    
    // 检查是否已有定时器在运行
    if autoRefreshCookieTimer != nil {
        print("[VIEWMODEL] 自动刷新Cookie定时器已在运行")
        return
    }
    
    // 从UserDefaults获取刷新间隔
    let defaults = UserDefaults.standard
    let autoRefreshCookie = defaults.bool(forKey: "autoRefreshCookie")
    let autoRefreshInterval = defaults.double(forKey: "autoRefreshInterval")
    
    guard autoRefreshCookie, autoRefreshInterval > 0 else {
        print("[VIEWMODEL] 自动刷新Cookie未启用或间隔为0")
        return
    }
    
    if autoRefreshInterval == 0 {
        // 默认每天刷新一次（24小时）
        defaults.set(86400.0, forKey: "autoRefreshInterval")
    }
    
    print("[VIEWMODEL] 启动自动刷新Cookie定时器，间隔: \(autoRefreshInterval)秒")
    
    // 创建定时器
    autoRefreshCookieTimer = Timer.scheduledTimer(withTimeInterval: autoRefreshInterval, repeats: true) { [weak self] _ in
        guard let self = self else { return }
        
        Task { @MainActor in
            print("[VIEWMODEL] 自动刷新Cookie定时器触发")
            await self.refreshCookieAutomatically()
        }
    }
}

/// 自动刷新Cookie（改进版）
private func refreshCookieAutomatically() async {
    print("[VIEWMODEL] 开始自动刷新Cookie")
    
    // 检查是否已登录
    guard service.isAuthenticated() else {
        print("[VIEWMODEL] 未登录，跳过自动刷新Cookie")
        return
    }
    
    // 检查是否在线
    guard isOnline else {
        print("[VIEWMODEL] 离线状态，跳过自动刷新Cookie")
        return
    }
    
    // 检查Cookie是否仍然有效，避免不必要的刷新
    guard !service.hasValidCookie() else {
        print("[VIEWMODEL] ✅ Cookie仍然有效，跳过自动刷新")
        return
    }
    
    do {
        // 尝试刷新Cookie
        let success = try await service.refreshCookie()
        if success {
            print("[VIEWMODEL] ✅ 自动刷新Cookie成功")
        } else {
            print("[VIEWMODEL] ⚠️ 自动刷新Cookie失败")
        }
    } catch {
        print("[VIEWMODEL] ❌ 自动刷新Cookie出错: \(error.localizedDescription)")
    }
}
```

### 5. Sources/MiNoteLibrary/View/SettingsView.swift
**修改内容**：
- 确保设置保存时正确启动/停止定时器
- 添加设置变更的即时生效逻辑

**具体修改**：
```swift
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
    if autoRefreshCookie && viewModel.isLoggedIn {
        viewModel.startAutoRefreshCookieIfNeeded()
    } else {
        viewModel.stopAutoRefreshCookie()
    }
    
    // 应用编辑器设置
    applyEditorSettings()
    
    print("[SettingsView] 设置已保存，autoRefreshCookie: \(autoRefreshCookie), silentRefreshOnFailure: \(silentRefreshOnFailure)")
}
```

## 函数修改

### 新增函数
1. `ContentView.checkCookieValidityOnStartup()` - 启动时检查Cookie有效性
2. `AuthenticationStateManager.attemptSilentRefresh()` - 尝试静默刷新Cookie
3. `AuthenticationStateManager.handleCookieExpiredSilently()` - 静默处理Cookie失效
4. `MiNoteService.performCookieRefresh()` - 执行实际的Cookie刷新逻辑
5. `NotesViewModel.handleCookieExpiredSilently()` - 静默处理Cookie失效

### 修改函数
1. `ContentView.handleAppear()` - 添加自动刷新定时器启动和Cookie检查
2. `AuthenticationStateManager.handleCookieExpired()` - 添加静默刷新逻辑
3. `MiNoteService.refreshCookie()` - 添加重试机制和有效性检查
4. `MiNoteService.hasValidCookie()` - 增强Cookie有效性检查
5. `NotesViewModel.startAutoRefreshCookieIfNeeded()` - 改进定时器启动逻辑
6. `NotesViewModel.refreshCookieAutomatically()` - 添加有效性检查避免不必要刷新
7. `SettingsView.saveSettings()` - 确保设置正确应用

## 类修改

### 修改类
1. `AuthenticationStateManager` - 添加静默刷新相关状态和方法
2. `MiNoteService` - 增强Cookie刷新和检查逻辑
3. `NotesViewModel` - 改进自动刷新定时器管理
4. `ContentView` - 添加启动时状态检查

## 依赖关系
无新的外部依赖，所有修改都在现有代码基础上进行。

## 测试策略

### 单元测试
1. 测试`MiNoteService.hasValidCookie()`方法的各种情况
2. 测试`MiNoteService.refreshCookie()`的重试逻辑
3. 测试`AuthenticationStateManager.attemptSilentRefresh()`的重试机制

### 集成测试
1. 测试应用启动时的Cookie检查流程
2. 测试静默刷新失败后的弹窗显示
3. 测试自动刷新定时器的启动和停止

### 手动测试
1. 模拟Cookie失效场景，验证静默刷新是否工作
2. 测试设置中启用/禁用自动刷新的效果
3. 验证在线状态显示的准确性

## 实现顺序

1. **第一步：修改MiNoteService**
   - 实现`refreshCookie()`的重试机制
   - 增强`hasValidCookie()`方法
   - 添加`performCookieRefresh()`私有方法

2. **第二步：修改AuthenticationStateManager**
   - 实现`attemptSilentRefresh()`方法
   - 修改`handleCookieExpired()`支持静默刷新
   - 添加`handleCookieExpiredSilently()`方法

3. **第三步：修改NotesViewModel**
   - 添加`handleCookieExpiredSilently()`方法
   - 改进`startAutoRefreshCookieIfNeeded()`逻辑
   - 改进`refreshCookieAutomatically()`方法

4. **第四步：修改ContentView**
   - 在`handleAppear()`中添加定时器启动
   - 添加`checkCookieValidityOnStartup()`方法

5. **第五步：修改SettingsView**
   - 确保设置保存时正确应用自动刷新设置

6. **第六步：测试和验证**
   - 运行单元测试
   - 进行集成测试
   - 手动验证所有场景

这个实现计划确保了所有问题都得到解决，并且修改是渐进式的，每个步骤都可以独立测试和验证。
