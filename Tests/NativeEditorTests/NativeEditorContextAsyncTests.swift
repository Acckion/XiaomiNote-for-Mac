//
//  NativeEditorContextAsyncTests.swift
//  MiNoteMac
//
//  测试 NativeEditorContext 的异步状态更新方法
//

import XCTest
@testable import MiNoteMac

@MainActor
final class NativeEditorContextAsyncTests: XCTestCase {
    
    var editorContext: NativeEditorContext!
    
    override func setUp() async throws {
        editorContext = NativeEditorContext()
    }
    
    override func tearDown() async throws {
        editorContext = nil
    }
    
    // MARK: - updateNSContentAsync 测试
    
    /// 测试异步更新内容方法
    func testUpdateNSContentAsync() async throws {
        // 1. 创建测试内容
        let testText = "测试异步更新内容"
        let attributedString = NSMutableAttributedString(string: testText)
        
        // 2. 调用异步更新方法
        editorContext.updateNSContentAsync(attributedString)
        
        // 3. 等待异步操作完成
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // 4. 验证内容已更新
        XCTAssertEqual(editorContext.nsAttributedText.string, testText, "内容应该已更新")
        XCTAssertTrue(editorContext.hasUnsavedChanges, "应该标记为有未保存的更改")
    }
    
    /// 测试异步更新内容不会阻塞主线程
    func testUpdateNSContentAsyncNonBlocking() async throws {
        // 1. 创建测试内容
        let testText = "测试非阻塞更新"
        let attributedString = NSMutableAttributedString(string: testText)
        
        // 2. 记录开始时间
        let startTime = Date()
        
        // 3. 调用异步更新方法（不等待）
        editorContext.updateNSContentAsync(attributedString)
        
        // 4. 立即检查时间（应该几乎没有延迟）
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        // 5. 验证调用是非阻塞的（应该在 10ms 内返回）
        XCTAssertLessThan(elapsedTime, 0.01, "异步调用应该立即返回，不阻塞主线程")
        
        // 6. 等待异步操作完成
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // 7. 验证内容已更新
        XCTAssertEqual(editorContext.nsAttributedText.string, testText, "内容应该已更新")
    }
    
    // MARK: - updateCurrentFormatsAsync 测试
    
    /// 测试异步更新格式状态方法
    func testUpdateCurrentFormatsAsync() async throws {
        // 1. 创建带格式的测试内容
        let testText = "测试格式"
        let attributedString = NSMutableAttributedString(string: testText)
        
        // 添加加粗格式
        let boldFont = NSFont.boldSystemFont(ofSize: 14)
        attributedString.addAttribute(.font, value: boldFont, range: NSRange(location: 0, length: testText.count))
        
        // 2. 更新编辑器内容
        editorContext.updateNSContent(attributedString)
        editorContext.updateCursorPosition(0)
        
        // 3. 调用异步更新格式方法
        editorContext.updateCurrentFormatsAsync()
        
        // 4. 等待异步操作完成
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // 5. 验证格式状态已更新
        XCTAssertTrue(editorContext.currentFormats.contains(.bold), "应该检测到加粗格式")
    }
    
    /// 测试异步更新格式不会阻塞主线程
    func testUpdateCurrentFormatsAsyncNonBlocking() async throws {
        // 1. 创建测试内容
        let testText = "测试非阻塞格式更新"
        let attributedString = NSMutableAttributedString(string: testText)
        editorContext.updateNSContent(attributedString)
        editorContext.updateCursorPosition(0)
        
        // 2. 记录开始时间
        let startTime = Date()
        
        // 3. 调用异步更新方法（不等待）
        editorContext.updateCurrentFormatsAsync()
        
        // 4. 立即检查时间（应该几乎没有延迟）
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        // 5. 验证调用是非阻塞的（应该在 10ms 内返回）
        XCTAssertLessThan(elapsedTime, 0.01, "异步调用应该立即返回，不阻塞主线程")
    }
    
    // MARK: - 并发安全性测试
    
    /// 测试多次并发调用异步更新方法的安全性
    func testConcurrentAsyncUpdates() async throws {
        // 1. 创建多个测试内容
        let contents = (1...10).map { i in
            NSMutableAttributedString(string: "测试内容 \(i)")
        }
        
        // 2. 并发调用异步更新方法
        await withTaskGroup(of: Void.self) { group in
            for content in contents {
                group.addTask { @MainActor in
                    self.editorContext.updateNSContentAsync(content)
                }
            }
        }
        
        // 3. 等待所有异步操作完成
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // 4. 验证最终状态一致（应该是最后一次更新的内容）
        XCTAssertFalse(editorContext.nsAttributedText.string.isEmpty, "内容不应该为空")
        XCTAssertTrue(editorContext.hasUnsavedChanges, "应该标记为有未保存的更改")
    }
    
    // MARK: - 与同步方法的对比测试
    
    /// 测试异步方法和同步方法的结果一致性
    func testAsyncSyncConsistency() async throws {
        // 1. 创建测试内容
        let testText = "测试一致性"
        let attributedString = NSMutableAttributedString(string: testText)
        
        // 2. 使用同步方法更新
        let context1 = NativeEditorContext()
        context1.updateNSContent(attributedString)
        
        // 3. 使用异步方法更新
        let context2 = NativeEditorContext()
        context2.updateNSContentAsync(attributedString)
        
        // 4. 等待异步操作完成
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // 5. 验证结果一致
        XCTAssertEqual(context1.nsAttributedText.string, context2.nsAttributedText.string, "同步和异步方法的结果应该一致")
        XCTAssertEqual(context1.hasUnsavedChanges, context2.hasUnsavedChanges, "未保存状态应该一致")
    }
}
