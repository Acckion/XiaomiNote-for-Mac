# 需求文档

## 简介

笔记列表视图功能扩展，新增一个工具栏按钮，提供排序方式选择、按日期分组开关、以及类似 Apple Notes 的画廊视图功能。画廊视图将笔记以卡片网格形式展示，点击笔记后展开到全屏编辑模式。

## 术语表

- **Notes_List_View**: 笔记列表视图组件，显示当前文件夹下的笔记列表
- **Gallery_View**: 画廊视图，以卡片网格形式展示笔记预览
- **List_View**: 列表视图，传统的垂直列表形式展示笔记
- **View_Options_Menu**: 视图选项菜单，包含排序、分组和视图切换选项
- **Sort_Order**: 排序方式，包括编辑时间、创建时间、标题
- **Sort_Direction**: 排序方向，升序或降序
- **Date_Grouping**: 按日期分组功能，将笔记按时间段分组显示
- **Note_Card**: 笔记卡片，画廊视图中的单个笔记预览组件
- **Expanded_View**: 展开视图，从画廊视图点击笔记后的全屏编辑模式

## 需求

### 需求 1：视图选项工具栏按钮

**用户故事：** 作为用户，我想要一个工具栏按钮来访问视图选项，以便我可以自定义笔记列表的显示方式。

#### 验收标准

1. THE Toolbar SHALL display a view options button with an appropriate icon (e.g., "list.bullet" or "square.grid.2x2")
2. WHEN the user clicks the view options button, THE System SHALL display a dropdown menu with all view options
3. THE View_Options_Menu SHALL be positioned below the toolbar button when displayed
4. WHEN the user clicks outside the menu, THE System SHALL dismiss the View_Options_Menu

### 需求 2：排序方式选择

**用户故事：** 作为用户，我想要选择笔记的排序方式，以便我可以按照自己的偏好组织笔记。

#### 验收标准

1. THE View_Options_Menu SHALL display sort options section with label "排序方式"
2. THE Sort_Order options SHALL include: 编辑时间、创建时间、标题
3. WHEN the user selects a Sort_Order, THE Notes_List_View SHALL immediately re-sort notes according to the selected order
4. THE View_Options_Menu SHALL display a visual indicator (checkmark) next to the currently selected Sort_Order
5. THE View_Options_Menu SHALL display a separator line after the sort options
6. THE View_Options_Menu SHALL display sort direction options: 升序、降序
7. WHEN the user selects a Sort_Direction, THE Notes_List_View SHALL immediately re-sort notes according to the selected direction
8. THE View_Options_Menu SHALL display a visual indicator (checkmark) next to the currently selected Sort_Direction
9. THE System SHALL persist the selected Sort_Order and Sort_Direction across app restarts

### 需求 3：按日期分组开关

**用户故事：** 作为用户，我想要开启或关闭按日期分组功能，以便我可以选择是否将笔记按时间段分组显示。

#### 验收标准

1. THE View_Options_Menu SHALL display a separator line before the date grouping option
2. THE View_Options_Menu SHALL display a "按日期分组" toggle option
3. WHEN Date_Grouping is enabled, THE Notes_List_View SHALL group notes by date sections (置顶、今天、昨天、本周、本月、本年、历史年份)
4. WHEN Date_Grouping is disabled, THE Notes_List_View SHALL display notes in a flat list without section headers
5. THE View_Options_Menu SHALL display a visual indicator (checkmark or toggle state) showing the current Date_Grouping state
6. THE System SHALL persist the Date_Grouping preference across app restarts
7. WHEN Date_Grouping state changes, THE Notes_List_View SHALL animate the transition between grouped and flat list views

### 需求 4：画廊视图切换

**用户故事：** 作为用户，我想要在列表视图和画廊视图之间切换，以便我可以以不同的方式浏览我的笔记。

#### 验收标准

1. THE View_Options_Menu SHALL display a separator line before the view mode options
2. THE View_Options_Menu SHALL display view mode options: 列表视图、画廊视图
3. WHEN the user selects Gallery_View mode, THE System SHALL replace the Notes_List_View and editor area with a full-width Gallery_View
4. WHEN in Gallery_View mode, THE System SHALL hide the note editor area
5. THE Gallery_View SHALL occupy the entire window area except for the sidebar and toolbar
6. THE View_Options_Menu SHALL display a visual indicator (checkmark) next to the currently selected view mode
7. THE System SHALL persist the selected view mode across app restarts

### 需求 5：画廊视图布局

**用户故事：** 作为用户，我想要在画廊视图中看到笔记的预览卡片，以便我可以快速浏览多个笔记的内容。

#### 验收标准

1. THE Gallery_View SHALL display notes as a grid of Note_Card components
2. EACH Note_Card SHALL display: note title, content preview (first few lines), last modified date
3. IF the note contains images, THE Note_Card SHALL display a thumbnail of the first image
4. IF the note is locked, THE Note_Card SHALL display a lock icon overlay
5. THE Gallery_View SHALL use a responsive grid layout that adjusts the number of columns based on available width
6. THE Note_Card SHALL have a minimum width of 200 points and maximum width of 300 points
7. THE Gallery_View SHALL support scrolling when notes exceed the visible area
8. THE Gallery_View SHALL respect the current Sort_Order and Sort_Direction settings
9. WHEN Date_Grouping is enabled, THE Gallery_View SHALL display section headers for each date group

### 需求 6：画廊视图笔记选择与展开

**用户故事：** 作为用户，我想要点击画廊中的笔记卡片来查看和编辑笔记，以便我可以无缝地从浏览切换到编辑模式。

#### 验收标准

1. WHEN the user clicks a Note_Card, THE System SHALL animate the card expanding to fill the entire content area (excluding sidebar and toolbar)
2. THE Expanded_View SHALL display the full note editor with the selected note loaded
3. THE Expanded_View SHALL include a back button or close button to return to Gallery_View
4. WHEN the user clicks the back/close button, THE System SHALL animate the editor collapsing back to the Note_Card position
5. THE expansion animation SHALL use a smooth easeInOut timing with duration of 300-400ms
6. WHILE in Expanded_View, THE System SHALL update the selectedNote in the ViewModel
7. WHEN returning to Gallery_View, THE System SHALL scroll to show the previously selected Note_Card if it's not visible

### 需求 7：画廊视图交互

**用户故事：** 作为用户，我想要在画廊视图中执行常见操作，以便我可以高效地管理我的笔记。

#### 验收标准

1. WHEN the user right-clicks a Note_Card, THE System SHALL display the same context menu as in List_View
2. THE Note_Card SHALL support hover state with subtle visual feedback (e.g., shadow or border highlight)
3. WHEN the user hovers over a Note_Card for 100ms, THE System SHALL preload the note content for faster opening
4. THE Gallery_View SHALL support keyboard navigation (arrow keys to move between cards, Enter to open)
5. WHEN the user presses Escape in Expanded_View, THE System SHALL return to Gallery_View

### 需求 8：状态同步

**用户故事：** 作为用户，我想要视图状态在不同组件之间保持同步，以便我的操作能够正确反映在界面上。

#### 验收标准

1. WHEN the user switches folders in the sidebar, THE Gallery_View SHALL update to show notes from the selected folder
2. WHEN a note is created, updated, or deleted, THE Gallery_View SHALL reflect the change immediately
3. WHEN the user performs a search, THE Gallery_View SHALL filter to show only matching notes
4. THE Gallery_View SHALL respect all search filter options (tags, checklist, images, audio, private)
5. WHEN switching between List_View and Gallery_View, THE System SHALL preserve the selected folder and search state

