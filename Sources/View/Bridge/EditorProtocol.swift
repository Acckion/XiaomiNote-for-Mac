//
//  EditorProtocol.swift
//  MiNoteMac
//
//  编辑器协议定义 - 定义原生编辑器的统一接口
//

import Foundation
import Combine

/// 编辑器协议 - 定义所有编辑器必须实现的接口
protocol EditorProtocol: AnyObject {
    
    // MARK: - Content Management
    
    /// 加载内容到编辑器
    /// - Parameter content: 要加载的内容（小米笔记 XML 格式）
    func loadContent(_ content: String)
    
    /// 获取编辑器当前内容
    /// - Returns: 当前内容（小米笔记 XML 格式）
    func getContent() -> String
    
    /// 清空编辑器内容
    func clearContent()
    
    // MARK: - Format Operations
    
    /// 应用文本格式
    /// - Parameter format: 要应用的格式
    func applyFormat(_ format: TextFormat)
    
    /// 插入特殊元素
    /// - Parameter element: 要插入的特殊元素
    func insertSpecialElement(_ element: SpecialElement)
    
    /// 获取当前选中文本的格式
    /// - Returns: 当前格式集合
    func getCurrentFormats() -> Set<TextFormat>
    
    // MARK: - Selection and Cursor
    
    /// 获取当前选择范围
    /// - Returns: 选择范围
    func getSelectedRange() -> NSRange
    
    /// 设置选择范围
    /// - Parameter range: 要设置的选择范围
    func setSelectedRange(_ range: NSRange)
    
    /// 获取光标位置
    /// - Returns: 光标位置
    func getCursorPosition() -> Int
    
    /// 设置光标位置
    /// - Parameter position: 要设置的光标位置
    func setCursorPosition(_ position: Int)
    
    // MARK: - Focus and State
    
    /// 设置编辑器焦点
    /// - Parameter focused: 是否获得焦点
    func setFocus(_ focused: Bool)
    
    /// 检查编辑器是否有焦点
    /// - Returns: 是否有焦点
    func hasFocus() -> Bool
    
    /// 检查编辑器是否可用
    /// - Returns: 是否可用
    func isAvailable() -> Bool
    
    // MARK: - Publishers
    
    /// 内容变化发布者
    var contentChangePublisher: AnyPublisher<String, Never> { get }
    
    /// 选择变化发布者
    var selectionChangePublisher: AnyPublisher<NSRange, Never> { get }
    
    /// 格式变化发布者
    var formatChangePublisher: AnyPublisher<Set<TextFormat>, Never> { get }
}

/// 编辑器创建错误
enum EditorCreationError: Error, LocalizedError {
    case unsupportedType(EditorType)
    case systemRequirementsNotMet(EditorType, String)
    case initializationFailed(EditorType, Error)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedType(let type):
            return "不支持的编辑器类型: \(type.displayName)"
        case .systemRequirementsNotMet(let type, let requirement):
            return "\(type.displayName) 不满足系统要求: \(requirement)"
        case .initializationFailed(let type, let error):
            return "\(type.displayName) 初始化失败: \(error.localizedDescription)"
        }
    }
}

/// 编辑器工厂 - 创建不同类型的编辑器
class EditorFactory {
    
    // MARK: - Static Properties
    
    /// 支持的编辑器类型
    static let supportedTypes: [EditorType] = EditorType.allCases
    
    /// 编辑器创建缓存
    private static nonisolated(unsafe) var editorCache: [EditorType: () -> EditorProtocol] = [:]
    
    // MARK: - Public Methods
    
    /// 创建编辑器实例
    /// - Parameter type: 编辑器类型
    /// - Returns: 编辑器实例
    /// - Throws: EditorCreationError
    static func createEditor(type: EditorType) throws -> EditorProtocol {
        // 检查编辑器类型是否支持
        guard supportedTypes.contains(type) else {
            throw EditorCreationError.unsupportedType(type)
        }
        
        // 检查编辑器是否可用
        guard isEditorAvailable(type) else {
            let requirement = getSystemRequirement(for: type)
            throw EditorCreationError.systemRequirementsNotMet(type, requirement)
        }
        
        do {
            return try createNativeEditor()
        } catch {
            throw EditorCreationError.initializationFailed(type, error)
        }
    }
    
    /// 创建编辑器实例（安全版本，带回退机制）
    /// - Parameter type: 编辑器类型
    /// - Returns: 编辑器实例
    /// - Throws: EditorCreationError 如果创建失败
    /// - Note: 实际的编辑器实现在 NativeEditorContext 中
    static func createEditorSafely(type: EditorType) throws -> EditorProtocol {
        return try createEditor(type: type)
    }
    
    /// 检查编辑器类型是否可用
    /// - Parameter type: 编辑器类型
    /// - Returns: 是否可用
    static func isEditorAvailable(_ type: EditorType) -> Bool {
        return checkNativeEditorSupport()
    }
    
    /// 获取所有可用的编辑器类型
    /// - Returns: 可用的编辑器类型数组
    static func getAvailableEditorTypes() -> [EditorType] {
        return supportedTypes.filter { isEditorAvailable($0) }
    }
    
    /// 获取编辑器的系统要求描述
    /// - Parameter type: 编辑器类型
    /// - Returns: 系统要求描述
    static func getSystemRequirement(for type: EditorType) -> String {
        return type.minimumSystemVersion
    }
    
    /// 获取编辑器的详细信息
    /// - Parameter type: 编辑器类型
    /// - Returns: 编辑器信息
    static func getEditorInfo(for type: EditorType) -> EditorInfo {
        return EditorInfo(
            type: type,
            isAvailable: isEditorAvailable(type),
            systemRequirement: getSystemRequirement(for: type),
            features: type.features
        )
    }
    
    /// 验证编辑器实例
    /// - Parameter editor: 编辑器实例
    /// - Returns: 是否有效
    static func validateEditor(_ editor: EditorProtocol) -> Bool {
        return editor.isAvailable()
    }
    
    // MARK: - Private Methods
    
    /// 创建原生编辑器
    /// - Returns: 原生编辑器实例
    /// - Throws: EditorCreationError
    /// - Note: 实际的原生编辑器实现在 NativeEditorContext 中，此方法仅用于验证系统支持
    private static func createNativeEditor() throws -> EditorProtocol {
        // 检查系统版本
        guard #available(macOS 13.0, *) else {
            throw EditorCreationError.systemRequirementsNotMet(.native, "需要 macOS 13.0 或更高版本")
        }
        
        // 检查必要的框架
        guard NSClassFromString("NSTextAttachment") != nil else {
            throw EditorCreationError.systemRequirementsNotMet(.native, "NSTextAttachment 不可用")
        }
        
        // 原生编辑器的实际实现在 NativeEditorContext 中
        // 此工厂方法不直接创建编辑器实例，而是由 UnifiedEditorWrapper 管理
        throw EditorCreationError.initializationFailed(.native, NSError(domain: "EditorFactory", code: -1, userInfo: [NSLocalizedDescriptionKey: "请使用 NativeEditorContext 创建原生编辑器"]))
    }
    
    /// 检查原生编辑器支持
    /// - Returns: 是否支持原生编辑器
    private static func checkNativeEditorSupport() -> Bool {
        // 检查系统版本
        if #available(macOS 13.0, *) {
            // 检查必要的框架
            let hasNSTextAttachment = NSClassFromString("NSTextAttachment") != nil
            print("[EditorFactory] checkNativeEditorSupport:")
            print("[EditorFactory]   - macOS 13.0+ 可用: true")
            print("[EditorFactory]   - NSTextAttachment 可用: \(hasNSTextAttachment)")
            return hasNSTextAttachment
        }
        print("[EditorFactory] checkNativeEditorSupport: macOS 13.0+ 不可用")
        return false
    }
}

/// 编辑器信息
struct EditorInfo {
    let type: EditorType
    let isAvailable: Bool
    let systemRequirement: String
    let features: [String]
    
    var displayName: String {
        return type.displayName
    }
    
    var description: String {
        return type.description
    }
    
    var icon: String {
        return type.icon
    }
}