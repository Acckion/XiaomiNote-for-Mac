import AppKit
import SwiftUI

/// 段落管理器调试视图
/// 用于可视化验证 ParagraphManager 的功能
struct ParagraphManagerDebugView: View {
    @State private var textContent = "标题段落\n这是第一段普通文本\n这是第二段普通文本\n这是第三段普通文本"
    @State private var paragraphs: [Paragraph] = []
    @State private var selectedParagraphIndex: Int?
    @State private var selectedFormatType: ParagraphType = .normal

    private let manager = ParagraphManager()
    private let textStorage = NSTextStorage()

    var body: some View {
        HSplitView {
            // 左侧：文本编辑区
            VStack(alignment: .leading, spacing: 12) {
                Text("文本编辑区")
                    .font(.headline)

                TextEditor(text: $textContent)
                    .font(.system(size: 14))
                    .frame(minHeight: 200)
                    .border(Color.gray.opacity(0.3))
                    .onChange(of: textContent) { _, _ in
                        updateParagraphs()
                    }

                HStack {
                    Button("更新段落列表") {
                        updateParagraphs()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("清空文本") {
                        textContent = ""
                        updateParagraphs()
                    }

                    Button("示例文本") {
                        textContent = "标题段落\n这是第一段普通文本\n这是第二段普通文本\n这是第三段普通文本"
                        updateParagraphs()
                    }
                }

                Divider()

                // 格式应用区
                VStack(alignment: .leading, spacing: 8) {
                    Text("应用段落格式")
                        .font(.headline)

                    Picker("格式类型", selection: $selectedFormatType) {
                        Text("标题段落").tag(ParagraphType.title)
                        Text("H1 标题").tag(ParagraphType.heading(level: 1))
                        Text("H2 标题").tag(ParagraphType.heading(level: 2))
                        Text("H3 标题").tag(ParagraphType.heading(level: 3))
                        Text("普通段落").tag(ParagraphType.normal)
                        Text("无序列表").tag(ParagraphType.list(.bullet))
                        Text("有序列表").tag(ParagraphType.list(.ordered))
                        Text("引用").tag(ParagraphType.quote)
                        Text("代码块").tag(ParagraphType.code)
                    }
                    .pickerStyle(.menu)

                    Button("应用到选中段落") {
                        applyFormatToSelectedParagraph()
                    }
                    .disabled(selectedParagraphIndex == nil)
                }
            }
            .padding()
            .frame(minWidth: 300)

            // 右侧：段落列表
            VStack(alignment: .leading, spacing: 12) {
                Text("段落列表 (\(paragraphs.count) 个)")
                    .font(.headline)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                            ParagraphInfoCard(
                                paragraph: paragraph,
                                index: index,
                                isSelected: selectedParagraphIndex == index,
                                onSelect: {
                                    selectedParagraphIndex = index
                                }
                            )
                        }
                    }
                }

                Divider()

                // 统计信息
                VStack(alignment: .leading, spacing: 4) {
                    Text("统计信息")
                        .font(.headline)

                    Text("总段落数: \(paragraphs.count)")
                    Text("标题段落: \(paragraphs.count(where: { $0.isTitle }))")
                    Text("普通段落: \(paragraphs.count(where: { $0.type == .normal }))")
                    Text("列表段落: \(paragraphs.count(where: { $0.isList }))")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
            .frame(minWidth: 300)
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            updateParagraphs()
        }
    }

    // MARK: - Helper Methods

    private func updateParagraphs() {
        // 更新 textStorage
        textStorage.setAttributedString(NSAttributedString(string: textContent))

        // 更新段落列表
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: 0, length: textContent.count))

        // 获取段落列表
        paragraphs = manager.paragraphs

        print("[ParagraphManagerDebugView] 更新段落列表: \(paragraphs.count) 个段落")
    }

    private func applyFormatToSelectedParagraph() {
        guard let index = selectedParagraphIndex, index < paragraphs.count else {
            return
        }

        let paragraph = paragraphs[index]

        print("[ParagraphManagerDebugView] 应用格式 \(selectedFormatType) 到段落 \(index)")

        // 应用格式
        manager.applyParagraphFormat(selectedFormatType, to: paragraph.range, in: textStorage)

        // 更新段落列表
        paragraphs = manager.paragraphs
    }
}

// MARK: - Paragraph Info Card

struct ParagraphInfoCard: View {
    let paragraph: Paragraph
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("段落 \(index)")
                    .font(.caption)
                    .fontWeight(.semibold)

                Spacer()

                Text(paragraph.type.description)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(typeColor.opacity(0.2))
                    .foregroundColor(typeColor)
                    .cornerRadius(4)
            }

            Text("范围: [\(paragraph.range.location), \(paragraph.range.location + paragraph.range.length))")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text("长度: \(paragraph.range.length) 字符")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text("版本: \(paragraph.version)")
                .font(.caption2)
                .foregroundColor(.secondary)

            if paragraph.needsReparse {
                Text("需要重新解析")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.05))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onTapGesture {
            onSelect()
        }
    }

    private var typeColor: Color {
        switch paragraph.type {
        case .title:
            .purple
        case .heading:
            .blue
        case .normal:
            .gray
        case .list:
            .green
        case .quote:
            .orange
        case .code:
            .pink
        }
    }
}

// MARK: - Preview

#Preview {
    ParagraphManagerDebugView()
}
