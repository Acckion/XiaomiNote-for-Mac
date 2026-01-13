# 设计文档

## 概述

本设计文档描述了修复笔记选择时错误更新时间戳问题的技术方案。问题的根本原因是在笔记切换过程中，即使内容没有实际变化，`buildUpdatedNote` 方法也会将 `updatedAt` 设置为当前时间，导致笔记在排序列表中错误移动。

## 架构

### 问题根因分析

当前的笔记选择和保存流程如下：

```
用户点击笔记
    ↓
handleSelectedNoteChange
    ↓
saveCurrentNoteBeforeSwitching
    ↓
内容变化检测 (可能失效)
    ↓
buildUpdatedNote (总是设置 updatedAt: Date())
    ↓
笔记时间戳被更新
    ↓
笔记在排序列表中移动
```

**问题点**：
1. `buildUpdatedNote` 方法总是设置 `updatedAt: Date()`，不考虑内容是否真正变化
2. 内容变化检测可能因为 `ensureNoteHasFullContent` 的副作用而失效
3. `lastSavedXMLContent` 可能与实际保存的内容不同步

### 解决方案架构

```
用户点击笔记
    ↓
handleSelectedNoteChange
    ↓
saveCurrentNoteBeforeSwitching
    ↓
改进的内容变化检测
    ↓
条件性的 buildUpdatedNote (保持原始时间戳或更新时间戳)
    ↓
正确的时间戳处理
    ↓
笔记位置保持稳定
```

## 组件和接口

### 修改 1：改进 buildUpdatedNote 方法

在 `NoteDetailView` 中修改 `buildUpdatedNote` 方法，添加一个参数来控制是否更新时间戳：

```swift
private func buildUpdatedNote(from note: Note, xmlContent: String, shouldUpdateTimestamp: Bool = true) -> Note {
    let titleToUse: String
    if note.id == currentEditingNoteId {
        titleToUse = editedTitle
    } else {
        titleToUse = note.title
    }
    
    // 合并 rawData
    var mergedRawData = note.rawData ?? [:]
    if let latestNote = viewModel.selectedNote, latestNote.id == note.id {
        if let latestRawData = latestNote.rawData {
            if let latestSetting = latestRawData["setting"] as? [String: Any] {
                mergedRawData["setting"] = latestSetting
            }
        }
    }
    
    // 根据参数决定是否更新时间戳
    let updatedAt = shouldUpdateTimestamp ? Date() : note.updatedAt
    
    return Note(
        id: note.id, 
        title: titleToUse, 
        content: xmlContent, 
        folderId: note.folderId, 
        isStarred: note.isStarred, 
        createdAt: note.createdAt, 
        updatedAt: updatedAt, 
        tags: note.tags, 
        rawData: mergedRawData
    )
}
```

### 修改 2：改进内容变化检测

创建一个专门的内容比较方法：

```swift
private func hasContentActuallyChanged(currentContent: String, savedContent: String, currentTitle: String, originalTitle: String) -> Bool {
    // 标准化内容比较（去除空白字符差异）
    let normalizedCurrent = currentContent.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedSaved = savedContent.trimmingCharacters(in: .whitespacesAndNewlines)
    
    let contentChanged = normalizedCurrent != normalizedSaved
    let titleChanged = currentTitle != originalTitle
    
    Swift.print("[内容检测] 内容变化: \(contentChanged), 标题变化: \(titleChanged)")
    Swift.print("[内容检测] 当前内容长度: \(normalizedCurrent.count), 保存内容长度: \(normalizedSaved.count)")
    
    return contentChanged || titleChanged
}
```

### 修改 3：更新 saveCurrentNoteBeforeSwitching 方法

修改保存逻辑，使用改进的内容检测和条件性时间戳更新：

```swift
private func saveCurrentNoteBeforeSwitching(newNoteId: String) -> Task<Void, Never>? {
    // ... 现有的前置检查逻辑 ...
    
    Task { @MainActor in
        defer { isSavingBeforeSwitch = false }
        
        // 获取内容
        var content: String = capturedContent
        // ... 现有的内容获取逻辑 ...
        
        // 使用改进的内容变化检测
        let hasActualChange = hasContentActuallyChanged(
            currentContent: content,
            savedContent: capturedLastSavedXMLContent,
            currentTitle: capturedTitle,
            originalTitle: capturedOriginalTitle
        )
        
        if hasActualChange {
            Swift.print("[笔记切换] 💾 检测到实际变化，执行保存")
            
            // 构建更新的笔记对象，更新时间戳
            let updated = buildUpdatedNote(from: currentNote, xmlContent: content, shouldUpdateTimestamp: true)
            
            // ... 现有的保存逻辑 ...
        } else {
            Swift.print("[笔记切换] ⏭️ 内容无实际变化，跳过保存")
        }
    }
    
    return nil
}
```

### 修改 4：修复 ensureNoteHasFullContent 的副作用

在 `NotesViewModel` 中修改 `ensureNoteHasFullContent` 方法，确保它不会意外更新时间戳：

```swift
func ensureNoteHasFullContent(_ note: Note) async {
    // ... 现有的前置检查 ...
    
    do {
        let noteDetails = try await service.fetchNoteDetails(noteId: note.id)
        
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            var updatedNote = notes[index]
            let originalUpdatedAt = updatedNote.updatedAt
            
            updatedNote.updateContent(from: noteDetails)
            
            // 检查内容是否真正变化
            let contentActuallyChanged = updatedNote.content != note.content
            
            // 如果内容没有实际变化，恢复原始时间戳
            if !contentActuallyChanged {
                updatedNote.updatedAt = originalUpdatedAt
                Swift.print("[VIEWMODEL] ensureNoteHasFullContent: 内容无变化，保持原始时间戳")
            }
            
            // ... 现有的保存和更新逻辑 ...
        }
    } catch {
        // ... 现有的错误处理 ...
    }
}
```

### 修改 5：同步 lastSavedXMLContent

确保在内容更新后正确同步 `lastSavedXMLContent`：

```swift
// 在 loadNoteContent 方法中
private func loadNoteContent(_ note: Note) async {
    // ... 现有逻辑 ...
    
    // 3. 如果内容为空，确保获取完整内容
    if note.content.isEmpty {
        await viewModel.ensureNoteHasFullContent(note)
        
        if let updated = viewModel.selectedNote, updated.id == note.id {
            currentXMLContent = updated.primaryXMLContent
            // 关键修复：同步 lastSavedXMLContent
            lastSavedXMLContent = currentXMLContent
            
            await MemoryCacheManager.shared.cacheNote(updated)
        }
    } else {
        // 关键修复：确保 lastSavedXMLContent 与实际内容同步
        lastSavedXMLContent = currentXMLContent
        await MemoryCacheManager.shared.cacheNote(note)
    }
    
    // ... 现有逻辑 ...
}
```

## 数据模型

无需修改数据模型。现有的 `Note` 模型已包含所需的字段。

## 正确性属性

*正确性属性是系统在所有有效执行中应保持为真的特征或行为——本质上是关于系统应该做什么的形式化陈述。*

### Property 1：时间戳保持不变性

*对于任意*笔记选择操作，如果笔记内容和标题都没有实际变化，则笔记的 `updatedAt` 时间戳应保持不变。

**验证: 需求 1.1, 1.2**

### Property 2：内容变化检测准确性

*对于任意*两个笔记内容字符串，内容变化检测方法应准确识别它们是否真正不同（忽略空白字符差异）。

**验证: 需求 2.1, 2.2**

### Property 3：时间戳更新一致性

*对于任意*笔记保存操作，当且仅当内容或标题发生实际变化时，`updatedAt` 时间戳才应被更新。

**验证: 需求 1.3, 2.4**

### Property 4：排序位置稳定性

*对于任意*按编辑时间排序的笔记列表，如果笔记的 `updatedAt` 时间戳未变化，则笔记在列表中的相对位置应保持不变。

**验证: 需求 1.2, 3.1**

## 错误处理

1. **内容获取失败**：如果 `ensureNoteHasFullContent` 失败，保持原始时间戳不变
2. **保存失败**：如果保存操作失败，不更新内存中的时间戳
3. **内容比较异常**：如果内容比较过程中出现异常，采用保守策略（假设有变化）

## 测试策略

### 单元测试

1. 测试 `hasContentActuallyChanged` 方法的各种输入组合
2. 测试 `buildUpdatedNote` 方法的时间戳控制逻辑
3. 测试 `ensureNoteHasFullContent` 的时间戳保持逻辑

### 集成测试

1. 测试笔记选择时的完整流程
2. 测试笔记切换时的保存逻辑
3. 测试排序列表中笔记位置的稳定性

### 手动测试

1. 在按编辑时间排序的列表中点击旧笔记，验证位置不变
2. 修改笔记内容后验证时间戳正确更新
3. 快速切换多个笔记验证性能和稳定性