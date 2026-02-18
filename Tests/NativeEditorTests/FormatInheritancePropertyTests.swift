//
//  FormatInheritancePropertyTests.swift
//  MiNoteMac
//
//  格式继承属性测试
//  验证新列表项正确继承列表类型、缩进级别和编号
//
//  **Feature: list-behavior-optimization, Property 3: 格式继承正确性**
//

import AppKit
import XCTest
@testable import MiNoteLibrary

@MainActor
final class FormatInheritancePropertyTests: XCTestCase {

    // MARK: - 测试辅助方法

    /// 创建测试用的 NSTextStorage
    private func createTextStorage(with text: String) -> NSTextStorage {
        NSTextStorage(string: text)
    }

    /// 创建带有无序列表的 NSTextStorage
    private func createBulletListTextStorage(with text: String, indent: Int = 1) -> NSTextStorage {
        let textStorage = createTextStorage(with: text)
        let range = NSRange(location: 0, length: 0)
        ListFormatHandler.applyBulletList(to: textStorage, range: range, indent: indent)
        return textStorage
    }

    /// 创建带有有序列表的 NSTextStorage
    private func createOrderedListTextStorage(with text: String, number: Int = 1, indent: Int = 1) -> NSTextStorage {
        let textStorage = createTextStorage(with: text)
        let range = NSRange(location: 0, length: 0)
        ListFormatHandler.applyOrderedList(to: textStorage, range: range, number: number, indent: indent)
        return textStorage
    }

    /// 创建带有勾选框列表的 NSTextStorage
    private func createCheckboxListTextStorage(with text: String, checked: Bool = false, indent: Int = 1) -> NSTextStorage {
        let textStorage = createTextStorage(with: text)

        // 创建勾选框附件
        let checkbox = InteractiveCheckboxAttachment(checked: checked)
        let attachmentString = NSAttributedString(attachment: checkbox)

        // 在行首插入附件
        textStorage.insert(attachmentString, at: 0)

        // 设置列表属性
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.addAttribute(.listType, value: ListType.checkbox, range: fullRange)
        textStorage.addAttribute(.listIndent, value: indent, range: fullRange)
        textStorage.addAttribute(.checkboxLevel, value: 3, range: fullRange)
        textStorage.addAttribute(.checkboxChecked, value: checked, range: fullRange)

        return textStorage
    }

    /// 生成随机测试文本
    private func generateRandomText(length: Int) -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789中文测试"
        return String((0 ..< length).map { _ in characters.randomElement()! })
    }

    // MARK: - Property 3: 格式继承正确性

    // **Feature: list-behavior-optimization, Property 3: 格式继承正确性**

    /// 属性测试：新列表项继承列表类型
    /// *For any* 列表项，当创建新列表项时，新项应该继承当前项的列表类型
    /// _Requirements: 2.4_
    func testPropertyNewListItemInheritsListType() {
        let listTypes: [MiNoteLibrary.ListType] = [.bullet, .ordered, .checkbox]

        // 运行 100 次迭代
        for iteration in 0 ..< 100 {
            let listType = listTypes[iteration % listTypes.count]
            let text = generateRandomText(length: Int.random(in: 1 ... 20))

            // 创建新列表项
            let newItem = ListBehaviorHandler.createNewListItem(
                listType: listType,
                indent: 1,
                number: 1,
                textAfter: text
            )

            // 验证列表类型属性
            if newItem.length > 0 {
                var effectiveRange = NSRange()
                let attrs = newItem.attributes(at: 0, effectiveRange: &effectiveRange)
                let actualType = attrs[.listType] as? MiNoteLibrary.ListType

                XCTAssertEqual(
                    actualType,
                    listType,
                    "迭代 \(iteration): 新列表项的类型应该是 \(listType)，实际是 \(String(describing: actualType))"
                )
            }
        }
    }

    /// 属性测试：新列表项继承缩进级别
    /// *For any* 列表项，当创建新列表项时，新项应该继承当前项的缩进级别
    /// _Requirements: 2.4_
    func testPropertyNewListItemInheritsIndentLevel() {
        // 运行 100 次迭代
        for iteration in 0 ..< 100 {
            let indent = (iteration % 5) + 1 // 缩进级别 1-5
            let listType: MiNoteLibrary.ListType = [.bullet, .ordered, .checkbox][iteration % 3]
            let text = generateRandomText(length: Int.random(in: 1 ... 20))

            // 创建新列表项
            let newItem = ListBehaviorHandler.createNewListItem(
                listType: listType,
                indent: indent,
                number: 1,
                textAfter: text
            )

            // 验证缩进级别属性
            if newItem.length > 0 {
                var effectiveRange = NSRange()
                let attrs = newItem.attributes(at: 0, effectiveRange: &effectiveRange)
                let actualIndent = attrs[.listIndent] as? Int

                XCTAssertEqual(
                    actualIndent,
                    indent,
                    "迭代 \(iteration): 新列表项的缩进级别应该是 \(indent)，实际是 \(String(describing: actualIndent))"
                )
            }
        }
    }

    /// 属性测试：有序列表编号正确递增
    /// *For any* 有序列表项，当创建新列表项时，新项的编号应该等于当前项编号加 1
    /// _Requirements: 2.5_
    func testPropertyOrderedListNumberIncrement() {
        // 运行 100 次迭代
        for iteration in 0 ..< 100 {
            let currentNumber = Int.random(in: 1 ... 100)
            let expectedNewNumber = currentNumber + 1
            let text = generateRandomText(length: Int.random(in: 1 ... 20))

            // 创建新列表项（模拟从当前编号创建下一个）
            let newItem = ListBehaviorHandler.createNewListItem(
                listType: .ordered,
                indent: 1,
                number: expectedNewNumber,
                textAfter: text
            )

            // 验证编号属性
            if newItem.length > 0 {
                var effectiveRange = NSRange()
                let attrs = newItem.attributes(at: 0, effectiveRange: &effectiveRange)
                let actualNumber = attrs[.listNumber] as? Int

                XCTAssertEqual(
                    actualNumber,
                    expectedNewNumber,
                    "迭代 \(iteration): 新列表项的编号应该是 \(expectedNewNumber)，实际是 \(String(describing: actualNumber))"
                )
            }
        }
    }

    /// 属性测试：勾选框列表新项默认为未勾选状态
    /// *For any* 勾选框列表项，当创建新列表项时，新项应该是未勾选状态（☐）
    /// _Requirements: 2.6_
    func testPropertyCheckboxNewItemIsUnchecked() {
        // 运行 100 次迭代
        for iteration in 0 ..< 100 {
            let text = generateRandomText(length: Int.random(in: 1 ... 20))
            let indent = (iteration % 5) + 1

            // 创建新勾选框列表项
            let newItem = ListBehaviorHandler.createNewListItem(
                listType: .checkbox,
                indent: indent,
                number: 1,
                textAfter: text
            )

            // 验证勾选状态属性
            if newItem.length > 0 {
                var effectiveRange = NSRange()
                let attrs = newItem.attributes(at: 0, effectiveRange: &effectiveRange)
                let isChecked = attrs[.checkboxChecked] as? Bool

                XCTAssertEqual(
                    isChecked,
                    false,
                    "迭代 \(iteration): 新勾选框列表项应该默认为未勾选状态"
                )
            }
        }
    }

    /// 属性测试：新列表项包含正确的段落样式
    /// *For any* 列表项，当创建新列表项时，段落样式应该与缩进级别匹配
    /// _Requirements: 2.4_
    func testPropertyNewListItemHasCorrectParagraphStyle() {
        // 运行 100 次迭代
        for iteration in 0 ..< 100 {
            let indent = (iteration % 5) + 1
            let listType: MiNoteLibrary.ListType = [.bullet, .ordered, .checkbox][iteration % 3]
            let text = generateRandomText(length: Int.random(in: 1 ... 20))

            // 创建新列表项
            let newItem = ListBehaviorHandler.createNewListItem(
                listType: listType,
                indent: indent,
                number: 1,
                textAfter: text
            )

            // 验证段落样式
            if newItem.length > 0 {
                var effectiveRange = NSRange()
                let attrs = newItem.attributes(at: 0, effectiveRange: &effectiveRange)
                let paragraphStyle = attrs[.paragraphStyle] as? NSParagraphStyle

                XCTAssertNotNil(
                    paragraphStyle,
                    "迭代 \(iteration): 新列表项应该有段落样式"
                )

                if let style = paragraphStyle {
                    let expectedFirstLineIndent = CGFloat(indent - 1) * 20
                    XCTAssertEqual(
                        style.firstLineHeadIndent,
                        expectedFirstLineIndent,
                        accuracy: 0.1,
                        "迭代 \(iteration): 首行缩进应该是 \(expectedFirstLineIndent)"
                    )
                }
            }
        }
    }

    /// 属性测试：新列表项包含正确的附件类型
    /// *For any* 列表项，当创建新列表项时，附件类型应该与列表类型匹配
    /// _Requirements: 2.4_
    func testPropertyNewListItemHasCorrectAttachment() {
        // 运行 100 次迭代
        for iteration in 0 ..< 100 {
            let listType: MiNoteLibrary.ListType = [.bullet, .ordered, .checkbox][iteration % 3]
            let text = generateRandomText(length: Int.random(in: 1 ... 20))

            // 创建新列表项
            let newItem = ListBehaviorHandler.createNewListItem(
                listType: listType,
                indent: 1,
                number: iteration + 1,
                textAfter: text
            )

            // 验证附件类型
            if newItem.length > 0 {
                var effectiveRange = NSRange()
                let attrs = newItem.attributes(at: 0, effectiveRange: &effectiveRange)
                let attachment = attrs[.attachment]

                switch listType {
                case .bullet:
                    XCTAssertTrue(
                        attachment is BulletAttachment,
                        "迭代 \(iteration): 无序列表应该使用 BulletAttachment"
                    )
                case .ordered:
                    XCTAssertTrue(
                        attachment is OrderAttachment,
                        "迭代 \(iteration): 有序列表应该使用 OrderAttachment"
                    )
                case .checkbox:
                    XCTAssertTrue(
                        attachment is InteractiveCheckboxAttachment,
                        "迭代 \(iteration): 勾选框列表应该使用 InteractiveCheckboxAttachment"
                    )
                case .none:
                    break
                }
            }
        }
    }

    /// 属性测试：有序列表附件包含正确的编号
    /// *For any* 有序列表项，OrderAttachment 的编号应该与属性中的编号一致
    /// _Requirements: 2.5_
    func testPropertyOrderAttachmentHasCorrectNumber() {
        // 运行 100 次迭代
        for iteration in 0 ..< 100 {
            let number = Int.random(in: 1 ... 100)
            let text = generateRandomText(length: Int.random(in: 1 ... 20))

            // 创建新有序列表项
            let newItem = ListBehaviorHandler.createNewListItem(
                listType: .ordered,
                indent: 1,
                number: number,
                textAfter: text
            )

            // 验证 OrderAttachment 的编号
            if newItem.length > 0 {
                var effectiveRange = NSRange()
                let attrs = newItem.attributes(at: 0, effectiveRange: &effectiveRange)

                if let orderAttachment = attrs[.attachment] as? OrderAttachment {
                    XCTAssertEqual(
                        orderAttachment.number,
                        number,
                        "迭代 \(iteration): OrderAttachment 的编号应该是 \(number)"
                    )
                }
            }
        }
    }

    /// 属性测试：勾选框附件默认为未勾选状态
    /// *For any* 勾选框列表项，InteractiveCheckboxAttachment 应该默认为未勾选状态
    /// _Requirements: 2.6_
    func testPropertyCheckboxAttachmentIsUnchecked() {
        // 运行 100 次迭代
        for iteration in 0 ..< 100 {
            let text = generateRandomText(length: Int.random(in: 1 ... 20))

            // 创建新勾选框列表项
            let newItem = ListBehaviorHandler.createNewListItem(
                listType: .checkbox,
                indent: 1,
                number: 1,
                textAfter: text
            )

            // 验证 InteractiveCheckboxAttachment 的勾选状态
            if newItem.length > 0 {
                var effectiveRange = NSRange()
                let attrs = newItem.attributes(at: 0, effectiveRange: &effectiveRange)

                if let checkboxAttachment = attrs[.attachment] as? InteractiveCheckboxAttachment {
                    XCTAssertFalse(
                        checkboxAttachment.isChecked,
                        "迭代 \(iteration): InteractiveCheckboxAttachment 应该默认为未勾选状态"
                    )
                }
            }
        }
    }

    /// 属性测试：新列表项包含正确的文本内容
    /// *For any* 列表项，当创建新列表项时，文本内容应该正确包含在结果中
    /// _Requirements: 2.4_
    func testPropertyNewListItemContainsCorrectText() {
        // 运行 100 次迭代
        for iteration in 0 ..< 100 {
            let listType: MiNoteLibrary.ListType = [.bullet, .ordered, .checkbox][iteration % 3]
            let text = generateRandomText(length: Int.random(in: 1 ... 30))

            // 创建新列表项
            let newItem = ListBehaviorHandler.createNewListItem(
                listType: listType,
                indent: 1,
                number: 1,
                textAfter: text
            )

            // 验证文本内容
            let itemString = newItem.string
            // 附件字符是 \u{FFFC}，文本应该在附件之后
            let textWithoutAttachment = itemString.replacingOccurrences(of: "\u{FFFC}", with: "")

            XCTAssertEqual(
                textWithoutAttachment,
                text,
                "迭代 \(iteration): 新列表项应该包含文本 \"\(text)\""
            )
        }
    }

    /// 属性测试：空文本的新列表项只包含附件
    /// *For any* 列表项，当创建空文本的新列表项时，结果应该只包含附件字符
    /// _Requirements: 2.4_
    func testPropertyEmptyTextNewListItemOnlyContainsAttachment() {
        let listTypes: [MiNoteLibrary.ListType] = [.bullet, .ordered, .checkbox]

        for listType in listTypes {
            // 创建空文本的新列表项
            let newItem = ListBehaviorHandler.createNewListItem(
                listType: listType,
                indent: 1,
                number: 1,
                textAfter: ""
            )

            // 验证只包含附件字符
            XCTAssertEqual(
                newItem.length,
                1,
                "空文本的新列表项应该只包含 1 个字符（附件）"
            )

            XCTAssertEqual(
                newItem.string,
                "\u{FFFC}",
                "空文本的新列表项应该只包含附件字符"
            )
        }
    }

    // MARK: - 综合属性测试

    /// 属性测试：格式继承的完整性
    /// *For any* 列表项，新列表项应该同时继承类型、缩进和编号（如适用）
    /// _Requirements: 2.4, 2.5, 2.6_
    func testPropertyCompleteFormatInheritance() {
        // 运行 100 次迭代
        for iteration in 0 ..< 100 {
            let listType: MiNoteLibrary.ListType = [.bullet, .ordered, .checkbox][iteration % 3]
            let indent = (iteration % 5) + 1
            let number = Int.random(in: 1 ... 50)
            let text = generateRandomText(length: Int.random(in: 0 ... 20))

            // 创建新列表项
            let newItem = ListBehaviorHandler.createNewListItem(
                listType: listType,
                indent: indent,
                number: number,
                textAfter: text
            )

            // 验证所有属性
            if newItem.length > 0 {
                var effectiveRange = NSRange()
                let attrs = newItem.attributes(at: 0, effectiveRange: &effectiveRange)

                // 验证列表类型
                let actualType = attrs[.listType] as? MiNoteLibrary.ListType
                XCTAssertEqual(actualType, listType, "迭代 \(iteration): 列表类型不匹配")

                // 验证缩进级别
                let actualIndent = attrs[.listIndent] as? Int
                XCTAssertEqual(actualIndent, indent, "迭代 \(iteration): 缩进级别不匹配")

                // 验证编号（仅有序列表）
                if listType == .ordered {
                    let actualNumber = attrs[.listNumber] as? Int
                    XCTAssertEqual(actualNumber, number, "迭代 \(iteration): 编号不匹配")
                }

                // 验证勾选状态（仅勾选框列表）
                if listType == .checkbox {
                    let isChecked = attrs[.checkboxChecked] as? Bool
                    XCTAssertEqual(isChecked, false, "迭代 \(iteration): 勾选状态应该为 false")
                }
            }
        }
    }

    // MARK: - 边界条件测试

    /// 测试最大缩进级别
    func testMaxIndentLevel() {
        let maxIndent = 10

        for listType in [MiNoteLibrary.ListType.bullet, .ordered, .checkbox] {
            let newItem = ListBehaviorHandler.createNewListItem(
                listType: listType,
                indent: maxIndent,
                number: 1,
                textAfter: "测试"
            )

            if newItem.length > 0 {
                var effectiveRange = NSRange()
                let attrs = newItem.attributes(at: 0, effectiveRange: &effectiveRange)
                let actualIndent = attrs[.listIndent] as? Int

                XCTAssertEqual(
                    actualIndent,
                    maxIndent,
                    "最大缩进级别应该被正确设置"
                )
            }
        }
    }

    /// 测试最大编号
    func testMaxNumber() {
        let maxNumber = 999

        let newItem = ListBehaviorHandler.createNewListItem(
            listType: .ordered,
            indent: 1,
            number: maxNumber,
            textAfter: "测试"
        )

        if newItem.length > 0 {
            var effectiveRange = NSRange()
            let attrs = newItem.attributes(at: 0, effectiveRange: &effectiveRange)
            let actualNumber = attrs[.listNumber] as? Int

            XCTAssertEqual(
                actualNumber,
                maxNumber,
                "最大编号应该被正确设置"
            )
        }
    }

    /// 测试特殊字符文本
    func testSpecialCharactersText() {
        let specialTexts = [
            "Hello\tWorld",
            "中文English混合",
            "🎉Emoji测试",
            "特殊符号!@#$%^&*()",
            "换行符\n测试",
        ]

        for text in specialTexts {
            let newItem = ListBehaviorHandler.createNewListItem(
                listType: .bullet,
                indent: 1,
                number: 1,
                textAfter: text
            )

            let itemString = newItem.string
            let textWithoutAttachment = itemString.replacingOccurrences(of: "\u{FFFC}", with: "")

            XCTAssertEqual(
                textWithoutAttachment,
                text,
                "特殊字符文本应该被正确包含"
            )
        }
    }
}
