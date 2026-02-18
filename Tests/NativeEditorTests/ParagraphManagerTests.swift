import XCTest
@testable import MiNoteLibrary

/// ParagraphManager 的单元测试
/// 测试段落边界检测算法的正确性
final class ParagraphManagerTests: XCTestCase {

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

    // MARK: - 边缘情况测试

    /// 测试空文本的情况
    func testDetectParagraphBoundaries_EmptyText() {
        // Given: 空文本
        textStorage.setAttributedString(NSAttributedString(string: ""))

        // When: 检测段落边界
        let ranges = manager.detectParagraphBoundaries(in: textStorage)

        // Then: 应该返回空数组
        XCTAssertEqual(ranges.count, 0, "空文本应该返回空数组")
    }

    /// 测试单个段落（无换行符）的情况
    func testDetectParagraphBoundaries_SingleParagraphNoNewline() {
        // Given: 单个段落，无换行符
        let text = "这是一个段落"
        textStorage.setAttributedString(NSAttributedString(string: text))

        // When: 检测段落边界
        let ranges = manager.detectParagraphBoundaries(in: textStorage)

        // Then: 应该返回一个段落
        XCTAssertEqual(ranges.count, 1, "应该检测到一个段落")
        XCTAssertEqual(ranges[0].location, 0, "段落起始位置应该是 0")
        XCTAssertEqual(ranges[0].length, text.count, "段落长度应该等于文本长度")
    }

    /// 测试只有一个换行符的情况
    func testDetectParagraphBoundaries_OnlyNewline() {
        // Given: 只有一个换行符
        textStorage.setAttributedString(NSAttributedString(string: "\n"))

        // When: 检测段落边界
        let ranges = manager.detectParagraphBoundaries(in: textStorage)

        // Then: 应该返回一个段落（包含换行符）
        XCTAssertEqual(ranges.count, 1, "应该检测到一个段落")
        XCTAssertEqual(ranges[0].location, 0, "段落起始位置应该是 0")
        XCTAssertEqual(ranges[0].length, 1, "段落长度应该是 1（包含换行符）")
    }

    // MARK: - 基本功能测试

    /// 测试两个段落（用 \n 分隔）
    func testDetectParagraphBoundaries_TwoParagraphsWithLF() {
        // Given: 两个段落，用 \n 分隔
        let text = "第一段\n第二段"
        textStorage.setAttributedString(NSAttributedString(string: text))

        // When: 检测段落边界
        let ranges = manager.detectParagraphBoundaries(in: textStorage)

        // Then: 应该返回两个段落
        XCTAssertEqual(ranges.count, 2, "应该检测到两个段落")

        // 第一个段落：包含 "第一段\n"
        XCTAssertEqual(ranges[0].location, 0, "第一段起始位置应该是 0")
        XCTAssertEqual(ranges[0].length, 4, "第一段长度应该是 4（包含换行符）")

        // 第二个段落：包含 "第二段"
        XCTAssertEqual(ranges[1].location, 4, "第二段起始位置应该是 4")
        XCTAssertEqual(ranges[1].length, 3, "第二段长度应该是 3")
    }

    /// 测试多个段落
    func testDetectParagraphBoundaries_MultipleParagraphs() {
        // Given: 三个段落
        let text = "第一段\n第二段\n第三段"
        textStorage.setAttributedString(NSAttributedString(string: text))

        // When: 检测段落边界
        let ranges = manager.detectParagraphBoundaries(in: textStorage)

        // Then: 应该返回三个段落
        XCTAssertEqual(ranges.count, 3, "应该检测到三个段落")

        XCTAssertEqual(ranges[0].location, 0, "第一段起始位置")
        XCTAssertEqual(ranges[0].length, 4, "第一段长度")

        XCTAssertEqual(ranges[1].location, 4, "第二段起始位置")
        XCTAssertEqual(ranges[1].length, 4, "第二段长度")

        XCTAssertEqual(ranges[2].location, 8, "第三段起始位置")
        XCTAssertEqual(ranges[2].length, 3, "第三段长度")
    }

    /// 测试文本以换行符结尾
    func testDetectParagraphBoundaries_EndsWithNewline() {
        // Given: 文本以换行符结尾
        let text = "第一段\n第二段\n"
        textStorage.setAttributedString(NSAttributedString(string: text))

        // When: 检测段落边界
        let ranges = manager.detectParagraphBoundaries(in: textStorage)

        // Then: 应该返回两个段落
        XCTAssertEqual(ranges.count, 2, "应该检测到两个段落")

        XCTAssertEqual(ranges[0].location, 0, "第一段起始位置")
        XCTAssertEqual(ranges[0].length, 4, "第一段长度")

        XCTAssertEqual(ranges[1].location, 4, "第二段起始位置")
        XCTAssertEqual(ranges[1].length, 4, "第二段长度（包含换行符）")
    }

    /// 测试连续的换行符
    func testDetectParagraphBoundaries_ConsecutiveNewlines() {
        // Given: 连续的换行符（空段落）
        let text = "第一段\n\n第三段"
        textStorage.setAttributedString(NSAttributedString(string: text))

        // When: 检测段落边界
        let ranges = manager.detectParagraphBoundaries(in: textStorage)

        // Then: 应该返回三个段落（包括空段落）
        XCTAssertEqual(ranges.count, 3, "应该检测到三个段落")

        XCTAssertEqual(ranges[0].location, 0, "第一段起始位置")
        XCTAssertEqual(ranges[0].length, 4, "第一段长度")

        XCTAssertEqual(ranges[1].location, 4, "空段落起始位置")
        XCTAssertEqual(ranges[1].length, 1, "空段落长度（只有换行符）")

        XCTAssertEqual(ranges[2].location, 5, "第三段起始位置")
        XCTAssertEqual(ranges[2].length, 3, "第三段长度")
    }

    // MARK: - 不同换行符测试

    /// 测试 \r 换行符
    func testDetectParagraphBoundaries_CarriageReturn() {
        // Given: 使用 \r 作为换行符
        let text = "第一段\r第二段"
        textStorage.setAttributedString(NSAttributedString(string: text))

        // When: 检测段落边界
        let ranges = manager.detectParagraphBoundaries(in: textStorage)

        // Then: 应该正确识别段落
        XCTAssertEqual(ranges.count, 2, "应该检测到两个段落")
        XCTAssertEqual(ranges[0].length, 4, "第一段长度应该包含 \\r")
        XCTAssertEqual(ranges[1].location, 4, "第二段起始位置")
    }

    /// 测试 \r\n 换行符（Windows 风格）
    func testDetectParagraphBoundaries_CRLF() {
        // Given: 使用 \r\n 作为换行符
        let text = "第一段\r\n第二段"
        textStorage.setAttributedString(NSAttributedString(string: text))

        // When: 检测段落边界
        let ranges = manager.detectParagraphBoundaries(in: textStorage)

        // Then: 应该正确识别段落，\r\n 应该被视为一个换行符
        XCTAssertEqual(ranges.count, 2, "应该检测到两个段落")
        XCTAssertEqual(ranges[0].length, 4, "第一段长度应该包含 \\r")
        // 注意：\r\n 中的 \n 应该被跳过
        XCTAssertEqual(ranges[1].location, 5, "第二段起始位置应该跳过 \\r\\n")
    }

    // MARK: - 段落覆盖性测试

    /// 测试段落范围覆盖整个文本且不重叠
    func testDetectParagraphBoundaries_CoverageAndNoOverlap() {
        // Given: 多个段落
        let text = "段落1\n段落2\n段落3"
        textStorage.setAttributedString(NSAttributedString(string: text))

        // When: 检测段落边界
        let ranges = manager.detectParagraphBoundaries(in: textStorage)

        // Then: 验证覆盖性和无重叠
        var coveredLocations = Set<Int>()

        for range in ranges {
            for location in range.location ..< (range.location + range.length) {
                // 检查是否有重叠
                XCTAssertFalse(
                    coveredLocations.contains(location),
                    "位置 \(location) 被多个段落覆盖"
                )
                coveredLocations.insert(location)
            }
        }

        // 检查是否覆盖了整个文本
        XCTAssertEqual(
            coveredLocations.count,
            text.count,
            "段落应该覆盖整个文本"
        )
    }

    // MARK: - 段落查询测试

    /// 测试按位置查询段落
    func testParagraphAtLocation() {
        // Given: 设置一些段落
        manager.setParagraphs([
            Paragraph(range: NSRange(location: 0, length: 5), type: .normal),
            Paragraph(range: NSRange(location: 5, length: 5), type: .normal),
            Paragraph(range: NSRange(location: 10, length: 5), type: .normal),
        ])

        // When & Then: 测试不同位置
        XCTAssertNotNil(manager.paragraph(at: 0), "位置 0 应该找到段落")
        XCTAssertNotNil(manager.paragraph(at: 4), "位置 4 应该找到段落")
        XCTAssertNotNil(manager.paragraph(at: 5), "位置 5 应该找到段落")
        XCTAssertNotNil(manager.paragraph(at: 10), "位置 10 应该找到段落")
        XCTAssertNotNil(manager.paragraph(at: 14), "位置 14 应该找到段落")
        XCTAssertNil(manager.paragraph(at: 15), "位置 15 应该找不到段落")
        XCTAssertNil(manager.paragraph(at: 100), "位置 100 应该找不到段落")
    }

    /// 测试按范围查询段落
    func testParagraphsInRange() {
        // Given: 设置一些段落
        manager.setParagraphs([
            Paragraph(range: NSRange(location: 0, length: 5), type: .normal),
            Paragraph(range: NSRange(location: 5, length: 5), type: .normal),
            Paragraph(range: NSRange(location: 10, length: 5), type: .normal),
        ])

        // When & Then: 测试不同范围
        let range1 = NSRange(location: 0, length: 5)
        let paragraphs1 = manager.paragraphs(in: range1)
        XCTAssertEqual(paragraphs1.count, 1, "范围 [0, 5) 应该包含 1 个段落")

        let range2 = NSRange(location: 0, length: 10)
        let paragraphs2 = manager.paragraphs(in: range2)
        XCTAssertEqual(paragraphs2.count, 2, "范围 [0, 10) 应该包含 2 个段落")

        let range3 = NSRange(location: 3, length: 5)
        let paragraphs3 = manager.paragraphs(in: range3)
        XCTAssertEqual(paragraphs3.count, 2, "范围 [3, 8) 应该包含 2 个段落")

        let range4 = NSRange(location: 15, length: 5)
        let paragraphs4 = manager.paragraphs(in: range4)
        XCTAssertEqual(paragraphs4.count, 0, "范围 [15, 20) 应该包含 0 个段落")
    }

    // MARK: - 标题段落测试

    /// 测试标题段落查询
    func testTitleParagraph() {
        // Given: 设置段落列表，第一个是标题段落
        manager.setParagraphs([
            Paragraph(range: NSRange(location: 0, length: 5), type: .title),
            Paragraph(range: NSRange(location: 5, length: 5), type: .normal),
            Paragraph(range: NSRange(location: 10, length: 5), type: .heading(level: 1)),
        ])

        // When: 查询标题段落
        let titleParagraph = manager.titleParagraph

        // Then: 应该返回第一个段落
        XCTAssertNotNil(titleParagraph, "应该找到标题段落")
        XCTAssertEqual(titleParagraph?.type, .title, "应该是标题类型")
        XCTAssertEqual(titleParagraph?.range.location, 0, "标题段落应该在位置 0")
    }

    /// 测试没有标题段落的情况
    func testTitleParagraph_NotFound() {
        // Given: 设置段落列表，没有标题段落
        manager.setParagraphs([
            Paragraph(range: NSRange(location: 0, length: 5), type: .normal),
            Paragraph(range: NSRange(location: 5, length: 5), type: .normal),
        ])

        // When: 查询标题段落
        let titleParagraph = manager.titleParagraph

        // Then: 应该返回 nil
        XCTAssertNil(titleParagraph, "没有标题段落时应该返回 nil")
    }

    // MARK: - 段落列表更新测试

    /// 测试首次初始化段落列表
    func testUpdateParagraphs_InitialLoad() {
        // Given: 空的段落列表和一些文本
        let text = "第一段\n第二段\n第三段"
        textStorage.setAttributedString(NSAttributedString(string: text))

        // When: 更新段落列表
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: 0, length: text.count))

        // Then: 应该创建所有段落
        XCTAssertEqual(manager.paragraphs.count, 3, "应该创建 3 个段落")
        XCTAssertEqual(manager.paragraphs[0].type, .title, "第一个段落应该是标题类型")
        XCTAssertEqual(manager.paragraphs[1].type, .normal, "第二个段落应该是普通类型")
        XCTAssertEqual(manager.paragraphs[2].type, .normal, "第三个段落应该是普通类型")
    }

    /// 测试在段落中间插入文本
    func testUpdateParagraphs_InsertTextInMiddle() {
        // Given: 已有段落列表
        let initialText = "第一段\n第二段"
        textStorage.setAttributedString(NSAttributedString(string: initialText))
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: 0, length: initialText.count))

        let initialVersion = manager.paragraphs[0].version

        // When: 在第一段中间插入文本
        let insertLocation = 2
        let insertText = "新"
        textStorage.insert(NSAttributedString(string: insertText), at: insertLocation)
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: insertLocation, length: insertText.count))

        // Then: 第一段的范围应该更新，版本应该递增
        XCTAssertEqual(manager.paragraphs.count, 2, "段落数量不应该变化")
        XCTAssertEqual(manager.paragraphs[0].range.length, 5, "第一段长度应该增加")
        XCTAssertGreaterThan(manager.paragraphs[0].version, initialVersion, "第一段版本应该递增")
        XCTAssertTrue(manager.paragraphs[0].needsReparse, "第一段应该标记为需要重新解析")
    }

    /// 测试插入换行符创建新段落
    func testUpdateParagraphs_InsertNewline() {
        // Given: 已有段落列表
        let initialText = "第一段"
        textStorage.setAttributedString(NSAttributedString(string: initialText))
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: 0, length: initialText.count))

        // When: 在末尾插入换行符和新文本
        let insertLocation = initialText.count
        let insertText = "\n第二段"
        textStorage.insert(NSAttributedString(string: insertText), at: insertLocation)
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: insertLocation, length: insertText.count))

        // Then: 应该创建新段落
        XCTAssertEqual(manager.paragraphs.count, 2, "应该创建新段落")
        XCTAssertEqual(manager.paragraphs[0].range.length, 4, "第一段应该包含换行符")
        XCTAssertEqual(manager.paragraphs[1].range.location, 4, "第二段起始位置正确")
        XCTAssertEqual(manager.paragraphs[1].range.length, 3, "第二段长度正确")
    }

    /// 测试删除文本
    func testUpdateParagraphs_DeleteText() {
        // Given: 已有段落列表
        let initialText = "第一段内容\n第二段"
        textStorage.setAttributedString(NSAttributedString(string: initialText))
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: 0, length: initialText.count))

        let initialVersion = manager.paragraphs[0].version

        // When: 删除第一段的部分文本
        let deleteRange = NSRange(location: 3, length: 2)
        textStorage.deleteCharacters(in: deleteRange)
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: deleteRange.location, length: 0))

        // Then: 第一段的范围应该更新
        XCTAssertEqual(manager.paragraphs.count, 2, "段落数量不应该变化")
        XCTAssertEqual(manager.paragraphs[0].range.length, 4, "第一段长度应该减少")
        XCTAssertGreaterThan(manager.paragraphs[0].version, initialVersion, "第一段版本应该递增")
    }

    /// 测试删除换行符合并段落
    func testUpdateParagraphs_DeleteNewlineMergeParagraphs() {
        // Given: 已有两个段落
        let initialText = "第一段\n第二段"
        textStorage.setAttributedString(NSAttributedString(string: initialText))
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: 0, length: initialText.count))

        // When: 删除换行符
        let deleteRange = NSRange(location: 3, length: 1)
        textStorage.deleteCharacters(in: deleteRange)
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: deleteRange.location, length: 0))

        // Then: 两个段落应该合并为一个
        XCTAssertEqual(manager.paragraphs.count, 1, "段落应该合并")
        XCTAssertEqual(manager.paragraphs[0].range.length, 6, "合并后的段落长度正确")
    }

    /// 测试段落版本跟踪
    func testUpdateParagraphs_VersionTracking() {
        // Given: 已有段落列表
        let initialText = "第一段\n第二段\n第三段"
        textStorage.setAttributedString(NSAttributedString(string: initialText))
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: 0, length: initialText.count))

        let version1 = manager.paragraphs[1].version

        // When: 修改第二段
        let insertLocation = 5
        textStorage.insert(NSAttributedString(string: "新"), at: insertLocation)
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: insertLocation, length: 1))

        let version2 = manager.paragraphs[1].version

        // Then: 第二段版本应该递增，其他段落版本不变
        XCTAssertGreaterThan(version2, version1, "修改后版本应该递增")

        // When: 再次修改第二段
        textStorage.insert(NSAttributedString(string: "文"), at: insertLocation + 1)
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: insertLocation + 1, length: 1))

        let version3 = manager.paragraphs[1].version

        // Then: 版本应该继续递增
        XCTAssertGreaterThan(version3, version2, "再次修改后版本应该继续递增")
    }

    /// 测试未受影响段落的范围调整
    func testUpdateParagraphs_AdjustUnaffectedParagraphs() {
        // Given: 已有三个段落
        let initialText = "第一段\n第二段\n第三段"
        textStorage.setAttributedString(NSAttributedString(string: initialText))
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: 0, length: initialText.count))

        let thirdParagraphInitialLocation = manager.paragraphs[2].range.location

        // When: 在第一段插入文本
        let insertLocation = 1
        let insertText = "新内容"
        textStorage.insert(NSAttributedString(string: insertText), at: insertLocation)
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: insertLocation, length: insertText.count))

        // Then: 第三段的位置应该相应调整
        let thirdParagraphNewLocation = manager.paragraphs[2].range.location
        XCTAssertEqual(
            thirdParagraphNewLocation,
            thirdParagraphInitialLocation + insertText.count,
            "第三段位置应该根据插入的文本长度调整"
        )
    }

    // MARK: - 段落格式应用测试

    /// 测试应用标题格式
    func testApplyParagraphFormat_Heading() {
        // Given: 设置文本和段落
        let text = "第一段\n第二段\n第三段"
        textStorage.setAttributedString(NSAttributedString(string: text))
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: 0, length: text.count))

        // When: 应用 H1 标题格式到第二段
        let secondParagraphRange = manager.paragraphs[1].range
        manager.applyParagraphFormat(.heading(level: 1), to: secondParagraphRange, in: textStorage)

        // Then: 第二段应该有标题格式
        let attributes = textStorage.attributes(at: secondParagraphRange.location, effectiveRange: nil)

        // 检查字体大小
        if let font = attributes[.font] as? NSFont {
            XCTAssertEqual(font.pointSize, 23, "H1 标题字体大小应该是 23pt")
        } else {
            XCTFail("应该有字体属性")
        }

        // 检查段落类型属性
        if let paragraphType = attributes[.paragraphType] as? ParagraphType {
            XCTAssertEqual(paragraphType, .heading(level: 1), "段落类型应该是 H1 标题")
        } else {
            XCTFail("应该有段落类型属性")
        }

        // 检查段落列表中的类型已更新
        XCTAssertEqual(manager.paragraphs[1].type, .heading(level: 1), "段落列表中的类型应该更新")
    }

    /// 测试应用普通段落格式
    func testApplyParagraphFormat_Normal() {
        // Given: 设置文本和段落，第二段是标题
        let text = "第一段\n第二段\n第三段"
        textStorage.setAttributedString(NSAttributedString(string: text))
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: 0, length: text.count))

        // 先应用标题格式
        let secondParagraphRange = manager.paragraphs[1].range
        manager.applyParagraphFormat(.heading(level: 1), to: secondParagraphRange, in: textStorage)

        // When: 应用普通段落格式
        manager.applyParagraphFormat(.normal, to: secondParagraphRange, in: textStorage)

        // Then: 第二段应该恢复为普通格式
        let attributes = textStorage.attributes(at: secondParagraphRange.location, effectiveRange: nil)

        // 检查字体大小恢复为正文大小
        if let font = attributes[.font] as? NSFont {
            XCTAssertEqual(font.pointSize, 14, "普通段落字体大小应该是 14pt")
        } else {
            XCTFail("应该有字体属性")
        }

        // 检查段落类型属性
        if let paragraphType = attributes[.paragraphType] as? ParagraphType {
            XCTAssertEqual(paragraphType, .normal, "段落类型应该是普通段落")
        } else {
            XCTFail("应该有段落类型属性")
        }

        // 检查块级格式属性已移除
        XCTAssertNil(attributes[.isTitle], "标题属性应该被移除")
        XCTAssertNil(attributes[.listType], "列表类型属性应该被移除")
        XCTAssertNil(attributes[.quoteBlock], "引用块属性应该被移除")
    }

    /// 测试应用列表格式
    func testApplyParagraphFormat_List() {
        // Given: 设置文本和段落
        let text = "第一段\n第二段\n第三段"
        textStorage.setAttributedString(NSAttributedString(string: text))
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: 0, length: text.count))

        // When: 应用无序列表格式到第二段
        let secondParagraphRange = manager.paragraphs[1].range
        manager.applyParagraphFormat(.list(.bullet), to: secondParagraphRange, in: textStorage)

        // Then: 第二段应该有列表格式
        let attributes = textStorage.attributes(at: secondParagraphRange.location, effectiveRange: nil)

        // 检查列表类型属性（存储为 ListType 枚举）
        let hasListType = attributes[.listType] != nil
        XCTAssertTrue(hasListType, "应该有列表类型属性")

        // 检查列表缩进属性
        if let listIndent = attributes[.listIndent] as? Int {
            XCTAssertEqual(listIndent, 1, "列表缩进应该是 1")
        } else {
            XCTFail("应该有列表缩进属性")
        }

        // 检查段落样式
        if let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle {
            XCTAssertEqual(paragraphStyle.headIndent, 24, "列表头部缩进应该是 24")
        } else {
            XCTFail("应该有段落样式")
        }

        // 检查段落列表中的类型已更新
        XCTAssertEqual(manager.paragraphs[1].type, .list(.bullet), "段落列表中的类型应该更新")
    }

    /// 测试应用引用格式
    func testApplyParagraphFormat_Quote() {
        // Given: 设置文本和段落
        let text = "第一段\n第二段\n第三段"
        textStorage.setAttributedString(NSAttributedString(string: text))
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: 0, length: text.count))

        // When: 应用引用格式到第二段
        let secondParagraphRange = manager.paragraphs[1].range
        manager.applyParagraphFormat(.quote, to: secondParagraphRange, in: textStorage)

        // Then: 第二段应该有引用格式
        let attributes = textStorage.attributes(at: secondParagraphRange.location, effectiveRange: nil)

        // 检查引用块属性
        if let isQuote = attributes[.quoteBlock] as? Bool {
            XCTAssertTrue(isQuote, "应该标记为引用块")
        } else {
            XCTFail("应该有引用块属性")
        }

        // 检查引用缩进属性
        if let quoteIndent = attributes[.quoteIndent] as? Int {
            XCTAssertEqual(quoteIndent, 1, "引用缩进应该是 1")
        } else {
            XCTFail("应该有引用缩进属性")
        }

        // 检查背景色
        XCTAssertNotNil(attributes[.backgroundColor], "应该有背景色")

        // 检查段落列表中的类型已更新
        XCTAssertEqual(manager.paragraphs[1].type, .quote, "段落列表中的类型应该更新")
    }

    /// 测试应用格式到多个段落
    func testApplyParagraphFormat_MultipleParagraphs() {
        // Given: 设置文本和段落
        let text = "第一段\n第二段\n第三段"
        textStorage.setAttributedString(NSAttributedString(string: text))
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: 0, length: text.count))

        // When: 应用 H2 标题格式到跨越第二和第三段的范围
        let range = NSRange(location: 5, length: 6) // 覆盖第二段和第三段
        manager.applyParagraphFormat(.heading(level: 2), to: range, in: textStorage)

        // Then: 第二段和第三段都应该有标题格式
        let secondParagraphAttrs = textStorage.attributes(at: manager.paragraphs[1].range.location, effectiveRange: nil)
        let thirdParagraphAttrs = textStorage.attributes(at: manager.paragraphs[2].range.location, effectiveRange: nil)

        // 检查第二段
        if let font = secondParagraphAttrs[.font] as? NSFont {
            XCTAssertEqual(font.pointSize, 20, "H2 标题字体大小应该是 20pt")
        }
        if let paragraphType = secondParagraphAttrs[.paragraphType] as? ParagraphType {
            XCTAssertEqual(paragraphType, .heading(level: 2), "第二段类型应该是 H2 标题")
        }

        // 检查第三段
        if let font = thirdParagraphAttrs[.font] as? NSFont {
            XCTAssertEqual(font.pointSize, 20, "H2 标题字体大小应该是 20pt")
        }
        if let paragraphType = thirdParagraphAttrs[.paragraphType] as? ParagraphType {
            XCTAssertEqual(paragraphType, .heading(level: 2), "第三段类型应该是 H2 标题")
        }

        // 检查段落列表中的类型已更新
        XCTAssertEqual(manager.paragraphs[1].type, .heading(level: 2), "第二段在段落列表中的类型应该更新")
        XCTAssertEqual(manager.paragraphs[2].type, .heading(level: 2), "第三段在段落列表中的类型应该更新")
    }

    /// 测试格式在整个段落内一致
    func testApplyParagraphFormat_ConsistencyAcrossParagraph() {
        // Given: 设置文本和段落
        let text = "这是一个较长的段落，包含多个字符"
        textStorage.setAttributedString(NSAttributedString(string: text))
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: 0, length: text.count))

        // When: 应用标题格式
        let paragraphRange = manager.paragraphs[0].range
        manager.applyParagraphFormat(.heading(level: 3), to: paragraphRange, in: textStorage)

        // Then: 整个段落的格式应该一致
        var previousFont: NSFont?
        var previousParagraphType: ParagraphType?

        for location in paragraphRange.location ..< (paragraphRange.location + paragraphRange.length) {
            let attributes = textStorage.attributes(at: location, effectiveRange: nil)

            if let font = attributes[.font] as? NSFont {
                if let prevFont = previousFont {
                    XCTAssertEqual(font.pointSize, prevFont.pointSize, "位置 \(location) 的字体大小应该一致")
                }
                previousFont = font
            }

            if let paragraphType = attributes[.paragraphType] as? ParagraphType {
                if let prevType = previousParagraphType {
                    XCTAssertEqual(paragraphType, prevType, "位置 \(location) 的段落类型应该一致")
                }
                previousParagraphType = paragraphType
            }
        }

        // 确保至少检查了一些属性
        XCTAssertNotNil(previousFont, "应该检查了字体属性")
        XCTAssertNotNil(previousParagraphType, "应该检查了段落类型属性")
    }

    /// 测试应用标题段落格式
    func testApplyParagraphFormat_Title() {
        // Given: 设置文本和段落
        let text = "标题段落\n正文段落"
        textStorage.setAttributedString(NSAttributedString(string: text))
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: 0, length: text.count))

        // When: 应用标题段落格式到第一段
        let firstParagraphRange = manager.paragraphs[0].range
        manager.applyParagraphFormat(.title, to: firstParagraphRange, in: textStorage)

        // Then: 第一段应该有标题段落格式
        let attributes = textStorage.attributes(at: firstParagraphRange.location, effectiveRange: nil)

        // 检查字体大小（标题段落使用较大字体）
        if let font = attributes[.font] as? NSFont {
            XCTAssertEqual(font.pointSize, 18, "标题段落字体大小应该是 18pt")
        } else {
            XCTFail("应该有字体属性")
        }

        // 检查标题标记属性
        if let isTitle = attributes[.isTitle] as? Bool {
            XCTAssertTrue(isTitle, "应该标记为标题段落")
        } else {
            XCTFail("应该有标题标记属性")
        }

        // 检查段落类型属性
        if let paragraphType = attributes[.paragraphType] as? ParagraphType {
            XCTAssertEqual(paragraphType, .title, "段落类型应该是标题段落")
        } else {
            XCTFail("应该有段落类型属性")
        }

        // 检查段落列表中的类型已更新
        XCTAssertEqual(manager.paragraphs[0].type, .title, "段落列表中的类型应该更新为标题段落")
    }

    /// 测试应用代码块格式
    func testApplyParagraphFormat_Code() {
        // Given: 设置文本和段落
        let text = "第一段\n第二段\n第三段"
        textStorage.setAttributedString(NSAttributedString(string: text))
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: 0, length: text.count))

        // When: 应用代码块格式到第二段
        let secondParagraphRange = manager.paragraphs[1].range
        manager.applyParagraphFormat(.code, to: secondParagraphRange, in: textStorage)

        // Then: 第二段应该有代码块格式
        let attributes = textStorage.attributes(at: secondParagraphRange.location, effectiveRange: nil)

        // 检查字体（应该是等宽字体）
        if let font = attributes[.font] as? NSFont {
            XCTAssertEqual(font.pointSize, 13, "代码块字体大小应该是 13pt")
            // 检查是否是等宽字体（通过检查字体是否是 monospaced）
            // 在 macOS 上，monospacedSystemFont 会返回 SF Mono 或类似的等宽字体
            print("代码块字体: \(font.fontName)")
        } else {
            XCTFail("应该有字体属性")
        }

        // 检查背景色
        XCTAssertNotNil(attributes[.backgroundColor], "代码块应该有背景色")

        // 检查段落类型属性
        if let paragraphType = attributes[.paragraphType] as? ParagraphType {
            XCTAssertEqual(paragraphType, .code, "段落类型应该是代码块")
        } else {
            XCTFail("应该有段落类型属性")
        }

        // 检查段落列表中的类型已更新
        XCTAssertEqual(manager.paragraphs[1].type, .code, "段落列表中的类型应该更新为代码块")
    }
}
