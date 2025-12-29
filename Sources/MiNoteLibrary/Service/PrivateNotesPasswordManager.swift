import Foundation
import Security
import LocalAuthentication

/// 私密笔记密码管理器
/// 
/// 使用 Keychain 安全存储私密笔记密码
public final class PrivateNotesPasswordManager: @unchecked Sendable {
    public static let shared = PrivateNotesPasswordManager()
    
    private let service = "com.mi.note.mac.privateNotes"
    private let account = "privateNotesPassword"
    private let accountForPasswordVerification = "privateNotesPasswordVerification" // 用于密码验证的账户名（不设置生物识别访问控制）
    
    private init() {}
    
    /// 检查是否已设置密码（不触发生物识别验证）
    /// 
    /// 使用 kSecReturnAttributes 而不是 kSecReturnData 来检查密码是否存在
    /// 这样可以避免触发生物识别验证
    /// 
    /// - Returns: 如果已设置密码返回 true，否则返回 false
    public func hasPassword() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,  // 只返回属性，不返回数据，避免触发验证
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        // 如果找到项，说明密码已设置
        return status == errSecSuccess
    }
    
    /// 获取存储的密码
    /// 
    /// - Returns: 密码字符串，如果未设置或获取失败返回 nil
    public func getPassword() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return password
    }
    
    /// 设置密码
    /// 
    /// 存储两个 Keychain 项：
    /// 1. 设置了生物识别访问控制的项（用于 Touch ID 验证）
    /// 2. 不设置访问控制的项（用于密码验证，不触发 Touch ID）
    /// 
    /// - Parameter password: 要设置的密码
    /// - Throws: 如果设置失败抛出错误
    public func setPassword(_ password: String) throws {
        guard let passwordData = password.data(using: .utf8) else {
            throw PasswordError.invalidPassword
        }
        
        // 先删除旧密码（如果存在）
        deletePassword()
        
        // 1. 存储用于密码验证的项（不设置生物识别访问控制）
        // 这样 verifyPassword() 不会触发 Touch ID 验证
        let verificationQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountForPasswordVerification,
            kSecValueData as String: passwordData
        ]
        
        var status = SecItemAdd(verificationQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PasswordError.saveFailed(status)
        }
        
        // 2. 如果启用了 Touch ID，存储设置了生物识别访问控制的项（用于 Touch ID 验证）
        if isTouchIDEnabled() && isBiometricAvailable() {
            var error: Unmanaged<CFError>?
            // 使用 .biometryCurrentSet 而不是 .biometryAny，避免权限弹窗
            // .biometryCurrentSet 要求使用当前已注册的生物识别，不会弹出权限请求
            guard let accessControl = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                [.biometryCurrentSet],  // 只使用当前已注册的生物识别，避免权限弹窗
                &error
            ) else {
                // 如果创建访问控制失败，只使用密码验证项
                print("[PrivateNotesPasswordManager] 警告：无法创建生物识别访问控制，仅使用密码验证")
                return
            }
            
            let touchIDQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrAccessControl as String: accessControl,
                kSecValueData as String: passwordData
            ]
            
            status = SecItemAdd(touchIDQuery as CFDictionary, nil)
            if status != errSecSuccess {
                // 如果 Touch ID 项添加失败，删除已添加的验证项
                SecItemDelete(verificationQuery as CFDictionary)
                throw PasswordError.saveFailed(status)
            }
        } else {
            // 如果未启用 Touch ID，也存储到主账户（不设置访问控制）
            let mainQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: passwordData
            ]
            
            status = SecItemAdd(mainQuery as CFDictionary, nil)
            if status != errSecSuccess {
                // 如果主项添加失败，删除已添加的验证项
                SecItemDelete(verificationQuery as CFDictionary)
                throw PasswordError.saveFailed(status)
            }
        }
    }
    
    /// 删除密码
    /// 
    /// 删除两个 Keychain 项（如果存在）
    /// 
    /// - Returns: 如果删除成功返回 true，否则返回 false
    @discardableResult
    public func deletePassword() -> Bool {
        // 删除用于 Touch ID 验证的项
        let touchIDQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status1 = SecItemDelete(touchIDQuery as CFDictionary)
        
        // 删除用于密码验证的项
        let verificationQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountForPasswordVerification
        ]
        let status2 = SecItemDelete(verificationQuery as CFDictionary)
        
        return (status1 == errSecSuccess || status1 == errSecItemNotFound) &&
               (status2 == errSecSuccess || status2 == errSecItemNotFound)
    }
    
    /// 验证密码（不触发生物识别验证）
    /// 
    /// 使用不设置生物识别访问控制的 Keychain 项来验证密码
    /// 这样不会触发 Touch ID 验证
    /// 
    /// - Parameter password: 要验证的密码
    /// - Returns: 如果密码正确返回 true，否则返回 false
    public func verifyPassword(_ password: String) -> Bool {
        // 从用于密码验证的 Keychain 项读取密码（不设置生物识别访问控制）
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountForPasswordVerification,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let storedPassword = String(data: data, encoding: .utf8) else {
            return false
        }
        
        return password == storedPassword
    }
    
    /// 检查是否启用了 Touch ID
    /// 
    /// - Returns: 如果启用了 Touch ID 返回 true，否则返回 false
    public func isTouchIDEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: "privateNotesTouchIDEnabled")
    }
    
    /// 设置 Touch ID 启用状态
    /// 
    /// - Parameter enabled: 是否启用 Touch ID
    public func setTouchIDEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "privateNotesTouchIDEnabled")
    }
    
    /// 检查设备是否支持生物识别（Touch ID 或 Face ID）
    /// 
    /// - Returns: 如果设备支持生物识别返回 true，否则返回 false
    public func isBiometricAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    /// 获取生物识别类型（Touch ID 或 Face ID）
    /// 
    /// - Returns: 生物识别类型字符串，如果不支持返回 nil
    public func getBiometricType() -> String? {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return nil
        }
        
        if #available(macOS 11.0, *) {
            switch context.biometryType {
            case .touchID:
                return "Touch ID"
            case .faceID:
                return "Face ID"
            case .none:
                return nil
            @unknown default:
                return nil
            }
        } else {
            // macOS 10.15 及以下版本
            return "Touch ID"
        }
    }
    
    /// 使用 Touch ID 验证
    /// 
    /// 使用 LocalAuthentication 框架进行真正的 Touch ID 验证
    /// 每次调用都需要用户进行生物识别验证
    /// 
    /// - Returns: 如果验证成功返回 true，否则返回 false
    /// - Throws: 如果验证过程中出现错误
    public func authenticateWithTouchID() async throws -> Bool {
        // 检查是否启用了Touch ID
        guard isTouchIDEnabled() && isBiometricAvailable() else {
            throw PasswordError.biometricNotAvailable("Touch ID未启用或不可用")
        }
        
        // 检查密码是否存在
        guard hasPassword() else {
            throw PasswordError.notFound
        }
        
        let context = LAContext()
        var error: NSError?
        
        // 检查是否支持生物识别
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            if let error = error {
                throw PasswordError.biometricNotAvailable(error.localizedDescription)
            }
            throw PasswordError.biometricNotAvailable("设备不支持生物识别")
        }
        
        // 执行生物识别验证
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "验证以访问私密笔记"
            )
            return success
        } catch {
            // 处理各种错误情况
            if let laError = error as? LAError {
                switch laError.code {
                case .userCancel:
                    throw PasswordError.biometricCancelled
                case .userFallback:
                    throw PasswordError.biometricFallback
                case .biometryNotAvailable:
                    throw PasswordError.biometricNotAvailable("生物识别不可用")
                case .biometryNotEnrolled:
                    throw PasswordError.biometricNotAvailable("未设置生物识别")
                case .biometryLockout:
                    throw PasswordError.biometricNotAvailable("生物识别已锁定，请稍后再试")
                default:
                    throw PasswordError.biometricNotAvailable(laError.localizedDescription)
                }
            }
            throw PasswordError.biometricNotAvailable(error.localizedDescription)
        }
    }
    
    /// 使用 Touch ID 验证（旧方法，保留用于兼容性，会弹出系统对话框）
    /// 
    /// - Parameter reason: 验证原因说明
    /// - Returns: 如果验证成功返回 true，否则返回 false
    /// - Throws: 如果验证过程中出现错误
    @available(*, deprecated, message: "使用authenticateWithTouchID()代替，该方法会弹出系统对话框")
    public func authenticateWithTouchIDWithDialog(reason: String = "验证以访问私密笔记") async throws -> Bool {
        let context = LAContext()
        var error: NSError?
        
        // 检查是否支持生物识别
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            if let error = error {
                throw PasswordError.biometricNotAvailable(error.localizedDescription)
            }
            throw PasswordError.biometricNotAvailable("设备不支持生物识别")
        }
        
        // 执行生物识别验证
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return success
        } catch {
            // 处理各种错误情况
            if let laError = error as? LAError {
                switch laError.code {
                case .userCancel:
                    throw PasswordError.biometricCancelled
                case .userFallback:
                    throw PasswordError.biometricFallback
                case .biometryNotAvailable:
                    throw PasswordError.biometricNotAvailable("生物识别不可用")
                case .biometryNotEnrolled:
                    throw PasswordError.biometricNotAvailable("未设置生物识别")
                case .biometryLockout:
                    throw PasswordError.biometricNotAvailable("生物识别已锁定，请稍后再试")
                default:
                    throw PasswordError.biometricNotAvailable(laError.localizedDescription)
                }
            }
            throw PasswordError.biometricNotAvailable(error.localizedDescription)
        }
    }
}

/// 密码错误类型
public enum PasswordError: LocalizedError {
    case invalidPassword
    case saveFailed(OSStatus)
    case notFound
    case biometricNotAvailable(String)
    case biometricCancelled
    case biometricFallback
    
    public var errorDescription: String? {
        switch self {
        case .invalidPassword:
            return "密码无效"
        case .saveFailed(let status):
            return "保存密码失败 (错误代码: \(status))"
        case .notFound:
            return "未找到密码"
        case .biometricNotAvailable(let message):
            return "生物识别不可用: \(message)"
        case .biometricCancelled:
            return "用户取消了生物识别验证"
        case .biometricFallback:
            return "用户选择使用密码验证"
        }
    }
}

