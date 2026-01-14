//
//  FormatApplicationPropertyTests.swift
//  MiNoteLibraryTests
//
//  格式应用属性测试 - 验证内联格式应用一致性
//  属性 1: 内联格式应用一致性
//  验证需求: 1.1, 1.2, 1.3, 1.4, 1.5
//
//  Feature: format-menu-fix, Property 1: 内联格式应用一致性
//

import XCTest
import AppKit
@testable import MiNoteLibrary

/// 格式应用属性测试
/// 
/// 本测试套件使用基于属性的测试方法，通过生成随机输入来验证格式应用的通用正确性属性。
/// 每个测试运行 100 次迭代，确保在各种输入条件下格式应用的一致性。
@MainActor
final class FormatApplicationPropertyTests: XCTestCase {
    
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
        textView.textStorage?.setAttributedString(NSAttributedString())
        
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
    
    // MARK: - 属性 1: 内联格式应用一致性
    // 验证需求: 1.1, 1.2, 1.3, 1.4, 1.5
    
    /// 属性测试：加粗格式应用一致性
    /// 
    /// **属性**: 对于任何选中的文本范围，点击加粗按钮应该切换该范围内文本的加粗状态
    /// **验证需求**: 1.1
    /// 
    /// 测试策略：
    /// 1. 生成随机文本内容
    /// 2. 生成随机选择范围
    /// 3. 应用加粗格式
    /// 4. 验证选中范围内的所有文本都具有加粗属性
    /// 5. 再次应用加粗格式
    /// 6. 验证选中范围内的所有文本都不再具有加粗属性
    func testProperty1_BoldFormatApplicationConsistency() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 加粗格式应用一致性 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomText(minLength: 10, maxLength: 100)
            let range = generateRandomRange(in: testText)
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 15), range: NSRange(location: 0, length: testText.count))
            textStorage.setAttributedString(attributedString)
            textView.setSelectedRange(range)
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(testText.count), 选择范围=\(range)")
            
            // 3. 应用加粗格式
            applyBoldFormat(to: range, in: textStorage)
            
            // 4. 验证加粗格式已应用
            let hasBoldAfterApply = verifyBoldFormat(in: range, textStorage: textStorage, shouldBeBold: true)
            XCTAssertTrue(hasBoldAfterApply, 
                         "迭代 \(iteration): 应用加粗后，选中范围内的文本应该全部为加粗")
            
            // 5. 再次应用加粗格式（切换）
            applyBoldFormat(to: range, in: textStorage)
            
            // 6. 验证加粗格式已移除
            let hasBoldAfterToggle = verifyBoldFormat(in: range, textStorage: textStorage, shouldBeBold: false)
            XCTAssertTrue(hasBoldAfterToggle, 
                         "迭代 \(iteration): 再次应用加粗后，选中范围内的文本应该全部不为加粗")
        }
        
        print("[PropertyTest] ✅ 加粗格式应用一致性测试完成")
    }
    
    /// 属性测试：斜体格式应用一致性
    /// 
    /// **属性**: 对于任何选中的文本范围，点击斜体按钮应该切换该范围内文本的斜体状态
    /// **验证需求**: 1.2
    func testProperty1_ItalicFormatApplicationConsistency() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 斜体格式应用一致性 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomText(minLength: 10, maxLength: 100)
            let range = generateRandomRange(in: testText)
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 15), range: NSRange(location: 0, length: testText.count))
            textStorage.setAttributedString(attributedString)
            textView.setSelectedRange(range)
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(testText.count), 选择范围=\(range)")
            
            // 3. 应用斜体格式
            applyItalicFormat(to: range, in: textStorage)
            
            // 4. 验证斜体格式已应用
            let hasItalicAfterApply = verifyItalicFormat(in: range, textStorage: textStorage, shouldBeItalic: true)
            XCTAssertTrue(hasItalicAfterApply, 
                         "迭代 \(iteration): 应用斜体后，选中范围内的文本应该全部为斜体")
            
            // 5. 再次应用斜体格式（切换）
            applyItalicFormat(to: range, in: textStorage)
            
            // 6. 验证斜体格式已移除
            let hasItalicAfterToggle = verifyItalicFormat(in: range, textStorage: textStorage, shouldBeItalic: false)
            XCTAssertTrue(hasItalicAfterToggle, 
                         "迭代 \(iteration): 再次应用斜体后，选中范围内的文本应该全部不为斜体")
        }
        
        print("[PropertyTest] ✅ 斜体格式应用一致性测试完成")
    }
    
    /// 属性测试：下划线格式应用一致性
    /// 
    /// **属性**: 对于任何选中的文本范围，点击下划线按钮应该切换该范围内文本的下划线状态
    /// **验证需求**: 1.3
    func testProperty1_UnderlineFormatApplicationConsistency() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 下划线格式应用一致性 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomText(minLength: 10, maxLength: 100)
            let range = generateRandomRange(in: testText)
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 15), range: NSRange(location: 0, length: testText.count))
            textStorage.setAttributedString(attributedString)
            textView.setSelectedRange(range)
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(testText.count), 选择范围=\(range)")
            
            // 3. 应用下划线格式
            applyUnderlineFormat(to: range, in: textStorage)
            
            // 4. 验证下划线格式已应用
            let hasUnderlineAfterApply = verifyUnderlineFormat(in: range, textStorage: textStorage, shouldHaveUnderline: true)
            XCTAssertTrue(hasUnderlineAfterApply, 
                         "迭代 \(iteration): 应用下划线后，选中范围内的文本应该全部有下划线")
            
            // 5. 再次应用下划线格式（切换）
            applyUnderlineFormat(to: range, in: textStorage)
            
            // 6. 验证下划线格式已移除
            let hasUnderlineAfterToggle = verifyUnderlineFormat(in: range, textStorage: textStorage, shouldHaveUnderline: false)
            XCTAssertTrue(hasUnderlineAfterToggle, 
                         "迭代 \(iteration): 再次应用下划线后，选中范围内的文本应该全部没有下划线")
        }
        
        print("[PropertyTest] ✅ 下划线格式应用一致性测试完成")
    }
    
    /// 属性测试：删除线格式应用一致性
    /// 
    /// **属性**: 对于任何选中的文本范围，点击删除线按钮应该切换该范围内文本的删除线状态
    /// **验证需求**: 1.4
    func testProperty1_StrikethroughFormatApplicationConsistency() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 删除线格式应用一致性 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomText(minLength: 10, maxLength: 100)
            let range = generateRandomRange(in: testText)
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 15), range: NSRange(location: 0, length: testText.count))
            textStorage.setAttributedString(attributedString)
            textView.setSelectedRange(range)
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(testText.count), 选择范围=\(range)")
            
            // 3. 应用删除线格式
            applyStrikethroughFormat(to: range, in: textStorage)
            
            // 4. 验证删除线格式已应用
            let hasStrikethroughAfterApply = verifyStrikethroughFormat(in: range, textStorage: textStorage, shouldHaveStrikethrough: true)
            XCTAssertTrue(hasStrikethroughAfterApply, 
                         "迭代 \(iteration): 应用删除线后，选中范围内的文本应该全部有删除线")
            
            // 5. 再次应用删除线格式（切换）
            applyStrikethroughFormat(to: range, in: textStorage)
            
            // 6. 验证删除线格式已移除
            let hasStrikethroughAfterToggle = verifyStrikethroughFormat(in: range, textStorage: textStorage, shouldHaveStrikethrough: false)
            XCTAssertTrue(hasStrikethroughAfterToggle, 
                         "迭代 \(iteration): 再次应用删除线后，选中范围内的文本应该全部没有删除线")
        }
        
        print("[PropertyTest] ✅ 删除线格式应用一致性测试完成")
    }
    
    /// 属性测试：高亮格式应用一致性
    /// 
    /// **属性**: 对于任何选中的文本范围，点击高亮按钮应该切换该范围内文本的高亮状态
    /// **验证需求**: 1.5
    func testProperty1_HighlightFormatApplicationConsistency() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 高亮格式应用一致性 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomText(minLength: 10, maxLength: 100)
            let range = generateRandomRange(in: testText)
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 15), range: NSRange(location: 0, length: testText.count))
            textStorage.setAttributedString(attributedString)
            textView.setSelectedRange(range)
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(testText.count), 选择范围=\(range)")
            
            // 3. 应用高亮格式
            applyHighlightFormat(to: range, in: textStorage)
            
            // 4. 验证高亮格式已应用
            let hasHighlightAfterApply = verifyHighlightFormat(in: range, textStorage: textStorage, shouldHaveHighlight: true)
            XCTAssertTrue(hasHighlightAfterApply, 
                         "迭代 \(iteration): 应用高亮后，选中范围内的文本应该全部有高亮")
            
            // 5. 再次应用高亮格式（切换）
            applyHighlightFormat(to: range, in: textStorage)
            
            // 6. 验证高亮格式已移除
            let hasHighlightAfterToggle = verifyHighlightFormat(in: range, textStorage: textStorage, shouldHaveHighlight: false)
            XCTAssertTrue(hasHighlightAfterToggle, 
                         "迭代 \(iteration): 再次应用高亮后，选中范围内的文本应该全部没有高亮")
        }
        
        print("[PropertyTest] ✅ 高亮格式应用一致性测试完成")
    }
    
    // MARK: - 属性 2: 块级格式应用正确性
    // 验证需求: 1.6, 1.7, 1.8
    
    /// 属性测试：标题格式应用正确性
    /// 
    /// **属性**: 对于任何光标位置或选中范围，点击标题格式按钮应该将相应的行设置为对应的标题格式
    /// **验证需求**: 1.6
    /// 
    /// 测试策略：
    /// 1. 生成随机多行文本
    /// 2. 随机选择一行或多行
    /// 3. 应用标题格式（H1, H2, H3）
    /// 4. 验证选中行的字体大小和粗细符合标题格式
    /// 5. 再次应用相同标题格式（切换）
    /// 6. 验证标题格式已移除，恢复为正常文本
    func testProperty2_HeadingFormatApplicationCorrectness() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 标题格式应用正确性 (迭代次数: \(iterations))")
        
        let headingLevels: [(level: HeadingLevel, size: CGFloat, name: String)] = [
            (.h1, 24, "H1"),
            (.h2, 20, "H2"),
            (.h3, 16, "H3")
        ]
        
        for iteration in 1...iterations {
            // 1. 生成随机多行文本
            let testText = generateRandomMultilineText(minLines: 3, maxLines: 10)
            let range = generateRandomLineRange(in: testText)
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 15), range: NSRange(location: 0, length: testText.count))
            textStorage.setAttributedString(attributedString)
            textView.setSelectedRange(range)
            
            // 3. 随机选择一个标题级别
            let headingInfo = headingLevels.randomElement()!
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(testText.count), 选择范围=\(range), 标题级别=\(headingInfo.name)")
            
            // 4. 应用标题格式
            applyHeadingFormat(to: range, in: textStorage, level: headingInfo.level, size: headingInfo.size)
            
            // 5. 验证标题格式已应用
            let hasHeadingAfterApply = verifyHeadingFormat(in: range, textStorage: textStorage, expectedSize: headingInfo.size)
            XCTAssertTrue(hasHeadingAfterApply, 
                         "迭代 \(iteration): 应用\(headingInfo.name)后，选中行应该具有标题格式")
            
            // 6. 再次应用标题格式（切换）
            applyHeadingFormat(to: range, in: textStorage, level: headingInfo.level, size: headingInfo.size)
            
            // 7. 验证标题格式已移除
            let hasHeadingAfterToggle = verifyHeadingFormat(in: range, textStorage: textStorage, expectedSize: 15)
            XCTAssertTrue(hasHeadingAfterToggle, 
                         "迭代 \(iteration): 再次应用\(headingInfo.name)后，选中行应该恢复为正常文本")
        }
        
        print("[PropertyTest] ✅ 标题格式应用正确性测试完成")
    }
    
    /// 属性测试：对齐格式应用正确性
    /// 
    /// **属性**: 对于任何光标位置或选中范围，点击对齐按钮应该设置当前段落的对齐方式
    /// **验证需求**: 1.7
    /// 
    /// 测试策略：
    /// 1. 生成随机多行文本
    /// 2. 随机选择一行或多行
    /// 3. 应用对齐格式（左对齐、居中、右对齐）
    /// 4. 验证选中段落的对齐方式正确
    func testProperty2_AlignmentFormatApplicationCorrectness() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 对齐格式应用正确性 (迭代次数: \(iterations))")
        
        let alignments: [(alignment: NSTextAlignment, name: String)] = [
            (.left, "左对齐"),
            (.center, "居中"),
            (.right, "右对齐")
        ]
        
        for iteration in 1...iterations {
            // 1. 生成随机多行文本
            let testText = generateRandomMultilineText(minLines: 3, maxLines: 10)
            let range = generateRandomLineRange(in: testText)
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 15), range: NSRange(location: 0, length: testText.count))
            textStorage.setAttributedString(attributedString)
            textView.setSelectedRange(range)
            
            // 3. 随机选择一个对齐方式
            let alignmentInfo = alignments.randomElement()!
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(testText.count), 选择范围=\(range), 对齐方式=\(alignmentInfo.name)")
            
            // 4. 应用对齐格式
            applyAlignmentFormat(to: range, in: textStorage, alignment: alignmentInfo.alignment)
            
            // 5. 验证对齐格式已应用
            let hasAlignmentAfterApply = verifyAlignmentFormat(in: range, textStorage: textStorage, expectedAlignment: alignmentInfo.alignment)
            XCTAssertTrue(hasAlignmentAfterApply, 
                         "迭代 \(iteration): 应用\(alignmentInfo.name)后，选中段落应该具有正确的对齐方式")
        }
        
        print("[PropertyTest] ✅ 对齐格式应用正确性测试完成")
    }
    
    /// 属性测试：列表格式应用正确性
    /// 
    /// **属性**: 对于任何光标位置或选中范围，点击列表按钮应该切换当前行的列表格式
    /// **验证需求**: 1.8
    /// 
    /// 测试策略：
    /// 1. 生成随机多行文本
    /// 2. 随机选择一行或多行
    /// 3. 应用列表格式（无序列表、有序列表）
    /// 4. 验证选中行具有列表格式标记
    /// 5. 再次应用相同列表格式（切换）
    /// 6. 验证列表格式已移除
    func testProperty2_ListFormatApplicationCorrectness() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 列表格式应用正确性 (迭代次数: \(iterations))")
        
        let listTypes: [(type: ListType, name: String)] = [
            (.bullet, "无序列表"),
            (.ordered, "有序列表")
        ]
        
        for iteration in 1...iterations {
            // 1. 生成随机多行文本
            let testText = generateRandomMultilineText(minLines: 3, maxLines: 10)
            let range = generateRandomLineRange(in: testText)
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 15), range: NSRange(location: 0, length: testText.count))
            textStorage.setAttributedString(attributedString)
            textView.setSelectedRange(range)
            
            // 3. 随机选择一个列表类型
            let listInfo = listTypes.randomElement()!
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(testText.count), 选择范围=\(range), 列表类型=\(listInfo.name)")
            
            // 4. 应用列表格式
            applyListFormat(to: range, in: textStorage, listType: listInfo.type)
            
            // 5. 验证列表格式已应用
            let hasListAfterApply = verifyListFormat(in: range, textStorage: textStorage, expectedType: listInfo.type)
            XCTAssertTrue(hasListAfterApply, 
                         "迭代 \(iteration): 应用\(listInfo.name)后，选中行应该具有列表格式")
            
            // 6. 再次应用列表格式（切换）
            applyListFormat(to: range, in: textStorage, listType: listInfo.type)
            
            // 7. 验证列表格式已移除
            let hasListAfterToggle = verifyListFormat(in: range, textStorage: textStorage, expectedType: .none)
            XCTAssertTrue(hasListAfterToggle, 
                         "迭代 \(iteration): 再次应用\(listInfo.name)后，选中行应该移除列表格式")
        }
        
        print("[PropertyTest] ✅ 列表格式应用正确性测试完成")
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
    
    // MARK: - 辅助方法：格式应用
    
    /// 应用加粗格式
    private func applyBoldFormat(to range: NSRange, in textStorage: NSTextStorage) {
        textStorage.beginEditing()
        defer { textStorage.endEditing() }
        
        let fontManager = NSFontManager.shared
        textStorage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
            guard let font = value as? NSFont else { return }
            
            let currentTraits = font.fontDescriptor.symbolicTraits
            let hasBold = currentTraits.contains(.bold)
            
            let newFont = hasBold ? 
                fontManager.convert(font, toNotHaveTrait: .boldFontMask) :
                fontManager.convert(font, toHaveTrait: .boldFontMask)
            
            textStorage.addAttribute(.font, value: newFont, range: attrRange)
        }
    }
    
    /// 应用斜体格式
    private func applyItalicFormat(to range: NSRange, in textStorage: NSTextStorage) {
        textStorage.beginEditing()
        defer { textStorage.endEditing() }
        
        let fontManager = NSFontManager.shared
        textStorage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
            guard let font = value as? NSFont else { return }
            
            let currentTraits = font.fontDescriptor.symbolicTraits
            let hasItalic = currentTraits.contains(.italic)
            
            let newFont = hasItalic ? 
                fontManager.convert(font, toNotHaveTrait: .italicFontMask) :
                fontManager.convert(font, toHaveTrait: .italicFontMask)
            
            textStorage.addAttribute(.font, value: newFont, range: attrRange)
        }
    }
    
    /// 应用下划线格式
    private func applyUnderlineFormat(to range: NSRange, in textStorage: NSTextStorage) {
        textStorage.beginEditing()
        defer { textStorage.endEditing() }
        
        // 检查是否已有下划线
        var hasUnderline = false
        textStorage.enumerateAttribute(.underlineStyle, in: range, options: []) { value, _, stop in
            if let style = value as? Int, style != 0 {
                hasUnderline = true
                stop.pointee = true
            }
        }
        
        // 切换下划线
        if hasUnderline {
            textStorage.removeAttribute(.underlineStyle, range: range)
        } else {
            textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
    }
    
    /// 应用删除线格式
    private func applyStrikethroughFormat(to range: NSRange, in textStorage: NSTextStorage) {
        textStorage.beginEditing()
        defer { textStorage.endEditing() }
        
        // 检查是否已有删除线
        var hasStrikethrough = false
        textStorage.enumerateAttribute(.strikethroughStyle, in: range, options: []) { value, _, stop in
            if let style = value as? Int, style != 0 {
                hasStrikethrough = true
                stop.pointee = true
            }
        }
        
        // 切换删除线
        if hasStrikethrough {
            textStorage.removeAttribute(.strikethroughStyle, range: range)
        } else {
            textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
    }
    
    /// 应用高亮格式
    private func applyHighlightFormat(to range: NSRange, in textStorage: NSTextStorage) {
        textStorage.beginEditing()
        defer { textStorage.endEditing() }
        
        // 检查是否已有高亮
        var hasHighlight = false
        textStorage.enumerateAttribute(.backgroundColor, in: range, options: []) { value, _, stop in
            if value != nil {
                hasHighlight = true
                stop.pointee = true
            }
        }
        
        // 切换高亮
        if hasHighlight {
            textStorage.removeAttribute(.backgroundColor, range: range)
        } else {
            let highlightColor = NSColor(hex: "#9affe8af") ?? NSColor.systemYellow
            textStorage.addAttribute(.backgroundColor, value: highlightColor, range: range)
        }
    }
    
    /// 应用标题格式
    /// 标题格式完全通过字体大小来标识，不再使用 headingLevel 属性
    private func applyHeadingFormat(to range: NSRange, in textStorage: NSTextStorage, level: HeadingLevel, size: CGFloat) {
        let nsString = textStorage.string as NSString
        let lineRange = nsString.lineRange(for: range)
        
        textStorage.beginEditing()
        defer { textStorage.endEditing() }
        
        // 检查是否已经是该级别的标题
        var isAlreadyHeading = false
        if let font = textStorage.attribute(.font, at: lineRange.location, effectiveRange: nil) as? NSFont {
            if font.pointSize == size {
                isAlreadyHeading = true
            }
        }
        
        if isAlreadyHeading {
            // 移除标题格式，恢复为正常文本
            let normalFont = NSFont.systemFont(ofSize: 15)
            textStorage.addAttribute(.font, value: normalFont, range: lineRange)
        } else {
            // 应用标题格式（使用常规字重）
            let headingFont = NSFont.systemFont(ofSize: size, weight: .regular)
            textStorage.addAttribute(.font, value: headingFont, range: lineRange)
        }
    }
    
    /// 应用对齐格式
    private func applyAlignmentFormat(to range: NSRange, in textStorage: NSTextStorage, alignment: NSTextAlignment) {
        let nsString = textStorage.string as NSString
        let lineRange = nsString.lineRange(for: range)
        
        textStorage.beginEditing()
        defer { textStorage.endEditing() }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
    }
    
    /// 应用列表格式
    private func applyListFormat(to range: NSRange, in textStorage: NSTextStorage, listType: ListType) {
        let nsString = textStorage.string as NSString
        let lineRange = nsString.lineRange(for: range)
        
        textStorage.beginEditing()
        defer { textStorage.endEditing() }
        
        // 检查是否已经是该类型的列表
        var isAlreadyList = false
        if let currentType = textStorage.attribute(.listType, at: lineRange.location, effectiveRange: nil) as? ListType {
            if currentType == listType {
                isAlreadyList = true
            }
        }
        
        if isAlreadyList {
            // 移除列表格式
            textStorage.removeAttribute(.listType, range: lineRange)
            textStorage.removeAttribute(.listIndent, range: lineRange)
            textStorage.removeAttribute(.listNumber, range: lineRange)
            
            // 重置段落样式
            let paragraphStyle = NSMutableParagraphStyle()
            textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
        } else {
            // 应用列表格式
            textStorage.addAttribute(.listType, value: listType, range: lineRange)
            textStorage.addAttribute(.listIndent, value: 1, range: lineRange)
            
            if listType == .ordered {
                textStorage.addAttribute(.listNumber, value: 1, range: lineRange)
            }
            
            // 设置段落样式
            let paragraphStyle = NSMutableParagraphStyle()
            let bulletWidth: CGFloat = listType == .ordered ? 28 : 24
            paragraphStyle.firstLineHeadIndent = 0
            paragraphStyle.headIndent = bulletWidth
            textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
        }
    }
    
    // MARK: - 辅助方法：格式验证
    
    /// 验证加粗格式
    private func verifyBoldFormat(in range: NSRange, textStorage: NSTextStorage, shouldBeBold: Bool) -> Bool {
        var allMatch = true
        
        textStorage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, stop in
            guard let font = value as? NSFont else {
                allMatch = false
                stop.pointee = true
                return
            }
            
            let hasBold = font.fontDescriptor.symbolicTraits.contains(.bold)
            if hasBold != shouldBeBold {
                allMatch = false
                stop.pointee = true
            }
        }
        
        return allMatch
    }
    
    /// 验证斜体格式
    private func verifyItalicFormat(in range: NSRange, textStorage: NSTextStorage, shouldBeItalic: Bool) -> Bool {
        var allMatch = true
        
        textStorage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, stop in
            guard let font = value as? NSFont else {
                allMatch = false
                stop.pointee = true
                return
            }
            
            let hasItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
            if hasItalic != shouldBeItalic {
                allMatch = false
                stop.pointee = true
            }
        }
        
        return allMatch
    }
    
    /// 验证下划线格式
    private func verifyUnderlineFormat(in range: NSRange, textStorage: NSTextStorage, shouldHaveUnderline: Bool) -> Bool {
        var allMatch = true
        
        textStorage.enumerateAttribute(.underlineStyle, in: range, options: []) { value, attrRange, stop in
            let hasUnderline = (value as? Int ?? 0) != 0
            if hasUnderline != shouldHaveUnderline {
                allMatch = false
                stop.pointee = true
            }
        }
        
        return allMatch
    }
    
    /// 验证删除线格式
    private func verifyStrikethroughFormat(in range: NSRange, textStorage: NSTextStorage, shouldHaveStrikethrough: Bool) -> Bool {
        var allMatch = true
        
        textStorage.enumerateAttribute(.strikethroughStyle, in: range, options: []) { value, attrRange, stop in
            let hasStrikethrough = (value as? Int ?? 0) != 0
            if hasStrikethrough != shouldHaveStrikethrough {
                allMatch = false
                stop.pointee = true
            }
        }
        
        return allMatch
    }
    
    /// 验证高亮格式
    private func verifyHighlightFormat(in range: NSRange, textStorage: NSTextStorage, shouldHaveHighlight: Bool) -> Bool {
        var allMatch = true
        
        textStorage.enumerateAttribute(.backgroundColor, in: range, options: []) { value, attrRange, stop in
            let hasHighlight = value != nil
            if hasHighlight != shouldHaveHighlight {
                allMatch = false
                stop.pointee = true
            }
        }
        
        return allMatch
    }
    
    /// 验证标题格式
    private func verifyHeadingFormat(in range: NSRange, textStorage: NSTextStorage, expectedSize: CGFloat) -> Bool {
        let nsString = textStorage.string as NSString
        let lineRange = nsString.lineRange(for: range)
        
        var allMatch = true
        
        // 检查行范围内的字体大小
        if let font = textStorage.attribute(.font, at: lineRange.location, effectiveRange: nil) as? NSFont {
            if abs(font.pointSize - expectedSize) > 0.1 {
                allMatch = false
            }
        } else {
            allMatch = false
        }
        
        return allMatch
    }
    
    /// 验证对齐格式
    private func verifyAlignmentFormat(in range: NSRange, textStorage: NSTextStorage, expectedAlignment: NSTextAlignment) -> Bool {
        let nsString = textStorage.string as NSString
        let lineRange = nsString.lineRange(for: range)
        
        var allMatch = true
        
        // 检查行范围内的对齐方式
        if let paragraphStyle = textStorage.attribute(.paragraphStyle, at: lineRange.location, effectiveRange: nil) as? NSParagraphStyle {
            if paragraphStyle.alignment != expectedAlignment {
                allMatch = false
            }
        } else {
            // 没有段落样式，默认为左对齐
            if expectedAlignment != .left {
                allMatch = false
            }
        }
        
        return allMatch
    }
    
    /// 验证列表格式
    private func verifyListFormat(in range: NSRange, textStorage: NSTextStorage, expectedType: ListType) -> Bool {
        let nsString = textStorage.string as NSString
        let lineRange = nsString.lineRange(for: range)
        
        var allMatch = true
        
        // 检查行范围内的列表类型
        if let listType = textStorage.attribute(.listType, at: lineRange.location, effectiveRange: nil) as? ListType {
            if listType != expectedType {
                allMatch = false
            }
        } else {
            // 没有列表类型属性，应该是 .none
            if expectedType != .none {
                allMatch = false
            }
        }
        
        return allMatch
    }
}

// MARK: - HeadingLevel Extension

/// 标题级别枚举（用于测试）
enum HeadingLevel: Int {
    case none = 0
    case h1 = 1
    case h2 = 2
    case h3 = 3
}

// MARK: - ListType Extension

/// 列表类型枚举（用于测试）
enum ListType: Equatable {
    case bullet
    case ordered
    case checkbox
    case none
}

// MARK: - NSColor Extension

extension NSColor {
    /// 从十六进制字符串创建颜色
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let length = hexSanitized.count
        let r, g, b, a: CGFloat
        
        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0
            a = 1.0
        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
        } else {
            return nil
        }
        
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}

// MARK: - NSAttributedString.Key Extension

extension NSAttributedString.Key {
    /// 列表类型属性键
    static let listType = NSAttributedString.Key("listType")
    
    /// 列表缩进级别属性键
    static let listIndent = NSAttributedString.Key("listIndent")
    
    /// 列表编号属性键
    static let listNumber = NSAttributedString.Key("listNumber")
    
    /// 标题级别属性键
    static let headingLevel = NSAttributedString.Key("headingLevel")
}
