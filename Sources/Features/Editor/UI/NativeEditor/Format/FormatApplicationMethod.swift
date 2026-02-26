//
//  FormatApplicationMethod.swift
//  MiNoteMac
//
//  格式应用方式枚举 - 用于区分不同的格式应用来源
//

import Foundation

/// 格式应用方式枚举
///
/// 用于标识格式是通过哪种方式应用的，以便进行一致性检查
enum FormatApplicationMethod: String, CaseIterable, Sendable {
    case menu // 通过格式菜单应用
    case keyboard // 通过快捷键应用
    case programmatic // 通过程序调用应用
    case toolbar // 通过工具栏应用

    /// 显示名称
    var displayName: String {
        switch self {
        case .menu: "格式菜单"
        case .keyboard: "快捷键"
        case .programmatic: "程序调用"
        case .toolbar: "工具栏"
        }
    }
}
