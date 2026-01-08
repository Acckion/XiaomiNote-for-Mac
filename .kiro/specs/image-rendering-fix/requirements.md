# 图片渲染修复需求文档

## 简介

本文档定义了修复原生编辑器图片渲染问题的需求。当前问题是原生编辑器无法正确加载和显示小米笔记 XML 格式中的图片，主要原因是图片文件名格式不匹配和加载逻辑不完整。

## 术语表

- **Native_Editor**: 基于 SwiftUI TextEditor、NSTextView 和自定义渲染的原生编辑器
- **Web_Editor**: 当前基于 WKWebView 的 Web 编辑器（参考实现）
- **XiaoMi_XML**: 小米笔记使用的 XML 格式，图片使用 `<img fileid="..." />` 标签
- **FileId_Format**: 图片文件 ID 格式，包含 `{userId}.{fileId}` 的完整格式
- **Image_Storage**: 本地图片存储系统，支持多种文件名格式
- **ImageAttachment**: 用于在原生编辑器中显示图片的自定义附件类
- **LocalStorageService**: 负责本地文件存储和加载的服务类

## 需求

### 需求 1：图片文件名格式统一

**用户故事：** 作为用户，我希望原生编辑器能够正确加载使用统一格式存储的图片文件。

#### 验收标准

1. WHEN XML 包含 `fileid="1315204657.9XhIhLRSK6iVoAq1L_lsMA"` THEN THE Native_Editor SHALL 使用完整的 fileId 作为文件名加载图片
2. WHEN 图片存储为 `images/{userId}.{fileId}.{extension}` 格式 THEN THE Image_Storage SHALL 能够找到并加载图片
3. WHEN 图片文件不存在 THEN THE Image_Storage SHALL 返回 nil 并记录错误信息
4. WHEN 系统尝试加载图片 THEN THE Image_Storage SHALL 仅尝试 `images/{fullFileId}.{format}` 格式
5. WHEN 加载图片成功 THEN THE System SHALL 缓存图片以提高后续访问性能

### 需求 2：图片加载逻辑简化

**用户故事：** 作为用户，我希望图片加载过程是简单和可预测的，使用统一的文件路径格式。

#### 验收标准

1. WHEN ImageAttachment 开始加载图片 THEN THE System SHALL 仅尝试 `images/{fullFileId}.{format}` 格式
2. WHEN 第一种图片格式加载失败 THEN THE System SHALL 尝试其他图片格式（jpg, png, gif）
3. WHEN 所有图片格式都加载失败 THEN THE System SHALL 显示占位符图片并记录错误日志
4. WHEN 图片加载成功 THEN THE System SHALL 缓存图片并记录成功信息
5. WHEN 图片文件不存在 THEN THE System SHALL 提供清晰的错误信息，不尝试其他路径

### 需求 3：Web 编辑器兼容性参考

**用户故事：** 作为开发者，我希望原生编辑器的图片加载逻辑与 Web 编辑器保持一致，确保相同的图片在两个编辑器中都能正常显示。

#### 验收标准

1. WHEN Web_Editor 能够显示图片 THEN THE Native_Editor SHALL 也能显示相同的图片
2. WHEN Web_Editor 使用特定的文件路径格式 THEN THE Native_Editor SHALL 支持相同的路径格式
3. WHEN Web_Editor 有回退加载机制 THEN THE Native_Editor SHALL 实现相同的回退机制
4. WHEN 图片 URL 格式为 `minote://image/{fileId}` THEN THE Native_Editor SHALL 正确解析并加载图片
5. WHEN 图片加载失败 THEN THE Native_Editor SHALL 提供与 Web_Editor 相同的用户体验

### 需求 4：错误处理和调试支持

**用户故事：** 作为开发者，我希望能够快速诊断和解决图片加载问题，通过详细的日志和错误信息。

#### 验收标准

1. WHEN 图片加载开始 THEN THE System SHALL 记录尝试的文件路径和格式
2. WHEN 图片加载失败 THEN THE System SHALL 记录失败原因和尝试的所有路径
3. WHEN 图片加载成功 THEN THE System SHALL 记录成功的路径和文件信息
4. WHEN 用户报告图片问题 THEN THE System SHALL 提供完整的加载过程日志
5. WHEN 开发者需要调试 THEN THE System SHALL 提供图片存储状态的详细信息

### 需求 5：性能和用户体验

**用户故事：** 作为用户，我希望图片加载过程是快速和流畅的，不会影响编辑器的整体性能。

#### 验收标准

1. WHEN 图片正在加载 THEN THE System SHALL 显示加载指示器而不是空白区域
2. WHEN 图片加载完成 THEN THE System SHALL 平滑地替换占位符，不产生布局跳动
3. WHEN 多个图片同时加载 THEN THE System SHALL 合理控制并发数量，避免性能问题
4. WHEN 图片已经缓存 THEN THE System SHALL 立即显示缓存的图片，不重复加载
5. WHEN 图片文件较大 THEN THE System SHALL 在后台异步加载，不阻塞 UI 线程

### 需求 6：图片存储路径统一

**用户故事：** 作为系统架构师，我希望图片存储路径格式是统一和可预测的，便于维护和扩展。

#### 验收标准

1. WHEN 新图片保存 THEN THE System SHALL 使用统一的 `images/{userId}.{fileId}.{extension}` 格式
2. WHEN 加载图片 THEN THE System SHALL 仅尝试 `images/{userId}.{fileId}.{extension}` 格式
3. WHEN 图片路径不存在 THEN THE System SHALL 明确报告错误，不尝试其他路径格式
4. WHEN 文件夹 ID 变化 THEN THE System SHALL 不影响图片的加载（因为不再依赖 folderId）
5. WHEN 清理无效图片 THEN THE System SHALL 能够识别和清理统一格式的无效图片文件

### 需求 7：向后兼容性

**用户故事：** 作为用户，我希望升级后仍然能够查看所有历史图片，无论它们是以何种格式存储的。

#### 验收标准

1. WHEN 用户升级应用 THEN THE System SHALL 继续支持所有历史图片格式
2. WHEN 历史图片使用旧的存储格式 THEN THE System SHALL 能够正确加载和显示
3. WHEN 同步旧笔记 THEN THE System SHALL 正确处理旧格式的图片引用
4. WHEN 用户在不同设备间同步 THEN THE System SHALL 确保图片在所有设备上都能正常显示
5. WHEN 回退到旧版本 THEN THE System SHALL 不破坏图片文件的兼容性