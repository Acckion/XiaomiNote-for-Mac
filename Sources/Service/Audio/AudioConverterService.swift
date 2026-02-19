//
//  AudioConverterService.swift
//  MiNoteMac
//
//  音频格式转换服务 - 将 M4A (AAC) 转换为 MP3 格式
//  用于确保上传到小米笔记服务器的音频文件格式正确
//

import Foundation

/// 音频格式转换服务
///
/// 使用 macOS 系统自带的 afconvert 工具将 AAC (M4A) 格式转换为 MP3 格式。
/// 小米笔记服务器期望的是 MP3 格式 (audio/mpeg)，但 AVAudioRecorder 默认录制为 AAC 格式。
final class AudioConverterService: @unchecked Sendable {

    // MARK: - 单例

    static let shared = AudioConverterService()

    // MARK: - 错误类型

    enum ConversionError: LocalizedError {
        case inputFileNotFound
        case conversionFailed(String)
        case outputFileNotFound
        case afconvertNotAvailable
        case ffmpegNotInstalled
        case invalidOutputFormat(String)

        var errorDescription: String? {
            switch self {
            case .inputFileNotFound:
                "输入文件不存在"
            case let .conversionFailed(message):
                "转换失败: \(message)"
            case .outputFileNotFound:
                "转换后的文件不存在"
            case .afconvertNotAvailable:
                "系统音频转换工具不可用"
            case .ffmpegNotInstalled:
                "需要安装 ffmpeg 才能上传语音。\n\n请在终端运行以下命令安装：\nbrew install ffmpeg"
            case let .invalidOutputFormat(format):
                "转换后的文件格式无效: \(format)，期望 MP3 格式"
            }
        }
    }

    // MARK: - 私有属性

    /// 临时文件目录
    private let tempDirectory: URL

    // MARK: - 初始化

    private init() {
        self.tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("AudioConversion")
        createTempDirectoryIfNeeded()
        LogService.shared.debug(.audio, "AudioConverterService 初始化完成")
    }

    /// 创建临时目录
    private func createTempDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: tempDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            } catch {
                LogService.shared.error(.audio, "创建临时目录失败: \(error)")
            }
        }
    }

    // MARK: - 公共方法

    /// 检查 ffmpeg 是否已安装
    ///
    /// - Returns: 如果 ffmpeg 已安装返回 true，否则返回 false
    func isFFmpegInstalled() -> Bool {
        findFFmpeg() != nil
    }

    /// 将 M4A (AAC) 文件转换为 MP3 格式
    ///
    /// - Parameter inputURL: 输入的 M4A 文件 URL
    /// - Returns: 转换后的 MP3 文件 URL
    /// - Throws: ConversionError
    func convertM4AToMP3(inputURL: URL) async throws -> URL {
        LogService.shared.info(.audio, "开始转换 M4A 到 MP3: \(inputURL.lastPathComponent)")

        // 检查输入文件是否存在
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            LogService.shared.error(.audio, "输入文件不存在: \(inputURL.lastPathComponent)")
            throw ConversionError.inputFileNotFound
        }

        // 缓存原始 M4A 文件（用于调试和预览播放）
        do {
            let cachedM4A = try cacheM4AFile(inputURL: inputURL)
            LogService.shared.debug(.audio, "已缓存原始 M4A 文件: \(cachedM4A.lastPathComponent)")
        } catch {
            LogService.shared.warning(.audio, "缓存 M4A 文件失败: \(error.localizedDescription)")
        }

        // 检查 ffmpeg 是否可用
        guard let ffmpegPath = findFFmpeg() else {
            LogService.shared.error(.audio, "ffmpeg 未安装")
            throw ConversionError.ffmpegNotInstalled
        }

        // 生成输出文件路径
        let outputFileName = inputURL.deletingPathExtension().lastPathComponent + ".mp3"
        let outputURL = tempDirectory.appendingPathComponent(outputFileName)

        // 如果输出文件已存在，先删除
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        // 使用 ffmpeg 进行转换
        let ffmpegResult = try await runFFmpeg(
            ffmpegPath: ffmpegPath,
            inputPath: inputURL.path,
            outputPath: outputURL.path
        )

        if ffmpegResult.success {
            // 验证输出文件格式
            let format = getAudioFormat(outputURL)

            // 检查是否为有效的 MP3 格式
            guard format.contains("MP3") else {
                LogService.shared.error(.audio, "转换后的文件不是有效的 MP3 格式: \(format)")
                try? FileManager.default.removeItem(at: outputURL)
                throw ConversionError.invalidOutputFormat(format)
            }

            LogService.shared.info(.audio, "MP3 转换成功: \(outputURL.lastPathComponent)")
            return outputURL
        } else {
            LogService.shared.error(.audio, "ffmpeg 转换失败: \(ffmpegResult.error)")
            throw ConversionError.conversionFailed(ffmpegResult.error)
        }
    }

    /// 查找 ffmpeg 可执行文件
    ///
    /// - Returns: ffmpeg 路径，如果未找到则返回 nil
    private func findFFmpeg() -> String? {
        // 常见的 ffmpeg 安装路径
        let possiblePaths = [
            "/usr/local/bin/ffmpeg", // Homebrew (Intel Mac)
            "/opt/homebrew/bin/ffmpeg", // Homebrew (Apple Silicon)
            "/usr/bin/ffmpeg", // 系统路径
            "/opt/local/bin/ffmpeg", // MacPorts
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // 尝试使用 which 命令查找
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ffmpeg"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty
                {
                    return path
                }
            }
        } catch {
            // 忽略错误
        }

        return nil
    }

    /// 使用 ffmpeg 进行转换
    private func runFFmpeg(ffmpegPath: String, inputPath: String, outputPath: String) async throws -> (success: Bool, error: String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpegPath)

            // 使用与小米手机 App 相同的音频参数
            // 小米手机录制的音频格式：
            // - 采样率：16000 Hz
            // - 比特率：24 kbps
            // - 声道：单声道
            // - 无 ID3 标签
            // - 无 Xing 头
            process.arguments = [
                "-i", inputPath,
                "-acodec", "libmp3lame",
                "-b:a", "24k", // 比特率 24kbps（与小米手机一致）
                "-ar", "16000", // 采样率 16000Hz（与小米手机一致）
                "-ac", "1", // 单声道
                "-write_xing", "0", // 不写入 Xing 头
                "-id3v2_version", "0", // 不写入 ID3v2 标签
                "-y",
                outputPath,
            ]

            let errorPipe = Pipe()
            let outputPipe = Pipe()
            process.standardError = errorPipe
            process.standardOutput = outputPipe

            do {
                try process.run()
                process.waitUntilExit()

                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorString = String(data: errorData, encoding: .utf8) ?? ""

                if process.terminationStatus == 0, FileManager.default.fileExists(atPath: outputPath) {
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: outputPath),
                       let size = attrs[.size] as? Int64
                    {
                        if size < 100 {
                            continuation.resume(returning: (false, "输出文件太小，可能转换失败"))
                            return
                        }
                    }
                    continuation.resume(returning: (true, ""))
                } else {
                    continuation.resume(returning: (false, errorString.isEmpty ? "退出码: \(process.terminationStatus)" : errorString))
                }
            } catch {
                continuation.resume(returning: (false, error.localizedDescription))
            }
        }
    }

    /// 缓存原始 M4A 文件到临时目录
    ///
    /// - Parameter inputURL: 原始 M4A 文件 URL
    /// - Returns: 缓存后的文件 URL
    func cacheM4AFile(inputURL: URL) throws -> URL {
        let fileName = inputURL.lastPathComponent
        let cachedURL = tempDirectory.appendingPathComponent(fileName)

        // 如果已经存在，先删除
        if FileManager.default.fileExists(atPath: cachedURL.path) {
            try FileManager.default.removeItem(at: cachedURL)
        }

        try FileManager.default.copyItem(at: inputURL, to: cachedURL)
        return cachedURL
    }

    /// 获取临时目录路径
    func getTempDirectory() -> URL {
        tempDirectory
    }

    /// 使用 ffprobe 检查音频文件信息
    func probeAudioFile(_ url: URL) -> String {
        // 查找 ffprobe
        let possiblePaths = [
            "/usr/local/bin/ffprobe",
            "/opt/homebrew/bin/ffprobe",
            "/usr/bin/ffprobe",
        ]

        var ffprobePath: String?
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                ffprobePath = path
                break
            }
        }

        guard let probePath = ffprobePath else {
            return "ffprobe 未安装"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: probePath)
        process.arguments = [
            "-v", "error",
            "-show_entries", "stream=codec_name,sample_rate,channels,duration",
            "-of", "default=noprint_wrappers=1",
            url.path,
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? "无法读取输出"
        } catch {
            return "执行失败: \(error.localizedDescription)"
        }
    }

    /// 使用 ffprobe 检查音频文件的详细信息（包括音量信息）
    func probeAudioFileDetailed(_ url: URL) -> String {
        // 查找 ffprobe
        let possiblePaths = [
            "/usr/local/bin/ffprobe",
            "/opt/homebrew/bin/ffprobe",
            "/usr/bin/ffprobe",
        ]

        var ffprobePath: String?
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                ffprobePath = path
                break
            }
        }

        guard let probePath = ffprobePath else {
            return "ffprobe 未安装"
        }

        // 获取基本流信息
        let process = Process()
        process.executableURL = URL(fileURLWithPath: probePath)
        process.arguments = [
            "-v", "error",
            "-show_entries", "stream=codec_name,codec_type,sample_rate,channels,bit_rate,duration",
            "-show_entries", "format=duration,size,bit_rate",
            "-of", "default=noprint_wrappers=1",
            url.path,
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        var result = ""

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            result = String(data: data, encoding: .utf8) ?? "无法读取输出"
        } catch {
            result = "执行失败: \(error.localizedDescription)"
        }

        // 检查音频是否有实际内容（使用 volumedetect 滤镜）
        let volumeProcess = Process()
        volumeProcess.executableURL = URL(fileURLWithPath: findFFmpeg() ?? "/opt/homebrew/bin/ffmpeg")
        volumeProcess.arguments = [
            "-i", url.path,
            "-af", "volumedetect",
            "-f", "null",
            "-",
        ]

        let volumePipe = Pipe()
        volumeProcess.standardError = volumePipe
        volumeProcess.standardOutput = FileHandle.nullDevice

        do {
            try volumeProcess.run()
            volumeProcess.waitUntilExit()

            let volumeData = volumePipe.fileHandleForReading.readDataToEndOfFile()
            let volumeOutput = String(data: volumeData, encoding: .utf8) ?? ""

            // 提取音量信息
            if let meanVolumeRange = volumeOutput.range(of: "mean_volume:.*dB", options: .regularExpression) {
                let meanVolume = String(volumeOutput[meanVolumeRange])
                result += "\n音量检测: \(meanVolume)"
            }
            if let maxVolumeRange = volumeOutput.range(of: "max_volume:.*dB", options: .regularExpression) {
                let maxVolume = String(volumeOutput[maxVolumeRange])
                result += "\n\(maxVolume)"
            }
        } catch {
            result += "\n音量检测失败: \(error.localizedDescription)"
        }

        return result
    }

    /// 将 M4A 文件转换为 ADTS AAC 格式（更通用的 AAC 格式）
    ///
    /// - Parameter inputURL: 输入的 M4A 文件 URL
    /// - Returns: 转换后的 AAC 文件 URL
    /// - Throws: ConversionError
    func convertM4AToAAC(inputURL: URL) async throws -> URL {
        LogService.shared.info(.audio, "开始转换为 AAC: \(inputURL.lastPathComponent)")

        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw ConversionError.inputFileNotFound
        }

        guard FileManager.default.fileExists(atPath: "/usr/bin/afconvert") else {
            throw ConversionError.afconvertNotAvailable
        }

        let outputFileName = inputURL.deletingPathExtension().lastPathComponent + ".aac"
        let outputURL = tempDirectory.appendingPathComponent(outputFileName)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let result = try await runAfconvert(
            inputPath: inputURL.path,
            outputPath: outputURL.path,
            dataFormat: "aac",
            fileFormat: "adts"
        )

        if result.success {
            LogService.shared.info(.audio, "AAC 转换成功: \(outputURL.lastPathComponent)")
            return outputURL
        } else {
            throw ConversionError.conversionFailed(result.error)
        }
    }

    /// 检查文件是否为有效的音频文件
    ///
    /// - Parameter url: 文件 URL
    /// - Returns: 是否为有效音频
    func isValidAudioFile(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count > 4 else { return false }

            // 检查文件头
            let header = [UInt8](data.prefix(12))

            // MP3 (ID3 标签)
            if header[0] == 0x49, header[1] == 0x44, header[2] == 0x33 {
                return true
            }

            // MP3 (帧同步)
            if header[0] == 0xFF, (header[1] & 0xE0) == 0xE0 {
                return true
            }

            // AAC (ADTS)
            if header[0] == 0xFF, (header[1] & 0xF0) == 0xF0 {
                return true
            }

            // M4A/MP4 (ftyp)
            if header[4] == 0x66, header[5] == 0x74, header[6] == 0x79, header[7] == 0x70 {
                return true
            }

            return false
        } catch {
            return false
        }
    }

    /// 获取音频文件的格式信息
    ///
    /// - Parameter url: 文件 URL
    /// - Returns: 格式描述字符串
    func getAudioFormat(_ url: URL) -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return "文件不存在"
        }

        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            return getAudioFormat(data)
        } catch {
            return "读取失败"
        }
    }

    /// 获取音频数据的格式信息
    ///
    /// - Parameter data: 音频数据
    /// - Returns: 格式描述字符串
    func getAudioFormat(_ data: Data) -> String {
        guard data.count > 12 else { return "数据太小" }

        let header = [UInt8](data.prefix(12))

        // MP3 (ID3)
        if header[0] == 0x49, header[1] == 0x44, header[2] == 0x33 {
            return "MP3 (ID3)"
        }

        // MP3 (帧同步)
        if header[0] == 0xFF, (header[1] & 0xE0) == 0xE0 {
            return "MP3"
        }

        // AAC (ADTS)
        if header[0] == 0xFF, (header[1] & 0xF0) == 0xF0 {
            return "AAC (ADTS)"
        }

        // M4A/MP4
        if header[4] == 0x66, header[5] == 0x74, header[6] == 0x79, header[7] == 0x70 {
            return "M4A/MP4 (AAC)"
        }

        return "未知格式 (头部: \(header.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " ")))"
    }

    /// 清理临时文件
    func cleanupTempFiles() {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
            for file in files {
                try FileManager.default.removeItem(at: file)
            }
            LogService.shared.info(.audio, "清理临时文件完成")
        } catch {
            LogService.shared.error(.audio, "清理临时文件失败: \(error)")
        }
    }

    // MARK: - 私有方法

    /// 运行 afconvert 命令
    private func runAfconvert(
        inputPath: String,
        outputPath: String,
        dataFormat: String,
        fileFormat: String
    ) async throws -> (success: Bool, error: String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
            process.arguments = [
                "-f", fileFormat, // 输出文件格式
                "-d", dataFormat, // 数据格式
                inputPath,
                outputPath,
            ]

            let errorPipe = Pipe()
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()

                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorString = String(data: errorData, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    if FileManager.default.fileExists(atPath: outputPath) {
                        continuation.resume(returning: (true, ""))
                    } else {
                        continuation.resume(returning: (false, "输出文件未生成"))
                    }
                } else {
                    continuation.resume(returning: (false, errorString.isEmpty ? "退出码: \(process.terminationStatus)" : errorString))
                }
            } catch {
                continuation.resume(returning: (false, error.localizedDescription))
            }
        }
    }
}
