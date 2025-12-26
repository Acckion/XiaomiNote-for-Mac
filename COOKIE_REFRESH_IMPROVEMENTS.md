# Cookie刷新和在线状态管理改进

## 问题描述
用户报告了以下问题：
1. Cookie静默刷新功能无法自动启用
2. 有时启动app之后实际上Cookie失效但是显示在线
3. 在线状态管理逻辑不正常

## 解决方案
我们已经对以下文件进行了改进：

### 1. MiNoteService.swift
- 添加了 `silentRefreshOnFailure` 设置支持
- 改进了Cookie验证逻辑，确保更准确的Cookie状态检测
- 添加了静默刷新失败时的重试机制

### 2. AuthenticationStateManager.swift
- 重构了在线状态管理逻辑，现在区分三种状态：
  - 在线：网络正常且Cookie有效
  - Cookie失效：网络正常但Cookie失效
  - 离线：网络断开
- 添加了静默刷新支持，当Cookie失效时自动尝试刷新（最多3次）
- 改进了状态转换逻辑，避免重复提示
- 添加了用户选择"保持离线模式"的功能

### 3. NotesViewModel.swift
- 添加了自动刷新Cookie的定时器支持
- 改进了在线状态同步逻辑
- 添加了静默刷新失败时的处理逻辑

### 4. ContentView.swift
- 集成了新的认证状态管理器
- 改进了Cookie失效弹窗的显示逻辑
- 添加了静默刷新状态指示器

### 5. SettingsView.swift
- 添加了"Cookie失效时静默刷新"设置选项
- 添加了自动刷新Cookie的频率设置
- 改进了设置保存逻辑

## 主要改进功能

### 1. 静默刷新机制
- 当Cookie失效时，如果启用了静默刷新，系统会自动尝试刷新Cookie
- 最多尝试3次，每次间隔5秒（指数退避）
- 如果静默刷新成功，用户不会看到任何提示
- 如果静默刷新失败，会显示弹窗要求用户手动刷新

### 2. 准确的在线状态显示
- 现在区分网络状态和Cookie状态
- 只有当网络正常且Cookie有效时才显示为在线
- Cookie失效时会立即显示为离线状态，避免误导用户

### 3. 用户控制选项
- 用户可以在设置中启用/禁用静默刷新
- 用户可以选择保持离线模式，阻止后续网络请求
- 用户可以设置自动刷新Cookie的频率（每天/每周/每月）

### 4. 避免重复提示
- 添加了 `cookieExpiredShown` 标志，避免重复显示弹窗
- 用户选择"保持离线模式"后，不再处理Cookie失效事件

## 测试验证
- 所有修改已通过编译测试
- 构建成功，没有编译错误
- 代码逻辑完整，保持了向后兼容性

## 使用说明
1. 打开设置 -> 同步设置
2. 启用"自动刷新Cookie"和"Cookie失效时静默刷新"
3. 设置合适的刷新频率
4. 当Cookie失效时，系统会自动尝试静默刷新
5. 如果静默刷新失败，会显示弹窗提示用户手动刷新

## 技术细节
- 使用 `UserDefaults` 存储静默刷新设置
- 使用 `Timer` 进行定期状态检查
- 使用 `Task` 和 `async/await` 进行异步刷新操作
- 使用 `@MainActor` 确保UI更新在主线程执行

## 文件修改清单
1. `Sources/MiNoteLibrary/Service/MiNoteService.swift` - Cookie服务改进
2. `Sources/MiNoteLibrary/Service/AuthenticationStateManager.swift` - 状态管理核心逻辑
3. `Sources/MiNoteLibrary/ViewModel/NotesViewModel.swift` - ViewModel集成
4. `Sources/MiNoteLibrary/View/ContentView.swift` - 主界面集成
5. `Sources/MiNoteLibrary/View/SettingsView.swift` - 设置界面更新

这些改进应该能够解决用户报告的Cookie刷新和在线状态管理问题。
