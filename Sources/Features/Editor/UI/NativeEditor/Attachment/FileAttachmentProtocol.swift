//
//  FileAttachmentProtocol.swift
//  MiNoteMac
//
//  文件类附件公共协议，统一 AudioAttachment 和 ImageAttachment 的加载接口
//

import Foundation

// MARK: - 文件附件加载状态

/// 文件附件加载状态
enum FileAttachmentLoadingState {
    case idle
    case loading
    case loaded
    case error(String)
}

// MARK: - 文件附件协议

/// 文件类附件公共协议（继承 ThemeAwareAttachment）
protocol FileAttachmentProtocol: ThemeAwareAttachment {
    /// 文件 ID
    var fileId: String? { get }
    /// 加载状态
    var loadingState: FileAttachmentLoadingState { get }
    /// 开始加载
    func startLoading()
}
