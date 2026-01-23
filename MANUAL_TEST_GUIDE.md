# 手动测试指南 - NotesViewModelAdapter

## 📋 测试准备

### 1. 启动应用（使用新架构）

由于 FeatureFlags 使用 UserDefaults，你有两种方式启用新架构：

#### 方式 A: 在应用内切换（推荐）
1. 先启动应用（使用旧架构）
2. 在应用中打开调试菜单或设置
3. 切换到新架构
4. 重启应用

#### 方式 B: 使用命令行设置
```bash
# 设置使用新架构
defaults write com.minote.MiNoteMac useNewArchitecture -bool true

# 启动应用
open /Users/acckion/Library/Developer/Xcode/DerivedData/MiNoteMac-*/Build/Products/Debug/MiNoteMac.app
```

#### 方式 C: 临时修改代码（最简单）
在 `Sources/Core/FeatureFlags.swift` 中临时修改默认值：
```swift
public static var useNewArchitecture: Bool {
    get {
        // 临时改为 true 进行测试
        UserDefaults.standard.object(forKey: "useNewArchitecture") as? Bool ?? true  // 改这里
    }
    set {
        UserDefaults.standard.set(newValue, forKey: "useNewArchitecture")
        print("[FeatureFlags] useNewArchitecture 设置为: \(newValue)")
    }
}
```

### 2. 验证使用的架构

启动应用后，在控制台查看日志：
- 如果看到 `[FeatureFlags] useNewArchitecture 设置为: true`，说明使用新架构
- 如果看到 `[AppCoordinator]` 相关日志，说明新架构正在运行

---

## 🧪 测试清单

### 阶段 1: 基础功能测试 (15 分钟)

#### ✅ 测试 1: 应用启动
- [x] 应用正常启动，无崩溃
- [x] 登录界面显示正常
- [x] 可以成功登录
- [x] 主窗口显示正常

#### ✅ 测试 2: 笔记列表
- [x] 笔记列表加载成功
- [x] 笔记数量正确
- [ ] 笔记排序正确（按修改时间）BUG: 无法按照创建时间排序
- [x] 可以选择笔记
- [x] 选中状态正确显示（高亮）
额外发现一个BUG: 如果笔记列表中有置顶笔记，粘性分组头显示的是“今天”而不是“置顶

#### ✅ 测试 3: 文件夹管理
- [x] 文件夹列表加载成功
- [x] 可以选择文件夹
- [x] 笔记列表根据文件夹过滤
- [x] 可以创建新文件夹
- [x] 可以删除文件夹
- [x] 可以重命名文件夹

#### ✅ 测试 4: 笔记编辑
- [x] 选择笔记后编辑器加载内容
- [x] 可以编辑笔记内容
- [x] 自动保存功能正常（3秒后）
- [x] 手动保存功能正常（Cmd+S）
- [x] 标题提取正确

#### ✅ 测试 5: 同步功能
- [x] 启动同步成功
- [x] 同步进度显示正确
- [x] 同步完成后笔记列表更新
- [x] 可以停止同步
- [x] 可以强制全量同步

---

### 阶段 2: 新增功能测试 (20 分钟)

#### ✅ 测试 6: 文件夹置顶 (toggleFolderPin)
- [ ] 右键点击文件夹，选择"置顶"
- [ ] 置顶状态正确显示（图标或标记）
- [ ] 置顶文件夹排序在前
- [ ] 可以取消置顶
BUG: 无法置顶，但暂时不需要该功能

#### ✅ 测试 7: 笔记历史 (getNoteHistory)
- [x] 选择一个笔记
- [x] 打开"历史版本"菜单
- [x] 可以看到历史版本列表
- [ ] 可以查看历史版本内容 BUG: 无法预览，提示“加载内容失败: XMLToHTMLConverter 类未定义”，似乎仍然使用旧的HTML编辑器
- [x] 可以恢复历史版本
- [x] 恢复后笔记内容正确

#### ✅ 测试 8: 回收站 (fetchDeletedNotes)
- [x] 删除一个笔记
- [x] 打开"回收站"
- [x] 可以看到已删除笔记列表
- [ ] 可以看到已删除笔记列表 BUG: 加载内容失败: XMLToHTMLConverter 类未定义
- [ ] 可以恢复已删除笔记 BUG: 无恢复按钮
- [ ] 可以永久删除笔记 BUG: 无永久删除按钮

#### ✅ 测试 9: 图片上传 (uploadImageAndInsertToNote)
- [x] 在编辑器中插入图片
- [x] 图片上传成功（查看进度）
- [x] 图片插入到正确位置
- [x] 图片显示正常
- [x] 保存后重新打开，图片仍然显示

#### ✅ 测试 10: 自动刷新 Cookie (startAutoRefreshCookieIfNeeded)
- [ ] 登录后自动刷新功能启动
- [ ] 查看控制台日志，确认定期刷新
- [ ] 刷新成功后无错误提示
- [ ] 刷新失败时有错误提示
- [ ] 退出登录后自动刷新停止
BUG: 似乎在检测到cookie失效后不会自动静默刷新
日志:
[ScheduledTaskManager] 开始执行任务: Cookie有效性检查
[CookieValidityCheckTask] 开始检查Cookie有效性
[MiNoteService] 开始实时检查Cookie在服务器端的有效性
📤 请求: GET https://i.mi.com/common/check?ts=1769147551994
📥 响应: GET https://i.mi.com/common/check?ts=1769147551994 - 状态码: 401
响应体: {"R":401,"S":"Err","D":"https://account.xiaomi.com/pass/serviceLogin?callback=https%3A%2F%2Fi.mi.com%2Fsts%3Fsign%3DIb3horUmfhQFoQV2LgZ1BLPKbRg%253D%26followup%3D%252F&sid=i.mi.com&_group=DEFAULT&checkSafePhone=true&_bal=true","E":false,"isSecondValidation":false}
[MiNoteService] 检测到Cookie过期（401 + 认证错误）
[MiNoteService] 响应包含登录重定向URL，确认需要重新登录
[MiNoteService] Cookie失效已被处理，跳过重复回调
❌ 错误: GET https://i.mi.com/common/check?ts=1769147551994 - Cookie已过期，请重新登录
[MiNoteService] ❌ Cookie有效性检查失败: cookieExpired
[CookieValidityCheckTask] Cookie有效性检查失败: cookieExpired
[AuthenticationStateManager] Cookie失效，标记为失效状态
[ScheduledTaskManager] 任务执行失败: Cookie有效性检查, 错误: Cookie已过期，请重新登录

BUG: 手动点击刷新时，也无法进行刷新
日志：
[SYNC] 网页版增量同步失败，回退到旧API增量同步: cookieExpired
[SYNC] 使用旧API增量同步
[SyncStateManager] 🔍 获取当前 syncTag
[LocalStorage] 🔍 开始加载同步状态
[LocalStorage] ✅ 成功加载同步状态:
[LocalStorage]   - lastSyncTime: 2026-01-23 05:34:29 +0000
[LocalStorage]   - syncTag: 49067866249119008
[SyncStateManager] ✅ 当前 syncTag: 49067866249119008
[SYNC] 从 SyncStateManager 获取 syncTag: 49067866249119008
📤 请求: GET https://i.mi.com/note/full/page?ts=1769147654893&limit=200
[SilentCookieRefreshManager] 🔄 收到刷新请求，类型: automatic
[SilentCookieRefreshManager] 在冷却期内，已过 30.7 秒，需等待 29.3 秒
[SilentCookieRefreshManager] 自动刷新在冷却期内，跳过刷新（剩余 29.3 秒）
[SilentCookieRefreshManager] ⏳ 跳过刷新，返回上次结果: true
[MiNoteService] ✅ 静默Cookie刷新成功
[MiNoteService] ✅ Cookie刷新成功
[AuthenticationStateManager] 📡 refreshCookie()返回: true
[AuthenticationStateManager] ✅ 静默刷新成功，开始验证Cookie有效性...
[MiNoteService] 开始实时检查Cookie在服务器端的有效性
📤 请求: GET https://i.mi.com/common/check?ts=1769147654915
📥 响应: GET https://i.mi.com/note/full/page?ts=1769147654893&limit=200 - 状态码: 401
响应体: {"R":401,"S":"Err","D":"https://account.xiaomi.com/pass/serviceLogin?callback=https%3A%2F%2Fi.mi.com%2Fsts%3Fsign%3DIb3horUmfhQFoQV2LgZ1BLPKbRg%253D%26followup%3D%252F&sid=i.mi.com&_group=DEFAULT&checkSafePhone=true&_bal=true","E":false,"isSecondValidation":false}
[MiNoteService] 检测到Cookie过期（401 + 认证错误）
[MiNoteService] 响应包含登录重定向URL，确认需要重新登录
[MiNoteService] Cookie失效已被处理，跳过重复回调
❌ 错误: GET https://i.mi.com/note/full/page?ts=1769147654893&limit=200 - Cookie已过期，请重新登录
[SYNC] 增量同步结束，isSyncing设置为false
[VIEWMODEL] Cookie过期，尝试静默刷新...
📥 响应: GET https://i.mi.com/common/check?ts=1769147654915 - 状态码: 401
响应体: {"R":401,"S":"Err","D":"https://account.xiaomi.com/pass/serviceLogin?callback=https%3A%2F%2Fi.mi.com%2Fsts%3Fsign%3DIb3horUmfhQFoQV2LgZ1BLPKbRg%253D%26followup%3D%252F&sid=i.mi.com&_group=DEFAULT&checkSafePhone=true&_bal=true","E":false,"isSecondValidation":false}
[MiNoteService] 检测到Cookie过期（401 + 认证错误）
[MiNoteService] 响应包含登录重定向URL，确认需要重新登录
[MiNoteService] Cookie失效已被处理，跳过重复回调
❌ 错误: GET https://i.mi.com/common/check?ts=1769147654915 - Cookie已过期，请重新登录
[MiNoteService] ❌ Cookie有效性检查失败: cookieExpired
[VIEWMODEL] 静默处理Cookie失效
[AuthenticationStateManager] 静默处理Cookie失效
[AuthenticationStateManager] ⚠️ 已在刷新周期中，跳过重复请求
[AuthenticationStateManager] ❌ 静默刷新失败: cookieExpired
[AuthenticationStateManager] ❌ 刷新失败，失败次数: 1/3
[ScheduledTaskManager] ▶️ 任务 cookie_validity_check 将在 30.0 秒后恢复
[ScheduledTaskManager] 停止任务: Cookie有效性检查
[ScheduledTaskManager] 启动任务: Cookie有效性检查, 间隔: 30.0秒
[ScheduledTaskManager] ▶️ 任务已恢复: Cookie有效性检查
[ScheduledTaskManager] 开始执行任务: Cookie有效性检查
[CookieValidityCheckTask] 开始检查Cookie有效性
[MiNoteService] 开始实时检查Cookie在服务器端的有效性
📤 请求: GET https://i.mi.com/common/check?ts=1769147686711
📥 响应: GET https://i.mi.com/common/check?ts=1769147686711 - 状态码: 401
响应体: {"R":401,"S":"Err","D":"https://account.xiaomi.com/pass/serviceLogin?callback=https%3A%2F%2Fi.mi.com%2Fsts%3Fsign%3DIb3horUmfhQFoQV2LgZ1BLPKbRg%253D%26followup%3D%252F&sid=i.mi.com&_group=DEFAULT&checkSafePhone=true&_bal=true","E":false,"isSecondValidation":false}
[MiNoteService] 检测到Cookie过期（401 + 认证错误）
[MiNoteService] 响应包含登录重定向URL，确认需要重新登录
[MiNoteService] Cookie失效已被处理，跳过重复回调
❌ 错误: GET https://i.mi.com/common/check?ts=1769147686711 - Cookie已过期，请重新登录
[MiNoteService] ❌ Cookie有效性检查失败: cookieExpired
[CookieValidityCheckTask] Cookie有效性检查失败: cookieExpired
[AuthenticationStateManager] Cookie失效，标记为失效状态
[ScheduledTaskManager] 任务执行失败: Cookie有效性检查, 错误: Cookie已过期，请重新登录

#### ✅ 测试 11: 同步间隔更新 (updateSyncInterval)
- [ ] 打开设置
- [ ] 修改同步间隔（例如从 5 分钟改为 10 分钟）
- [ ] 保存设置
- [ ] 查看控制台日志，确认新间隔生效
- [ ] 同步按新间隔执行

#### ✅ 测试 12: 待上传检查 (hasPendingUpload)
- [ ] 创建一个新笔记
- [ ] 断开网络
- [ ] 编辑笔记并保存
- [ ] 查看是否显示"待上传"标记
- [ ] 恢复网络
- [ ] 确认自动上传
- [ ] "待上传"标记消失

#### ✅ 测试 13: 私密笔记密码验证 (verifyPrivateNotesPassword)
- [ ] 创建一个私密笔记
- [ ] 退出登录
- [ ] 重新登录
- [ ] 尝试打开私密笔记
- [ ] 输入错误密码，验证失败
- [ ] 输入正确密码，验证通过
- [ ] 可以查看私密笔记内容

---

### 阶段 3: 边界情况测试 (15 分钟)

#### ✅ 测试 14: 空数据
- [ ] 删除所有笔记，界面显示"无笔记"
- [ ] 删除所有文件夹，界面显示"无文件夹"
- [ ] 搜索不存在的内容，显示"无结果"

#### ✅ 测试 15: 大量数据
- [ ] 加载 100+ 笔记，性能正常
- [ ] 滚动笔记列表，流畅无卡顿
- [ ] 搜索响应快速（< 500ms）

#### ✅ 测试 16: 网络异常
- [ ] 断开网络
- [ ] 尝试同步，显示错误提示
- [ ] 编辑笔记，自动加入离线队列
- [ ] 恢复网络
- [ ] 离线操作自动同步

#### ✅ 测试 17: 并发操作
- [ ] 同时编辑多个笔记（打开多个窗口）
- [ ] 同时同步和编辑
- [ ] 无数据冲突
- [ ] 无崩溃

---

### 阶段 4: 性能测试 (10 分钟)

#### ✅ 测试 18: 启动时间
- [ ] 记录应用启动时间
- [ ] 应该 < 2 秒

#### ✅ 测试 19: 内存占用
- [ ] 打开活动监视器
- [ ] 查看 MiNoteMac 内存占用
- [ ] 应该 < 200MB

#### ✅ 测试 20: CPU 占用
- [ ] 空闲时 CPU < 5%
- [ ] 同步时 CPU < 30%
- [ ] 编辑时 CPU < 20%

---

## 🐛 问题记录模板

如果发现问题，请记录：

```
### 问题 X: [简短描述]

**重现步骤**:
1. 
2. 
3. 

**预期行为**:


**实际行为**:


**错误日志**:
```


**截图**:
[如果有]

**环境信息**:
- macOS 版本: 
- 应用版本: 
- 使用架构: 新架构 (useNewArchitecture = true)
```

---

## ✅ 测试完成后

### 1. 切换回旧架构验证
```bash
# 切换回旧架构
defaults write com.minote.MiNoteMac useNewArchitecture -bool false

# 重启应用
open /Users/acckion/Library/Developer/Xcode/DerivedData/MiNoteMac-*/Build/Products/Debug/MiNoteMac.app
```

验证：
- [ ] 应用正常启动
- [ ] 所有功能正常工作
- [ ] 无明显性能下降

### 2. 清理测试数据
```bash
# 如果需要，重置 UserDefaults
defaults delete com.minote.MiNoteMac useNewArchitecture
```

### 3. 更新文档
- [ ] 更新 `docs/Phase7.3-进度总结.md`
- [ ] 标记任务 11.3 为完成
- [ ] 记录测试结果

### 4. 提交代码
如果测试通过：
```bash
git add .
git commit -m "test(viewmodel): 完成 NotesViewModelAdapter 手动测试

测试结果:
- 基础功能: 5/5 通过
- 新增功能: 8/8 通过
- 边界情况: 4/4 通过
- 性能测试: 3/3 通过

所有功能正常工作，可以切换新旧架构"
```

---

## 📞 需要帮助？

如果遇到问题：
1. 查看控制台日志
2. 检查 `[FeatureFlags]` 和 `[AppCoordinator]` 相关日志
3. 记录问题详情
4. 向 Kiro 报告

---

**创建日期**: 2026-01-23  
**测试人员**: [你的名字]
