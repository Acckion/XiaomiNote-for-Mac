# 设计文档

## 概述

本设计文档描述修复语音录制和上传功能的技术方案，主要解决两个问题：
1. 录制完成后预览播放无声音
2. 录制格式为 AAC，但小米服务器需要 MP3 格式，且必须使用 ffmpeg 进行真正的格式转换

## 架构

### 组件关系

```
┌─────────────────────────────────────────────────────────────┐
│                    AudioRecorderView                         │
│  ┌─────────────────┐    ┌─────────────────┐                 │
│  │  录制界面        │ -> │  预览界面        │                 │
│  └─────────────────┘    └─────────────────┘                 │
│           │                      │                           │
│           v                      v                           │
│  ┌─────────────────┐    ┌─────────────────┐                 │
│  │AudioRecorderSvc │    │AudioPlayerSvc   │                 │
│  └─────────────────┘    └─────────────────┘                 │
└─────────────────────────────────────────────────────────────┘
                    │
                    v (确认上传)
┌─────────────────────────────────────────────────────────────┐
│                  AudioUploadService                          │
│  ┌─────────────────┐    ┌─────────────────┐                 │
│  │AudioConverterSvc│ -> │  MiNoteService  │                 │
│  │  (AAC -> MP3)   │    │  (上传到服务器)  │                 │
│  └─────────────────┘    └─────────────────┘                 │
└─────────────────────────────────────────────────────────────┘
```

## 组件和接口

### 1. AudioRecorderService 修改

当前问题：录制设置使用 `kAudioFormatMPEG4AAC` 格式，输出 `.m4a` 文件。这个格式本身是正确的，但需要确保录制器正确配置。

修改方案：保持 AAC 格式录制（这是 macOS 原生支持的高质量格式），但确保录制设置正确。

```swift
// 保持现有录制设置（已经是正确的）
private let recordingSettings: [String: Any] = [
    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
    AVSampleRateKey: 44100.0,
    AVNumberOfChannelsKey: 1,
    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    AVEncoderBitRateKey: 128000
]
```

### 2. AudioRecorderView 修改

当前问题：`loadAudioForPreview` 方法先调用 `play()` 然后立即调用 `pause()`，这可能导致播放器还没准备好就被暂停。

修改方案：不要在加载时自动播放，而是只准备播放器，等用户点击播放按钮时再播放。

```swift
/// 加载音频用于预览（修改后）
private func loadAudioForPreview(_ url: URL) {
    // 不再自动播放然后暂停
    // 只需要验证文件可以被加载
    if let duration = playerService.getDuration(for: url) {
        print("[AudioRecorderView] 预览音频加载成功，时长: \(duration)")
    } else {
        print("[AudioRecorderView] ⚠️ 无法获取音频时长")
    }
}
```

### 3. AudioConverterService 修改

当前问题：如果未安装 ffmpeg，会直接复制文件并更改扩展名，这会导致文件损坏。

修改方案：
1. 移除回退方案（直接复制文件）
2. 如果未安装 ffmpeg，抛出明确错误
3. 添加 ffmpeg 安装检查方法

```swift
/// 将 M4A (AAC) 文件转换为 MP3 格式
func convertM4AToMP3(inputURL: URL) async throws -> URL {
    // 检查输入文件是否存在
    guard FileManager.default.fileExists(atPath: inputURL.path) else {
        throw ConversionError.inputFileNotFound
    }
    
    // 检查 ffmpeg 是否可用
    guard let ffmpegPath = findFFmpeg() else {
        throw ConversionError.ffmpegNotInstalled
    }
    
    // 生成输出文件路径
    let outputFileName = inputURL.deletingPathExtension().lastPathComponent + ".mp3"
    let outputURL = tempDirectory.appendingPathComponent(outputFileName)
    
    // 如果输出文件已存在，先删除
    if FileManager.default.fileExists(atPath: outputURL.path) {
        try? FileManager.default.removeItem(at: outputURL)
    }
    
    // 使用 ffmpeg 转换
    let result = try await runFFmpeg(
        ffmpegPath: ffmpegPath,
        inputPath: inputURL.path,
        outputPath: outputURL.path
    )
    
    if result.success {
        // 验证输出文件格式
        let format = getAudioFormat(outputURL)
        guard format.contains("MP3") else {
            throw ConversionError.conversionFailed("转换后的文件不是有效的 MP3 格式")
        }
        return outputURL
    } else {
        throw ConversionError.conversionFailed(result.error)
    }
}

/// 检查 ffmpeg 是否已安装
func isFFmpegInstalled() -> Bool {
    return findFFmpeg() != nil
}
```

### 4. 新增错误类型

```swift
enum ConversionError: LocalizedError {
    case inputFileNotFound
    case conversionFailed(String)
    case outputFileNotFound
    case afconvertNotAvailable
    case ffmpegNotInstalled  // 新增
    
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
        case .ffmpegNotInstalled:
            return "需要安装 ffmpeg 才能上传语音。请使用 Homebrew 安装：brew install ffmpeg"
        }
    }
}
```

### 5. AudioUploadService 修改

修改上传流程，在转换失败时提供更好的错误提示：

```swift
@MainActor
func uploadAudio(fileURL: URL, fileName: String? = nil, mimeType: String = "audio/mpeg") async throws -> UploadResult {
    // ... 现有代码 ...
    
    do {
        // 检查文件格式，如果是 M4A 则转换为 MP3
        var uploadFileURL = fileURL
        let originalFormat = AudioConverterService.shared.getAudioFormat(fileURL)
        
        if originalFormat.contains("M4A") || originalFormat.contains("AAC") || fileURL.pathExtension.lowercased() == "m4a" {
            // 转换为 MP3（如果失败会抛出错误）
            uploadFileURL = try await AudioConverterService.shared.convertM4AToMP3(inputURL: fileURL)
        }
        
        // ... 继续上传 ...
        
    } catch AudioConverterService.ConversionError.ffmpegNotInstalled {
        // 特殊处理 ffmpeg 未安装的情况
        let errorMsg = "需要安装 ffmpeg 才能上传语音。\n\n请在终端运行以下命令安装：\nbrew install ffmpeg"
        state = .failed(errorMsg)
        errorMessage = errorMsg
        throw UploadError.conversionFailed(errorMsg)
    } catch {
        // 其他错误
        throw error
    }
}
```

## 数据模型

无需修改现有数据模型。

## 正确性属性

*属性是一种特征或行为，应该在系统的所有有效执行中保持为真——本质上是关于系统应该做什么的正式声明。属性作为人类可读规范和机器可验证正确性保证之间的桥梁。*

### Property 1: 录制文件可播放性

*对于任意* 通过 AudioRecorderService 录制的音频文件，AVAudioPlayer 应该能够成功加载并获取其时长（时长 > 0）。

**Validates: Requirements 1.1, 2.1, 2.2, 3.4**

### Property 2: 播放器状态正确性

*对于任意* 有效的音频文件 URL，当 AudioPlayerService 播放该文件时，currentTime 应该在 0 到 duration 之间，progress 应该在 0.0 到 1.0 之间。

**Validates: Requirements 1.3**

### Property 3: 格式转换正确性

*对于任意* 有效的 M4A/AAC 音频文件，如果 ffmpeg 已安装，AudioConverterService.convertM4AToMP3 应该生成一个有效的 MP3 文件（文件头为 MP3 格式）。

**Validates: Requirements 2.3, 2.5**

### Property 4: ffmpeg 未安装时的错误处理

*对于* ffmpeg 未安装的情况，AudioConverterService.convertM4AToMP3 应该抛出 ffmpegNotInstalled 错误，而不是生成损坏的文件。

**Validates: Requirements 2.4, 2.5**

## 错误处理

| 错误场景 | 处理方式 |
|---------|---------|
| 录制文件无法播放 | 显示错误提示，允许重录 |
| ffmpeg 未安装 | 显示安装指南，阻止上传 |
| 格式转换失败 | 显示错误详情，允许重试 |
| 上传失败 | 显示错误提示，允许重试 |

## 测试策略

### 单元测试

1. 测试 AudioRecorderService 录制设置是否正确配置
2. 测试 AudioConverterService.isFFmpegInstalled() 方法
3. 测试 AudioConverterService 在 ffmpeg 未安装时抛出正确错误

### 属性测试

1. **Property 1**: 录制文件可播放性测试
   - 生成随机时长的录制
   - 验证文件可被 AVAudioPlayer 加载
   - 最少 100 次迭代

2. **Property 3**: 格式转换正确性测试（需要 ffmpeg）
   - 生成随机 AAC 文件
   - 转换为 MP3
   - 验证输出文件格式

### 集成测试

1. 完整录制 -> 预览 -> 上传流程测试
2. 错误恢复流程测试

