//
//  EditorChangeTrackerTests.swift
//  MiNoteMac
//
//  EditorChangeTracker 单元测试
//

import XCTest
@testable import MiNoteMac

@MainActor
final class EditorChangeTrackerTests: XCTestCase {
    
    var tracker: EditorChangeTracker!
    
    override func setUp() async throws {
        tracker = EditorChangeTracker()
    }
    
    override func tearDown() async throws {
        tracker = nil
    }
    
    // MARK: - 版本号递增测试
    
    func testInitialState() {
        XCTAssertEqual(tracker.contentVersion, 0, "初始版本号应为 0")
        XCTAssertFalse(tracker.needsSave, "初始状态不需要保存")
        XCTAssertEqual(tracker.versionDelta, 0, "初始版本差异应为 0")
    }
    
    func testTextDidChange() {
        tracker.textDidChange()
        
        XCTAssertEqual(tracker.contentVersion, 1, "文本变化后版本号应为 1")
        XCTAssertTrue(tracker.needsSave, "文本变化后需要保存")
    }
    
    func testFormatDidChange() {
        tracker.formatDidChange()
        
        XCTAssertEqual(tracker.contentVersion, 1, "格式变化后版本号应为 1")
        XCTAssertTrue(tracker.needsSave, "格式变化后需要保存")
    }
    
    func testAttachmentDidChange() {
        tracker.attachmentDidChange()
        
        XCTAssertEqual(tracker.contentVersion, 1, "附件变化后版本号应为 1")
        XCTAssertTrue(tracker.needsSave, "附件变化后需要保存")
    }
    
    func testMultipleChanges() {
        tracker.textDidChange()
        tracker.formatDidChange()
        tracker.attachmentDidChange()
        
        XCTAssertEqual(tracker.contentVersion, 3, "多次变化后版本号应为 3")
        XCTAssertTrue(tracker.needsSave, "多次变化后需要保存")
        XCTAssertEqual(tracker.versionDelta, 3, "版本差异应为 3")
    }
    
    // MARK: - 程序化修改测试
    
    func testProgrammaticChange() {
        tracker.performProgrammaticChange {
            // 模拟加载内容
        }
        
        XCTAssertEqual(tracker.contentVersion, 0, "程序化修改不应增加版本号")
        XCTAssertFalse(tracker.needsSave, "程序化修改后不需要保存")
    }
    
    func testProgrammaticChangeWithTextChange() {
        tracker.performProgrammaticChange {
            tracker.textDidChange()
        }
        
        XCTAssertEqual(tracker.contentVersion, 0, "程序化修改中的文本变化不应增加版本号")
        XCTAssertFalse(tracker.needsSave, "程序化修改后不需要保存")
    }
    
    func testNestedProgrammaticChange() {
        tracker.performProgrammaticChange {
            tracker.performProgrammaticChange {
                tracker.textDidChange()
            }
        }
        
        XCTAssertEqual(tracker.contentVersion, 0, "嵌套程序化修改不应增加版本号")
        XCTAssertFalse(tracker.needsSave, "嵌套程序化修改后不需要保存")
    }
    
    func testAsyncProgrammaticChange() async {
        await tracker.performProgrammaticChange {
            tracker.textDidChange()
        }
        
        XCTAssertEqual(tracker.contentVersion, 0, "异步程序化修改不应增加版本号")
        XCTAssertFalse(tracker.needsSave, "异步程序化修改后不需要保存")
    }
    
    // MARK: - 保存状态管理测试
    
    func testSaveSuccess() {
        tracker.textDidChange()
        XCTAssertTrue(tracker.needsSave, "编辑后需要保存")
        
        tracker.didSaveSuccessfully()
        
        XCTAssertFalse(tracker.needsSave, "保存成功后不需要保存")
        XCTAssertEqual(tracker.versionDelta, 0, "保存成功后版本差异应为 0")
    }
    
    func testSaveFailure() {
        tracker.textDidChange()
        let versionBeforeSave = tracker.contentVersion
        
        tracker.didSaveFail()
        
        XCTAssertEqual(tracker.contentVersion, versionBeforeSave, "保存失败后版本号应保持不变")
        XCTAssertTrue(tracker.needsSave, "保存失败后仍需要保存")
    }
    
    func testMultipleSaveCycles() {
        // 第一次编辑和保存
        tracker.textDidChange()
        tracker.didSaveSuccessfully()
        XCTAssertFalse(tracker.needsSave)
        
        // 第二次编辑和保存
        tracker.formatDidChange()
        XCTAssertTrue(tracker.needsSave)
        tracker.didSaveSuccessfully()
        XCTAssertFalse(tracker.needsSave)
        
        // 第三次编辑和保存
        tracker.attachmentDidChange()
        XCTAssertTrue(tracker.needsSave)
        tracker.didSaveSuccessfully()
        XCTAssertFalse(tracker.needsSave)
    }
    
    // MARK: - 并发编辑检测测试
    
    func testHasNewEditsSince() {
        tracker.textDidChange() // 版本 1
        let savingVersion = tracker.contentVersion
        
        XCTAssertFalse(tracker.hasNewEditsSince(savingVersion: savingVersion), "保存版本与当前版本相同，无新编辑")
        
        tracker.formatDidChange() // 版本 2
        
        XCTAssertTrue(tracker.hasNewEditsSince(savingVersion: savingVersion), "保存后有新编辑")
    }
    
    func testConcurrentEditingScenario() {
        // 模拟并发编辑场景
        tracker.textDidChange() // 版本 1
        tracker.formatDidChange() // 版本 2
        
        let savingVersion = tracker.contentVersion // 保存版本 2
        
        // 保存期间用户继续编辑
        tracker.textDidChange() // 版本 3
        
        XCTAssertTrue(tracker.hasNewEditsSince(savingVersion: savingVersion), "保存期间有新编辑")
        XCTAssertEqual(tracker.contentVersion, 3, "当前版本应为 3")
        
        // 第一次保存完成
        // 注意：这里不调用 didSaveSuccessfully，因为有新编辑
        
        // 再次保存
        let secondSavingVersion = tracker.contentVersion // 保存版本 3
        tracker.didSaveSuccessfully()
        
        XCTAssertFalse(tracker.needsSave, "第二次保存后不需要保存")
        XCTAssertFalse(tracker.hasNewEditsSince(savingVersion: secondSavingVersion), "第二次保存后无新编辑")
    }
    
    // MARK: - 重置测试
    
    func testReset() {
        tracker.textDidChange()
        tracker.formatDidChange()
        
        XCTAssertTrue(tracker.needsSave, "重置前需要保存")
        
        tracker.reset()
        
        XCTAssertEqual(tracker.contentVersion, 0, "重置后版本号应为 0")
        XCTAssertFalse(tracker.needsSave, "重置后不需要保存")
        XCTAssertEqual(tracker.versionDelta, 0, "重置后版本差异应为 0")
    }
    
    func testResetAfterSave() {
        tracker.textDidChange()
        tracker.didSaveSuccessfully()
        
        tracker.reset()
        
        XCTAssertEqual(tracker.contentVersion, 0, "重置后版本号应为 0")
        XCTAssertFalse(tracker.needsSave, "重置后不需要保存")
    }
    
    // MARK: - 调试信息测试
    
    func testGetDebugInfo() {
        tracker.textDidChange()
        
        let debugInfo = tracker.getDebugInfo()
        
        XCTAssertTrue(debugInfo.contains("contentVersion: 1"), "调试信息应包含版本号")
        XCTAssertTrue(debugInfo.contains("needsSave: true"), "调试信息应包含保存状态")
    }
    
    // MARK: - 边界测试
    
    func testLargeNumberOfEdits() {
        // 测试大量编辑操作
        for _ in 0..<1000 {
            tracker.textDidChange()
        }
        
        XCTAssertEqual(tracker.contentVersion, 1000, "1000次编辑后版本号应为 1000")
        XCTAssertTrue(tracker.needsSave, "大量编辑后需要保存")
    }
    
    func testAlternatingEditAndSave() {
        // 测试交替编辑和保存
        for i in 1...10 {
            tracker.textDidChange()
            XCTAssertEqual(tracker.contentVersion, i, "第\(i)次编辑后版本号应为 \(i)")
            XCTAssertTrue(tracker.needsSave, "第\(i)次编辑后需要保存")
            
            tracker.didSaveSuccessfully()
            XCTAssertFalse(tracker.needsSave, "第\(i)次保存后不需要保存")
        }
    }
    
    // MARK: - 性能测试
    
    func testPerformanceOfVersionCheck() {
        // 测试版本号检查的性能
        tracker.textDidChange()
        
        measure {
            for _ in 0..<10000 {
                _ = tracker.needsSave
            }
        }
    }
    
    func testPerformanceOfTextDidChange() {
        // 测试 textDidChange 的性能
        measure {
            for _ in 0..<1000 {
                tracker.textDidChange()
            }
        }
    }
}
