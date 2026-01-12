# 需求文档

## 简介

修复语音录制和上传功能中的两个关键问题：
1. 录制完成后预览播放无声音
2. 录制格式为 AAC，但小米服务器需要 MP3 格式

## 术语表

- **AudioRecorderService**: 音频录制服务，负责录制语音
- **AudioPlayerService**: 音频播放服务，负责播放音频文件
- **AudioConverterService**: 音频格式转换服务，负责将 AAC 转换为 MP3
- **AVAudioRecorder**: macOS 系统音频录制 API
- **AVAudioPlayer**: macOS 系统音频播放 API
- **AAC**: Advanced Audio Coding，高级音频编码格式
- **MP3**: MPEG Audio Layer 3，常用音频压缩格式
- **M4A**: MPEG-4 Audio，AAC 编码的容器格式

## 需求

### 需求 1：修复录音预览播放无声音问题

**用户故事：** 作为用户，我希望在确认上传前能够预览刚录制的语音，以便确认录音质量。

#### 验收标准

1. WHEN 录制完成后进入预览状态 THEN AudioRecorderView SHALL 正确加载录制的音频文件用于预览
2. WHEN 用户点击预览播放按钮 THEN AudioPlayerService SHALL 播放录制的音频并输出声音
3. WHEN 预览播放时 THEN AudioPlayerService SHALL 正确显示播放进度和时间
4. IF 音频文件加载失败 THEN AudioRecorderView SHALL 显示错误提示并允许重试

### 需求 2：确保录制格式与服务器兼容

**用户故事：** 作为用户，我希望录制的语音能够成功上传到小米服务器，以便在其他设备上也能播放。

#### 验收标准

1. WHEN AudioRecorderService 开始录制 THEN 系统 SHALL 使用与 AVAudioPlayer 兼容的格式录制
2. WHEN 录制完成后 THEN 录制的文件 SHALL 能够被 AVAudioPlayer 正常播放
3. WHEN 上传语音文件时 THEN AudioUploadService SHALL 将音频转换为 MP3 格式
4. IF 系统未安装 ffmpeg THEN AudioConverterService SHALL 抛出明确错误并提示用户安装 ffmpeg
5. THE AudioConverterService SHALL NOT 直接更改文件扩展名而不进行实际格式转换

### 需求 3：优化录制设置

**用户故事：** 作为用户，我希望录制的语音质量良好且文件大小适中。

#### 验收标准

1. THE AudioRecorderService SHALL 使用 44100 Hz 采样率录制
2. THE AudioRecorderService SHALL 使用单声道录制以减小文件大小
3. THE AudioRecorderService SHALL 使用高质量编码设置
4. WHEN 录制完成 THEN 生成的文件 SHALL 能够被系统音频播放器正常播放

