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
final class AudioUploadService: ObservableObject, @unchecked Sendable {

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
    static let uploadStateDidChangeNotification = Notification.Name("AudioUploadService.uploadStateDidChange")

    /// 上传进度变化通知
    static let uploadProgressDidChangeNotification = Notification.Name("AudioUploadService.uploadProgressDidChange")

    /// 上传完成通知
    static let uploadDidCompleteNotification = Notification.Name("AudioUploadService.uploadDidComplete")

    /// 上传失败通知
    static let uploadDidFailNotification = Notification.Name("AudioUploadService.uploadDidFail")

    // MARK: - 私有属性

    /// 当前上传任务
    private var currentUploadTask: Task<UploadResult, Error>?

    /// 重试次数
    private var retryCount = 0

    /// 最大重试次数
    private let maxRetryCount = 3

    // MARK: - 初始化

    private init() {
        print("[AudioUploadService] 初始化完成")
    }

    // MARK: - 公共方法

    /// 上传语音文件
    ///
    /// - Parameters:
    ///   - fileURL: 本地语音文件 URL
    ///   - fileName: 文件名（可选，默认从 URL 获取）
    ///   - mimeType: MIME 类型（默认 audio/mpeg）
    /// - Returns: 上传结果
    /// - Throws: 上传失败时抛出错误
    @MainActor
    func uploadAudio(fileURL: URL, fileName: String? = nil, mimeType: String = "audio/mpeg") async throws -> UploadResult {
        print("[AudioUploadService] 开始上传语音文件: \(fileURL.lastPathComponent)")

        // 取消之前的上传任务
        currentUploadTask?.cancel()

        // 重置状态
        state = .uploading
        progress = 0.0
        errorMessage = nil
        retryCount = 0

        // 发送状态变化通知
        postStateNotification(oldState: .idle, newState: .uploading)

        do {
            // 检查文件格式，如果是 M4A 则转换为 MP3
            var uploadFileURL = fileURL
            let originalFormat = AudioConverterService.shared.getAudioFormat(fileURL)
            print("[AudioUploadService] 原始文件格式: \(originalFormat)")

            if originalFormat.contains("M4A") || originalFormat.contains("AAC") || fileURL.pathExtension.lowercased() == "m4a" {
                print("[AudioUploadService] 检测到 M4A/AAC 格式，开始转换为 MP3...")
                do {
                    uploadFileURL = try await AudioConverterService.shared.convertM4AToMP3(inputURL: fileURL)
                    let convertedFormat = AudioConverterService.shared.getAudioFormat(uploadFileURL)
                    print("[AudioUploadService] 转换后文件格式: \(convertedFormat)")
                } catch AudioConverterService.ConversionError.ffmpegNotInstalled {
                    // 特殊处理 ffmpeg 未安装的情况
                    let errorMsg = "需要安装 ffmpeg 才能上传语音。\n\n请在终端运行以下命令安装：\nbrew install ffmpeg"
                    print("[AudioUploadService] ❌ ffmpeg 未安装")
                    state = .failed(errorMsg)
                    errorMessage = errorMsg
                    postStateNotification(oldState: .uploading, newState: .failed(errorMsg))
                    postFailNotification(error: errorMsg)
                    throw UploadError.conversionFailed(errorMsg)
                } catch let AudioConverterService.ConversionError.invalidOutputFormat(format) {
                    // 处理转换后格式无效的情况
                    let errorMsg = "音频格式转换失败：输出格式无效 (\(format))"
                    print("[AudioUploadService] ❌ 转换后格式无效: \(format)")
                    state = .failed(errorMsg)
                    errorMessage = errorMsg
                    postStateNotification(oldState: .uploading, newState: .failed(errorMsg))
                    postFailNotification(error: errorMsg)
                    throw UploadError.conversionFailed(errorMsg)
                } catch {
                    // 其他转换错误
                    let errorMsg = "音频格式转换失败：\(error.localizedDescription)"
                    print("[AudioUploadService] ❌ MP3 转换失败: \(error.localizedDescription)")
                    state = .failed(errorMsg)
                    errorMessage = errorMsg
                    postStateNotification(oldState: .uploading, newState: .failed(errorMsg))
                    postFailNotification(error: errorMsg)
                    throw UploadError.conversionFailed(errorMsg)
                }
            }

            // 读取文件数据
            let audioData = try Data(contentsOf: uploadFileURL)

            // 确保文件名使用 .mp3 扩展名（API 只接受 .mp3）
            var actualFileName = fileName ?? fileURL.lastPathComponent
            if actualFileName.hasSuffix(".m4a") {
                actualFileName = actualFileName.replacingOccurrences(of: ".m4a", with: ".mp3")
            } else if !actualFileName.hasSuffix(".mp3") {
                // 如果不是 .mp3 或 .m4a，添加 .mp3 扩展名
                let nameWithoutExt = (actualFileName as NSString).deletingPathExtension
                actualFileName = nameWithoutExt + ".mp3"
            }

            print("[AudioUploadService] 文件大小: \(audioData.count) 字节")

            // 阶段 1: 读取文件完成
            progress = 0.1
            postProgressNotification()

            // 阶段 2: 准备上传
            progress = 0.2
            postProgressNotification()

            // 启动进度模拟任务（因为实际上传是原子操作）
            let progressTask = Task { @MainActor in
                var currentProgress = 0.2
                while currentProgress < 0.9, !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    currentProgress += 0.05
                    if currentProgress < 0.9 {
                        self.progress = currentProgress
                        self.postProgressNotification()
                    }
                }
            }

            // 调用 MiNoteService 上传
            let result = try await MiNoteService.shared.uploadAudio(
                audioData: audioData,
                fileName: actualFileName,
                mimeType: mimeType
            )

            // 取消进度模拟任务
            progressTask.cancel()

            // 更新进度到完成
            progress = 1.0
            postProgressNotification()

            // 解析结果
            guard let fileId = result["fileId"] as? String else {
                throw UploadError.invalidResponse
            }

            let digest = result["digest"] as? String
            let resultMimeType = result["mimeType"] as? String ?? mimeType

            let uploadResult = UploadResult(
                fileId: fileId,
                digest: digest,
                mimeType: resultMimeType
            )

            // 更新状态
            state = .success
            postStateNotification(oldState: .uploading, newState: .success)
            postCompleteNotification(result: uploadResult)

            print("[AudioUploadService] ✅ 上传成功: fileId=\(fileId)")

            return uploadResult
        } catch {
            let errorMsg = error.localizedDescription
            print("[AudioUploadService] ❌ 上传失败: \(errorMsg)")

            // 检查是否可以重试
            if retryCount < maxRetryCount, shouldRetry(error: error) {
                retryCount += 1
                print("[AudioUploadService] 尝试重试 (\(retryCount)/\(maxRetryCount))...")

                // 延迟后重试
                try await Task.sleep(nanoseconds: UInt64(1_000_000_000 * retryCount)) // 1秒 * 重试次数
                return try await uploadAudio(fileURL: fileURL, fileName: fileName, mimeType: mimeType)
            }

            // 更新状态
            state = .failed(errorMsg)
            errorMessage = errorMsg
            postStateNotification(oldState: .uploading, newState: .failed(errorMsg))
            postFailNotification(error: errorMsg)

            throw error
        }
    }

    /// 取消当前上传
    func cancelUpload() {
        print("[AudioUploadService] 取消上传")
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
