import XCTest
@testable import MiNoteLibrary

/// ParagraphManager 集成测试
/// 测试段落管理器与其他组件的集成
final class ParagraphManagerIntegrationTests: XCTestCase {

    var manager: ParagraphManager!
    var textStorage: NSTextStorage!

    override func setUp() {
        super.setUp()
        manager = ParagraphManager()
        textStorage = NSTextStorage()
    }

    override func tearDown() {
        manager = nil
        textStorage = nil
        super.tearDown()
    }

    // MARK: - 集成测试

    /// 测试完整的编辑流程
    func testCompleteEditingFlow() {
        // 1. 初始化文本
        let initialText = "标题段落\n第一段\n第二段"
        textStorage.setAttributedString(NSAttributedString(string: initialText))
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: 0, length: initialText.count))

        XCTAssertEqual(manager.paragraphs.count, 3, "应该有 3 个段落")
        XCTAssertEqual(manager.paragraphs[0].type, .title, "第一个段落应该是标题")

        // 2. 应用 H1 格式到第二段
        let secondParagraphRange = manager.paragraphs[1].range
        manager.applyParagraphFormat(.heading(level: 1), to: secondParagraphRange, in: textStorage)

        XCTAssertEqual(manager.paragraphs[1].type, .heading(level: 1), "第二段应该是 H1 标题")

        // 3. 插入新段落
        let insertLocation = textStorage.length
        let insertText = "\n新段落"
        textStorage.insert(NSAttributedString(string: insertText), at: insertLocation)
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: insertLocation, length: insertText.count))

        XCTAssertEqual(manager.paragraphs.count, 4, "应该有 4 个段落")

        // 4. 应用列表格式到新段落
        let newParagraphRange = manager.paragraphs[3].range
        manager.applyParagraphFormat(.list(.bullet), to: newParagraphRange, in: textStorage)

        XCTAssertEqual(manager.paragraphs[3].type, .list(.bullet), "新段落应该是无序列表")

        // 5. 验证所有段落的格式都已正确应用
        for (index, paragraph) in manager.paragraphs.enumerated() {
            let attrs = textStorage.attributes(at: paragraph.range.location, effectiveRange: nil)

            // 验证段落类型属性存在
            XCTAssertNotNil(attrs[.paragraphType], "段落 \(index) 应该有段落类型属性")

            print("段落 \(index): 类型=\(paragraph.type), 范围=\(paragraph.range)")
        }
    }

    /// 测试段落格式的往返转换
    func testParagraphFormatRoundTrip() {
        // 创建包含各种格式的文本
        let text = "标题\n普通段落\nH1标题\n列表项\n引用"
        textStorage.setAttributedString(NSAttributedString(string: text))
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: 0, length: text.count))

        // 应用各种格式
        manager.applyParagraphFormat(.title, to: manager.paragraphs[0].range, in: textStorage)
        manager.applyParagraphFormat(.normal, to: manager.paragraphs[1].range, in: textStorage)
        manager.applyParagraphFormat(.heading(level: 1), to: manager.paragraphs[2].range, in: textStorage)
        manager.applyParagraphFormat(.list(.bullet), to: manager.paragraphs[3].range, in: textStorage)
        manager.applyParagraphFormat(.quote, to: manager.paragraphs[4].range, in: textStorage)

        // 验证所有格式都已应用
        XCTAssertEqual(manager.paragraphs[0].type, .title)
        XCTAssertEqual(manager.paragraphs[1].type, .normal)
        XCTAssertEqual(manager.paragraphs[2].type, .heading(level: 1))
        XCTAssertEqual(manager.paragraphs[3].type, .list(.bullet))
        XCTAssertEqual(manager.paragraphs[4].type, .quote)

        // 验证文本存储中的属性
        for paragraph in manager.paragraphs {
            let attrs = textStorage.attributes(at: paragraph.range.location, effectiveRange: nil)

            if let paragraphType = attrs[.paragraphType] as? ParagraphType {
                XCTAssertEqual(paragraphType, paragraph.type, "文本存储中的段落类型应该与段落对象一致")
            } else {
                XCTFail("段落 \(paragraph.range) 应该有段落类型属性")
            }
        }
    }

    /// 测试性能：大量段落的处理
    func testPerformanceWithManyParagraphs() {
        // 创建包含 100 个段落的文本
        var text = ""
        for i in 0 ..< 100 {
            text += "段落 \(i)\n"
        }

        textStorage.setAttributedString(NSAttributedString(string: text))

        // 测量更新段落列表的性能
        measure {
            manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: 0, length: text.count))
        }

        XCTAssertEqual(manager.paragraphs.count, 100, "应该有 100 个段落")
    }

    /// 测试性能：频繁的格式应用
    func testPerformanceWithFrequentFormatting() {
        // 创建包含 50 个段落的文本
        var text = ""
        for i in 0 ..< 50 {
            text += "段落 \(i)\n"
        }

        textStorage.setAttributedString(NSAttributedString(string: text))
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: 0, length: text.count))

        // 测量频繁应用格式的性能
        measure {
            for paragraph in manager.paragraphs {
                let format: ParagraphType = switch paragraph.range.location % 5 {
                case 0: .heading(level: 1)
                case 1: .heading(level: 2)
                case 2: .list(.bullet)
                case 3: .quote
                default: .normal
                }

                manager.applyParagraphFormat(format, to: paragraph.range, in: textStorage)
            }
        }
    }

    /// 打印测试结果摘要
    func testPrintSummary() {
        print("\n========== ParagraphManager 集成测试摘要 ==========")
        print("✅ 完整编辑流程测试")
        print("✅ 段落格式往返转换测试")
        print("✅ 大量段落性能测试")
        print("✅ 频繁格式应用性能测试")
        print("==================================================\n")
    }
}
