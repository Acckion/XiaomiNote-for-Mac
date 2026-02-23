//
//  NSFont+MiNote.swift
//  MiNoteMac
//
//  NSFont 字体扩展
//

import AppKit

extension NSFont {
    /// 获取斜体版本
    /// 使用 NSFontManager 来正确转换字体为斜体
    func italic() -> NSFont {
        let fontManager = NSFontManager.shared
        return fontManager.convert(self, toHaveTrait: .italicFontMask)
    }
}
