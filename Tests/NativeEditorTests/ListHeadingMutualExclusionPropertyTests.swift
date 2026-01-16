//
//  ListHeadingMutualExclusionPropertyTests.swift
//  MiNoteLibraryTests
//
//  列表与标题互斥属性测试
//  Property 5: 列表与标题格式互斥
//  验证需求: 5.1, 5.2, 5.3
//
//  Feature: list-format-enhancement, Property 5: 列表与标题格式互斥
//

import XCTest
import AppKit
@testable import MiNoteLibrary

/// 列表与标题互斥属性测试
///
/// 本测试套件使用基于属性的测试方法，通过生成随机输入来验证列表与标题格式互斥的正确性。
/// 每个测试运行 100 次迭代，确保在各种输入条件下互斥逻辑的一致性。
///
/// **Property 5: 列表与标题格式互斥**
/// *For any* 行，列表格式和标题格式不能同时存在。当应用列表格式时，标题格式应该被移除；
/// 当应用标题格式时，列表格式应该被移除。列表行的字体大小应该始终为正文大小（14pt）。
/// 
@MainActor
final class ListHeadingMutualExclusionPropertyTests: XCTestCase {
    
    // MARK: - Properties
    
    var textStorage: NSTextStorage!
    var textView: NSTextView!
    
    // MARK: - 常量
    
    /// 正文字体大小
    private var bodyFontSize: CGFloat { FontSizeManager.shared.bodySize }
    
    /// 标题字体大小
    private let headingSizes: [(level: Int, size: CGFloat, name: String)] = [
        (1, 23, "大标题"),
        (2, 20, "二级标题"),
        (3, 17, "三级标题")
    ]
    
    /// 列表类型
    private let listTypes: [(type: MiNoteLibrary.ListType, name: String)] = [
        (.bullet, "无序列表"),
        (.ordered, "有序列表")
    ]
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // 创建测试用的文本存储和文本视图
        textStorage = NSTextStorage()
        
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer()
        layoutManager.addTextContainer(textContainer)
        textView = NSTextView(frame: .zero, textContainer: textContainer)
    }
    
    override func tearDown() async throws {
        textStorage = nil
        textView = nil
        try await super.tearDown()
    }
    
    // MARK: - Property 5.1: 应用列表格式时移除标题格式
    
    /// 属性测试：应用无序列表时移除标题格式
    ///
    /// **属性**: 对于任何标题行，当应用无序列表格式时，标题格式应该被移除，字体大小应该变为正文大小
    /// **验证需求**: 5.1, 5.3
    ///
    /// 测试策略：
    /// 1. 生成随机文本内容
    /// 2. 随机选择一个标题级别并应用
    /// 3. 应用无序列表格式
    /// 4. 验证标题格式已移除（字体大小为正文大小）
    /// 5. 验证列表格式已应用
    func testProperty5_1_ApplyBulletListRemovesHeadingFormat() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 应用无序列表时移除标题格式 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomText(minLength: 5, maxLength: 50) + "\n"
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            let fullRange = NSRange(location: 0, length: testText.count)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: bodyFontSize), range: fullRange)
            textStorage.setAttributedString(attributedString)
            
            // 3. 随机选择一个标题级别并应用
            let headingInfo = headingSizes.randomElement()!
            let headingFont = NSFont.systemFont(ofSize: headingInfo.size, weight: .regular)
            let lineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: 0, length: 0))
            textStorage.addAttribute(.font, value: headingFont, range: lineRange)
            
            // 验证标题格式已应用
            if let font = textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
                XCTAssertEqual(font.pointSize, headingInfo.size, 
                    "迭代 \(iteration): 标题格式应该已应用")
            }
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(testText.count), 标题级别=\(headingInfo.name)")
            
            // 4. 应用无序列表格式
            ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: 0, length: 0))
            
            // 5. 验证标题格式已移除（字体大小为正文大小）
            let fontSizeIsBody = verifyFontSizeIsBody(in: textStorage, at: 0)
            XCTAssertTrue(fontSizeIsBody, 
                "迭代 \(iteration): 应用无序列表后，字体大小应该是正文大小 \(bodyFontSize)pt")
            
            // 6. 验证列表格式已应用
            let listType = ListFormatHandler.detectListType(in: textStorage, at: 0)
            XCTAssertEqual(listType, .bullet, 
                "迭代 \(iteration): 应该检测到无序列表格式")
        }
        
        print("[PropertyTest] ✅ 应用无序列表时移除标题格式测试完成")
    }
    
    /// 属性测试：应用有序列表时移除标题格式
    ///
    /// **属性**: 对于任何标题行，当应用有序列表格式时，标题格式应该被移除，字体大小应该变为正文大小
    /// **验证需求**: 5.1, 5.3
    func testProperty5_1_ApplyOrderedListRemovesHeadingFormat() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 应用有序列表时移除标题格式 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomText(minLength: 5, maxLength: 50) + "\n"
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            let fullRange = NSRange(location: 0, length: testText.count)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: bodyFontSize), range: fullRange)
            textStorage.setAttributedString(attributedString)
            
            // 3. 随机选择一个标题级别并应用
            let headingInfo = headingSizes.randomElement()!
            let headingFont = NSFont.systemFont(ofSize: headingInfo.size, weight: .regular)
            let lineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: 0, length: 0))
            textStorage.addAttribute(.font, value: headingFont, range: lineRange)
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(testText.count), 标题级别=\(headingInfo.name)")
            
            // 4. 应用有序列表格式
            ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: 0, length: 0))
            
            // 5. 验证标题格式已移除（字体大小为正文大小）
            let fontSizeIsBody = verifyFontSizeIsBody(in: textStorage, at: 0)
            XCTAssertTrue(fontSizeIsBody, 
                "迭代 \(iteration): 应用有序列表后，字体大小应该是正文大小 \(bodyFontSize)pt")
            
            // 6. 验证列表格式已应用
            let listType = ListFormatHandler.detectListType(in: textStorage, at: 0)
            XCTAssertEqual(listType, .ordered, 
                "迭代 \(iteration): 应该检测到有序列表格式")
        }
        
        print("[PropertyTest] ✅ 应用有序列表时移除标题格式测试完成")
    }
    
    // MARK: - Property 5.2: 应用标题格式时移除列表格式
    
    /// 属性测试：应用标题格式时移除列表格式
    ///
    /// **属性**: 对于任何列表行，当应用标题格式时，列表格式应该被移除
    /// **验证需求**: 5.2
    ///
    /// 测试策略：
    /// 1. 生成随机文本内容
    /// 2. 随机选择一个列表类型并应用
    /// 3. 调用标题-列表互斥处理
    /// 4. 验证列表格式已移除
    func testProperty5_2_ApplyHeadingRemovesListFormat() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 应用标题格式时移除列表格式 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomText(minLength: 5, maxLength: 50) + "\n"
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            let fullRange = NSRange(location: 0, length: testText.count)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: bodyFontSize), range: fullRange)
            textStorage.setAttributedString(attributedString)
            
            // 3. 随机选择一个列表类型并应用
            let listInfo = listTypes.randomElement()!
            if listInfo.type == .bullet {
                ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: 0, length: 0))
            } else {
                ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: 0, length: 0))
            }
            
            // 验证列表格式已应用
            let listTypeBeforeHeading = ListFormatHandler.detectListType(in: textStorage, at: 0)
            XCTAssertEqual(listTypeBeforeHeading, listInfo.type, 
                "迭代 \(iteration): 列表格式应该已应用")
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(testText.count), 列表类型=\(listInfo.name)")
            
            // 4. 调用标题-列表互斥处理（模拟应用标题格式前的处理）
            let lineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: 0, length: 0))
            let removed = ListFormatHandler.handleHeadingListMutualExclusion(in: textStorage, range: lineRange)
            
            // 5. 验证列表格式已移除
            XCTAssertTrue(removed, 
                "迭代 \(iteration): handleHeadingListMutualExclusion 应该返回 true")
            
            let listTypeAfterHeading = ListFormatHandler.detectListType(in: textStorage, at: 0)
            XCTAssertEqual(listTypeAfterHeading, .none, 
                "迭代 \(iteration): 应用标题格式后，列表格式应该被移除")
        }
        
        print("[PropertyTest] ✅ 应用标题格式时移除列表格式测试完成")
    }
    
    // MARK: - Property 5.3: 列表行始终使用正文字体大小
    
    /// 属性测试：列表行始终使用正文字体大小
    ///
    /// **属性**: 对于任何列表行，字体大小应该始终为正文大小（14pt）
    /// **验证需求**: 5.3
    ///
    /// 测试策略：
    /// 1. 生成随机文本内容
    /// 2. 随机选择一个列表类型并应用
    /// 3. 验证字体大小为正文大小
    func testProperty5_3_ListAlwaysUsesBodyFontSize() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 列表行始终使用正文字体大小 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomText(minLength: 5, maxLength: 50) + "\n"
            
            // 2. 设置初始文本（使用随机字体大小）
            let attributedString = NSMutableAttributedString(string: testText)
            let randomFontSize = CGFloat.random(in: 10...30)
            let fullRange = NSRange(location: 0, length: testText.count)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: randomFontSize), range: fullRange)
            textStorage.setAttributedString(attributedString)
            
            // 3. 随机选择一个列表类型并应用
            let listInfo = listTypes.randomElement()!
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(testText.count), 初始字体大小=\(randomFontSize), 列表类型=\(listInfo.name)")
            
            if listInfo.type == .bullet {
                ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: 0, length: 0))
            } else {
                ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: 0, length: 0))
            }
            
            // 4. 验证字体大小为正文大小
            let fontSizeIsBody = verifyFontSizeIsBody(in: textStorage, at: 0)
            XCTAssertTrue(fontSizeIsBody, 
                "迭代 \(iteration): 列表行的字体大小应该是正文大小 \(bodyFontSize)pt")
        }
        
        print("[PropertyTest] ✅ 列表行始终使用正文字体大小测试完成")
    }
    
    // MARK: - 综合属性测试：列表与标题格式互斥
    
    /// 综合属性测试：列表与标题格式不能同时存在
    ///
    /// **属性**: 对于任何行，列表格式和标题格式不能同时存在
    /// **验证需求**: 5.1, 5.2, 5.3
    ///
    /// 测试策略：
    /// 1. 生成随机文本内容
    /// 2. 随机选择先应用列表还是标题
    /// 3. 应用第一种格式
    /// 4. 应用第二种格式
    /// 5. 验证只有第二种格式存在
    func testProperty5_ListAndHeadingMutualExclusion() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 列表与标题格式互斥 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomText(minLength: 5, maxLength: 50) + "\n"
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            let fullRange = NSRange(location: 0, length: testText.count)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: bodyFontSize), range: fullRange)
            textStorage.setAttributedString(attributedString)
            
            // 3. 随机选择先应用列表还是标题
            let applyListFirst = Bool.random()
            let listInfo = listTypes.randomElement()!
            let headingInfo = headingSizes.randomElement()!
            
            print("[PropertyTest] 迭代 \(iteration): 先应用\(applyListFirst ? listInfo.name : headingInfo.name)")
            
            if applyListFirst {
                // 先应用列表，再应用标题
                if listInfo.type == .bullet {
                    ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: 0, length: 0))
                } else {
                    ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: 0, length: 0))
                }
                
                // 验证列表格式已应用
                let listTypeAfterList = ListFormatHandler.detectListType(in: textStorage, at: 0)
                XCTAssertEqual(listTypeAfterList, listInfo.type, 
                    "迭代 \(iteration): 列表格式应该已应用")
                
                // 应用标题格式（先调用互斥处理）
                let lineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: 0, length: 0))
                ListFormatHandler.handleHeadingListMutualExclusion(in: textStorage, range: lineRange)
                
                // 验证列表格式已移除
                let listTypeAfterHeading = ListFormatHandler.detectListType(in: textStorage, at: 0)
                XCTAssertEqual(listTypeAfterHeading, .none, 
                    "迭代 \(iteration): 应用标题后，列表格式应该被移除")
                
            } else {
                // 先应用标题，再应用列表
                let headingFont = NSFont.systemFont(ofSize: headingInfo.size, weight: .regular)
                let lineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: 0, length: 0))
                textStorage.addAttribute(.font, value: headingFont, range: lineRange)
                
                // 验证标题格式已应用
                if let font = textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
                    XCTAssertEqual(font.pointSize, headingInfo.size, 
                        "迭代 \(iteration): 标题格式应该已应用")
                }
                
                // 应用列表格式
                if listInfo.type == .bullet {
                    ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: 0, length: 0))
                } else {
                    ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: 0, length: 0))
                }
                
                // 验证标题格式已移除（字体大小为正文大小）
                let fontSizeIsBody = verifyFontSizeIsBody(in: textStorage, at: 0)
                XCTAssertTrue(fontSizeIsBody, 
                    "迭代 \(iteration): 应用列表后，字体大小应该是正文大小")
                
                // 验证列表格式已应用
                let listTypeAfterList = ListFormatHandler.detectListType(in: textStorage, at: 0)
                XCTAssertEqual(listTypeAfterList, listInfo.type, 
                    "迭代 \(iteration): 列表格式应该已应用")
            }
        }
        
        print("[PropertyTest] ✅ 列表与标题格式互斥测试完成")
    }
    
    // MARK: - 属性测试：保留字体特性
    
    /// 属性测试：应用列表时保留加粗特性
    ///
    /// **属性**: 当标题行有加粗特性时，应用列表格式后应该保留加粗特性
    /// **验证需求**: 5.1, 5.3
    func testProperty5_PreserveBoldTraitWhenApplyingList() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 应用列表时保留加粗特性 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomText(minLength: 5, maxLength: 50) + "\n"
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            let fullRange = NSRange(location: 0, length: testText.count)
            
            // 3. 随机选择一个标题级别并应用加粗
            let headingInfo = headingSizes.randomElement()!
            let boldHeadingFont = NSFont.boldSystemFont(ofSize: headingInfo.size)
            attributedString.addAttribute(.font, value: boldHeadingFont, range: fullRange)
            textStorage.setAttributedString(attributedString)
            
            // 验证加粗标题格式已应用
            if let font = textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
                XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold), 
                    "迭代 \(iteration): 加粗特性应该已应用")
            }
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(testText.count), 标题级别=\(headingInfo.name)")
            
            // 4. 随机选择一个列表类型并应用
            let listInfo = listTypes.randomElement()!
            if listInfo.type == .bullet {
                ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: 0, length: 0))
            } else {
                ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: 0, length: 0))
            }
            
            // 5. 验证字体大小为正文大小
            let fontSizeIsBody = verifyFontSizeIsBody(in: textStorage, at: 0)
            XCTAssertTrue(fontSizeIsBody, 
                "迭代 \(iteration): 应用列表后，字体大小应该是正文大小")
            
            // 6. 验证加粗特性保留
            let hasBold = verifyBoldTrait(in: textStorage, at: 0)
            XCTAssertTrue(hasBold, 
                "迭代 \(iteration): 应用列表后，加粗特性应该保留")
        }
        
        print("[PropertyTest] ✅ 应用列表时保留加粗特性测试完成")
    }
    
    // MARK: - 辅助方法：随机数据生成
    
    /// 生成随机文本
    private func generateRandomText(minLength: Int, maxLength: Int) -> String {
        let length = Int.random(in: minLength...maxLength)
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789中文测试 "
        return String((0..<length).map { _ in characters.randomElement()! })
    }
    
    // MARK: - 辅助方法：格式验证
    
    /// 验证字体大小是否为正文大小
    private func verifyFontSizeIsBody(in textStorage: NSTextStorage, at position: Int) -> Bool {
        guard position >= 0 && position < textStorage.length else { return false }
        
        // 获取当前行范围
        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: position, length: 0))
        
        var foundBodyFont = false
        textStorage.enumerateAttribute(.font, in: lineRange, options: []) { value, _, _ in
            if let font = value as? NSFont {
                // 允许小误差（浮点数比较）
                if abs(font.pointSize - bodyFontSize) < 0.1 {
                    foundBodyFont = true
                }
            }
        }
        
        return foundBodyFont
    }
    
    /// 验证是否有加粗特性
    private func verifyBoldTrait(in textStorage: NSTextStorage, at position: Int) -> Bool {
        guard position >= 0 && position < textStorage.length else { return false }
        
        // 获取当前行范围
        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: position, length: 0))
        
        var hasBold = false
        textStorage.enumerateAttribute(.font, in: lineRange, options: []) { value, _, stop in
            if let font = value as? NSFont {
                if font.fontDescriptor.symbolicTraits.contains(.bold) {
                    hasBold = true
                    stop.pointee = true
                }
            }
        }
        
        return hasBold
    }
}
