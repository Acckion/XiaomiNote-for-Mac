# 图片渲染修复设计文档

## 概述

本设计文档详细说明如何修复原生编辑器的图片渲染问题。核心问题是图片文件名格式不匹配：XML 中的 `fileid` 是完整的 `{userId}.{fileId}` 格式，但当前的加载逻辑只尝试 `{fileId}.{format}` 格式。

## 架构

### 当前问题分析

1. **XML 格式**：`<img fileid="1315204657.9XhIhLRSK6iVoAq1L_lsMA" imgshow="0" imgdes="" />`
2. **当前加载逻辑**：只尝试 `9XhIhLRSK6iVoAq1L_lsMA.jpg`
3. **实际文件存储为**：`1315204657.9XhIhLRSK6iVoAq1L_lsMA.jpg`

### 解决方案

**统一使用 `images/{userId}.{fileId}.{format}` 格式**：
- XML 中的 `fileid="1315204657.9XhIhLRSK6iVoAq1L_lsMA"` 直接作为完整文件名
- 图片存储路径：`images/1315204657.9XhIhLRSK6iVoAq1L_lsMA.jpg`
- 移除所有回退机制，简化加载逻辑

## 组件和接口

### 1. LocalStorageService 简化

**新增方法**：
```swift
// 仅使用完整格式加载图片
func loadImageWithFullFormat(fullFileId: String, fileType: String) -> Data?

// 自动尝试所有图片格式
func loadImageWithFullFormatAllFormats(fullFileId: String) -> (data: Data, fileType: String)?
```

**移除的方法**：
- `parseFileId()` - 不再需要解析
- `loadImageSmart()` - 不再需要智能加载
- `loadImageFromSpecialDirectory()` - 不再支持特殊目录

### 2. ImageAttachment 简化

**修改的方法**：
```swift
private func loadImageFromLocalStorage(fileId: String, folderId: String) {
    // 仅使用 localStorage.loadImageWithFullFormatAllFormats(fullFileId: fileId)
    // 移除所有回退逻辑
}
```

### 3. ImageStorageManager 简化

**修改的方法**：
```swift
func loadImage(fileId: String) -> NSImage? {
    // 仅使用 localStorage.loadImageWithFullFormatAllFormats(fullFileId: fileId)
    // 移除所有回退逻辑
}
```

## 数据模型

### 图片存储格式

**唯一格式**：`images/{userId}.{fileId}.{extension}`
- 例如：`images/1315204657.9XhIhLRSK6iVoAq1L_lsMA.jpg`

**不再支持的格式**：
- ~~纯 fileId 格式~~：`images/{fileId}.{extension}`
- ~~特殊目录格式~~：`images/图片/{fileId}.{extension}`
- ~~旧格式回退~~：`images/{folderId}/{fileId}.jpg`

### 加载逻辑

```swift
// 简化的加载流程
func loadImage(fullFileId: String) -> Data? {
    // 1. 尝试 images/{fullFileId}.jpg
    // 2. 尝试 images/{fullFileId}.jpeg
    // 3. 尝试 images/{fullFileId}.png
    // 4. 尝试 images/{fullFileId}.gif
    // 5. 如果都失败，返回 nil
}
```

## 错误处理

### 加载失败处理

1. **记录详细日志**：记录尝试的完整路径
2. **显示占位符**：加载失败时显示友好的占位符
3. **明确错误信息**：只尝试一种格式，错误信息更清晰

### 调试支持

```swift
struct ImageLoadingDebugInfo {
    let fullFileId: String
    let attemptedPath: String  // 只有一个路径
    let success: Bool
    let fileType: String?
    let loadingTime: TimeInterval
}
```

## 测试策略

### 单元测试

1. **完整格式加载测试**
   - 测试 `{userId}.{fileId}.{extension}` 格式的加载
   - 测试各种图片格式（jpg, png, gif）

2. **错误处理测试**
   - 测试文件不存在的情况
   - 测试无效文件格式的情况

### 集成测试

1. **端到端图片显示测试**
   - 从 XML 解析到图片显示的完整流程
   - 使用真实的小米笔记数据测试

### 属性测试

**Property 1: 完整格式加载一致性**
*对于任何* 有效的完整 fileId（格式为 `{userId}.{fileId}`）和存在的图片文件，系统应该能够正确加载
**验证：需求 1.1, 1.2**

**Property 2: 错误处理完整性**
*对于任何* 不存在的 fileId，系统应该返回 nil 并记录详细的错误信息
**验证：需求 4.2, 4.3**

**Property 3: 缓存一致性**
*对于任何* 成功加载的图片，后续的加载请求应该使用缓存，不重复文件系统访问
**验证：需求 5.4**