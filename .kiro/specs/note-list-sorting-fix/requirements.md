# 需求文档

## 简介

修复笔记列表排序功能的两个问题：
1. 按创建时间排序时，笔记列表视图中显示的是最后修改时间，需要改为显示创建时间
2. 按编辑时间排序时，点击某些笔记会错误地移动到列表顶部，且选中状态（高亮）不正确

## 术语表

- **Notes_List_View**: 笔记列表视图，显示当前文件夹中的笔记列表
- **NoteRow**: 笔记列表中的单行视图，显示笔记标题、时间和预览
- **NoteCardView**: 画廊视图中的笔记卡片
- **ViewOptionsManager**: 视图选项管理器，管理排序方式等设置
- **NoteSortOrder**: 排序方式枚举（editDate/createDate/title）
- **selectedNote**: 当前选中的笔记

## 需求

### 需求 1：按创建时间排序时显示创建时间

**用户故事：** 作为用户，我希望在按创建时间排序时，笔记列表中显示的是创建时间而非修改时间，以便我能直观地看到笔记的创建日期。

#### 验收标准

1. WHEN 用户选择按创建时间排序 THEN Notes_List_View 中的 NoteRow SHALL 显示笔记的创建时间（createdAt）
2. WHEN 用户选择按编辑时间排序 THEN Notes_List_View 中的 NoteRow SHALL 显示笔记的修改时间（updatedAt）
3. WHEN 用户选择按标题排序 THEN Notes_List_View 中的 NoteRow SHALL 显示笔记的修改时间（updatedAt）
4. WHEN 排序方式变化 THEN NoteRow 中显示的时间 SHALL 立即更新为对应的时间字段
5. WHEN 用户在画廊视图中查看笔记 THEN NoteCardView SHALL 根据排序方式显示对应的时间字段

### 需求 2：修复笔记选择时的错误移动

**用户故事：** 作为用户，我希望点击笔记列表中的笔记时，笔记不会错误地移动位置，且选中状态能正确显示高亮。

#### 验收标准

1. WHEN 用户点击笔记列表中的笔记 THEN 该笔记 SHALL 保持在原位置不移动
2. WHEN 用户点击笔记列表中的笔记 THEN 该笔记 SHALL 正确显示选中高亮状态
3. WHEN 用户再次点击已选中的笔记 THEN 该笔记 SHALL 保持选中高亮状态
4. WHEN 笔记内容被编辑并保存 THEN 笔记在列表中的位置 SHALL 根据排序规则正确更新
5. IF 笔记的 updatedAt 时间戳未变化 THEN 笔记在列表中的位置 SHALL 保持不变

### 需求 3：日期分组与排序方式一致性

**用户故事：** 作为用户，我希望日期分组功能能与当前排序方式保持一致，按创建时间排序时按创建时间分组，按编辑时间排序时按编辑时间分组。

#### 验收标准

1. WHEN 用户选择按创建时间排序且启用日期分组 THEN 分组 SHALL 基于笔记的创建时间（createdAt）
2. WHEN 用户选择按编辑时间排序且启用日期分组 THEN 分组 SHALL 基于笔记的修改时间（updatedAt）
3. WHEN 排序方式变化 THEN 日期分组 SHALL 立即重新计算并更新显示
