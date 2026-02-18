//
//  BaseTestCase.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  测试基类 - 为所有测试提供通用的设置和工具
//

import XCTest
@testable import MiNoteLibrary

/// 测试基类
///
/// 提供了测试所需的基础设施，包括：
/// - 依赖注入容器
/// - Mock 服务配置
/// - 通用的 setUp 和 tearDown
class BaseTestCase: XCTestCase {
    var container: DIContainer {
        DIContainer.shared
    }

    override func setUp() {
        super.setUp()
        configureMockServices()
    }

    override func tearDown() {
        container.reset()
        super.tearDown()
    }

    /// 配置 Mock 服务
    ///
    /// 子类可以重写此方法来注册自定义的 mock 服务
    /// 默认实现为空，子类根据需要添加服务注册
    func configureMockServices() {
        // 子类重写此方法来注册 mock 服务
        // 例如：
        // let mockNoteService = MockNoteService()
        // container.register(NoteServiceProtocol.self, instance: mockNoteService)
    }

    // MARK: - Helper Methods

    /// 创建测试用的笔记
    /// - Parameters:
    ///   - id: 笔记ID，默认为随机UUID
    ///   - title: 笔记标题，默认为 "Test Note"
    ///   - content: 笔记内容，默认为 "Test Content"
    ///   - folderId: 文件夹ID，默认为 "0"
    /// - Returns: 测试笔记对象
    func createTestNote(
        id: String = UUID().uuidString,
        title: String = "Test Note",
        content: String = "Test Content",
        folderId: String = "0"
    ) -> Note {
        Note(
            id: id,
            title: title,
            content: content,
            folderId: folderId,
            isStarred: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    /// 创建测试用的文件夹
    /// - Parameters:
    ///   - id: 文件夹ID，默认为随机UUID
    ///   - name: 文件夹名称，默认为 "Test Folder"
    ///   - count: 笔记数量，默认为 0
    /// - Returns: 测试文件夹对象
    func createTestFolder(
        id: String = UUID().uuidString,
        name: String = "Test Folder",
        count: Int = 0
    ) -> Folder {
        Folder(
            id: id,
            name: name,
            count: count,
            isSystem: false
        )
    }

    /// 等待异步操作完成
    /// - Parameters:
    ///   - timeout: 超时时间，默认为 5 秒
    ///   - block: 异步操作闭包
    func waitForAsync(timeout _: TimeInterval = 5.0, _ block: @escaping () async throws -> Void) async throws {
        try await block()
    }
}
