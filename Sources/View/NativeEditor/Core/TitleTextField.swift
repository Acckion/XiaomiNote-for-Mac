//
//  TitleTextField.swift
//  MiNoteMac
//
//  标题编辑 TextField - 独立的标题编辑控件
//

import AppKit

/// 标题编辑 TextField
/// 使用 NSTextField 实现单行纯文本标题编辑，视觉效果与原标题段落一致
class TitleTextField: NSTextField {

    /// 焦点转移回调（Enter/Tab 键触发）
    var onCommit: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupAppearance()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupAppearance() {
        font = NSFont.systemFont(ofSize: 40, weight: .semibold)
        textColor = .labelColor
        placeholderString = "标题"
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        lineBreakMode = .byTruncatingTail
        maximumNumberOfLines = 1
        cell?.wraps = false
        cell?.isScrollable = true
        translatesAutoresizingMaskIntoConstraints = false
    }
}
