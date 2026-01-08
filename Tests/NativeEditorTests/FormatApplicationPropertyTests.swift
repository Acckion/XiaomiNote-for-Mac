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
