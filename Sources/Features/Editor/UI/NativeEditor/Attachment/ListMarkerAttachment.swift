//
//  ListMarkerAttachment.swift
//  MiNoteMac
//
//  列表标记附件基类，提取 CheckboxAttachment、BulletAttachment、OrderAttachment 的公共属性
//

import AppKit

// MARK: - 列表标记附件基类

/// 列表标记附件基类（继承 NSTextAttachment，遵循 ThemeAwareAttachment）
///
/// 提供列表标记附件的公共属性和主题适配逻辑。
/// 子类：InteractiveCheckboxAttachment、BulletAttachment、OrderAttachment
class ListMarkerAttachment: NSTextAttachment, ThemeAwareAttachment {

    // MARK: - 公共属性

    /// 缩进级别（对应 XML 中的 level 属性）
    var level = 3

    /// 缩进值（对应 XML 中的 indent 属性）
    var indent = 1

    /// 是否为深色模式
    var isDarkMode = false

    // MARK: - Initialization

    override nonisolated init(data contentData: Data?, ofType uti: String?) {
        super.init(data: contentData, ofType: uti)
    }

    required nonisolated init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - ThemeAwareAttachment

    func updateTheme() {
        guard let currentAppearance = NSApp?.effectiveAppearance else {
            return
        }
        let newIsDarkMode = currentAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        if isDarkMode != newIsDarkMode {
            isDarkMode = newIsDarkMode
        }
    }
}
