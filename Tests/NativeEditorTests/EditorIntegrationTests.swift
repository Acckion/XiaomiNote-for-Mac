//
//  EditorIntegrationTests.swift
//  MiNoteLibraryTests
//
//  编辑器集成测试 - 验证编辑器切换和数据同步功能
//  需求: 1.2, 1.3, 7.1-7.12
//

import XCTest
@testable import MiNoteLibrary

/// 编辑器集成测试
@MainActor
final class EditorIntegrationTests: XCTestCase {
    
    // MARK: - Properties
    
    var preferencesService: EditorPreferencesService!
    var nativeEditorContext: NativeEditorContext!
    var formatConverter: XiaoMiFormatConverter!
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // 使用测试专用的 UserDefaults
        let testDefaults = UserDefaults(suiteName: "com.minote.test.integration")!
        testDefaults.removePersistentDomain(forName: "com.minote.test.integration")
        
        preferencesService = EditorPreferencesService(userDefaults: testDefaults)
        nativeEditorContext = NativeEditorContext()
        formatConverter = XiaoMiFormatConverter.shared
    }
    
    override func tearDown() async throws {
        preferencesService = nil
        nativeEditorContext = nil
        formatConverter = nil
        try await super.tearDown()
    }
    
    // MARK: - 编辑器切换测试
    
    /// 测试编辑器类型切换
    func testEditorTypeSwitch() async throws {
        // 初始状态
        let initialType = preferencesService.selectedEditorType
        
        // 切换到 Web 编辑器
        let switchToWeb = preferencesService.setEditorType(.web)
        XCTAssertTrue(switchToWeb, "应该能够切换到 Web 编辑器")
        XCTAssertEqual(preferencesService.selectedEditorType, .web)
        
        // 如果原生编辑器可用，测试切换到原生编辑器
        if preferencesService.isNativeEditorAvailable {
            let switchToNative = preferencesService.setEditorType(.native)
            XCTAssertTrue(switchToNative, "应该能够切换到原生编辑器")
            XCTAssertEqual(preferencesService.selectedEditorType, .native)
        }
        
        // 恢复初始状态
        _ = preferencesService.setEditorType(initialType)
    }
    
    /// 测试编辑器工厂创建
    func testEditorFactoryCreation() async throws {
        // 测试编辑器可用性检查
        XCTAssertTrue(EditorFactory.isEditorAvailable(.web), "Web 编辑器应该可用")
        
        // 测试获取可用编辑器类型
        let availableTypes = EditorFactory.getAvailableEditorTypes()
        XCTAssertTrue(availableTypes.contains(.web), "可用类型应包含 Web 编辑器")
        
        // 测试获取编辑器信息
        let webInfo = EditorFactory.getEditorInfo(for: .web)
        XCTAssertTrue(webInfo.isAvailable, "Web 编辑器信息应显示可用")
        
        // 测试原生编辑器可用性（如果可用）
        if EditorFactory.isEditorAvailable(.native) {
            let nativeInfo = EditorFactory.getEditorInfo(for: .native)
            XCTAssertTrue(nativeInfo.isAvailable, "原生编辑器信息应显示可用")
        }
    }
    
    // MARK: - 格式转换测试
    
    /// 测试简单文本的格式转换
    func testSimpleTextFormatConversion() async throws {
        let xml = "<text indent=\"1\">测试文本</text>"
        
        // XML -> AttributedString
        let attributedString = try formatConverter.xmlToAttributedString(xml)
        XCTAssertFalse(attributedString.characters.isEmpty, "转换后的文本不应为空")
        
        // AttributedString -> XML
        let convertedXML = try formatConverter.attributedStringToXML(attributedString)
        XCTAssertFalse(convertedXML.isEmpty, "转换后的 XML 不应为空")
    }
    
    /// 测试复杂文档的格式转换
    func testComplexDocumentFormatConversion() async throws {
        let complexXML = """
        <text indent="1"><b>加粗文本</b></text>
        <text indent="1"><i>斜体文本</i></text>
        <text indent="1"><u>下划线文本</u></text>
        <bullet indent="1" />项目符号</bullet>
        <order indent="1" inputNumber="1" />有序列表</order>
        <hr />
        <quote><text indent="1">引用内容</text></quote>
        """
        
        // XML -> AttributedString
        let attributedString = try formatConverter.xmlToAttributedString(complexXML)
        XCTAssertFalse(attributedString.characters.isEmpty, "转换后的文本不应为空")
        
        // AttributedString -> XML
        let convertedXML = try formatConverter.attributedStringToXML(attributedString)
        XCTAssertFalse(convertedXML.isEmpty, "转换后的 XML 不应为空")
    }
    
    /// 测试格式转换的往返一致性
    func testRoundTripConsistency() async throws {
        let originalXML = "<text indent=\"1\">测试往返转换</text>"
        
        // 第一次转换
        let attributedString1 = try formatConverter.xmlToAttributedString(originalXML)
        let xml1 = try formatConverter.attributedStringToXML(attributedString1)
        
        // 第二次转换
        let attributedString2 = try formatConverter.xmlToAttributedString(xml1)
        let xml2 = try formatConverter.attributedStringToXML(attributedString2)
        
        // 验证两次转换结果一致
        XCTAssertEqual(xml1, xml2, "两次往返转换的结果应该一致")
    }
    
    // MARK: - 编辑器上下文测试
    
    /// 测试编辑器上下文的格式应用
    func testEditorContextFormatApplication() async throws {
        // 应用加粗格式
        nativeEditorContext.applyFormat(.bold)
        XCTAssertTrue(nativeEditorContext.isFormatActive(.bold), "加粗格式应该被激活")
        
        // 应用斜体格式
        nativeEditorContext.applyFormat(.italic)
        XCTAssertTrue(nativeEditorContext.isFormatActive(.italic), "斜体格式应该被激活")
        
        // 取消加粗格式
        nativeEditorContext.applyFormat(.bold)
        XCTAssertFalse(nativeEditorContext.isFormatActive(.bold), "加粗格式应该被取消")
    }
    
    /// 测试编辑器上下文的特殊元素插入
    func testEditorContextSpecialElementInsertion() async throws {
        var receivedElement: SpecialElement?
        
        // 订阅特殊元素发布者
        let cancellable = nativeEditorContext.specialElementPublisher
            .sink { element in
                receivedElement = element
            }
        
        // 插入分割线
        nativeEditorContext.insertHorizontalRule()
        
        // 等待异步操作完成
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        XCTAssertNotNil(receivedElement, "应该收到特殊元素")
        if case .horizontalRule = receivedElement {
            // 正确
        } else {
            XCTFail("应该收到分割线元素")
        }
        
        cancellable.cancel()
    }
    
    /// 测试编辑器上下文的内容加载
    func testEditorContextContentLoading() async throws {
        let xml = "<text indent=\"1\">测试内容加载</text>"
        
        // 加载 XML 内容
        nativeEditorContext.loadFromXML(xml)
        
        // 验证内容已加载
        XCTAssertFalse(nativeEditorContext.attributedText.characters.isEmpty, "内容应该已加载")
    }
    
    // MARK: - 性能测试
    
    /// 测试编辑器切换性能
    func testEditorSwitchPerformance() async throws {
        measure {
            // 测试编辑器可用性检查性能
            let _ = EditorFactory.isEditorAvailable(.web)
            let _ = EditorFactory.getEditorInfo(for: .web)
            
            // 如果原生编辑器可用，也测试原生编辑器
            if EditorFactory.isEditorAvailable(.native) {
                let _ = EditorFactory.getEditorInfo(for: .native)
            }
        }
    }
    
    /// 测试格式转换性能
    func testFormatConversionPerformance() async throws {
        let xml = "<text indent=\"1\">性能测试文本</text>"
        
        measure {
            do {
                let attributedString = try formatConverter.xmlToAttributedString(xml)
                let _ = try formatConverter.attributedStringToXML(attributedString)
            } catch {
                XCTFail("格式转换失败: \(error)")
            }
        }
    }
}
