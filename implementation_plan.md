# Implementation Plan

修复笔记切换时内容污染问题，确保HTML->XML->云端的保存流程正确执行。

## 概述
当前存在严重的数据污染问题：修改一篇笔记后立即切换到另一篇笔记，另一篇笔记的全部文本会变成刚刚修改的那篇笔记的内容。问题的根本原因在于状态管理混乱和WebEditorWrapper的内容绑定不正确。

## 问题分析

### 1. 根本问题
- **WebEditorWrapper绑定问题**：使用`Binding(get: { note.primaryXMLContent }, set: { _ in })`，setter为空，不会更新源数据
- **状态管理混乱**：`currentEditingNoteId`、`lastSavedXMLContent`、`currentXMLContent`等多个状态变量没有正确同步
- **笔记切换逻辑缺陷**：`saveCurrentNoteBeforeSwitching`函数可能没有等待保存完成就切换了笔记
- **内容污染**：编辑器的内容没有正确重置，导致新笔记显示旧笔记的内容

### 2. 现有保存流程
1. **Tier 0 (HTML缓存保存)**：`flashSaveHTML` - 立即保存HTML内容
2. **Tier 1 (本地XML保存)**：`saveToLocalOnlyWithContent` - 异步保存XML内容
3. **Tier 2 (云端同步)**：`scheduleCloudUpload` - 延迟3秒后同步

## 类型系统修改
无需修改类型系统，但需要优化状态管理。

## 文件修改

### 1. Sources/MiNoteLibrary/View/NoteDetailView.swift
**主要修改：**
- 修复WebEditorWrapper的内容绑定，使用正确的双向绑定
- 优化状态管理：确保`currentEditingNoteId`、`lastSavedXMLContent`、`currentXMLContent`正确同步
- 改进笔记切换逻辑：确保保存完成后再加载新笔记内容
- 添加内容污染防护机制

**具体修改点：**
1. 第149行：修改`WebEditorWrapper`的`content`绑定，使用`$currentXMLContent`而不是只读绑定
2. 优化`handleSelectedNoteChange`函数，确保状态正确重置
3. 改进`saveCurrentNoteBeforeSwitching`函数，添加等待机制
4. 在`loadNoteContent`函数中添加内容重置逻辑

### 2. Sources/MiNoteLibrary/View/WebEditorWrapper.swift
**次要修改：**
- 确保`onChange(of: content)`正确处理外部内容变化
- 优化编辑器内容加载逻辑

## 函数修改

### 新函数
无

### 修改函数
1. **`bodyEditorView`属性**：
   - 修改`WebEditorWrapper`的`content`参数绑定
   - 从`Binding(get: { note.primaryXMLContent }, set: { _ in })`改为使用`$currentXMLContent`

2. **`loadNoteContent`函数**：
   - 添加内容重置逻辑，确保编辑器加载正确的内容
   - 修复状态变量初始化顺序

3. **`saveCurrentNoteBeforeSwitching`函数**：
   - 添加异步等待机制，确保保存完成
   - 改进错误处理

4. **`handleSelectedNoteChange`函数**：
   - 优化状态管理，确保`currentEditingNoteId`正确更新
   - 添加内容污染检查

### 删除函数
无

## 类修改
无新类需要创建，现有类需要优化。

## 依赖关系
无需修改依赖关系。

## 实现顺序

### 步骤1：修复WebEditorWrapper绑定
1. 修改`bodyEditorView`中的`WebEditorWrapper`初始化
2. 将`content`参数从只读绑定改为使用`$currentXMLContent`
3. 确保`onContentChange`回调正确更新`currentXMLContent`

### 步骤2：优化状态管理
1. 在`loadNoteContent`函数中确保所有状态变量正确重置
2. 添加内容污染检查机制
3. 确保`currentEditingNoteId`与当前编辑的笔记ID一致

### 步骤3：改进笔记切换逻辑
1. 修改`saveCurrentNoteBeforeSwitching`函数，添加等待机制
2. 确保保存完成后再加载新笔记内容
3. 添加超时处理，避免无限等待

### 步骤4：添加内容污染防护
1. 在编辑器加载新内容前，强制清空编辑器内容
2. 添加验证机制，确保加载的内容与当前笔记ID匹配
3. 添加日志记录，便于调试

### 步骤5：测试验证
1. 构建应用并测试笔记切换功能
2. 验证内容污染问题是否解决
3. 测试保存流程是否正常工作

## 任务进度
- [ ] 步骤1：修复WebEditorWrapper绑定
- [ ] 步骤2：优化状态管理
- [ ] 步骤3：改进笔记切换逻辑
- [ ] 步骤4：添加内容污染防护
- [ ] 步骤5：测试验证

## 预期结果
1. 修改笔记A后切换到笔记B，笔记B显示自己的正确内容
2. 保存流程正常工作：HTML缓存、本地XML保存、云端同步
3. 无数据污染问题
4. 用户体验流畅，无闪烁或延迟
