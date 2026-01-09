//
//  NativeEditorContextTests.swift
//  MiNoteMac
//
//  原生编辑器上下文测试
//

import XCTest
import Combine
@testable import MiNoteLibrary

@MainActor
final class NativeEditorContextTests: XCTestCase {
    
    var context: NativeEditorContext!
    var cancellables: Set<AnyCancellable>!
    
    override func setUpWithError() throws {
        context = NativeEditorContext()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDownWithError() throws {
        cancellables.removeAll()
        context = nil
    }
    
    // MARK: - 初始化测试
    
    func testInitialState() {
        XCTAssertTrue(context.currentFormats.isEmpty, "初始格式集合应该为空")
        XCTAssertEqual(context.cursorPosition, 0, "初始光标位置应该为 0")
        XCTAssertEqual(context.selectedRange.location, 0, "初始选择范围位置应该为 0")
        XCTAssertEqual(context.selectedRange.length, 0, "初始选择范围长度应该为 0")
        XCTAssertFalse(context.isEditorFocused, "初始焦点状态应该为 false")
        XCTAssertTrue(context.attributedText.characters.isEmpty, "初始内容应该为空")
    }
    
    // MARK: - 格式应用测试
    
    func testApplyFormat() {
        let expectation = XCTestExpectation(description: "格式变化发布")
        
        context.formatChangePublisher
            .sink { format in
                XCTAssertEqual(format, .bold, "应该发布正确的格式变化")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        context.applyFormat(.bold)
        
        XCTAssertTrue(context.currentFormats.contains(.bold), "格式应该被添加到当前格式集合")
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testToggleFormat() {
        // 首次应用格式
        context.applyFormat(.italic)
        XCTAssertTrue(context.currentFormats.contains(.italic), "格式应该被添加")
        
        // 再次应用相同格式应该移除
        context.applyFormat(.italic)
        XCTAssertFalse(context.currentFormats.contains(.italic), "格式应该被移除")
    }
    
    func testMultipleFormats() {
        context.applyFormat(.bold)
        context.applyFormat(.italic)
        context.applyFormat(.underline)
        
        XCTAssertTrue(context.currentFormats.contains(.bold), "应该包含加粗格式")
        XCTAssertTrue(context.currentFormats.contains(.italic), "应该包含斜体格式")
        XCTAssertTrue(context.currentFormats.contains(.underline), "应该包含下划线格式")
        XCTAssertEqual(context.currentFormats.count, 3, "应该有 3 个格式")
    }
    
    // MARK: - 特殊元素插入测试
    
    func testInsertSpecialElement() {
        let expectation = XCTestExpectation(description: "特殊元素插入发布")
        let testElement = SpecialElement.checkbox(checked: false, level: 3)
        
        context.specialElementPublisher
            .sink { element in
                if case .checkbox(let checked, let level) = element {
                    XCTAssertFalse(checked, "复选框应该未选中")
                    XCTAssertEqual(level, 3, "复选框级别应该为 3")
                    expectation.fulfill()
                } else {
                    XCTFail("应该接收到复选框元素")
                }
            }
            .store(in: &cancellables)
        
        context.insertSpecialElement(testElement)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testInsertHorizontalRule() {
        let expectation = XCTestExpectation(description: "分割线插入发布")
        
        context.specialElementPublisher
            .sink { element in
                if case .horizontalRule = element {
                    expectation.fulfill()
                } else {
                    XCTFail("应该接收到分割线元素")
                }
            }
            .store(in: &cancellables)
        
        context.insertSpecialElement(.horizontalRule)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - 光标和选择测试
    
    func testUpdateCursorPosition() {
        context.updateCursorPosition(10)
        XCTAssertEqual(context.cursorPosition, 10, "光标位置应该正确更新")
    }
    
    func testUpdateSelectedRange() {
        let range = NSRange(location: 5, length: 10)
        context.updateSelectedRange(range)
        
        XCTAssertEqual(context.selectedRange.location, 5, "选择范围位置应该正确更新")
        XCTAssertEqual(context.selectedRange.length, 10, "选择范围长度应该正确更新")
    }
    
    // MARK: - 焦点状态测试
    
    func testSetEditorFocused() {
        context.setEditorFocused(true)
        XCTAssertTrue(context.isEditorFocused, "编辑器焦点状态应该为 true")
        
        context.setEditorFocused(false)
        XCTAssertFalse(context.isEditorFocused, "编辑器焦点状态应该为 false")
    }
    
    // MARK: - 内容更新测试
    
    func testUpdateContent() {
        let testContent = AttributedString("测试内容")
        context.updateContent(testContent)
        
        XCTAssertEqual(String(context.attributedText.characters), "测试内容", "内容应该正确更新")
    }
    
    // MARK: - 发布者测试
    
    func testFormatChangePublisher() {
        let expectation = XCTestExpectation(description: "格式变化发布者")
        expectation.expectedFulfillmentCount = 2
        
        var receivedFormats: [TextFormat] = []
        
        context.formatChangePublisher
            .sink { format in
                receivedFormats.append(format)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        context.applyFormat(.bold)
        context.applyFormat(.italic)
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(receivedFormats.count, 2, "应该接收到 2 个格式变化")
        XCTAssertTrue(receivedFormats.contains(.bold), "应该包含加粗格式")
        XCTAssertTrue(receivedFormats.contains(.italic), "应该包含斜体格式")
    }
    
    func testSpecialElementPublisher() {
        let expectation = XCTestExpectation(description: "特殊元素发布者")
        expectation.expectedFulfillmentCount = 2
        
        var receivedElements: [SpecialElement] = []
        
        context.specialElementPublisher
            .sink { element in
                receivedElements.append(element)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        context.insertSpecialElement(.horizontalRule)
        context.insertSpecialElement(.checkbox(checked: true, level: 1))
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(receivedElements.count, 2, "应该接收到 2 个特殊元素")
    }
}