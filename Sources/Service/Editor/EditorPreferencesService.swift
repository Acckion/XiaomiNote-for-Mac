//
//  EditorPreferencesService.swift
//  MiNoteMac
//
//  编辑器偏好设置服务 - 管理编辑器相关的偏好设置
//

import Foundation
import Combine

/// 编辑器偏好设置服务
@MainActor
class EditorPreferencesService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = EditorPreferencesService()
    
    // MARK: - Published Properties
    
    /// 原生编辑器是否可用
    @Published var isNativeEditorAvailable: Bool = false
    
    // MARK: - Private Properties
    
    private let userDefaults: UserDefaults
    
    // MARK: - Initialization
    
    /// 初始化编辑器偏好设置服务
    /// - Parameter userDefaults: UserDefaults 实例，默认使用 .standard
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        
        // 检查原生编辑器可用性
        let isNativeAvailable = EditorFactory.isEditorAvailable(.native)
        self.isNativeEditorAvailable = isNativeAvailable
        
        print("[EditorPreferencesService] 初始化")
        print("[EditorPreferencesService]   - isNativeAvailable: \(isNativeAvailable)")
        
        // 清理旧的编辑器类型偏好设置（如果存在）
        if userDefaults.string(forKey: "selectedEditorType") != nil {
            userDefaults.removeObject(forKey: "selectedEditorType")
            print("[EditorPreferencesService]   - 已清理旧的编辑器类型偏好设置")
        }
    }
    
    /// 私有初始化方法，用于单例
    private convenience init() {
        self.init(userDefaults: .standard)
    }
    
    // MARK: - Public Methods
    
    /// 获取当前编辑器类型（始终返回原生编辑器）
    /// - Returns: 编辑器类型
    func getCurrentEditorType() -> EditorType {
        return .native
    }
    
    /// 重新检查原生编辑器可用性
    func recheckNativeEditorAvailability() {
        isNativeEditorAvailable = EditorFactory.isEditorAvailable(.native)
    }
}