//
//  FormatSpanMerger.swift
//  MiNoteMac
//
//  格式跨度合并器
//  优化 AST 结构，解决格式边界问题
//  核心算法：扁平化格式树 → 合并相邻相同格式 → 重建嵌套结构
//

import Foundation

// MARK: - 格式跨度合并器

/// 格式跨度合并器 - 优化 AST 结构，解决格式边界问题
///
/// 核心算法：
/// 1. NSAttributedString → FormatSpan[]：遍历属性运行段，提取格式集合
/// 2. 合并相邻相同格式的跨度
/// 3. FormatSpan[] → InlineNode[]：按照固定的嵌套顺序重建格式树
///
/// 这是解决 `</b></i><i><b>` 问题的关键组件。
public final class FormatSpanMerger: Sendable {

    /// 格式标签的嵌套顺序（从外到内）
    /// 生成 XML 时按此顺序嵌套标签
    ///
    /// 顺序说明：
    /// - 标题最外层（因为标题通常影响整行）
    /// - 对齐次之（段落级别的格式）
    /// - 背景色（视觉上的底层）
    /// - 删除线、下划线（装饰性格式）
    /// - 斜体、粗体最内层（最常用的文本格式）
    public static let formatOrder: [ASTNodeType] = [
        .heading1, .heading2, .heading3, // 标题最外层
        .centerAlign, .rightAlign, // 对齐
        .highlight, // 背景色
        .strikethrough, // 删除线
        .underline, // 下划线
        .italic, // 斜体
        .bold, // 粗体最内层
    ]

    public init() {}

    // MARK: - 合并相邻跨度

    /// 合并相邻的相同格式跨度
    ///
    /// 这是解决 `</b></i><i><b>` 问题的关键步骤。
    /// 当用户在格式化文本末尾添加内容时，如果新内容继承了相同格式，
    /// 合并后就不会产生多余的闭合/开启标签。
    ///
    /// 算法：
    /// 1. 遍历所有跨度
    /// 2. 如果当前跨度与前一个跨度格式相同，合并它们
    /// 3. 否则，保存前一个跨度，开始新跨度
    ///
    /// - Parameter spans: 格式跨度数组
    /// - Returns: 合并后的格式跨度数组
    public func mergeAdjacentSpans(_ spans: [FormatSpan]) -> [FormatSpan] {
        guard !spans.isEmpty else { return [] }

        var result: [FormatSpan] = []
        var current = spans[0]

        for i in 1 ..< spans.count {
            let next = spans[i]
            if current.canMerge(with: next) {
                // 格式相同，合并
                current = current.merged(with: next)
            } else {
                // 格式不同，保存当前跨度，开始新跨度
                if !current.isEmpty {
                    result.append(current)
                }
                current = next
            }
        }

        // 添加最后一个跨度
        if !current.isEmpty {
            result.append(current)
        }

        return result
    }

    // MARK: - 跨度转换为行内节点

    /// 将格式跨度数组转换为行内节点树
    ///
    /// 按照 formatOrder 的顺序，从外到内构建嵌套的格式节点。
    ///
    /// 算法：
    /// 1. 对每个跨度，创建一个 TextNode 作为最内层
    /// 2. 按照 formatOrder 的逆序（从内到外），依次包裹格式节点
    /// 3. 最终得到正确嵌套的格式树
    ///
    /// 示例：
    /// FormatSpan(text: "文本", formats: [.bold, .italic])
    /// → FormattedNode(.bold, [FormattedNode(.italic, [TextNode("文本")])])
    ///
    /// - Parameter spans: 格式跨度数组
    /// - Returns: 行内节点数组
    public func spansToInlineNodes(_ spans: [FormatSpan]) -> [any InlineNode] {
        spans.map { span in
            spanToInlineNode(span)
        }
    }

    /// 将单个格式跨度转换为行内节点
    ///
    /// - Parameter span: 格式跨度
    /// - Returns: 行内节点
    private func spanToInlineNode(_ span: FormatSpan) -> any InlineNode {
        // 如果没有格式，直接返回文本节点
        if span.formats.isEmpty {
            return TextNode(text: span.text)
        }

        // 创建最内层的文本节点
        var node: any InlineNode = TextNode(text: span.text)

        // 按照从内到外的顺序包裹格式节点
        // formatOrder 是从外到内的顺序，所以需要反转
        for format in Self.formatOrder.reversed() {
            if span.formats.contains(format) {
                let color = (format == .highlight) ? span.highlightColor : nil
                node = FormattedNode(type: format, content: [node], color: color)
            }
        }

        return node
    }

    // MARK: - 行内节点转换为跨度

    /// 将行内节点树展平为格式跨度数组
    ///
    /// 递归遍历节点树，收集每个叶子节点的格式集合。
    ///
    /// 算法：
    /// 1. 递归遍历节点树
    /// 2. 遇到 TextNode 时，创建 FormatSpan，格式为累积的所有父节点格式
    /// 3. 遇到 FormattedNode 时，将其格式添加到累积集合，继续遍历子节点
    ///
    /// - Parameter nodes: 行内节点数组
    /// - Returns: 格式跨度数组
    public func inlineNodesToSpans(_ nodes: [any InlineNode]) -> [FormatSpan] {
        var spans: [FormatSpan] = []

        /// 递归展平节点
        /// - Parameters:
        ///   - node: 当前节点
        ///   - formats: 累积的格式集合
        ///   - highlightColor: 累积的高亮颜色
        func flatten(_ node: any InlineNode, formats: Set<ASTNodeType>, highlightColor: String?) {
            if let textNode = node as? TextNode {
                // 叶子节点：创建格式跨度
                spans.append(FormatSpan(
                    text: textNode.text,
                    formats: formats,
                    highlightColor: highlightColor
                ))
            } else if let formattedNode = node as? FormattedNode {
                // 格式节点：添加格式，继续遍历子节点
                var newFormats = formats
                newFormats.insert(formattedNode.nodeType)
                let newColor = formattedNode.color ?? highlightColor

                for child in formattedNode.content {
                    flatten(child, formats: newFormats, highlightColor: newColor)
                }
            }
        }

        for node in nodes {
            flatten(node, formats: [], highlightColor: nil)
        }

        return spans
    }

    // MARK: - 优化行内节点

    /// 优化行内节点数组
    ///
    /// 将行内节点树展平为跨度，合并相邻相同格式，然后重建节点树。
    /// 这是解决格式边界问题的完整流程。
    ///
    /// - Parameter nodes: 原始行内节点数组
    /// - Returns: 优化后的行内节点数组
    public func optimizeInlineNodes(_ nodes: [any InlineNode]) -> [any InlineNode] {
        // 1. 展平为跨度
        let spans = inlineNodesToSpans(nodes)

        // 2. 合并相邻相同格式
        let mergedSpans = mergeAdjacentSpans(spans)

        // 3. 重建节点树
        return spansToInlineNodes(mergedSpans)
    }
}

// MARK: - 便捷方法

public extension FormatSpanMerger {
    /// 检查两个行内节点数组是否语义等价
    ///
    /// 通过比较展平后的跨度来判断，忽略嵌套结构的差异。
    ///
    /// - Parameters:
    ///   - lhs: 第一个节点数组
    ///   - rhs: 第二个节点数组
    /// - Returns: 是否语义等价
    func areInlineNodesEquivalent(_ lhs: [any InlineNode], _ rhs: [any InlineNode]) -> Bool {
        let lhsSpans = mergeAdjacentSpans(inlineNodesToSpans(lhs))
        let rhsSpans = mergeAdjacentSpans(inlineNodesToSpans(rhs))
        return lhsSpans == rhsSpans
    }

    /// 提取行内节点数组的纯文本内容
    ///
    /// - Parameter nodes: 行内节点数组
    /// - Returns: 纯文本字符串
    func extractPlainText(_ nodes: [any InlineNode]) -> String {
        let spans = inlineNodesToSpans(nodes)
        return spans.map(\.text).joined()
    }
}
