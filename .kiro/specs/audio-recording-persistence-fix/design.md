# 录音模板持久化修复设计文档

## 概述

本设计文档描述了如何修复录音模板持久化问题。核心思路是使用小米笔记的XML格式，通过临时占位符和最终更新的方式来确保录音内容能正确保存到数据库并在笔记切换后保持可见。

## 架构

### 当前问题分析

1. **录音模板更新正常**：`updateRecordingTemplate` 方法能正确替换DOM中的模板
2. **内容通知正常**：`notifyContentChanged` 方法被正确调用
3. **持久化缺失**：内容变化没有可靠地保存到数据库

### 解决方案架构

```
录音开始 -> 插入XML占位符 -> 录音完成 -> 更新XML内容 -> 强制保存 -> 验证持久化
    |           |              |           |            |          |
    v           v              v           v            v          v
临时模板ID   <sound fileid=   上传完成    去掉des属性   立即保存   切换验证
           "tempid" des=                 更新fileid    到数据库
           "temp"/>
```

## 组件和接口

### 1. XML占位符格式

**临时占位符**（录音开始时插入）：
```xml
<sound fileid="temp_[UUID]" des="temp"/>
```

**最终音频元素**（录音完成后更新）：
```xml
<sound fileid="[实际文件ID]"/>
```

### 2. 核心组件修改

#### WebEditorContext 扩展
```swift
class WebEditorContext {
    // 新增：强制保存并验证
    func updateRecordingTemplateAndSave(templateId: String, fileId: String, digest: String?, mimeType: String?) async throws
    
    // 新增：验证内容持久化
    func verifyContentPersistence(expectedContent: String) async -> Bool
}
```

#### NativeEditorContext 扩展
```swift
class NativeEditorContext {
    // 新增：插入XML格式的录音模板
    func insertRecordingTemplate(templateId: String)
    
    // 新增：更新录音模板为音频附件
    func updateRecordingTemplate(templateId: String, fileId: String, digest: String?, mimeType: String?)
    
    // 新增：强制保存并验证
    func updateRecordingTemplateAndSave(templateId: String, fileId: String, digest: String?, mimeType: String?) async throws
    
    // 新增：验证内容持久化
    func verifyContentPersistence(expectedContent: String) async -> Bool
}
```

#### FormatManager 增强
```javascript
const FormatManager = {
    // 修改：插入XML格式的临时占位符
    insertRecordingTemplate: function(templateId) {
        // 插入 <sound fileid="temp_[templateId]" des="temp"/>
    },
    
    // 修改：更新为最终XML格式
    updateRecordingTemplate: function(templateId, fileId, digest, mimeType) {
        // 更新为 <sound fileid="[fileId]"/>
        // 立即触发强制保存
    }
}
```

#### MainWindowController 增强
```swift
class MainWindowController {
    // 修改：录音完成处理，增加强制保存和验证
    private func handleAudioRecordingComplete(url: URL) async {
        // 1. 上传音频
        // 2. 根据当前编辑器类型更新XML内容
        //    - Web编辑器：调用 webEditorContext.updateRecordingTemplateAndSave
        //    - 原生编辑器：调用 nativeEditorContext.updateRecordingTemplateAndSave
        // 3. 强制保存到数据库
        // 4. 验证持久化成功
        // 5. 更新内存缓存
    }
    
    // 新增：统一的录音模板插入接口
    private func insertRecordingTemplate(templateId: String) {
        if isUsingNativeEditor {
            nativeEditorContext.insertRecordingTemplate(templateId: templateId)
        } else {
            webEditorContext.insertRecordingTemplate(templateId: templateId)
        }
    }
}
```

## 数据模型

### 录音模板状态
```swift
enum RecordingTemplateState {
    case inserting(templateId: String)
    case recording(templateId: String)
    case uploading(templateId: String, tempFileURL: URL)
    case updating(templateId: String, fileId: String)
    case completed(fileId: String)
    case failed(error: Error)
}
```

### 内容持久化验证
```swift
struct ContentPersistenceVerification {
    let noteId: String
    let expectedContent: String
    let actualContent: String
    let isValid: Bool
    let timestamp: Date
}
```

## 正确性属性

*属性是一个特征或行为，应该在系统的所有有效执行中保持为真。属性作为人类可读规范和机器可验证正确性保证之间的桥梁。*

### 属性 1：录音完成后立即保存
*对于任何* 录音完成事件，当模板更新为音频附件时，系统应该立即触发数据库保存操作，并且保存后的XML内容应该包含实际的音频元素而不是临时模板
**验证：需求 1.1, 1.2**

### 属性 2：内容持久化往返一致性
*对于任何* 包含音频附件的笔记，执行"录音->保存->切换笔记->切换回来"的操作序列后，加载的内容应该与保存前的内容一致
**验证：需求 1.3**

### 属性 3：模板更新触发保存
*对于任何* updateRecordingTemplate 方法调用，系统应该确保后续的数据库保存操作被正确执行，并且笔记的修改状态被正确标记
**验证：需求 2.1, 1.5**

### 属性 4：内容变化检测准确性
*对于任何* notifyContentChanged 触发，当且仅当内容确实发生变化时，系统才应该执行保存操作
**验证：需求 2.2**

### 属性 5：缓存一致性维护
*对于任何* 数据库保存操作完成后，内存缓存中的笔记内容应该与数据库中的内容保持一致，并且未保存内容标志应该被清除
**验证：需求 2.3, 2.4**

### 属性 6：错误处理状态保持
*对于任何* 模板更新失败的情况，系统应该记录错误信息并保持原有状态不变
**验证：需求 2.5**

### 属性 7：内容加载验证
*对于任何* 笔记切换加载操作，系统应该验证加载的内容是否包含预期的音频附件
**验证：需求 3.4**

### 属性 8：编辑器类型无关性
*对于任何* 编辑器类型（Web编辑器或原生编辑器），录音模板的插入、更新和持久化流程应该产生相同的最终结果
**验证：需求 4.1, 4.2, 4.3**

## 错误处理

### 1. 上传失败处理
- 保留临时占位符
- 显示错误提示
- 允许重试上传

### 2. 保存失败处理
- 记录详细错误日志
- 保持编辑器状态
- 标记为未保存状态

### 3. 验证失败处理
- 记录验证失败信息
- 触发重新保存
- 通知用户潜在问题

## 测试策略

### 单元测试
- 测试XML占位符的正确生成和更新
- 测试保存操作的触发时机
- 测试错误处理逻辑

### 属性测试
- 使用随机生成的录音场景验证持久化一致性
- 测试各种异常情况下的状态保持
- 验证内容变化检测的准确性

**属性测试配置**：
- 最少100次迭代验证每个属性
- 每个属性测试必须引用其设计文档属性
- 标签格式：**Feature: audio-recording-persistence-fix, Property {number}: {property_text}**

### 集成测试
- 端到端录音流程测试
- 笔记切换场景测试
- 多用户并发录音测试