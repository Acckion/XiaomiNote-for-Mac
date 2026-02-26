//
//  NSColor+Hex.swift
//  MiNoteMac
//
//  NSColor 十六进制颜色转换扩展
//

import AppKit

extension NSColor {
    /// 从十六进制字符串创建颜色
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }

        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            alpha: Double(a) / 255
        )
    }

    /// 转换为十六进制字符串
    func toHexString() -> String {
        let red = Int(round(redComponent * 255))
        let green = Int(round(greenComponent * 255))
        let blue = Int(round(blueComponent * 255))
        let alpha = Int(round(alphaComponent * 255))

        if alpha < 255 {
            return String(format: "#%02x%02x%02x%02x", alpha, red, green, blue)
        } else {
            return String(format: "#%02x%02x%02x", red, green, blue)
        }
    }
}
