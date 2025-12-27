# Cookie检查逻辑修复总结

## 问题描述

根据用户提供的日志，存在以下问题：

```
📥 响应: POST https://i.mi.com/note/note - 状态码: 401
[MiNoteService] Cookie检查：Cookie有效
[MiNoteService] 401错误但不是明确的认证失败，仍视为Cookie过期，设置为离线状态
```

**核心问题**：当服务器返回401错误时，`hasValidCookie()` 方法仍然显示"Cookie有效"，但实际上Cookie已经失效。

## 根本原因分析

1. **`hasValidCookie()` 方法逻辑缺陷**：
   - 原方法只检查Cookie是否存在且包含必要的字段（userId和serviceToken）
   - 但即使Cookie包含这些字段，实际上可能已经过期
   - 方法无法检测到实际的Cookie失效状态

2. **状态不一致**：
   - 服务器返回401错误，表明Cookie已失效
   - 但`hasValidCookie()` 仍然返回true
   - 导致系统状态与实际状态不一致

## 解决方案

### 1. 修改 `hasValidCookie()` 方法

在 `MiNoteService.swift` 中，修改了 `hasValidCookie()` 方法：

```swift
func hasValidCookie() -> Bool {
    // 首先检查是否有Cookie失效标志
    cookieExpiredLock.lock()
    let isExpired = cookieExpiredFlag
    cookieExpiredLock.unlock()
    
    if isExpired {
        print("[MiNoteService] Cookie检查：Cookie已标记为失效")
        return false
    }
    
    // 检查Cookie是否存在且包含必要的字段
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

### 2. 关键改进

1. **添加Cookie失效标志检查**：
   - 当`handle401Error()` 方法检测到Cookie过期时，会设置`cookieExpiredFlag = true`
   - `hasValidCookie()` 首先检查这个标志，如果为true则直接返回false

2. **保持现有逻辑**：
   - 仍然检查Cookie是否存在且包含必要字段
   - 保持了向后兼容性

3. **线程安全**：
   - 使用`NSLock`保护`cookieExpiredFlag`的访问
   - 确保多线程环境下的数据一致性

## 预期效果

修复后，当发生401错误时：

1. `handle401Error()` 方法会设置 `cookieExpiredFlag = true`
2. 后续调用 `hasValidCookie()` 会返回false
3. 日志将显示："Cookie检查：Cookie已标记为失效"
4. 系统状态与实际Cookie状态保持一致

## 测试验证

1. **编译测试**：项目成功编译，无语法错误
2. **逻辑验证**：
   - 当Cookie有效时：`hasValidCookie()` 返回true
   - 当发生401错误时：`cookieExpiredFlag` 被设置为true
   - 后续调用 `hasValidCookie()` 返回false
   - 系统正确显示离线状态

## 相关文件

- `Sources/MiNoteLibrary/Service/MiNoteService.swift` - 主要修复文件
- `Sources/MiNoteLibrary/Service/AuthenticationStateManager.swift` - 状态管理文件（未修改）

## 注意事项

1. **Cookie失效标志的清除**：
   - 当设置新Cookie时（`setCookie()` 方法），会自动清除失效标志
   - 确保刷新Cookie后能恢复正常状态

2. **保护期机制**：
   - 系统仍然保留Cookie设置后的保护期机制
   - 避免刚设置Cookie后的临时认证失败被误判为过期

3. **静默刷新**：
   - 如果启用了静默刷新，系统会尝试自动刷新Cookie
   - 刷新成功后，失效标志会被清除

## 后续建议

1. **添加更智能的Cookie验证**：
   - 可以考虑添加Cookie过期时间检查
   - 或者定期调用轻量级API验证Cookie有效性

2. **改进错误处理**：
   - 区分不同类型的401错误
   - 提供更详细的错误信息和恢复建议

3. **增强日志**：
   - 记录Cookie失效的具体原因
   - 跟踪Cookie生命周期，便于问题排查
