//
//  EditorPreferencesService.swift
//  MiNoteMac
//
//  编辑器偏好设置服务 - 管理用户的编辑器选择偏好
//

import Foundation
import Combine

/// 编辑器偏好设置服务
@MainActor
class EditorPreferencesService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = EditorPreferencesService()
    
    // MARK: - Published Properties
    
    /// 当前选择的编辑器类型
    @Published var selectedEditorType: EditorType
    
    /// 原生编辑器是否可用
    @Published var isNativeEditorAvailable: Bool = false
    
    // MARK: - Private Properties
    
    private let userDefaults: UserDefaults
    private let editorTypeKey = "selectedEditorType"
    
    // MARK: - Initialization
    
    /// 初始化编辑器偏好设置服务
    /// - Parameter userDefaults: UserDefaults 实例，默认使用 .standard
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        
        // 检查原生编辑器可用性
        let isNativeAvailable = EditorFactory.isEditorAvailable(.native)
        self.isNativeEditorAvailable = isNativeAvailable
        
        // 初始化 selectedEditorType
        if let savedType = userDefaults.string(forKey: editorTypeKey),
           let editorType = EditorType(rawValue: savedType) {
            // 如果保存的是原生编辑器但不可用，则回退到 Web 编辑器
            if editorType == .native && !isNativeAvailable {
                self.selectedEditorType = .web
            } else {
                self.selectedEditorType = editorType
            }
        } else {
            // 首次使用，根据系统版本设置默认编辑器
            self.selectedEditorType = isNativeAvailable ? .native : .web
        }
        
        // 保存初始设置
        saveEditorPreference()
    }
    
    /// 私有初始化方法，用于单例
    private convenience init() {
        self.init(userDefaults: .standard)
    }
    
    // MARK: - Public Methods
    
    /// 设置编辑器类型
    /// - Parameter type: 编辑器类型
    /// - Returns: 是否设置成功
    @discardableResult
    func setEditorType(_ type: EditorType) -> Bool {
        // 检查编辑器是否可用
        guard EditorFactory.isEditorAvailable(type) else {
            return false
        }
        
        selectedEditorType = type
        saveEditorPreference()
        return true
    }
    
    /// 获取当前编辑器类型
    /// - Returns: 当前编辑器类型
    func getCurrentEditorType() -> EditorType {
        return selectedEditorType
    }
    
    /// 检查指定编辑器类型是否可用
    /// - Parameter type: 编辑器类型
    /// - Returns: 是否可用
    func isEditorTypeAvailable(_ type: EditorType) -> Bool {
        return EditorFactory.isEditorAvailable(type)
    }
    
    /// 获取可用的编辑器类型列表
    /// - Returns: 可用的编辑器类型数组
    func getAvailableEditorTypes() -> [EditorType] {
        return EditorType.allCases.filter { isEditorTypeAvailable($0) }
    }
    
    /// 重新检查原生编辑器可用性
    func recheckNativeEditorAvailability() {
        let wasAvailable = isNativeEditorAvailable
        isNativeEditorAvailable = EditorFactory.isEditorAvailable(.native)
        
        // 如果原生编辑器变为不可用，且当前选择的是原生编辑器，则切换到 Web 编辑器
        if wasAvailable && !isNativeEditorAvailable && selectedEditorType == .native {
            selectedEditorType = .web
            saveEditorPreference()
        }
    }
    
    // MARK: - Private Methods
    
    /// 保存编辑器偏好到 UserDefaults
    private func saveEditorPreference() {
        userDefaults.set(selectedEditorType.rawValue, forKey: editorTypeKey)
    }
}

/// UserDefaults 扩展 - 提供编辑器偏好的便捷访问
extension UserDefaults {
    
    /// 编辑器类型偏好
    var editorType: EditorType {
        get {
            if let savedType = string(forKey: "selectedEditorType"),
               let editorType = EditorType(rawValue: savedType) {
                return editorType
            }
            // 默认值：如果原生编辑器可用则使用原生编辑器，否则使用 Web 编辑器
            return EditorFactory.isEditorAvailable(.native) ? .native : .web
        }
        set {
            set(newValue.rawValue, forKey: "selectedEditorType")
        }
    }
}