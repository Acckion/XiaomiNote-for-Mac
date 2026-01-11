# 实现计划：语音录制修复

## 概述

本实现计划修复语音录制和上传功能中的两个关键问题：预览播放无声音和格式转换问题。

## 任务

- [-] 1. 修复 AudioConverterService 格式转换逻辑
  - [ ] 1.1 添加 ffmpegNotInstalled 错误类型
    - 在 ConversionError 枚举中添加新的错误类型
    - 提供包含安装指南的错误描述
    - _Requirements: 2.4_
  - [ ] 1.2 移除直接复制文件的回退方案
    - 删除 convertM4AToMP3 方法中的回退逻辑
    - 如果 ffmpeg 未安装，直接抛出 ffmpegNotInstalled 错误
    - _Requirements: 2.4, 2.5_
  - [ ] 1.3 添加 isFFmpegInstalled 公共方法
    - 提供检查 ffmpeg 是否安装的便捷方法
    - _Requirements: 2.4_
  - [ ] 1.4 添加转换后格式验证
    - 转换完成后验证输出文件确实是 MP3 格式
    - 如果不是有效 MP3，抛出错误
    - _Requirements: 2.3, 2.5_

- [ ] 2. 修复 AudioRecorderView 预览播放问题
  - [ ] 2.1 修改 loadAudioForPreview 方法
    - 移除自动播放然后暂停的逻辑
    - 只验证文件可以被加载
    - _Requirements: 1.1_
  - [ ] 2.2 修改 togglePreviewPlayback 方法
    - 确保从头开始播放时正确初始化
    - _Requirements: 1.2_

- [ ] 3. 更新 AudioUploadService 错误处理
  - [ ] 3.1 添加 conversionFailed 错误类型
    - 在 UploadError 枚举中添加新的错误类型
    - _Requirements: 2.4_
  - [ ] 3.2 特殊处理 ffmpeg 未安装的情况
    - 捕获 ffmpegNotInstalled 错误
    - 提供用户友好的错误提示
    - _Requirements: 2.4_

- [ ] 4. 检查点 - 验证修复效果
  - 测试录制后预览播放是否有声音
  - 测试 ffmpeg 未安装时的错误提示
  - 测试完整的录制 -> 预览 -> 上传流程

## 注意事项

- 修改 AudioConverterService 时要确保不破坏现有的下载音频播放功能
- 错误提示要清晰，包含解决方案（安装 ffmpeg 的命令）
- 保持 AAC 格式录制，只在上传时转换为 MP3

