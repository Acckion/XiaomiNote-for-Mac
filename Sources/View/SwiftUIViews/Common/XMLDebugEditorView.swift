import AppKit
import SwiftUI

// MARK: - DebugSaveStatus Enum

/// 调试编辑器保存状态枚举
///
enum DebugSaveStatus: Equatable {
    case saved // 已保存
    case saving // 保存中
    case unsaved // 未保存
    case error(String) // 保存失败

    static func == (lhs: DebugSaveStatus, rhs: DebugSaveStatus) -> Bool {
        switch (lhs, rhs) {
        case (.saved, .saved), (.saving, .saving), (.unsaved, .unsaved):
            true
        case let (.error(lhsMsg), .error(rhsMsg)):
            lhsMsg == rhsMsg
        default:
            false
        }
    }
}

/// XML 调试编辑器视图
///
/// 提供原始 XML 内容的查看和编辑功能，用于调试格式转换问题和排查数据异常。
///
@available(macOS 14.0, *)
struct XMLDebugEditorView: View {

    // MARK: - Properties

    /// 绑定的 XML 内容
    @Binding var xmlContent: String

    /// 是否可编辑
    @Binding var isEditable: Bool

    /// 保存状态
    @Binding var saveStatus: DebugSaveStatus

    /// 保存回调
    var onSave: () -> Void

    /// 内容变化回调
    var onContentChange: (String) -> Void

    // MARK: - State

    /// 内部编辑内容（用于跟踪变化）
    @State private var editingContent = ""

    /// 是否已初始化
    @State private var isInitialized = false

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏区域
            debugToolbar

            Divider()

            // 编辑器区域
            editorArea
        }
        .onAppear {
            initializeContent()
        }
        .onChange(of: xmlContent) { _, newValue in
            // 外部内容变化时同步到编辑器（仅在未初始化或内容不同时）
            if !isInitialized || editingContent != newValue {
                editingContent = newValue
                isInitialized = true
            }
        }
    }

    // MARK: - View Components

    /// 调试工具栏
    ///
    /// 包含保存按钮和状态指示器
    ///
    private var debugToolbar: some View {
        HStack(spacing: 12) {
            // 保存按钮
            Button {
                onSave()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                    Text("保存")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(saveStatus == .saving || saveStatus == .saved)
            .keyboardShortcut("s", modifiers: .command)
            .help("保存 XML 内容 (⌘S)")

            Spacer()

            // 保存状态指示器
            toolbarSaveStatusIndicator
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: NSColor.controlBackgroundColor))
    }

    /// 工具栏保存状态指示器
    ///
    private var toolbarSaveStatusIndicator: some View {
        HStack(spacing: 6) {
            switch saveStatus {
            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("已保存")
                    .foregroundColor(.green)
            case .saving:
                ProgressView()
                    .scaleEffect(0.7)
                Text("保存中...")
                    .foregroundColor(.orange)
            case .unsaved:
                Image(systemName: "circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 8))
                Text("未保存")
                    .foregroundColor(.red)
            case let .error(message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("保存失败")
                    .foregroundColor(.red)
                    .help(message)
            }
        }
        .font(.system(size: 12))
    }

    /// 编辑器区域
    ///
    @ViewBuilder
    private var editorArea: some View {
        if xmlContent.isEmpty, editingContent.isEmpty {
            // 空内容占位符
            emptyContentPlaceholder
        } else {
            // XML 编辑器
            xmlEditor
        }
    }

    /// 空内容占位符
    ///
    /// 当 XML 内容为空时显示占位符提示
    ///
    private var emptyContentPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("无 XML 内容")
                .font(.system(.title2, design: .monospaced))
                .foregroundColor(.secondary)

            Text("当前笔记没有 XML 内容")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundColor)
    }

    /// XML 编辑器
    ///
    /// 使用 TextEditor 显示和编辑 XML 内容
    ///
    private var xmlEditor: some View {
        ScrollView([.horizontal, .vertical]) {
            TextEditor(text: $editingContent)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(backgroundColor)
                .disabled(!isEditable)
                .onChange(of: editingContent) { oldValue, newValue in
                    handleContentChange(oldValue: oldValue, newValue: newValue)
                }
                .frame(minWidth: 600, minHeight: 400)
        }
        .background(backgroundColor)
    }

    // MARK: - Computed Properties

    /// 背景颜色（支持深色/浅色模式）
    ///
    private var backgroundColor: Color {
        Color(nsColor: NSColor.textBackgroundColor)
    }

    // MARK: - Methods

    /// 初始化内容
    private func initializeContent() {
        if !isInitialized {
            editingContent = xmlContent
            isInitialized = true
        }
    }

    /// 处理内容变化
    ///
    private func handleContentChange(oldValue: String, newValue: String) {
        guard isInitialized, oldValue != newValue else { return }

        // 更新绑定的内容
        xmlContent = newValue

        // 标记为未保存
        if saveStatus != .saving {
            saveStatus = .unsaved
        }

        // 通知内容变化
        onContentChange(newValue)
    }
}

// MARK: - Preview

#if DEBUG
    @available(macOS 14.0, *)
    #Preview("XML Debug Editor - With Content") {
        XMLDebugEditorPreviewWrapper(
            initialContent: """
            <?xml version="1.0" encoding="UTF-8"?>
            <note>
                <text>
                    <p>这是一段测试文本</p>
                    <p style="font-weight: bold;">这是加粗文本</p>
                </text>
            </note>
            """,
            initialStatus: .saved
        )
    }

    @available(macOS 14.0, *)
    #Preview("XML Debug Editor - Empty") {
        XMLDebugEditorPreviewWrapper(initialContent: "", initialStatus: .saved)
    }

    @available(macOS 14.0, *)
    #Preview("XML Debug Editor - Unsaved") {
        XMLDebugEditorPreviewWrapper(
            initialContent: "<note><text>未保存的内容</text></note>",
            initialStatus: .unsaved
        )
    }

    @available(macOS 14.0, *)
    #Preview("XML Debug Editor - Saving") {
        XMLDebugEditorPreviewWrapper(
            initialContent: "<note><text>保存中...</text></note>",
            initialStatus: .saving
        )
    }

    @available(macOS 14.0, *)
    #Preview("XML Debug Editor - Error") {
        XMLDebugEditorPreviewWrapper(
            initialContent: "<note><text>保存失败的内容</text></note>",
            initialStatus: .error("网络连接失败，请稍后重试")
        )
    }

    @available(macOS 14.0, *)
    struct XMLDebugEditorPreviewWrapper: View {
        @State private var content: String
        @State private var isEditable = true
        @State private var saveStatus: DebugSaveStatus

        init(initialContent: String, initialStatus: DebugSaveStatus = .saved) {
            _content = State(initialValue: initialContent)
            _saveStatus = State(initialValue: initialStatus)
        }

        var body: some View {
            XMLDebugEditorView(
                xmlContent: $content,
                isEditable: $isEditable,
                saveStatus: $saveStatus,
                onSave: {
                    saveStatus = .saving
                    // 模拟保存延迟
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        saveStatus = .saved
                    }
                },
                onContentChange: { newContent in
                    if saveStatus != .saving {
                        saveStatus = .unsaved
                    }
                }
            )
            .frame(width: 800, height: 600)
        }
    }
#endif
