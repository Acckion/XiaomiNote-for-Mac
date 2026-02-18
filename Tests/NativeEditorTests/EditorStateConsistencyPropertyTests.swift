//
//  EditorStateConsistencyPropertyTests.swift
//  MiNoteLibraryTests
//
//  编辑器状态一致性属性测试 - 验证编辑器状态与格式按钮状态的一致性
//  属性 10: 编辑器状态一致性
//  验证需求: 4.3 - 当编辑器处于不可编辑状态时，格式菜单应禁用所有格式按钮
//
//  Feature: format-menu-fix, Property 10: 编辑器状态一致性
//

import AppKit
import XCTest
@testable import MiNoteLibrary

/// 编辑器状态一致性属性测试
///
/// 本测试套件使用基于属性的测试方法，验证编辑器状态与格式按钮状态的一致性。
/// 每个测试运行 100 次迭代，确保在各种编辑器状态下格式按钮的启用/禁用状态正确。
@MainActor
final class EditorStateConsistencyPropertyTests: XCTestCase {

    // MARK: - Properties

    var stateChecker: EditorStateConsistencyChecker!
    var editorContext: NativeEditorContext!
    var textStorage: NSTextStorage!
    var textView: NSTextView!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        // 获取状态检查器
        stateChecker = EditorStateConsistencyChecker.shared
        stateChecker.reset()

        // 创建测试用的编辑器上下文
        editorContext = NativeEditorContext()

        // 创建测试用的文本存储和文本视图
        textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer()
        layoutManager.addTextContainer(textContainer)
        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), textContainer: textContainer)
        textView.isEditable = true
    }

    override func tearDown() async throws {
        stateChecker.reset()
        editorContext = nil
        textStorage = nil
        textView = nil
        try await super.tearDown()
    }

    // MARK: - 属性 10: 编辑器状态一致性

    // 验证需求: 4.3 - 当编辑器处于不可编辑状态时，格式菜单应禁用所有格式按钮

    /// 属性测试：编辑器状态与格式按钮启用状态一致性
    ///
    /// **属性**: 对于任何编辑器状态，格式按钮的启用状态应该与编辑器状态的 allowsFormatting 属性一致
    /// **验证需求**: 4.3
    ///
    /// 测试策略：
    /// 1. 生成随机的编辑器状态
    /// 2. 更新状态检查器
    /// 3. 验证格式按钮启用状态与编辑器状态一致
    func testProperty10_EditorStateFormatButtonConsistency() {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 编辑器状态与格式按钮一致性 (迭代次数: \(iterations))")

        for iteration in 1 ... iterations {
            // 1. 生成随机的编辑器状态
            let state = generateRandomEditorState()

            print("[PropertyTest] 迭代 \(iteration): 状态=\(state.description)")

            // 2. 更新状态检查器
            stateChecker.updateState(state, reason: "测试迭代 \(iteration)")

            // 3. 验证格式按钮启用状态
            let expectedEnabled = state.allowsFormatting
            let actualEnabled = stateChecker.formatButtonsEnabled

            XCTAssertEqual(
                actualEnabled,
                expectedEnabled,
                "迭代 \(iteration): 格式按钮启用状态应该与编辑器状态一致 (状态: \(state.description), 期望: \(expectedEnabled), 实际: \(actualEnabled))"
            )
        }

        print("[PropertyTest] ✅ 编辑器状态与格式按钮一致性测试完成")
    }

    /// 属性测试：只读状态下格式按钮禁用
    ///
    /// **属性**: 当编辑器处于只读状态时，所有格式按钮应该被禁用
    /// **验证需求**: 4.3
    func testProperty10_ReadOnlyStateDisablesFormatButtons() throws {
        let iterations = 50
        print("\n[PropertyTest] 开始属性测试: 只读状态禁用格式按钮 (迭代次数: \(iterations))")

        for iteration in 1 ... iterations {
            // 1. 设置只读状态
            stateChecker.updateState(.readOnly, reason: "测试只读状态 \(iteration)")

            // 2. 验证格式按钮被禁用
            XCTAssertFalse(
                stateChecker.formatButtonsEnabled,
                "迭代 \(iteration): 只读状态下格式按钮应该被禁用"
            )

            // 3. 验证格式操作被拒绝
            let format = try XCTUnwrap(TextFormat.allCases.randomElement())
            let allowed = stateChecker.validateFormatOperation(format)

            XCTAssertFalse(
                allowed,
                "迭代 \(iteration): 只读状态下格式操作 \(format.displayName) 应该被拒绝"
            )

            print("[PropertyTest] 迭代 \(iteration): 只读状态，格式 \(format.displayName) 被正确拒绝")
        }

        print("[PropertyTest] ✅ 只读状态禁用格式按钮测试完成")
    }

    /// 属性测试：未获得焦点状态下格式按钮禁用
    ///
    /// **属性**: 当编辑器未获得焦点时，所有格式按钮应该被禁用
    /// **验证需求**: 4.3
    func testProperty10_UnfocusedStateDisablesFormatButtons() throws {
        let iterations = 50
        print("\n[PropertyTest] 开始属性测试: 未获得焦点状态禁用格式按钮 (迭代次数: \(iterations))")

        for iteration in 1 ... iterations {
            // 1. 设置未获得焦点状态
            stateChecker.updateState(.unfocused, reason: "测试未获得焦点状态 \(iteration)")

            // 2. 验证格式按钮被禁用
            XCTAssertFalse(
                stateChecker.formatButtonsEnabled,
                "迭代 \(iteration): 未获得焦点状态下格式按钮应该被禁用"
            )

            // 3. 验证格式操作被拒绝
            let format = try XCTUnwrap(TextFormat.allCases.randomElement())
            let allowed = stateChecker.validateFormatOperation(format)

            XCTAssertFalse(
                allowed,
                "迭代 \(iteration): 未获得焦点状态下格式操作 \(format.displayName) 应该被拒绝"
            )

            print("[PropertyTest] 迭代 \(iteration): 未获得焦点状态，格式 \(format.displayName) 被正确拒绝")
        }

        print("[PropertyTest] ✅ 未获得焦点状态禁用格式按钮测试完成")
    }

    /// 属性测试：可编辑状态下格式按钮启用
    ///
    /// **属性**: 当编辑器处于可编辑状态时，所有格式按钮应该被启用
    /// **验证需求**: 4.3
    func testProperty10_EditableStateEnablesFormatButtons() throws {
        let iterations = 50
        print("\n[PropertyTest] 开始属性测试: 可编辑状态启用格式按钮 (迭代次数: \(iterations))")

        for iteration in 1 ... iterations {
            // 1. 设置可编辑状态
            stateChecker.updateState(.editable, reason: "测试可编辑状态 \(iteration)")

            // 2. 验证格式按钮被启用
            XCTAssertTrue(
                stateChecker.formatButtonsEnabled,
                "迭代 \(iteration): 可编辑状态下格式按钮应该被启用"
            )

            // 3. 验证格式操作被允许
            let format = try XCTUnwrap(TextFormat.allCases.randomElement())
            let allowed = stateChecker.validateFormatOperation(format)

            XCTAssertTrue(
                allowed,
                "迭代 \(iteration): 可编辑状态下格式操作 \(format.displayName) 应该被允许"
            )

            print("[PropertyTest] 迭代 \(iteration): 可编辑状态，格式 \(format.displayName) 被正确允许")
        }

        print("[PropertyTest] ✅ 可编辑状态启用格式按钮测试完成")
    }

    /// 属性测试：状态转换一致性
    ///
    /// **属性**: 状态转换后，格式按钮启用状态应该立即更新
    /// **验证需求**: 4.3
    func testProperty10_StateTransitionConsistency() {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 状态转换一致性 (迭代次数: \(iterations))")

        for iteration in 1 ... iterations {
            // 1. 生成随机的状态序列
            let states = generateRandomStateSequence(length: Int.random(in: 2 ... 5))

            print("[PropertyTest] 迭代 \(iteration): 状态序列=\(states.map(\.description))")

            // 2. 依次转换状态并验证
            for (index, state) in states.enumerated() {
                stateChecker.updateState(state, reason: "状态转换 \(index + 1)")

                // 验证格式按钮状态立即更新
                let expectedEnabled = state.allowsFormatting
                let actualEnabled = stateChecker.formatButtonsEnabled

                XCTAssertEqual(
                    actualEnabled,
                    expectedEnabled,
                    "迭代 \(iteration), 转换 \(index + 1): 状态转换后格式按钮状态应该立即更新"
                )
            }
        }

        print("[PropertyTest] ✅ 状态转换一致性测试完成")
    }

    /// 属性测试：所有格式类型的验证一致性
    ///
    /// **属性**: 对于任何编辑器状态，所有格式类型的验证结果应该一致
    /// **验证需求**: 4.3
    func testProperty10_AllFormatTypesValidationConsistency() {
        let iterations = 50
        print("\n[PropertyTest] 开始属性测试: 所有格式类型验证一致性 (迭代次数: \(iterations))")

        for iteration in 1 ... iterations {
            // 1. 生成随机的编辑器状态
            let state = generateRandomEditorState()
            stateChecker.updateState(state, reason: "测试迭代 \(iteration)")

            let expectedAllowed = state.allowsFormatting

            print("[PropertyTest] 迭代 \(iteration): 状态=\(state.description), 期望允许=\(expectedAllowed)")

            // 2. 验证所有格式类型
            for format in TextFormat.allCases {
                let allowed = stateChecker.validateFormatOperation(format)

                XCTAssertEqual(
                    allowed,
                    expectedAllowed,
                    "迭代 \(iteration): 格式 \(format.displayName) 的验证结果应该与编辑器状态一致"
                )
            }
        }

        print("[PropertyTest] ✅ 所有格式类型验证一致性测试完成")
    }

    /// 属性测试：状态统计信息准确性
    ///
    /// **属性**: 状态统计信息应该准确反映当前状态
    /// **验证需求**: 4.3
    func testProperty10_StateStatisticsAccuracy() {
        let iterations = 50
        print("\n[PropertyTest] 开始属性测试: 状态统计信息准确性 (迭代次数: \(iterations))")

        for iteration in 1 ... iterations {
            // 1. 生成随机的编辑器状态
            let state = generateRandomEditorState()
            let reason = "测试迭代 \(iteration)"

            // 2. 更新状态
            stateChecker.updateState(state, reason: reason)

            // 3. 获取统计信息
            let stats = stateChecker.getStateStatistics()

            // 4. 验证统计信息
            let currentStateDesc = stats["currentState"] as? String
            let formatButtonsEnabled = stats["formatButtonsEnabled"] as? Bool
            let stateChangeReason = stats["stateChangeReason"] as? String

            XCTAssertEqual(
                currentStateDesc,
                state.description,
                "迭代 \(iteration): 统计信息中的当前状态应该准确"
            )
            XCTAssertEqual(
                formatButtonsEnabled,
                state.allowsFormatting,
                "迭代 \(iteration): 统计信息中的格式按钮启用状态应该准确"
            )
            XCTAssertEqual(
                stateChangeReason,
                reason,
                "迭代 \(iteration): 统计信息中的状态变化原因应该准确"
            )

            print("[PropertyTest] 迭代 \(iteration): 统计信息验证通过")
        }

        print("[PropertyTest] ✅ 状态统计信息准确性测试完成")
    }

    // MARK: - 辅助方法

    /// 生成随机的编辑器状态
    private func generateRandomEditorState() -> EditorState {
        let states: [EditorState] = [
            .editable,
            .readOnly,
            .unfocused,
            .empty,
            .loading,
            .error("测试错误 \(Int.random(in: 1 ... 100))"),
        ]
        return states.randomElement()!
    }

    /// 生成随机的状态序列
    private func generateRandomStateSequence(length: Int) -> [EditorState] {
        (0 ..< length).map { _ in generateRandomEditorState() }
    }
}
