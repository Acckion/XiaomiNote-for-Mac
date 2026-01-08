//
//  FormatStateDetectionPropertyTests.swift
//  MiNoteLibraryTests
//
//  格式状态检测属性测试 - 验证内联格式状态检测准确性
//  属性 3: 内联格式状态检测准确性
//  验证需求: 2.1, 2.2, 2.3, 2.4, 2.5
//
//  Feature: format-menu-fix, Property 3: 内联格式状态检测准确性
//

import XCTest
import AppKit
@testable import MiNoteLibrary

/// 格式状态检测属性测试
/// 
/// 本测试套件使用基于属性的测试方法，通过生成随机输入来验证格式状态检测的通用正确性属性。
/// 每个测试运行 100 次迭代，确保在各种输入条件下格式状态检测的准确性。
@MainActor
final class FormatStateDetectionPropertyTests: XCTestCase {
    
    // MARK: - Properties
    
    var editorContext: NativeEditorContext!
    var textStorage: NSTextStorage!
    var textView: NSTextView!
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // 创建测试用的编辑器上下文
        editorContext = NativeEditorContext()
        
        // 创建测试用的文本存储和文本视图
        textStorage = NSTextStorage()
        textView = NSTextView()
        
        // 使用我们的测试文本存储
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer()
        layoutManager.addTextContainer(textContainer)
        textView = NSTextView(frame: .zero, textContainer: textContainer)
    }
    
    override func tearDown() async throws {
        editorContext = nil
        textStorage = nil
        textView = nil
        try await super.tearDown()
    }
    
    // MARK: - 属性 3: 内联格式状态检测准确性
    // 验证需求: 2.1, 2.2, 2.3, 2.4, 2.5
    
    /// 属性测试：加粗格式状态检测准确性
    /// 
    /// **属性**: 对于任何包含加粗格式的文本位置，当光标移动到该位置时，格式菜单应该显示加粗按钮为激活状态
    /// **验证需求**: 2.1
    /// 
    /// 测试策略：
    /// 1. 生成随机文本内容
    /// 2. 在随机位置应用加粗格式
    /// 3. 将光标移动到加粗文本位置
    /// 4. 更新格式状态
    /// 5. 验证加粗格式被正确检测
    func testProperty3_BoldFormatStateDetectionAccuracy() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 加粗格式状态检测准确性 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomText(minLength: 20, maxLength: 100)
            let boldRange = generateRandomRange(in: testText)
            
            // 2. 设置初始文本并应用加粗格式
            let attributedString = NSMutableAttributedString(string: testText)
            let normalFont = NSFont.systemFont(ofSize: 15)
            attributedString.addAttribute(.font, value: normalFont, range: NSRange(location: 0, length: testText.count))
            
            // 应用加粗到指定范围
            let fontManager = NSFontManager.shared
            attributedString.enumerateAttribute(.font, in: boldRange, options: []) { value, attrRange, _ in
                if let font = value as? NSFont {
                    let boldFont = fontManager.convert(font, toHaveTrait: .boldFontMask)
                    attributedString.addAttribute(.font, value: boldFont, range: attrRange)
                }
            }
            
            // 3. 更新编辑器上下文
            editorContext.updateNSContent(attributedString)
            
            // 4. 将光标移动到加粗文本中的随机位置
            let cursorPosition = boldRange.location + Int.random(in: 0..<max(1, boldRange.length))
            editorContext.updateCursorPosition(cursorPosition)
            editorContext.forceUpdateFormats()
            
            // 立即强制更新格式状态（不使用防抖）
            editorContext.forceUpdateFormats()
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(testText.count), 加粗范围=\(boldRange), 光标位置=\(cursorPosition)")
            
            // 5. 验证加粗格式被检测到
            let isBoldDetected = editorContext.isFormatActive(.bold)
            XCTAssertTrue(isBoldDetected, 
                         "迭代 \(iteration): 光标在加粗文本位置 \(cursorPosition)，应该检测到加粗格式")
            
            // 6. 验证工具栏按钮状态
            let buttonState = editorContext.toolbarButtonStates[.bold] ?? false
            XCTAssertTrue(buttonState, 
                         "迭代 \(iteration): 加粗按钮应该显示为激活状态")
        }
        
        print("[PropertyTest] ✅ 加粗格式状态检测准确性测试完成")
    }
    
    /// 属性测试：斜体格式状态检测准确性
    /// 
    /// **属性**: 对于任何包含斜体格式的文本位置，当光标移动到该位置时，格式菜单应该显示斜体按钮为激活状态
    /// **验证需求**: 2.2
    func testProperty3_ItalicFormatStateDetectionAccuracy() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 斜体格式状态检测准确性 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomText(minLength: 20, maxLength: 100)
            let italicRange = generateRandomRange(in: testText)
            
            // 2. 设置初始文本并应用斜体格式
            let attributedString = NSMutableAttributedString(string: testText)
            let normalFont = NSFont.systemFont(ofSize: 15)
            attributedString.addAttribute(.font, value: normalFont, range: NSRange(location: 0, length: testText.count))
            
            // 应用斜体到指定范围
            let fontManager = NSFontManager.shared
            attributedString.enumerateAttribute(.font, in: italicRange, options: []) { value, attrRange, _ in
                if let font = value as? NSFont {
                    let italicFont = fontManager.convert(font, toHaveTrait: .italicFontMask)
                    attributedString.addAttribute(.font, value: italicFont, range: attrRange)
                }
            }
            
            // 3. 更新编辑器上下文
            editorContext.updateNSContent(attributedString)
            
            // 4. 将光标移动到斜体文本中的随机位置
            let cursorPosition = italicRange.location + Int.random(in: 0..<max(1, italicRange.length))
            editorContext.updateCursorPosition(cursorPosition)
            editorContext.forceUpdateFormats()
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(testText.count), 斜体范围=\(italicRange), 光标位置=\(cursorPosition)")
            
            // 5. 验证斜体格式被检测到
            let isItalicDetected = editorContext.isFormatActive(.italic)
            XCTAssertTrue(isItalicDetected, 
                         "迭代 \(iteration): 光标在斜体文本位置 \(cursorPosition)，应该检测到斜体格式")
            
            // 6. 验证工具栏按钮状态
            let buttonState = editorContext.toolbarButtonStates[.italic] ?? false
            XCTAssertTrue(buttonState, 
                         "迭代 \(iteration): 斜体按钮应该显示为激活状态")
        }
        
        print("[PropertyTest] ✅ 斜体格式状态检测准确性测试完成")
    }
    
    /// 属性测试：下划线格式状态检测准确性
    /// 
    /// **属性**: 对于任何包含下划线格式的文本位置，当光标移动到该位置时，格式菜单应该显示下划线按钮为激活状态
    /// **验证需求**: 2.3
    func testProperty3_UnderlineFormatStateDetectionAccuracy() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 下划线格式状态检测准确性 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomText(minLength: 20, maxLength: 100)
            let underlineRange = generateRandomRange(in: testText)
            
            // 2. 设置初始文本并应用下划线格式
            let attributedString = NSMutableAttributedString(string: testText)
            let normalFont = NSFont.systemFont(ofSize: 15)
            attributedString.addAttribute(.font, value: normalFont, range: NSRange(location: 0, length: testText.count))
            
            // 应用下划线到指定范围
            attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: underlineRange)
            
            // 3. 更新编辑器上下文
            editorContext.updateNSContent(attributedString)
            
            // 4. 将光标移动到下划线文本中的随机位置
            let cursorPosition = underlineRange.location + Int.random(in: 0..<max(1, underlineRange.length))
            editorContext.updateCursorPosition(cursorPosition)
            editorContext.forceUpdateFormats()
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(testText.count), 下划线范围=\(underlineRange), 光标位置=\(cursorPosition)")
            
            // 5. 验证下划线格式被检测到
            let isUnderlineDetected = editorContext.isFormatActive(.underline)
            XCTAssertTrue(isUnderlineDetected, 
                         "迭代 \(iteration): 光标在下划线文本位置 \(cursorPosition)，应该检测到下划线格式")
            
            // 6. 验证工具栏按钮状态
            let buttonState = editorContext.toolbarButtonStates[.underline] ?? false
            XCTAssertTrue(buttonState, 
                         "迭代 \(iteration): 下划线按钮应该显示为激活状态")
        }
        
        print("[PropertyTest] ✅ 下划线格式状态检测准确性测试完成")
    }
    
    /// 属性测试：删除线格式状态检测准确性
    /// 
    /// **属性**: 对于任何包含删除线格式的文本位置，当光标移动到该位置时，格式菜单应该显示删除线按钮为激活状态
    /// **验证需求**: 2.4
    func testProperty3_StrikethroughFormatStateDetectionAccuracy() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 删除线格式状态检测准确性 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomText(minLength: 20, maxLength: 100)
            let strikethroughRange = generateRandomRange(in: testText)
            
            // 2. 设置初始文本并应用删除线格式
            let attributedString = NSMutableAttributedString(string: testText)
            let normalFont = NSFont.systemFont(ofSize: 15)
            attributedString.addAttribute(.font, value: normalFont, range: NSRange(location: 0, length: testText.count))
            
            // 应用删除线到指定范围
            attributedString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: strikethroughRange)
            
            // 3. 更新编辑器上下文
            editorContext.updateNSContent(attributedString)
            
            // 4. 将光标移动到删除线文本中的随机位置
            let cursorPosition = strikethroughRange.location + Int.random(in: 0..<max(1, strikethroughRange.length))
            editorContext.updateCursorPosition(cursorPosition)
            editorContext.forceUpdateFormats()
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(testText.count), 删除线范围=\(strikethroughRange), 光标位置=\(cursorPosition)")
            
            // 5. 验证删除线格式被检测到
            let isStrikethroughDetected = editorContext.isFormatActive(.strikethrough)
            XCTAssertTrue(isStrikethroughDetected, 
                         "迭代 \(iteration): 光标在删除线文本位置 \(cursorPosition)，应该检测到删除线格式")
            
            // 6. 验证工具栏按钮状态
            let buttonState = editorContext.toolbarButtonStates[.strikethrough] ?? false
            XCTAssertTrue(buttonState, 
                         "迭代 \(iteration): 删除线按钮应该显示为激活状态")
        }
        
        print("[PropertyTest] ✅ 删除线格式状态检测准确性测试完成")
    }
    
    /// 属性测试：高亮格式状态检测准确性
    /// 
    /// **属性**: 对于任何包含高亮格式的文本位置，当光标移动到该位置时，格式菜单应该显示高亮按钮为激活状态
    /// **验证需求**: 2.5
    func testProperty3_HighlightFormatStateDetectionAccuracy() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 高亮格式状态检测准确性 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomText(minLength: 20, maxLength: 100)
            let highlightRange = generateRandomRange(in: testText)
            
            // 2. 设置初始文本并应用高亮格式
            let attributedString = NSMutableAttributedString(string: testText)
            let normalFont = NSFont.systemFont(ofSize: 15)
            attributedString.addAttribute(.font, value: normalFont, range: NSRange(location: 0, length: testText.count))
            
            // 应用高亮到指定范围
            let highlightColor = NSColor.systemYellow
            attributedString.addAttribute(.backgroundColor, value: highlightColor, range: highlightRange)
            
            // 3. 更新编辑器上下文
            editorContext.updateNSContent(attributedString)
            
            // 4. 将光标移动到高亮文本中的随机位置
            let cursorPosition = highlightRange.location + Int.random(in: 0..<max(1, highlightRange.length))
            editorContext.updateCursorPosition(cursorPosition)
            editorContext.forceUpdateFormats()
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(testText.count), 高亮范围=\(highlightRange), 光标位置=\(cursorPosition)")
            
            // 5. 验证高亮格式被检测到
            let isHighlightDetected = editorContext.isFormatActive(.highlight)
            XCTAssertTrue(isHighlightDetected, 
                         "迭代 \(iteration): 光标在高亮文本位置 \(cursorPosition)，应该检测到高亮格式")
            
            // 6. 验证工具栏按钮状态
            let buttonState = editorContext.toolbarButtonStates[.highlight] ?? false
            XCTAssertTrue(buttonState, 
                         "迭代 \(iteration): 高亮按钮应该显示为激活状态")
        }
        
        print("[PropertyTest] ✅ 高亮格式状态检测准确性测试完成")
    }
    
    /// 属性测试：混合内联格式状态检测准确性
    /// 
    /// **属性**: 对于任何包含多种内联格式的文本位置，当光标移动到该位置时，格式菜单应该显示所有相应按钮为激活状态
    /// **验证需求**: 2.1, 2.2, 2.3, 2.4, 2.5
    func testProperty3_MixedInlineFormatStateDetectionAccuracy() async throws {
        let iterations = 50
        print("\n[PropertyTest] 开始属性测试: 混合内联格式状态检测准确性 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomText(minLength: 30, maxLength: 100)
            let formatRange = generateRandomRange(in: testText)
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            let normalFont = NSFont.systemFont(ofSize: 15)
            attributedString.addAttribute(.font, value: normalFont, range: NSRange(location: 0, length: testText.count))
            
            // 3. 随机应用多种格式
            var appliedFormats: Set<TextFormat> = []
            let fontManager = NSFontManager.shared
            
            // 随机决定应用哪些格式
            if Bool.random() {
                // 应用加粗
                attributedString.enumerateAttribute(.font, in: formatRange, options: []) { value, attrRange, _ in
                    if let font = value as? NSFont {
                        let boldFont = fontManager.convert(font, toHaveTrait: .boldFontMask)
                        attributedString.addAttribute(.font, value: boldFont, range: attrRange)
                    }
                }
                appliedFormats.insert(.bold)
            }
            
            if Bool.random() {
                // 应用斜体
                attributedString.enumerateAttribute(.font, in: formatRange, options: []) { value, attrRange, _ in
                    if let font = value as? NSFont {
                        let italicFont = fontManager.convert(font, toHaveTrait: .italicFontMask)
                        attributedString.addAttribute(.font, value: italicFont, range: attrRange)
                    }
                }
                appliedFormats.insert(.italic)
            }
            
            if Bool.random() {
                // 应用下划线
                attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: formatRange)
                appliedFormats.insert(.underline)
            }
            
            if Bool.random() {
                // 应用删除线
                attributedString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: formatRange)
                appliedFormats.insert(.strikethrough)
            }
            
            if Bool.random() {
                // 应用高亮
                attributedString.addAttribute(.backgroundColor, value: NSColor.systemYellow, range: formatRange)
                appliedFormats.insert(.highlight)
            }
            
            // 确保至少应用了一种格式
            if appliedFormats.isEmpty {
                attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: formatRange)
                appliedFormats.insert(.underline)
            }
            
            // 4. 更新编辑器上下文
            editorContext.updateNSContent(attributedString)
            
            // 5. 将光标移动到格式化文本中的随机位置
            let cursorPosition = formatRange.location + Int.random(in: 0..<max(1, formatRange.length))
            editorContext.updateCursorPosition(cursorPosition)
            editorContext.forceUpdateFormats()
            
            let formatNames = appliedFormats.map { $0.displayName }.joined(separator: ", ")
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(testText.count), 格式范围=\(formatRange), 光标位置=\(cursorPosition), 应用的格式=[\(formatNames)]")
            
            // 6. 验证所有应用的格式都被检测到
            for format in appliedFormats {
                let isDetected = editorContext.isFormatActive(format)
                XCTAssertTrue(isDetected, 
                             "迭代 \(iteration): 光标在位置 \(cursorPosition)，应该检测到\(format.displayName)格式")
                
                let buttonState = editorContext.toolbarButtonStates[format] ?? false
                XCTAssertTrue(buttonState, 
                             "迭代 \(iteration): \(format.displayName)按钮应该显示为激活状态")
            }
        }
        
        print("[PropertyTest] ✅ 混合内联格式状态检测准确性测试完成")
    }
    
    // MARK: - 辅助方法：随机数据生成
    
    /// 生成随机文本
    /// - Parameters:
    ///   - minLength: 最小长度
    ///   - maxLength: 最大长度
    /// - Returns: 随机文本
    private func generateRandomText(minLength: Int, maxLength: Int) -> String {
        let length = Int.random(in: minLength...maxLength)
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "
        return String((0..<length).map { _ in characters.randomElement()! })
    }
    
    /// 生成随机范围
    /// - Parameter text: 文本
    /// - Returns: 随机范围
    private func generateRandomRange(in text: String) -> NSRange {
        let length = text.count
        guard length > 0 else { return NSRange(location: 0, length: 0) }
        
        let location = Int.random(in: 0..<length)
        let maxLength = length - location
        let rangeLength = Int.random(in: 1...min(maxLength, 20)) // 限制最大选择长度为 20
        
        return NSRange(location: location, length: rangeLength)
    }
    
    // MARK: - 属性 4: 块级格式状态检测准确性
    // 验证需求: 2.6, 2.7, 2.8, 2.9, 2.10
    
    /// 属性测试：标题格式状态检测准确性
    /// 
    /// **属性**: 对于任何包含标题格式的文本位置，当光标移动到该位置时，格式菜单应该显示对应标题级别按钮为激活状态
    /// **验证需求**: 2.6
    /// 
    /// 测试策略：
    /// 1. 生成随机多行文本
    /// 2. 在随机行应用标题格式（H1, H2, H3）
    /// 3. 将光标移动到标题行
    /// 4. 更新格式状态
    /// 5. 验证标题格式被正确检测
    func testProperty4_HeadingFormatStateDetectionAccuracy() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 标题格式状态检测准确性 (迭代次数: \(iterations))")
        
        let headingLevels: [(format: TextFormat, size: CGFloat, name: String)] = [
            (.heading1, 24, "H1"),
            (.heading2, 20, "H2"),
            (.heading3, 16, "H3")
        ]
        
        for iteration in 1...iterations {
            // 1. 生成随机多行文本
            let testText = generateRandomMultilineText(minLines: 3, maxLines: 10)
            let lineRange = generateRandomLineRange(in: testText)
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            let normalFont = NSFont.systemFont(ofSize: 15)
            attributedString.addAttribute(.font, value: normalFont, range: NSRange(location: 0, length: testText.count))
            
            // 3. 随机选择一个标题级别
            let headingInfo = headingLevels.randomElement()!
            
            // 4. 应用标题格式到指定行
            let weight: NSFont.Weight = headingInfo.format == .heading1 ? .bold : (headingInfo.format == .heading2 ? .semibold : .medium)
            let headingFont = NSFont.systemFont(ofSize: headingInfo.size, weight: weight)
            attributedString.addAttribute(.font, value: headingFont, range: lineRange)
            
            // 5. 更新编辑器上下文
            editorContext.updateNSContent(attributedString)
            
            // 6. 将光标移动到标题行中的随机位置
            let cursorPosition = lineRange.location + Int.random(in: 0..<max(1, lineRange.length))
            editorContext.updateCursorPosition(cursorPosition)
            editorContext.forceUpdateFormats()
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(testText.count), 标题行范围=\(lineRange), 光标位置=\(cursorPosition), 标题级别=\(headingInfo.name)")
            
            // 7. 验证标题格式被检测到
            let isHeadingDetected = editorContext.isFormatActive(headingInfo.format)
            XCTAssertTrue(isHeadingDetected, 
                         "迭代 \(iteration): 光标在\(headingInfo.name)文本位置 \(cursorPosition)，应该检测到\(headingInfo.name)格式")
            
            // 8. 验证工具栏按钮状态
            let buttonState = editorContext.toolbarButtonStates[headingInfo.format] ?? false
            XCTAssertTrue(buttonState, 
                         "迭代 \(iteration): \(headingInfo.name)按钮应该显示为激活状态")
        }
        
        print("[PropertyTest] ✅ 标题格式状态检测准确性测试完成")
    }
    
    /// 属性测试：对齐格式状态检测准确性
    /// 
    /// **属性**: 对于任何包含对齐格式的文本位置，当光标移动到该位置时，格式菜单应该显示对应对齐按钮为激活状态
    /// **验证需求**: 2.7, 2.8
    func testProperty4_AlignmentFormatStateDetectionAccuracy() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 对齐格式状态检测准确性 (迭代次数: \(iterations))")
        
        let alignments: [(format: TextFormat, alignment: NSTextAlignment, name: String)] = [
            (.alignCenter, .center, "居中"),
            (.alignRight, .right, "右对齐")
        ]
        
        for iteration in 1...iterations {
            // 1. 生成随机多行文本
            let testText = generateRandomMultilineText(minLines: 3, maxLines: 10)
            let lineRange = generateRandomLineRange(in: testText)
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            let normalFont = NSFont.systemFont(ofSize: 15)
            attributedString.addAttribute(.font, value: normalFont, range: NSRange(location: 0, length: testText.count))
            
            // 3. 随机选择一个对齐方式
            let alignmentInfo = alignments.randomElement()!
            
            // 4. 应用对齐格式到指定行
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = alignmentInfo.alignment
            attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
            
            // 5. 更新编辑器上下文
            editorContext.updateNSContent(attributedString)
            
            // 6. 将光标移动到对齐行中的随机位置
            let cursorPosition = lineRange.location + Int.random(in: 0..<max(1, lineRange.length))
            editorContext.updateCursorPosition(cursorPosition)
            editorContext.forceUpdateFormats()
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(testText.count), 对齐行范围=\(lineRange), 光标位置=\(cursorPosition), 对齐方式=\(alignmentInfo.name)")
            
            // 7. 验证对齐格式被检测到
            let isAlignmentDetected = editorContext.isFormatActive(alignmentInfo.format)
            XCTAssertTrue(isAlignmentDetected, 
                         "迭代 \(iteration): 光标在\(alignmentInfo.name)文本位置 \(cursorPosition)，应该检测到\(alignmentInfo.name)格式")
            
            // 8. 验证工具栏按钮状态
            let buttonState = editorContext.toolbarButtonStates[alignmentInfo.format] ?? false
            XCTAssertTrue(buttonState, 
                         "迭代 \(iteration): \(alignmentInfo.name)按钮应该显示为激活状态")
        }
        
        print("[PropertyTest] ✅ 对齐格式状态检测准确性测试完成")
    }
    
    /// 属性测试：引用块格式状态检测准确性
    /// 
    /// **属性**: 对于任何包含引用块格式的文本位置，当光标移动到该位置时，格式菜单应该显示引用按钮为激活状态
    /// **验证需求**: 2.10
    func testProperty4_QuoteFormatStateDetectionAccuracy() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 引用块格式状态检测准确性 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机多行文本
            let testText = generateRandomMultilineText(minLines: 3, maxLines: 10)
            let lineRange = generateRandomLineRange(in: testText)
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            let normalFont = NSFont.systemFont(ofSize: 15)
            attributedString.addAttribute(.font, value: normalFont, range: NSRange(location: 0, length: testText.count))
            
            // 3. 应用引用块格式到指定行
            attributedString.addAttribute(.quoteBlock, value: true, range: lineRange)
            
            // 4. 更新编辑器上下文
            editorContext.updateNSContent(attributedString)
            
            // 5. 将光标移动到引用块中的随机位置
            let cursorPosition = lineRange.location + Int.random(in: 0..<max(1, lineRange.length))
            editorContext.updateCursorPosition(cursorPosition)
            editorContext.forceUpdateFormats()
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(testText.count), 引用块范围=\(lineRange), 光标位置=\(cursorPosition)")
            
            // 6. 验证引用块格式被检测到
            let isQuoteDetected = editorContext.isFormatActive(.quote)
            XCTAssertTrue(isQuoteDetected, 
                         "迭代 \(iteration): 光标在引用块位置 \(cursorPosition)，应该检测到引用格式")
            
            // 7. 验证工具栏按钮状态
            let buttonState = editorContext.toolbarButtonStates[.quote] ?? false
            XCTAssertTrue(buttonState, 
                         "迭代 \(iteration): 引用按钮应该显示为激活状态")
        }
        
        print("[PropertyTest] ✅ 引用块格式状态检测准确性测试完成")
    }
    
    // MARK: - 辅助方法：多行文本生成
    
    /// 生成随机多行文本
    /// - Parameters:
    ///   - minLines: 最小行数
    ///   - maxLines: 最大行数
    /// - Returns: 随机多行文本
    private func generateRandomMultilineText(minLines: Int, maxLines: Int) -> String {
        let lineCount = Int.random(in: minLines...maxLines)
        var lines: [String] = []
        
        for _ in 0..<lineCount {
            let lineLength = Int.random(in: 10...50)
            let line = generateRandomText(minLength: lineLength, maxLength: lineLength)
            lines.append(line)
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// 生成随机行范围（选择一行或多行）
    /// - Parameter text: 文本
    /// - Returns: 随机行范围
    private func generateRandomLineRange(in text: String) -> NSRange {
        let nsString = text as NSString
        let length = text.count
        guard length > 0 else { return NSRange(location: 0, length: 0) }
        
        // 随机选择一个位置
        let location = Int.random(in: 0..<length)
        
        // 获取该位置所在行的范围
        let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
        
        // 随机决定是选择单行还是多行
        if Bool.random() && lineRange.location + lineRange.length < length {
            // 选择多行
            let nextLineStart = lineRange.location + lineRange.length
            let remainingLength = length - nextLineStart
            let additionalLength = Int.random(in: 1...min(remainingLength, 100))
            return NSRange(location: lineRange.location, length: lineRange.length + additionalLength)
        } else {
            // 选择单行
            return lineRange
        }
    }
}

// MARK: - NSAttributedString.Key Extension

extension NSAttributedString.Key {
    /// 引用块属性键（与 QuoteBlockRenderer.swift 中的定义保持一致）
    static let quoteBlock = NSAttributedString.Key("MiNote.quoteBlock")
}
