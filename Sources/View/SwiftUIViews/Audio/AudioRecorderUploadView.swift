//
//  AudioRecorderUploadView.swift
//  MiNoteMac
//
//  语音录制和上传视图 - 集成录制完成后的上传流程

import Combine
import SwiftUI

/// 语音录制和上传视图
///
/// 集成录制和上传流程，包括：
/// - 录制语音
/// - 预览录音
/// - 上传到服务器
/// - 获取 fileId 并回调
///
struct AudioRecorderUploadView: View {

    // MARK: - Properties

    /// 上传服务
    @ObservedObject private var uploadService = AudioUploadService.shared

    /// 录制完成并上传成功的回调
    /// - Parameters:
    ///   - fileId: 上传后的文件 ID
    ///   - digest: 文件摘要
    ///   - mimeType: MIME 类型
    let onUploadComplete: (String, String?, String) -> Void

    /// 取消回调
    let onCancel: () -> Void

    /// 当前视图状态
    @State private var viewState: ViewState = .recording

    /// 录制完成的文件 URL
    @State private var recordedFileURL: URL?

    /// 上传进度
    @State private var uploadProgress = 0.0

    /// 错误信息
    @State private var errorMessage: String?

    /// 是否显示重试按钮
    @State private var showRetryButton = false

    // MARK: - View State

    /// 视图状态枚举
    enum ViewState {
        case recording // 录制中
        case uploading // 上传中
        case success // 成功
        case error // 错误
    }

    // MARK: - Body

    var body: some View {
        Group {
            switch viewState {
            case .recording:
                // 录制视图
                AudioRecorderView(
                    onComplete: { url in
                        recordedFileURL = url
                        startUpload(fileURL: url)
                    },
                    onCancel: onCancel
                )
            case .uploading:
                uploadingView
            case .success:
                successView
            case .error:
                errorView
            }
        }
        .onChange(of: uploadService.state) { _, newState in
            handleUploadStateChange(newState)
        }
        .onChange(of: uploadService.progress) { _, newProgress in
            uploadProgress = newProgress
        }
    }

    // MARK: - Subviews

    /// 上传中视图
    private var uploadingView: some View {
        VStack(spacing: 20) {
            // 标题
            HStack {
                Image(systemName: "icloud.and.arrow.up")
                    .foregroundColor(.orange)
                    .font(.title2)
                    .symbolEffect(.pulse)

                Text("正在上传")
                    .font(.headline)

                Spacer()
            }

            // 进度指示器
            VStack(spacing: 12) {
                // 圆形进度指示器
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                        .frame(width: 80, height: 80)

                    Circle()
                        .trim(from: 0, to: CGFloat(uploadProgress))
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: uploadProgress)

                    Text("\(Int(uploadProgress * 100))%")
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.medium)
                }
                .padding(.vertical, 10)

                // 线性进度条
                ProgressView(value: uploadProgress)
                    .progressViewStyle(.linear)
                    .tint(.orange)

                // 状态文字
                Text(uploadStatusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 10)

            // 取消按钮
            Button("取消上传") {
                cancelUpload()
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(width: 320)
        .background(backgroundView)
    }

    /// 上传状态文字
    private var uploadStatusText: String {
        if uploadProgress < 0.2 {
            "准备上传..."
        } else if uploadProgress < 0.9 {
            "正在上传语音文件..."
        } else {
            "即将完成..."
        }
    }

    /// 成功视图
    private var successView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("上传成功")
                .font(.headline)

            Text("语音已添加到笔记中")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(width: 320)
        .background(backgroundView)
        .onAppear {
            // 成功后自动关闭
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // 视图会在 onUploadComplete 回调后被关闭
            }
        }
    }

    /// 错误视图
    private var errorView: some View {
        VStack(spacing: 20) {
            // 标题
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.title2)

                Text("上传失败")
                    .font(.headline)

                Spacer()

                // 关闭按钮
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }

            // 错误信息
            Text(errorMessage ?? "上传失败，请重试")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.vertical, 10)

            // 操作按钮
            HStack(spacing: 16) {
                // 取消按钮
                Button("取消") {
                    cleanupAndCancel()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                // 重试按钮
                Button("重试") {
                    retryUpload()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        .frame(width: 320)
        .background(backgroundView)
    }

    /// 背景视图
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(NSColor.controlBackgroundColor))
            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

    // MARK: - Actions

    /// 开始上传
    private func startUpload(fileURL: URL) {
        viewState = .uploading
        uploadProgress = 0.0
        errorMessage = nil

        Task { @MainActor in
            do {
                let result = try await uploadService.uploadAudio(fileURL: fileURL)

                // 上传成功
                viewState = .success

                // 回调
                onUploadComplete(result.fileId, result.digest, result.mimeType)
            } catch {
                // 上传失败
                errorMessage = error.localizedDescription
                viewState = .error
            }
        }
    }

    /// 取消上传
    private func cancelUpload() {
        uploadService.cancelUpload()
        cleanupAndCancel()
    }

    /// 重试上传
    private func retryUpload() {
        guard let fileURL = recordedFileURL else {
            // 没有录制文件，返回录制状态
            viewState = .recording
            return
        }

        startUpload(fileURL: fileURL)
    }

    /// 清理并取消
    private func cleanupAndCancel() {
        // 删除临时文件
        if let url = recordedFileURL {
            try? FileManager.default.removeItem(at: url)
        }

        uploadService.reset()
        onCancel()
    }

    /// 处理上传状态变化
    private func handleUploadStateChange(_ newState: AudioUploadService.UploadState) {
        switch newState {
        case .idle:
            break
        case .uploading:
            viewState = .uploading
        case .success:
            viewState = .success
        case let .failed(message):
            errorMessage = message
            viewState = .error
        }
    }
}

// MARK: - Audio Recorder Upload Sheet View

/// 语音录制上传 Sheet 视图（用于从其他视图弹出）
struct AudioRecorderUploadSheetView: View {

    @Environment(\.dismiss) private var dismiss

    /// 上传完成回调
    let onUploadComplete: (String, String?, String) -> Void

    var body: some View {
        AudioRecorderUploadView(
            onUploadComplete: { fileId, digest, mimeType in
                onUploadComplete(fileId, digest, mimeType)
                dismiss()
            },
            onCancel: {
                dismiss()
            }
        )
    }
}

// MARK: - Audio Recorder Upload Popover View

/// 语音录制上传弹出视图
struct AudioRecorderUploadPopoverView: View {

    /// 上传完成回调
    let onUploadComplete: (String, String?, String) -> Void

    /// 关闭回调
    let onDismiss: () -> Void

    var body: some View {
        AudioRecorderUploadView(
            onUploadComplete: { fileId, digest, mimeType in
                onUploadComplete(fileId, digest, mimeType)
                onDismiss()
            },
            onCancel: onDismiss
        )
    }
}

// MARK: - Preview

#Preview("Uploading State") {
    AudioRecorderUploadView(
        onUploadComplete: { fileId, _, _ in
            print("Upload complete: fileId=\(fileId)")
        },
        onCancel: {
            print("Cancelled")
        }
    )
    .padding()
}
