//
//  MixedFormatApplicationPropertyTests.swift
//  MiNoteLibraryTests
//
//  混合格式应用一致性属性测试
//  属性 15: 混合格式应用一致性
//  验证需求: 6.3
//
//  Feature: format-menu-fix, Property 15: 混合格式应用一致性
//

import XCTest
import AppKit
@testable import MiNoteLibrary

/// 混合格式应用一致性属性测试
/// 
/// 本测试套件使用基于属性的测试方法，验证混合格式应用的正确性。
/// 每个测试运行 100 次迭代，确保在各种输入条件下混合格式应用的一致性。
@MainActor
final class MixedFormatApplicationPropertyTests: XCTestCase {
    
    // MARK: - Properties
    
    var editorContext: NativeEditorContext!
    var mixedFormatHandler: MixedFormatStateHandler!
    var applicationHandler: MixedFormatApplicationHandler!
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        editorContext = NativeEditorContext()
        mixedFormatHandler = MixedFormatStateHandler.shared
        applicationHandler = MixedFormatApplicationHandler.shared
    }
    
    override func tearDown() async throws {
        editorContext = nil
        mixedFormatHandler = nil
        applicationHandler = nil
        try await super.tearDown()
    }
    
    // MARK: - 属性 15: 混合格式应用一致性
    // 验证需求: 6.3
    
    /// 属性测试：混合格式应用到整个选中范围
    /// 
    /// **属性**: 对于任何包含混合格式的选中文本，应用格式应该影响整个选中范围
    /// **验证需求**: 6.3
    /// 
    /// 测试策略：
    /// 1. 生成随机文本
    /// 2. 在文本的一部分应用格式
    /// 3. 选中包含格式和非格式的范围
    /// 4. 应用格式到整个选中范围
    /// 5. 验证整个选中范围都有格式
    func testProperty15_MixedFormatApplicationToEntireRange() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 混合格式应用到整个选中范围 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机文本
            let testText = generateRandomText(minLength: 40, maxLength: 100)
            let textLength = testText.count
            
            // 2. 设置初始文本（使用 NSTextStorage）
            let textStorage = NSTextStorage(string: testText)
            let normalFont = NSFont.systemFont(ofSize: 15)
            textStorage.addAttribute(.font, value: normalFont, range: NSRange(location: 0, length: textLength))
            
            // 3. 在文本的一部分应用下划线格式（确保不是全部）
            let formatStart = Int.random(in: 5..<(textLength / 2))
            let formatLength = Int.random(in: 5..<min(15, textLength - formatStart - 5))
            let formatRange = NSRange(location: formatStart, length: formatLength)
            
            textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: formatRange)
            
            // 4. 选中包含格式和非格式的范围
            let selectionStart = max(0, formatStart - 5)
            let selectionEnd = min(textLength, formatStart + formatLength + 5)
            let selectionRange = NSRange(location: selectionStart, length: selectionEnd - selectionStart)
            
            // 5. 验证初始状态是混合格式
            let initialState = mixedFormatHandler.detectFormatState(.underline, in: textStorage, range: selectionRange)
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(textLength), 格式范围=\(formatRange), 选中范围=\(selectionRange)")
            print("[PropertyTest]   - 初始状态: \(initialState.stateType), 激活比例: \(String(format: "%.2f", initialState.activationRatio))")
            
            // 6. 强制应用格式到整个选中范围
            applicationHandler.forceApplyFormat(.underline, to: textStorage, range: selectionRange)
            
            // 7. 验证整个选中范围都有格式
            let finalState = mixedFormatHandler.detectFormatState(.underline, in: textStorage, range: selectionRange)
            
            print("[PropertyTest]   - 最终状态: \(finalState.stateType), 激活比例: \(String(format: "%.2f", finalState.activationRatio))")
            
            XCTAssertEqual(finalState.stateType, .fullyActive,
                          "迭代 \(iteration): 应用格式后，整个选中范围应该是完全激活状态")
            XCTAssertEqual(finalState.activationRatio, 1.0,
                          "迭代 \(iteration): 激活比例应该是 1.0")
        }
        
        print("[PropertyTest] ✅ 混合格式应用到整个选中范围测试完成")
    }
    
    /// 属性测试：混合格式移除从整个选中范围
    /// 
    /// **属性**: 对于任何包含混合格式的选中文本，移除格式应该影响整个选中范围
    /// **验证需求**: 6.3
    func testProperty15_MixedFormatRemovalFromEntireRange() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 混合格式移除从整个选中范围 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机文本
            let testText = generateRandomText(minLength: 40, maxLength: 100)
            let textLength = testText.count
            
            // 2. 设置初始文本（使用 NSTextStorage）
            let textStorage = NSTextStorage(string: testText)
            let normalFont = NSFont.systemFont(ofSize: 15)
            textStorage.addAttribute(.font, value: normalFont, range: NSRange(location: 0, length: textLength))
            
            // 3. 在文本的一部分应用删除线格式
            let formatStart = Int.random(in: 5..<(textLength / 2))
            let formatLength = Int.random(in: 5..<min(15, textLength - formatStart - 5))
            let formatRange = NSRange(location: formatStart, length: formatLength)
            
            textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: formatRange)
            
            // 4. 选中包含格式和非格式的范围
            let selectionStart = max(0, formatStart - 5)
            let selectionEnd = min(textLength, formatStart + formatLength + 5)
            let selectionRange = NSRange(location: selectionStart, length: selectionEnd - selectionStart)
            
            // 5. 验证初始状态是混合格式
            let initialState = mixedFormatHandler.detectFormatState(.strikethrough, in: textStorage, range: selectionRange)
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(textLength), 格式范围=\(formatRange), 选中范围=\(selectionRange)")
            print("[PropertyTest]   - 初始状态: \(initialState.stateType), 激活比例: \(String(format: "%.2f", initialState.activationRatio))")
            
            // 6. 强制移除格式从整个选中范围
            applicationHandler.forceRemoveFormat(.strikethrough, from: textStorage, range: selectionRange)
            
            // 7. 验证整个选中范围都没有格式
            let finalState = mixedFormatHandler.detectFormatState(.strikethrough, in: textStorage, range: selectionRange)
            
            print("[PropertyTest]   - 最终状态: \(finalState.stateType), 激活比例: \(String(format: "%.2f", finalState.activationRatio))")
            
            XCTAssertEqual(finalState.stateType, .inactive,
                          "迭代 \(iteration): 移除格式后，整个选中范围应该是未激活状态")
            XCTAssertEqual(finalState.activationRatio, 0.0,
                          "迭代 \(iteration): 激活比例应该是 0.0")
        }
        
        print("[PropertyTest] ✅ 混合格式移除从整个选中范围测试完成")
    }
    
    /// 属性测试：切换策略的混合格式应用
    /// 
    /// **属性**: 对于任何包含混合格式的选中文本，使用切换策略时应该根据激活比例决定应用或移除
    /// **验证需求**: 6.3
    func testProperty15_ToggleStrategyMixedFormatApplication() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 切换策略的混合格式应用 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机文本
            let testText = generateRandomText(minLength: 50, maxLength: 100)
            let textLength = testText.count
            
            // 2. 设置初始文本（使用 NSTextStorage）
            let textStorage = NSTextStorage(string: testText)
            let normalFont = NSFont.systemFont(ofSize: 15)
            textStorage.addAttribute(.font, value: normalFont, range: NSRange(location: 0, length: textLength))
            
            // 3. 选中一个范围
            let selectionStart = Int.random(in: 5..<(textLength / 3))
            let selectionLength = Int.random(in: 20..<min(40, textLength - selectionStart))
            let selectionRange = NSRange(location: selectionStart, length: selectionLength)
            
            // 4. 随机决定格式覆盖比例（小于或大于 50%）
            let coverageRatio = Double.random(in: 0.1..<0.9)
            let formatLength = Int(Double(selectionLength) * coverageRatio)
            let formatRange = NSRange(location: selectionStart, length: formatLength)
            
            // 5. 应用高亮格式到部分范围
            let highlightColor = NSColor(hex: "#9affe8af") ?? NSColor.systemYellow
            textStorage.addAttribute(.backgroundColor, value: highlightColor, range: formatRange)
            
            // 6. 检测初始状态
            let initialState = mixedFormatHandler.detectFormatState(.highlight, in: textStorage, range: selectionRange)
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(textLength), 选中范围=\(selectionRange)")
            print("[PropertyTest]   - 覆盖比例: \(String(format: "%.2f", coverageRatio)), 格式范围=\(formatRange)")
            print("[PropertyTest]   - 初始状态: \(initialState.stateType), 激活比例: \(String(format: "%.2f", initialState.activationRatio))")
            
            // 7. 使用切换策略应用格式
            applicationHandler.applyFormat(.highlight, to: textStorage, range: selectionRange, strategy: .toggle)
            
            // 8. 检测最终状态
            let finalState = mixedFormatHandler.detectFormatState(.highlight, in: textStorage, range: selectionRange)
            
            print("[PropertyTest]   - 最终状态: \(finalState.stateType), 激活比例: \(String(format: "%.2f", finalState.activationRatio))")
            
            // 9. 验证切换策略的行为
            // 如果初始激活比例 < 0.5，应该应用格式（最终完全激活）
            // 如果初始激活比例 >= 0.5，应该移除格式（最终未激活）
            if initialState.activationRatio < 0.5 {
                XCTAssertEqual(finalState.stateType, .fullyActive,
                              "迭代 \(iteration): 初始激活比例 < 0.5，应该应用格式")
            } else {
                XCTAssertEqual(finalState.stateType, .inactive,
                              "迭代 \(iteration): 初始激活比例 >= 0.5，应该移除格式")
            }
        }
        
        print("[PropertyTest] ✅ 切换策略的混合格式应用测试完成")
    }

    
    /// 属性测试：加粗格式的混合应用
    /// 
    /// **属性**: 对于任何包含部分加粗的选中文本，应用加粗格式应该使整个范围都加粗
    /// **验证需求**: 6.3
    func testProperty15_BoldMixedFormatApplication() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 加粗格式的混合应用 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机文本
            let testText = generateRandomText(minLength: 40, maxLength: 80)
            let textLength = testText.count
            
            // 2. 设置初始文本（使用 NSTextStorage）
            let textStorage = NSTextStorage(string: testText)
            let normalFont = NSFont.systemFont(ofSize: 15)
            textStorage.addAttribute(.font, value: normalFont, range: NSRange(location: 0, length: textLength))
            
            // 3. 在文本的一部分应用加粗格式
            let boldStart = Int.random(in: 5..<(textLength / 2))
            let boldLength = Int.random(in: 5..<min(15, textLength - boldStart - 5))
            let boldRange = NSRange(location: boldStart, length: boldLength)
            
            let fontManager = NSFontManager.shared
            textStorage.enumerateAttribute(.font, in: boldRange, options: []) { value, attrRange, _ in
                if let font = value as? NSFont {
                    let boldFont = fontManager.convert(font, toHaveTrait: .boldFontMask)
                    textStorage.addAttribute(.font, value: boldFont, range: attrRange)
                }
            }
            
            // 4. 选中包含加粗和非加粗的范围
            let selectionStart = max(0, boldStart - 5)
            let selectionEnd = min(textLength, boldStart + boldLength + 5)
            let selectionRange = NSRange(location: selectionStart, length: selectionEnd - selectionStart)
            
            // 5. 验证初始状态是混合格式
            let initialState = mixedFormatHandler.detectFormatState(.bold, in: textStorage, range: selectionRange)
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(textLength), 加粗范围=\(boldRange), 选中范围=\(selectionRange)")
            print("[PropertyTest]   - 初始状态: \(initialState.stateType), 激活比例: \(String(format: "%.2f", initialState.activationRatio))")
            
            // 6. 强制应用加粗格式到整个选中范围
            applicationHandler.forceApplyFormat(.bold, to: textStorage, range: selectionRange)
            
            // 7. 验证整个选中范围都有加粗格式
            let finalState = mixedFormatHandler.detectFormatState(.bold, in: textStorage, range: selectionRange)
            
            print("[PropertyTest]   - 最终状态: \(finalState.stateType), 激活比例: \(String(format: "%.2f", finalState.activationRatio))")
            
            XCTAssertEqual(finalState.stateType, .fullyActive,
                          "迭代 \(iteration): 应用加粗格式后，整个选中范围应该是完全激活状态")
            XCTAssertEqual(finalState.activationRatio, 1.0,
                          "迭代 \(iteration): 激活比例应该是 1.0")
        }
        
        print("[PropertyTest] ✅ 加粗格式的混合应用测试完成")
    }
    
    /// 属性测试：斜体格式的混合应用
    /// 
    /// **属性**: 对于任何包含部分斜体的选中文本，应用斜体格式应该使整个范围都斜体
    /// **验证需求**: 6.3
    func testProperty15_ItalicMixedFormatApplication() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 斜体格式的混合应用 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机文本
            let testText = generateRandomText(minLength: 40, maxLength: 80)
            let textLength = testText.count
            
            // 2. 设置初始文本（使用 NSTextStorage）
            let textStorage = NSTextStorage(string: testText)
            let normalFont = NSFont.systemFont(ofSize: 15)
            textStorage.addAttribute(.font, value: normalFont, range: NSRange(location: 0, length: textLength))
            
            // 3. 在文本的一部分应用斜体格式
            let italicStart = Int.random(in: 5..<(textLength / 2))
            let italicLength = Int.random(in: 5..<min(15, textLength - italicStart - 5))
            let italicRange = NSRange(location: italicStart, length: italicLength)
            
            let fontManager = NSFontManager.shared
            textStorage.enumerateAttribute(.font, in: italicRange, options: []) { value, attrRange, _ in
                if let font = value as? NSFont {
                    let italicFont = fontManager.convert(font, toHaveTrait: .italicFontMask)
                    textStorage.addAttribute(.font, value: italicFont, range: attrRange)
                }
            }
            
            // 4. 选中包含斜体和非斜体的范围
            let selectionStart = max(0, italicStart - 5)
            let selectionEnd = min(textLength, italicStart + italicLength + 5)
            let selectionRange = NSRange(location: selectionStart, length: selectionEnd - selectionStart)
            
            // 5. 验证初始状态是混合格式
            let initialState = mixedFormatHandler.detectFormatState(.italic, in: textStorage, range: selectionRange)
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(textLength), 斜体范围=\(italicRange), 选中范围=\(selectionRange)")
            print("[PropertyTest]   - 初始状态: \(initialState.stateType), 激活比例: \(String(format: "%.2f", initialState.activationRatio))")
            
            // 6. 强制应用斜体格式到整个选中范围
            applicationHandler.forceApplyFormat(.italic, to: textStorage, range: selectionRange)
            
            // 7. 验证整个选中范围都有斜体格式
            let finalState = mixedFormatHandler.detectFormatState(.italic, in: textStorage, range: selectionRange)
            
            print("[PropertyTest]   - 最终状态: \(finalState.stateType), 激活比例: \(String(format: "%.2f", finalState.activationRatio))")
            
            XCTAssertEqual(finalState.stateType, .fullyActive,
                          "迭代 \(iteration): 应用斜体格式后，整个选中范围应该是完全激活状态")
            XCTAssertEqual(finalState.activationRatio, 1.0,
                          "迭代 \(iteration): 激活比例应该是 1.0")
        }
        
        print("[PropertyTest] ✅ 斜体格式的混合应用测试完成")
    }
    
    // MARK: - 辅助方法
    
    /// 生成随机文本
    private func generateRandomText(minLength: Int, maxLength: Int) -> String {
        let length = Int.random(in: minLength...maxLength)
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "
        return String((0..<length).map { _ in characters.randomElement()! })
    }
}
