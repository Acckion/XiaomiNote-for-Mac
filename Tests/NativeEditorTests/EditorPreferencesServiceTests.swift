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

        // 注意：这里使用 shared 实例进行测试
        service = EditorPreferencesService.shared
    }

    override func tearDownWithError() throws {
        userDefaults.removePersistentDomain(forName: "test.editor.preferences")
        userDefaults = nil
        service = nil
    }

    // MARK: - 初始化测试

    func testDefaultEditorSelection() {
        let currentType = service.getCurrentEditorType()
        XCTAssertEqual(currentType, .native, "应该始终返回原生编辑器")
    }

    func testNativeEditorAvailabilityCheck() {
        let isAvailable = service.isNativeEditorAvailable

        // 在 macOS 13.0+ 上应该可用
        if #available(macOS 13.0, *) {
            XCTAssertTrue(isAvailable, "在支持的系统版本上原生编辑器应该可用")
        } else {
            XCTAssertFalse(isAvailable, "在不支持的系统版本上原生编辑器应该不可用")
        }
    }

    // MARK: - 可用性重新检查测试

    func testRecheckAvailability() {
        let initialAvailability = service.isNativeEditorAvailable

        service.recheckNativeEditorAvailability()

        // 可用性状态应该保持一致（在同一测试环境中）
        XCTAssertEqual(service.isNativeEditorAvailable, initialAvailability, "重新检查后可用性应该保持一致")
    }

    // MARK: - 编辑器类型测试

    func testEditorTypeAlwaysNative() {
        // 验证编辑器类型始终为原生编辑器
        let currentType = service.getCurrentEditorType()
        XCTAssertEqual(currentType, .native, "编辑器类型应该始终为原生编辑器")

        // 多次调用应该返回相同结果
        for _ in 0 ..< 5 {
            XCTAssertEqual(service.getCurrentEditorType(), .native, "编辑器类型应该始终为原生编辑器")
        }
    }

    // MARK: - 旧数据清理测试

    func testOldPreferencesCleanup() {
        // 设置旧的编辑器类型偏好
        userDefaults.set("web", forKey: "selectedEditorType")

        // 重新初始化服务应该清理旧的偏好设置
        let newService = EditorPreferencesService(userDefaults: userDefaults)

        // 验证旧的偏好设置已被清理
        let savedType = userDefaults.string(forKey: "selectedEditorType")
        XCTAssertNil(savedType, "旧的编辑器类型偏好设置应该被清理")

        // 验证当前编辑器类型为原生编辑器
        XCTAssertEqual(newService.getCurrentEditorType(), .native, "应该返回原生编辑器")
    }
}
