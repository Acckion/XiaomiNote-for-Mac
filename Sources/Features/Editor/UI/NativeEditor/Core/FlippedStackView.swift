//
//  FlippedStackView.swift
//  MiNoteMac
//
//  翻转坐标系的 NSStackView，确保子视图从上到下排列
//

import AppKit

/// 翻转坐标系的 NSStackView
/// NSScrollView 的 documentView 需要翻转坐标系才能正确从顶部开始布局
class FlippedStackView: NSStackView {
    override var isFlipped: Bool {
        true
    }
}
