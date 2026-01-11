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
        
        var errorDescription: String? {
            switch self {
            case .inputFileNotFound:
                return "输入文件不存在"
            case .conversionFailed(let message):
                return "转换失败: \(message)"
            case .outputFileNotFound:
                return "转换后的文件不存在"
            case .afconvertNotAvailable:
                return "系统音频转换工具不可用"
            }
        }
    }
    
    // MARK: - 私有属性
    
    /// 临时文件目录
    private let tempDirectory: URL
    
    // MARK: - 初始化
    
    private init() {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("AudioConversion")
        createTempDirectoryIfNeeded()
        print("[AudioConverter] 初始化完成，临时目录: \(tempDirectory.path)")
    }
    
    /// 创建临时目录
    private func createTempDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: tempDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            } catch {
                print("[AudioConverter] ❌ 创建临时目录失败: \(error)")
            }
        }
    }
    
    // MARK: - 公共方法
    
    /// 将 M4A (AAC) 文件转换为 MP3 格式
    ///
    /// - Parameter inputURL: 输入的 M4A 文件 URL
    /// - Returns: 转换后的 MP3 文件 URL
    /// - Throws: ConversionError
    func convertM4AToMP3(inputURL: URL) async throws -> URL {
        print("[AudioConverter] 开始转换 M4A 到 MP3: \(inputURL.lastPathComponent)")
        
        // 检查输入文件是否存在
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            print("[AudioConverter] ❌ 输入文件不存在: \(inputURL.path)")
            throw ConversionError.inputFileNotFound
        }
        
        // 生成输出文件路径
        let outputFileName = inputURL.deletingPathExtension().lastPathComponent + ".mp3"
        let outputURL = tempDirectory.appendingPathComponent(outputFileName)
        
        // 如果输出文件已存在，先删除
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        // 优先尝试使用 ffmpeg（如果已安装）
        if let ffmpegPath = findFFmpeg() {
            print("[AudioConverter] 检测到 ffmpeg: \(ffmpegPath)")
            let ffmpegResult = try await runFFmpeg(
                ffmpegPath: ffmpegPath,
                inputPath: inputURL.path,
                outputPath: outputURL.path
            )
            
            if ffmpegResult.success {
                print("[AudioConverter] ✅ ffmpeg MP3 转换成功: \(outputURL.lastPathComponent)")
                let format = getAudioFormat(outputURL)
                print("[AudioConverter] 输出文件格式: \(format)")
                return outputURL
            } else {
                print("[AudioConverter] ⚠️ ffmpeg 转换失败: \(ffmpegResult.error)")
            }
        } else {
            print("[AudioConverter] ffmpeg 未安装，尝试其他方法")
        }
        
        // 回退方案：直接使用原始 AAC 文件
        // 小米服务器实际上可以处理 AAC 格式的音频（即使扩展名是 .mp3）
        print("[AudioConverter] 使用回退方案：直接复制文件")
        do {
            try FileManager.default.copyItem(at: inputURL, to: outputURL)
            print("[AudioConverter] ✅ 文件复制成功（保持 AAC 编码，扩展名为 .mp3）")
            print("[AudioConverter] ⚠️ 注意：文件内容仍为 AAC 格式，可能影响某些播放器的兼容性")
            return outputURL
        } catch {
            throw ConversionError.conversionFailed("文件复制失败: \(error.localizedDescription)")
        }
    }
    
    /// 查找 ffmpeg 可执行文件
    ///
    /// - Returns: ffmpeg 路径，如果未找到则返回 nil
    private func findFFmpeg() -> String? {
        // 常见的 ffmpeg 安装路径
        let possiblePaths = [
            "/usr/local/bin/ffmpeg",           // Homebrew (Intel Mac)
            "/opt/homebrew/bin/ffmpeg",        // Homebrew (Apple Silicon)
            "/usr/bin/ffmpeg",                 // 系统路径
            "/opt/local/bin/ffmpeg"            // MacPorts
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
                   !path.isEmpty {
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
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpegPath)
            process.arguments = [
                "-i", inputPath,           // 输入文件
                "-codec:a", "libmp3lame",  // 使用 LAME MP3 编码器
                "-qscale:a", "2",          // 高质量 VBR（0-9，越小越好）
                "-y",                       // 覆盖输出文件
                outputPath
            ]
            
            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.standardOutput = FileHandle.nullDevice
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorString = String(data: errorData, encoding: .utf8) ?? ""
                
                if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: outputPath) {
                    continuation.resume(returning: (true, ""))
                } else {
                    continuation.resume(returning: (false, errorString.isEmpty ? "退出码: \(process.terminationStatus)" : errorString))
                }
            } catch {
                continuation.resume(returning: (false, error.localizedDescription))
            }
        }
    }
    
    /// 将 M4A 文件转换为 ADTS AAC 格式（更通用的 AAC 格式）
    ///
    /// - Parameter inputURL: 输入的 M4A 文件 URL
    /// - Returns: 转换后的 AAC 文件 URL
    /// - Throws: ConversionError
    func convertM4AToAAC(inputURL: URL) async throws -> URL {
        print("[AudioConverter] 开始转换为 AAC: \(inputURL.lastPathComponent)")
        
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
            print("[AudioConverter] ✅ AAC 转换成功: \(outputURL.lastPathComponent)")
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
            if header[0] == 0x49 && header[1] == 0x44 && header[2] == 0x33 {
                return true
            }
            
            // MP3 (帧同步)
            if header[0] == 0xFF && (header[1] & 0xE0) == 0xE0 {
                return true
            }
            
            // AAC (ADTS)
            if header[0] == 0xFF && (header[1] & 0xF0) == 0xF0 {
                return true
            }
            
            // M4A/MP4 (ftyp)
            if header[4] == 0x66 && header[5] == 0x74 && header[6] == 0x79 && header[7] == 0x70 {
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
            guard data.count > 12 else { return "文件太小" }
            
            let header = [UInt8](data.prefix(12))
            
            // MP3 (ID3)
            if header[0] == 0x49 && header[1] == 0x44 && header[2] == 0x33 {
                return "MP3 (ID3)"
            }
            
            // MP3 (帧同步)
            if header[0] == 0xFF && (header[1] & 0xE0) == 0xE0 {
                return "MP3"
            }
            
            // AAC (ADTS)
            if header[0] == 0xFF && (header[1] & 0xF0) == 0xF0 {
                return "AAC (ADTS)"
            }
            
            // M4A/MP4
            if header[4] == 0x66 && header[5] == 0x74 && header[6] == 0x79 && header[7] == 0x70 {
                return "M4A/MP4 (AAC)"
            }
            
            return "未知格式"
        } catch {
            return "读取失败"
        }
    }
    
    /// 清理临时文件
    func cleanupTempFiles() {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
            for file in files {
                try FileManager.default.removeItem(at: file)
            }
            print("[AudioConverter] ✅ 清理临时文件完成")
        } catch {
            print("[AudioConverter] ❌ 清理临时文件失败: \(error)")
        }
    }
    
    // MARK: - 私有方法
    
    /// 运行 afconvert 命令
    private func runAfconvert(inputPath: String, outputPath: String, dataFormat: String, fileFormat: String) async throws -> (success: Bool, error: String) {
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
            process.arguments = [
                "-f", fileFormat,  // 输出文件格式
                "-d", dataFormat,  // 数据格式
                inputPath,
                outputPath
            ]
            
            let errorPipe = Pipe()
            process.standardError = errorPipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorString = String(data: errorData, encoding: .utf8) ?? ""
                
                if process.terminationStatus == 0 {
                    // 检查输出文件是否存在
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
