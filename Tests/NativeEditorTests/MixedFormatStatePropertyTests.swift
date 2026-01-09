//
//  MixedFormatStatePropertyTests.swift
//  MiNoteLibraryTests
//
//  混合格式状态处理属性测试
//  属性 14: 混合格式状态处理
//  验证需求: 6.1, 6.2
//
//  Feature: format-menu-fix, Property 14: 混合格式状态处理
//

import XCTest
import AppKit
@testable import MiNoteLibrary

/// 混合格式状态处理属性测试
/// 
/// 本测试套件使用基于属性的测试方法，验证混合格式状态检测的正确性。
/// 每个测试运行 100 次迭代，确保在各种输入条件下混合格式状态检测的准确性。
@MainActor
final class MixedFormatStatePropertyTests: XCTestCase {
    
    // MARK: - Properties
    
    var editorContext: NativeEditorContext!
    var mixedFormatHandler: MixedFormatStateHandler!
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        editorContext = NativeEditorContext()
        mixedFormatHandler = MixedFormatStateHandler.shared
    }
    
    override func tearDown() async throws {
        editorContext = nil
        mixedFormatHandler = nil
        try await super.tearDown()
    }
    
    // MARK: - 属性 14: 混合格式状态处理
    // 验证需求: 6.1, 6.2
    
    /// 属性测试：部分加粗文本的混合格式状态检测
    /// 
    /// **属性**: 对于任何包含部分加粗部分非加粗的选中文本，格式菜单应该显示加粗按钮为部分激活状态或根据主要格式显示
    /// **验证需求**: 6.1
    /// 
    /// 测试策略：
    /// 1. 生成随机文本
    /// 2. 在文本的一部分应用加粗格式
    /// 3. 选中包含加粗和非加粗的范围
    /// 4. 验证混合格式状态被正确检测
    func testProperty14_PartialBoldMixedFormatStateDetection() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 部分加粗混合格式状态检测 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机文本
            let testText = generateRandomText(minLength: 40, maxLength: 100)
            let textLength = testText.count
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            let normalFont = NSFont.systemFont(ofSize: 15)
            attributedString.addAttribute(.font, value: normalFont, range: NSRange(location: 0, length: textLength))
            
            // 3. 在文本的一部分应用加粗格式（确保不是全部）
            let boldStart = Int.random(in: 5..<(textLength / 2))
            let boldLength = Int.random(in: 5..<min(20, textLength - boldStart - 5))
            let boldRange = NSRange(location: boldStart, length: boldLength)
            
            let fontManager = NSFontManager.shared
            attributedString.enumerateAttribute(.font, in: boldRange, options: []) { value, attrRange, _ in
                if let font = value as? NSFont {
                    let boldFont = fontManager.convert(font, toHaveTrait: .boldFontMask)
                    attributedString.addAttribute(.font, value: boldFont, range: attrRange)
                }
            }
            
            // 4. 选中包含加粗和非加粗的范围
            let selectionStart = max(0, boldStart - 5)
            let selectionEnd = min(textLength, boldStart + boldLength + 5)
            let selectionRange = NSRange(location: selectionStart, length: selectionEnd - selectionStart)
            
            // 5. 检测混合格式状态
            let state = mixedFormatHandler.detectFormatState(.bold, in: attributedString, range: selectionRange)
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(textLength), 加粗范围=\(boldRange), 选中范围=\(selectionRange)")
            print("[PropertyTest]   - 状态类型: \(state.stateType), 激活比例: \(String(format: "%.2f", state.activationRatio))")
            
            // 6. 验证混合格式状态
            // 由于选中范围包含加粗和非加粗文本，应该是部分激活状态
            XCTAssertTrue(state.shouldShowAsActive,
                         "迭代 \(iteration): 选中范围包含加粗文本，应该显示为激活状态")
            
            // 验证激活比例在合理范围内（不是 0 也不是 1）
            XCTAssertGreaterThan(state.activationRatio, 0.0,
                                "迭代 \(iteration): 激活比例应该大于 0")
            XCTAssertLessThan(state.activationRatio, 1.0,
                             "迭代 \(iteration): 激活比例应该小于 1（因为是混合格式）")
            
            // 验证状态类型是部分激活
            XCTAssertEqual(state.stateType, .partiallyActive,
                          "迭代 \(iteration): 状态类型应该是部分激活")
        }
        
        print("[PropertyTest] ✅ 部分加粗混合格式状态检测测试完成")
    }
    
    /// 属性测试：多种混合格式状态检测
    /// 
    /// **属性**: 对于任何包含多种格式的选中文本，格式菜单应该显示所有适用格式的按钮状态
    /// **验证需求**: 6.2
    func testProperty14_MultipleMixedFormatStateDetection() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 多种混合格式状态检测 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机文本
            let testText = generateRandomText(minLength: 60, maxLength: 120)
            let textLength = testText.count
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            let normalFont = NSFont.systemFont(ofSize: 15)
            attributedString.addAttribute(.font, value: normalFont, range: NSRange(location: 0, length: textLength))
            
            // 3. 在不同部分应用不同格式
            let segment1Start = 5
            let segment1Length = min(15, textLength / 4)
            let segment1Range = NSRange(location: segment1Start, length: segment1Length)
            
            let segment2Start = segment1Start + segment1Length + 5
            let segment2Length = min(15, textLength / 4)
            let segment2Range = NSRange(location: segment2Start, length: segment2Length)
            
            // 应用加粗到第一段
            let fontManager = NSFontManager.shared
            attributedString.enumerateAttribute(.font, in: segment1Range, options: []) { value, attrRange, _ in
                if let font = value as? NSFont {
                    let boldFont = fontManager.convert(font, toHaveTrait: .boldFontMask)
                    attributedString.addAttribute(.font, value: boldFont, range: attrRange)
                }
            }
            
            // 应用下划线到第二段
            attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: segment2Range)
            
            // 4. 选中包含两种格式的范围
            let selectionStart = segment1Start
            let selectionEnd = min(textLength, segment2Start + segment2Length)
            let selectionRange = NSRange(location: selectionStart, length: selectionEnd - selectionStart)
            
            // 5. 检测所有混合格式状态
            let states = mixedFormatHandler.detectMixedFormatStates(in: attributedString, range: selectionRange)
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(textLength), 选中范围=\(selectionRange)")
            
            // 6. 验证加粗格式状态
            if let boldState = states[.bold] {
                XCTAssertTrue(boldState.shouldShowAsActive,
                             "迭代 \(iteration): 加粗格式应该显示为激活状态")
                print("[PropertyTest]   - 加粗: \(boldState.stateType), 比例: \(String(format: "%.2f", boldState.activationRatio))")
            }
            
            // 7. 验证下划线格式状态
            if let underlineState = states[.underline] {
                XCTAssertTrue(underlineState.shouldShowAsActive,
                             "迭代 \(iteration): 下划线格式应该显示为激活状态")
                print("[PropertyTest]   - 下划线: \(underlineState.stateType), 比例: \(String(format: "%.2f", underlineState.activationRatio))")
            }
        }
        
        print("[PropertyTest] ✅ 多种混合格式状态检测测试完成")
    }
    
    /// 属性测试：完全激活格式状态检测
    /// 
    /// **属性**: 对于任何选中范围内所有文本都有某格式的情况，该格式应该显示为完全激活状态
    /// **验证需求**: 6.1
    func testProperty14_FullyActiveFormatStateDetection() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 完全激活格式状态检测 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机文本
            let testText = generateRandomText(minLength: 20, maxLength: 60)
            let textLength = testText.count
            
            // 2. 设置初始文本并应用格式到全部
            let attributedString = NSMutableAttributedString(string: testText)
            let normalFont = NSFont.systemFont(ofSize: 15)
            attributedString.addAttribute(.font, value: normalFont, range: NSRange(location: 0, length: textLength))
            
            // 3. 选择一个随机范围
            let selectionStart = Int.random(in: 0..<(textLength / 2))
            let selectionLength = Int.random(in: 5..<min(30, textLength - selectionStart))
            let selectionRange = NSRange(location: selectionStart, length: selectionLength)
            
            // 4. 在选中范围内应用下划线格式
            attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: selectionRange)
            
            // 5. 检测格式状态
            let state = mixedFormatHandler.detectFormatState(.underline, in: attributedString, range: selectionRange)
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(textLength), 选中范围=\(selectionRange)")
            print("[PropertyTest]   - 状态类型: \(state.stateType), 激活比例: \(String(format: "%.2f", state.activationRatio))")
            
            // 6. 验证完全激活状态
            XCTAssertEqual(state.stateType, .fullyActive,
                          "迭代 \(iteration): 选中范围内所有文本都有下划线，应该是完全激活状态")
            XCTAssertEqual(state.activationRatio, 1.0,
                          "迭代 \(iteration): 激活比例应该是 1.0")
        }
        
        print("[PropertyTest] ✅ 完全激活格式状态检测测试完成")
    }
    
    /// 属性测试：未激活格式状态检测
    /// 
    /// **属性**: 对于任何选中范围内没有文本有某格式的情况，该格式应该显示为未激活状态
    /// **验证需求**: 6.1
    func testProperty14_InactiveFormatStateDetection() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 未激活格式状态检测 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机文本
            let testText = generateRandomText(minLength: 20, maxLength: 60)
            let textLength = testText.count
            
            // 2. 设置初始文本（不应用任何特殊格式）
            let attributedString = NSMutableAttributedString(string: testText)
            let normalFont = NSFont.systemFont(ofSize: 15)
            attributedString.addAttribute(.font, value: normalFont, range: NSRange(location: 0, length: textLength))
            
            // 3. 选择一个随机范围
            let selectionStart = Int.random(in: 0..<(textLength / 2))
            let selectionLength = Int.random(in: 5..<min(30, textLength - selectionStart))
            let selectionRange = NSRange(location: selectionStart, length: selectionLength)
            
            // 4. 检测格式状态（检测删除线，因为我们没有应用它）
            let state = mixedFormatHandler.detectFormatState(.strikethrough, in: attributedString, range: selectionRange)
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(textLength), 选中范围=\(selectionRange)")
            print("[PropertyTest]   - 状态类型: \(state.stateType), 激活比例: \(String(format: "%.2f", state.activationRatio))")
            
            // 5. 验证未激活状态
            XCTAssertEqual(state.stateType, .inactive,
                          "迭代 \(iteration): 选中范围内没有删除线，应该是未激活状态")
            XCTAssertEqual(state.activationRatio, 0.0,
                          "迭代 \(iteration): 激活比例应该是 0.0")
            XCTAssertFalse(state.shouldShowAsActive,
                          "迭代 \(iteration): 不应该显示为激活状态")
        }
        
        print("[PropertyTest] ✅ 未激活格式状态检测测试完成")
    }
    
    /// 属性测试：NativeEditorContext 混合格式状态集成
    /// 
    /// **属性**: 对于任何包含混合格式的选中文本，NativeEditorContext 应该正确更新部分激活格式集合
    /// **验证需求**: 6.2
    func testProperty14_EditorContextMixedFormatStateIntegration() async throws {
        let iterations = 50
        print("\n[PropertyTest] 开始属性测试: EditorContext 混合格式状态集成 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机文本
            let testText = generateRandomText(minLength: 40, maxLength: 80)
            let textLength = testText.count
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            let normalFont = NSFont.systemFont(ofSize: 15)
            attributedString.addAttribute(.font, value: normalFont, range: NSRange(location: 0, length: textLength))
            
            // 3. 在文本的一部分应用高亮格式
            let highlightStart = Int.random(in: 5..<(textLength / 2))
            let highlightLength = Int.random(in: 5..<min(15, textLength - highlightStart - 5))
            let highlightRange = NSRange(location: highlightStart, length: highlightLength)
            
            attributedString.addAttribute(.backgroundColor, value: NSColor.systemYellow, range: highlightRange)
            
            // 4. 更新编辑器上下文
            editorContext.updateNSContent(attributedString)
            
            // 5. 设置选中范围（包含高亮和非高亮部分）
            let selectionStart = max(0, highlightStart - 5)
            let selectionEnd = min(textLength, highlightStart + highlightLength + 5)
            let selectionRange = NSRange(location: selectionStart, length: selectionEnd - selectionStart)
            
            editorContext.updateSelectedRange(selectionRange)
            editorContext.forceUpdateFormats()
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(textLength), 高亮范围=\(highlightRange), 选中范围=\(selectionRange)")
            
            // 6. 验证部分激活格式集合
            let partiallyActive = editorContext.partiallyActiveFormats
            print("[PropertyTest]   - 部分激活格式: \(partiallyActive.map { $0.displayName })")
            
            // 高亮格式应该在部分激活集合中
            XCTAssertTrue(partiallyActive.contains(.highlight),
                         "迭代 \(iteration): 高亮格式应该在部分激活集合中")
            
            // 7. 验证激活比例
            let ratio = editorContext.formatActivationRatios[.highlight] ?? 0.0
            XCTAssertGreaterThan(ratio, 0.0,
                                "迭代 \(iteration): 高亮激活比例应该大于 0")
            XCTAssertLessThan(ratio, 1.0,
                             "迭代 \(iteration): 高亮激活比例应该小于 1")
            
            print("[PropertyTest]   - 高亮激活比例: \(String(format: "%.2f", ratio))")
        }
        
        print("[PropertyTest] ✅ EditorContext 混合格式状态集成测试完成")
    }
    
    // MARK: - 辅助方法
    
    /// 生成随机文本
    private func generateRandomText(minLength: Int, maxLength: Int) -> String {
        let length = Int.random(in: minLength...maxLength)
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "
        return String((0..<length).map { _ in characters.randomElement()! })
    }
}
