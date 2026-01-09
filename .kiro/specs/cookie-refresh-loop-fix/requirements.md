# Requirements Document

## Introduction

修复 Cookie 静默刷新功能中的无限循环问题。当应用运行一段时间后，Cookie 刷新会陷入高频率的重复刷新循环，即使 WebView 成功提取了 Cookie，但服务器端验证仍然失败，导致系统不断触发新的刷新尝试。

## Glossary

- **Silent_Cookie_Refresh_Manager**: 静默 Cookie 刷新管理器，使用隐藏的 WKWebView 在后台刷新 Cookie
- **Authentication_State_Manager**: 认证状态管理器，统一管理登录、Cookie 刷新和认证相关的 UI 状态
- **Cookie_Validity_Check_Task**: Cookie 有效性检查任务，定期检查 Cookie 在服务器端是否有效
- **Scheduled_Task_Manager**: 定时任务管理器，管理所有后台定时任务
- **WKWebView_Cookie_Store**: WebView 的 Cookie 存储，与 URLSession 的 Cookie 存储独立
- **HTTPCookieStorage**: URLSession 使用的 Cookie 存储
- **Refresh_Cooldown**: 刷新冷却期，两次刷新之间的最小间隔时间

## Requirements

### Requirement 1: 刷新冷却机制

**User Story:** 作为用户，我希望系统不会在短时间内重复尝试刷新 Cookie，以避免资源浪费和无限循环。

#### Acceptance Criteria

1. WHEN a cookie refresh completes, THE Silent_Cookie_Refresh_Manager SHALL record the completion timestamp
2. WHEN a new refresh request arrives within the cooldown period, THE Silent_Cookie_Refresh_Manager SHALL reject the request and return the previous result
3. THE Silent_Cookie_Refresh_Manager SHALL use a minimum cooldown period of 60 seconds between refresh attempts
4. WHEN the cooldown period expires, THE Silent_Cookie_Refresh_Manager SHALL allow new refresh requests

### Requirement 2: 刷新后验证同步

**User Story:** 作为用户，我希望 Cookie 刷新成功后，系统能正确验证并同步状态，而不是立即再次触发刷新。

#### Acceptance Criteria

1. WHEN a cookie refresh succeeds, THE Authentication_State_Manager SHALL wait for the validity check to complete before updating online status
2. WHEN updating cookie validity cache, THE Authentication_State_Manager SHALL use await to ensure the operation completes synchronously
3. IF the validity check fails after a successful refresh, THEN THE Authentication_State_Manager SHALL NOT immediately trigger another refresh
4. WHEN a refresh cycle completes, THE Authentication_State_Manager SHALL set a flag to prevent re-entry during the same cycle

### Requirement 3: Cookie 同步一致性

**User Story:** 作为用户，我希望从 WebView 提取的 Cookie 能正确同步到 URLSession，确保后续 API 请求使用正确的认证信息。

#### Acceptance Criteria

1. WHEN extracting cookies from WKWebView, THE Silent_Cookie_Refresh_Manager SHALL synchronize all cookies to HTTPCookieStorage
2. WHEN setting cookies, THE Silent_Cookie_Refresh_Manager SHALL wait for the synchronization to complete before reporting success
3. THE Silent_Cookie_Refresh_Manager SHALL verify that the serviceToken in HTTPCookieStorage matches the one extracted from WKWebView
4. IF cookie synchronization fails, THEN THE Silent_Cookie_Refresh_Manager SHALL report the refresh as failed

### Requirement 4: 最大重试限制

**User Story:** 作为用户，我希望系统在多次刷新失败后停止尝试，而不是无限循环。

#### Acceptance Criteria

1. THE Authentication_State_Manager SHALL track the number of consecutive refresh failures
2. WHEN consecutive failures reach the maximum limit of 3, THE Authentication_State_Manager SHALL stop automatic refresh attempts
3. WHEN consecutive failures reach the maximum limit, THE Authentication_State_Manager SHALL display the cookie expired alert to the user
4. WHEN the user manually triggers a refresh, THE Authentication_State_Manager SHALL reset the failure counter

### Requirement 5: 状态恢复逻辑修正

**User Story:** 作为用户，我希望系统在刷新成功后能正确恢复在线状态，而不是错误地保持离线状态。

#### Acceptance Criteria

1. WHEN a refresh is reported as successful, THE Authentication_State_Manager SHALL verify the cookie validity before restoring online status
2. IF the cookie is valid after refresh, THEN THE Authentication_State_Manager SHALL set isOnline to true and isCookieExpired to false
3. IF the cookie is still invalid after refresh, THEN THE Authentication_State_Manager SHALL NOT print "成功恢复在线状态" message
4. THE Authentication_State_Manager SHALL ensure cookieExpiredShown flag is only cleared when the cookie is actually valid

### Requirement 6: 定时检查与刷新协调

**User Story:** 作为用户，我希望定时 Cookie 检查任务不会与正在进行的刷新操作冲突。

#### Acceptance Criteria

1. WHILE a cookie refresh is in progress, THE Cookie_Validity_Check_Task SHALL skip its scheduled check
2. WHEN a refresh completes, THE Cookie_Validity_Check_Task SHALL wait for a grace period before resuming checks
3. THE Scheduled_Task_Manager SHALL provide a method to temporarily pause a specific task
4. WHEN the refresh manager starts a refresh, THE Scheduled_Task_Manager SHALL pause the cookie validity check task
