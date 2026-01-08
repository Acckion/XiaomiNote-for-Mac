//
//  EditorPreferencesServiceTests.swift
//  MiNoteMac
//
//  编辑器偏好设置服务测试
//

import XCTest
@testable import MiNoteLibrary

@MainActor
final class EditorPreferencesServiceTests: XCTestCase {
    
    var service: EditorPreferencesService!
    var userDefaults: UserDefaults!
    
    override func setUpWithError() throws {
        // 使用测试专用的 UserDefaults
        userDefaults = UserDefaults(suiteName: "test.editor.preferences")
        userDefaults.removePersistentDomain(forName: "test.editor.preferences")
        
        // 注意：这里需要修改 EditorPreferencesService 以支持依赖注入
        // 目前使用 shared 实例进行测试
        service = EditorPreferencesService.shared
    }
    
    override func tearDownWithError() throws {
        userDefaults.removePersistentDomain(forName: "test.editor.preferences")
        userDefaults = nil
        service = nil
    }
    
    // MARK: - 初始化测试
    
    func testDefaultEditorSelection() {
        // 测试默认编辑器选择逻辑
        let availableTypes = service.getAvailableEditorTypes()
        XCTAssertFalse(availableTypes.isEmpty, "应该至少有一个可用的编辑器类型")
        
        let currentType = service.getCurrentEditorType()
        XCTAssertTrue(availableTypes.contains(currentType), "当前编辑器类型应该在可用类型中")
    }
    
    func testNativeEditorAvailabilityCheck() {
        let isAvailable = service.isEditorTypeAvailable(.native)
        
        // 在 macOS 13.0+ 上应该可用
        if #available(macOS 13.0, *) {
            XCTAssertTrue(isAvailable, "在支持的系统版本上原生编辑器应该可用")
        } else {
            XCTAssertFalse(isAvailable, "在不支持的系统版本上原生编辑器应该不可用")
        }
    }
    
    func testWebEditorAlwaysAvailable() {
        let isAvailable = service.isEditorTypeAvailable(.web)
        XCTAssertTrue(isAvailable, "Web 编辑器应该总是可用")
    }
    
    // MARK: - 编辑器切换测试
    
    func testEditorTypeSwitch() {
        let availableTypes = service.getAvailableEditorTypes()
        
        for type in availableTypes {
            let success = service.setEditorType(type)
            XCTAssertTrue(success, "设置可用的编辑器类型应该成功")
            XCTAssertEqual(service.getCurrentEditorType(), type, "编辑器类型应该正确设置")
        }
    }
    
    func testInvalidEditorTypeSwitch() {
        // 如果原生编辑器不可用，尝试设置应该失败
        if !service.isEditorTypeAvailable(.native) {
            let success = service.setEditorType(.native)
            XCTAssertFalse(success, "设置不可用的编辑器类型应该失败")
        }
    }
    
    // MARK: - 可用性重新检查测试
    
    func testRecheckAvailability() {
        let initialAvailability = service.isNativeEditorAvailable
        
        service.recheckNativeEditorAvailability()
        
        // 可用性状态应该保持一致（在同一测试环境中）
        XCTAssertEqual(service.isNativeEditorAvailable, initialAvailability, "重新检查后可用性应该保持一致")
    }
    
    func testFallbackToWebEditor() {
        // 模拟原生编辑器变为不可用的情况
        // 注意：这个测试需要修改 EditorPreferencesService 以支持模拟
        // 目前只能测试逻辑的正确性
        
        let availableTypes = service.getAvailableEditorTypes()
        XCTAssertTrue(availableTypes.contains(.web), "Web 编辑器应该总是在可用类型中")
    }
    
    // MARK: - UserDefaults 扩展测试
    
    func testUserDefaultsExtension() {
        let availableTypes = service.getAvailableEditorTypes()
        
        for type in availableTypes {
            userDefaults.editorType = type
            XCTAssertEqual(userDefaults.editorType, type, "UserDefaults 扩展应该正确工作")
        }
    }
}