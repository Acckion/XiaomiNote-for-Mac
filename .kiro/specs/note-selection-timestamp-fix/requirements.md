# 需求文档

## 简介

修复笔记选择时错误更新时间戳的问题。当用户点击笔记列表中的笔记时，即使没有修改笔记内容，笔记的 `updatedAt` 时间戳也会被更新为当前时间，导致笔记在按编辑时间排序时错误地跳到列表顶部。

## 术语表

- **selectedNote**: 当前选中的笔记
- **updatedAt**: 笔记的最后修改时间戳
- **lastSavedXMLContent**: 上次保存的 XML 内容
- **buildUpdatedNote**: 构建更新笔记对象的方法
- **saveCurrentNoteBeforeSwitching**: 切换笔记前保存当前笔记的方法
- **ensureNoteHasFullContent**: 确保笔记有完整内容的方法

## 需求

### 需求 1：修复笔记选择时的时间戳更新问题

**用户故事：** 作为用户，我希望点击查看笔记时，如果没有修改笔记内容，笔记的编辑时间不会被更新，这样笔记在列表中的位置保持不变。

#### 验收标准

1. WHEN 用户点击笔记列表中的笔记且笔记内容未发生变化 THEN 笔记的 updatedAt 时间戳 SHALL 保持不变
2. WHEN 用户点击笔记列表中的笔记且笔记内容未发生变化 THEN 笔记在按编辑时间排序的列表中的位置 SHALL 保持不变
3. WHEN 用户实际修改笔记内容并保存 THEN 笔记的 updatedAt 时间戳 SHALL 更新为当前时间
4. WHEN ensureNoteHasFullContent 方法获取完整内容但内容实际未变化 THEN 笔记的 updatedAt 时间戳 SHALL 保持不变
5. WHEN buildUpdatedNote 方法被调用但内容实际未变化 THEN 应该使用原始的 updatedAt 时间戳而非当前时间

### 需求 2：改进内容变化检测逻辑

**用户故事：** 作为开发者，我希望内容变化检测逻辑更加准确，能够正确识别内容是否真正发生了变化。

#### 验收标准

1. WHEN 比较笔记内容变化时 THEN 系统 SHALL 使用标准化的内容比较方法
2. WHEN ensureNoteHasFullContent 更新内容后 THEN 系统 SHALL 正确更新 lastSavedXMLContent 以反映最新状态
3. WHEN 笔记从服务器获取完整内容时 THEN 系统 SHALL 区分内容获取和内容修改操作
4. WHEN 检测到内容确实发生变化时 THEN 系统 SHALL 更新时间戳
5. WHEN 检测到内容未发生变化时 THEN 系统 SHALL 保持原始时间戳

### 需求 3：优化笔记切换时的保存逻辑

**用户故事：** 作为用户，我希望在笔记之间快速切换时，系统能够智能地判断是否需要保存，避免不必要的时间戳更新。

#### 验收标准

1. WHEN 用户从笔记A切换到笔记B且笔记A内容未变化 THEN 系统 SHALL 跳过保存操作
2. WHEN 用户从笔记A切换到笔记B且笔记A内容已变化 THEN 系统 SHALL 执行保存操作并更新时间戳
3. WHEN 保存操作被跳过时 THEN 系统 SHALL 记录相应的日志信息
4. WHEN 执行保存操作时 THEN 系统 SHALL 使用准确的内容变化检测结果
5. WHEN 笔记切换过程中发生错误 THEN 系统 SHALL 保持数据一致性不破坏时间戳
