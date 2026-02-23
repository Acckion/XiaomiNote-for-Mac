//
//  AudioUploadService.swift
//  MiNoteMac
//
//  语音文件上传服务 - 处理录制完成后的上传流程
//

import Combine
import Foundation

/// 语音文件上传服务
///
/// 负责处理录制完成后的上传流程，包括：
/// - 上传语音文件到服务器
/// - 获取 fileId
/// - 进度回调
/// - 错误处理和重试
///
@MainActor
final class AudioUploadService: ObservableObject {

    // MARK: - 单例

    static let shared = AudioUploadService()

    // MARK: - 上传状态枚举

    /// 上传状态
    enum UploadState: Equatable {
        case idle // 空闲
        case uploading // 上传中
        case success // 成功
        case failed(String) // 失败

        static func == (lhs: UploadState, rhs: UploadState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.uploading, .uploading), (.success, .success):
                true
            case let (.failed(lhsMsg), .failed(rhsMsg)):
                lhsMsg == rhsMsg
            default:
                false
            }
        }

        /// 是否正在上传
        var isUploading: Bool {
            if case .uploading = self {
                return true
            }
            return false
        }

        /// 错误信息（如果有）
        var errorMessage: String? {
            if case let .failed(message) = self {
                return message
            }
            return nil
        }
    }

    // MARK: - 上传结果

    /// 上传结果
    struct UploadResult {
        /// 文件 ID
        let fileId: String

        /// 文件摘要
        let digest: String?

        /// MIME 类型
        let mimeType: String
    }

    // MARK: - 发布属性

    /// 当前上传状态
    @Published private(set) var state: UploadState = .idle

    /// 上传进度（0.0 - 1.0）
    @Published private(set) var progress = 0.0

    /// 错误信息
    @Published private(set) var errorMessage: String?

    // MARK: - 通知名称

    /// 上传状态变化通知
    nonisolated(unsafe) static let uploadStateDidChangeNotification = Notification.Name("AudioUploadService.uploadStateDidChange")

    /// 上传进度变化通知
    nonisolated(unsafe) static let uploadProgressDidChangeNotification = Notification.Name("AudioUploadService.uploadProgressDidChange")

    /// 上传完成通知
    nonisolated(unsafe) static let uploadDidCompleteNotification = Notification.Name("AudioUploadService.uploadDidComplete")

    /// 上传失败通知
    nonisolated(unsafe) static let uploadDidFailNotification = Notification.Name("AudioUploadService.uploadDidFail")

    // MARK: - 私有属性

    /// 当前上传任务
    private var currentUploadTask: Task<UploadResult, Error>?

    /// 重试次数
    private var retryCount = 0

    /// 最大重试次数
    private let maxRetryCount = 3

    // MARK: - 初始化

    private init() {}

    @MainActor
    func uploadAudio(fileURL: URL, fileName: String? = nil, mimeType: String = "audio/mpeg") async throws -> UploadResult {
        currentUploadTask?.cancel()

        state = .uploading
        progress = 0.0
        errorMessage = nil
        retryCount = 0

        postStateNotification(oldState: .idle, newState: .uploading)

        do {
            var uploadFileURL = fileURL
            let originalFormat = AudioConverterService.shared.getAudioFormat(fileURL)

            if originalFormat.contains("M4A") || originalFormat.contains("AAC") || fileURL.pathExtension.lowercased() == "m4a" {
                LogService.shared.debug(.audio, "检测到 M4A/AAC 格式，开始转换为 MP3")
                do {
                    uploadFileURL = try await AudioConverterService.shared.convertM4AToMP3(inputURL: fileURL)
                } catch AudioConverterService.ConversionError.ffmpegNotInstalled {
                    let errorMsg = "需要安装 ffmpeg 才能上传语音。\n\n请在终端运行以下命令安装：\nbrew install ffmpeg"
                    LogService.shared.error(.audio, "ffmpeg 未安装")
                    state = .failed(errorMsg)
                    errorMessage = errorMsg
                    postStateNotification(oldState: .uploading, newState: .failed(errorMsg))
                    postFailNotification(error: errorMsg)
                    throw UploadError.conversionFailed(errorMsg)
                } catch let AudioConverterService.ConversionError.invalidOutputFormat(format) {
                    let errorMsg = "音频格式转换失败：输出格式无效 (\(format))"
                    LogService.shared.error(.audio, errorMsg)
                    state = .failed(errorMsg)
                    errorMessage = errorMsg
                    postStateNotification(oldState: .uploading, newState: .failed(errorMsg))
                    postFailNotification(error: errorMsg)
                    throw UploadError.conversionFailed(errorMsg)
                } catch {
                    let errorMsg = "音频格式转换失败：\(error.localizedDescription)"
                    LogService.shared.error(.audio, errorMsg)
                    state = .failed(errorMsg)
                    errorMessage = errorMsg
                    postStateNotification(oldState: .uploading, newState: .failed(errorMsg))
                    postFailNotification(error: errorMsg)
                    throw UploadError.conversionFailed(errorMsg)
                }
            }

            let audioData = try Data(contentsOf: uploadFileURL)

            var actualFileName = fileName ?? fileURL.lastPathComponent
            if actualFileName.hasSuffix(".m4a") {
                actualFileName = actualFileName.replacingOccurrences(of: ".m4a", with: ".mp3")
            } else if !actualFileName.hasSuffix(".mp3") {
                let nameWithoutExt = (actualFileName as NSString).deletingPathExtension
                actualFileName = nameWithoutExt + ".mp3"
            }

            // 生成临时 fileId，保存到本地，入队操作
            let temporaryFileId = NoteOperation.generateTemporaryId()

            try LocalStorageService.shared.savePendingUpload(data: audioData, fileId: temporaryFileId, extension: "mp3")

            progress = 1.0
            postProgressNotification()

            let uploadResult = UploadResult(
                fileId: temporaryFileId,
                digest: nil,
                mimeType: mimeType
            )

            state = .success
            postStateNotification(oldState: .uploading, newState: .success)
            postCompleteNotification(result: uploadResult)

            LogService.shared.info(.audio, "语音已入队上传: temporaryFileId=\(temporaryFileId.prefix(20))..., fileName=\(actualFileName)")

            return uploadResult
        } catch {
            let errorMsg = error.localizedDescription
            LogService.shared.error(.audio, "语音上传准备失败: \(errorMsg)")

            state = .failed(errorMsg)
            errorMessage = errorMsg
            postStateNotification(oldState: .uploading, newState: .failed(errorMsg))
            postFailNotification(error: errorMsg)

            throw error
        }
    }

    /// 入队音频上传操作
    ///
    /// 在 AudioUploadService.uploadAudio 返回临时 fileId 后，
    /// 由调用方（MainWindowController）调用此方法将操作入队。
    func enqueueAudioUpload(temporaryFileId: String, fileName: String, mimeType: String, noteId: String) throws {
        let uploadData = FileUploadOperationData(
            temporaryFileId: temporaryFileId,
            localFilePath: LocalStorageService.shared.pendingUploadsDirectory
                .appendingPathComponent("\(temporaryFileId).mp3").path,
            fileName: fileName,
            mimeType: mimeType,
            noteId: noteId
        )
        let operation = NoteOperation(
            type: .audioUpload,
            noteId: noteId,
            data: uploadData.encoded(),
            isLocalId: NoteOperation.isTemporaryId(noteId)
        )
        _ = try UnifiedOperationQueue.shared.enqueue(operation)
        LogService.shared.debug(.audio, "音频上传操作已入队: \(temporaryFileId.prefix(20))...")
    }

    func cancelUpload() {
        currentUploadTask?.cancel()
        currentUploadTask = nil

        let oldState = state
        state = .idle
        progress = 0.0
        errorMessage = nil

        postStateNotification(oldState: oldState, newState: .idle)
    }

    /// 重置状态
    func reset() {
        state = .idle
        progress = 0.0
        errorMessage = nil
        retryCount = 0
        currentUploadTask = nil
    }

    // MARK: - 私有方法

    /// 判断是否应该重试
    private func shouldRetry(error: Error) -> Bool {
        // 网络错误可以重试
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }

        // 其他错误不重试
        return false
    }

    // MARK: - 通知发送

    /// 发送状态变化通知
    private func postStateNotification(oldState: UploadState, newState: UploadState) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.uploadStateDidChangeNotification,
                object: self,
                userInfo: [
                    "oldState": oldState,
                    "newState": newState,
                ]
            )
        }
    }

    /// 发送进度变化通知
    private func postProgressNotification() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.uploadProgressDidChangeNotification,
                object: self,
                userInfo: [
                    "progress": self.progress,
                ]
            )
        }
    }

    /// 发送上传完成通知
    private func postCompleteNotification(result: UploadResult) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.uploadDidCompleteNotification,
                object: self,
                userInfo: [
                    "fileId": result.fileId,
                    "digest": result.digest as Any,
                    "mimeType": result.mimeType,
                ]
            )
        }
    }

    /// 发送上传失败通知
    private func postFailNotification(error: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.uploadDidFailNotification,
                object: self,
                userInfo: [
                    "error": error,
                ]
            )
        }
    }
}

// MARK: - 上传错误类型

extension AudioUploadService {

    /// 上传错误
    enum UploadError: LocalizedError {
        case fileNotFound // 文件未找到
        case invalidResponse // 响应无效
        case uploadFailed // 上传失败
        case cancelled // 已取消
        case conversionFailed(String) // 格式转换失败

        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                "语音文件未找到"
            case .invalidResponse:
                "服务器响应无效"
            case .uploadFailed:
                "上传失败，请重试"
            case .cancelled:
                "上传已取消"
            case let .conversionFailed(message):
                message
            }
        }
    }
}
