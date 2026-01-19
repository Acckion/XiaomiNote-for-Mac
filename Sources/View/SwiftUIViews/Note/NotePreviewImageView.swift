import SwiftUI
import AppKit

/// 笔记预览图片视图
///
/// 用于在笔记列表中显示图片预览。
/// 支持异步加载、加载状态指示器、错误处理和占位符。
///
/// **使用方式**：
/// ```swift
/// NotePreviewImageView(
///     fileId: "1315204657.mqD6sEiru5CFpGR0vUZaMA",
///     fileType: "png",
///     size: 50
/// )
/// ```
struct NotePreviewImageView: View {
    /// 文件ID（完整格式：userId.fileId）
    let fileId: String
    
    /// 文件类型（如 "png", "jpg"）
    let fileType: String
    
    /// 预览图片尺寸（宽高相同）
    let size: CGFloat
    
    /// 预览服务
    @StateObject private var previewService = NotePreviewService.shared
    
    /// 加载的图片
    @State private var image: NSImage?
    
    /// 是否正在加载
    @State private var isLoading = false
    
    /// 是否加载失败
    @State private var loadFailed = false
    
    init(fileId: String, fileType: String, size: CGFloat = 50) {
        self.fileId = fileId
        self.fileType = fileType
        self.size = size
    }
    
    var body: some View {
        Group {
            if let nsImage = image {
                // 显示图片
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                // 显示加载指示器
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: size, height: size)
            } else if loadFailed {
                // 显示错误占位符
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: size * 0.4))
                    .foregroundColor(.secondary)
            } else {
                // 显示默认占位符
                Image(systemName: "photo")
                    .font(.system(size: size * 0.4))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
        .onAppear {
            loadImage()
        }
        .onChange(of: fileId) { _, _ in
            // 当 fileId 变化时重新加载
            loadImage()
        }
    }
    
    /// 加载图片
    private func loadImage() {
        // 重置状态
        image = nil
        loadFailed = false
        isLoading = true
        
        // 异步加载图片
        Task {
            // 从预览服务加载
            if let loadedImage = previewService.loadPreviewImage(fileId: fileId, fileType: fileType) {
                await MainActor.run {
                    self.image = loadedImage
                    self.isLoading = false
                }
            } else {
                // 加载失败
                await MainActor.run {
                    self.loadFailed = true
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - 预览

#Preview("有图片") {
    NotePreviewImageView(
        fileId: "test.image",
        fileType: "png",
        size: 50
    )
    .padding()
}

#Preview("加载中") {
    VStack {
        ProgressView()
            .scaleEffect(0.6)
    }
    .frame(width: 50, height: 50)
    .background(Color(NSColor.controlBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 4))
    .overlay(
        RoundedRectangle(cornerRadius: 4)
            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
    )
    .padding()
}

#Preview("加载失败") {
    VStack {
        Image(systemName: "exclamationmark.triangle")
            .font(.system(size: 20))
            .foregroundColor(.secondary)
    }
    .frame(width: 50, height: 50)
    .background(Color(NSColor.controlBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 4))
    .overlay(
        RoundedRectangle(cornerRadius: 4)
            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
    )
    .padding()
}
