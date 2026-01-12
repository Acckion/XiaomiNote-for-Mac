# Requirements Document

## Introduction

本功能旨在解决 MiNoteMac 应用中侧边栏（文件夹）、笔记列表视图和编辑器之间的状态同步问题。当前存在三个主要问题：

1. 更新笔记内容时，笔记可能会重新加载，导致笔记列表视图的选择丢失
2. 更新笔记内容时，笔记修改时间刷新，导致笔记列表视图闪动，缺少平滑的动画过渡
3. 侧边栏、笔记列表视图、编辑器三者之间缺乏层级关系的同步机制

## Glossary

- **Sidebar**：侧边栏视图，显示文件夹列表，用户通过选择文件夹来筛选笔记
- **Notes_List_View**：笔记列表视图，显示当前文件夹下的笔记列表
- **Editor**：编辑器视图，显示和编辑当前选中笔记的内容
- **NotesViewModel**：笔记视图模型，管理应用的主要业务逻辑和状态
- **Selection_State**：选择状态，包括当前选中的文件夹和笔记
- **View_Hierarchy**：视图层级关系，指侧边栏→笔记列表→编辑器的层级对应关系
- **State_Coordinator**：状态协调器，负责协调三个视图之间的状态同步

## Requirements

### Requirement 1: 笔记内容更新时保持选择状态

**User Story:** 作为用户，我希望在编辑笔记内容时，笔记列表中的选择状态保持不变，这样我可以专注于编辑而不会被意外的选择变化打断。

#### Acceptance Criteria

1. WHEN 用户在 Editor 中编辑笔记内容 THEN Notes_List_View SHALL 保持当前笔记的选中状态不变
2. WHEN 笔记内容保存触发 notes 数组更新 THEN Notes_List_View SHALL 不重置 selectedNote 的值
3. WHEN 笔记的 updatedAt 时间戳变化 THEN Notes_List_View SHALL 保持当前选中笔记的高亮状态
4. IF 笔记内容更新导致视图重建 THEN Notes_List_View SHALL 在重建后恢复之前的选择状态

### Requirement 2: 笔记列表移动动画

**User Story:** 作为用户，我希望当笔记因修改时间变化而在列表中移动位置时，能看到平滑的动画效果，这样我可以清楚地知道笔记移动到了哪里。

#### Acceptance Criteria

1. WHEN 笔记的 updatedAt 时间戳变化导致排序位置改变 THEN Notes_List_View SHALL 使用动画将笔记移动到新位置
2. WHEN 笔记从一个时间分组移动到另一个分组 THEN Notes_List_View SHALL 使用淡入淡出动画显示分组变化
3. WHEN 多个笔记同时更新位置 THEN Notes_List_View SHALL 批量处理动画以避免视觉混乱
4. THE Notes_List_View SHALL 使用 300ms 的动画持续时间进行列表项移动

### Requirement 3: 视图层级状态同步

**User Story:** 作为用户，我希望侧边栏、笔记列表和编辑器始终保持层级对应关系，这样当我切换文件夹时，笔记列表和编辑器会自动更新为对应文件夹的内容。

#### Acceptance Criteria

1. WHEN 用户在 Sidebar 中选择一个新文件夹 THEN Notes_List_View SHALL 立即显示该文件夹下的笔记列表
2. WHEN 用户在 Sidebar 中选择一个新文件夹 THEN Editor SHALL 清空当前内容或显示该文件夹的第一篇笔记
3. WHEN 用户在 Sidebar 中选择一个新文件夹 THEN Notes_List_View SHALL 清除之前的笔记选择状态
4. WHEN Editor 显示的笔记不属于当前选中文件夹 THEN State_Coordinator SHALL 自动同步三者状态
5. WHILE 用户在 Editor 中编辑笔记 WHEN 用户切换到另一个文件夹 THEN State_Coordinator SHALL 先保存当前编辑内容再切换

### Requirement 4: 状态协调器

**User Story:** 作为开发者，我需要一个状态协调器来统一管理三个视图之间的状态同步，这样可以避免状态不一致的问题。

#### Acceptance Criteria

1. THE State_Coordinator SHALL 作为单一数据源管理 selectedFolder 和 selectedNote 的状态
2. WHEN selectedFolder 变化 THEN State_Coordinator SHALL 按顺序更新 Notes_List_View 和 Editor
3. WHEN selectedNote 变化 THEN State_Coordinator SHALL 验证该笔记是否属于当前 selectedFolder
4. IF selectedNote 不属于当前 selectedFolder THEN State_Coordinator SHALL 自动更新 selectedFolder 或清除 selectedNote
5. THE State_Coordinator SHALL 提供状态变化的日志记录以便调试

### Requirement 5: 防止不必要的视图重建

**User Story:** 作为用户，我希望应用在更新笔记时不会出现闪烁或卡顿，这样可以获得流畅的使用体验。

#### Acceptance Criteria

1. WHEN 笔记内容更新 THEN NotesViewModel SHALL 仅更新 notes 数组中对应笔记的属性而非替换整个数组
2. WHEN Notes_List_View 接收到 notes 数组更新 THEN Notes_List_View SHALL 使用 id 标识符进行差异更新
3. THE Notes_List_View SHALL 使用 Equatable 协议比较笔记对象以避免不必要的重绘
4. WHEN 笔记的非显示属性（如 rawData）变化 THEN Notes_List_View SHALL 不触发行视图重建

### Requirement 6: 文件夹切换时的编辑器状态处理

**User Story:** 作为用户，我希望在切换文件夹时，如果当前笔记有未保存的更改，系统能够自动保存，这样我不会丢失编辑内容。

#### Acceptance Criteria

1. WHEN 用户切换文件夹且 Editor 有未保存内容 THEN State_Coordinator SHALL 先触发保存操作
2. WHEN 保存操作完成 THEN State_Coordinator SHALL 继续执行文件夹切换
3. IF 保存操作失败 THEN State_Coordinator SHALL 显示错误提示并询问用户是否继续切换
4. WHEN 切换到新文件夹 THEN Editor SHALL 清空内容或加载新文件夹的第一篇笔记
