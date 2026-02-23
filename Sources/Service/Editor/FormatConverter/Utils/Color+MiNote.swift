//
//  Color+MiNote.swift
//  MiNoteMac
//
//  SwiftUI Color 扩展
//

import AppKit
import SwiftUI

extension Color {
    /// 转换为 NSColor
    var nsColor: NSColor {
        NSColor(self)
    }

    /// 转换为十六进制字符串
    func toHexString() -> String {
        nsColor.toHexString()
    }
}
