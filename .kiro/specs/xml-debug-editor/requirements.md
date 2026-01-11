# Requirements Document

## Introduction

本功能为小米笔记 macOS 客户端添加一个调试编辑器模式，允许开发者直接查看和编辑笔记的原始 XML 数据。这对于调试格式转换问题、排查数据异常、以及理解小米笔记的 XML 格式非常有用。

## Glossary

- **Debug_Editor**: 调试编辑器，用于直接编辑原始 XML 数据的界面组件
- **XML_Content**: 小米笔记格式的 XML 内容，存储在 Note.content 字段中
- **Normal_Editor**: 普通编辑器，包括原生编辑器和 Web 编辑器
- **Editor_Mode**: 编辑器模式，可以是普通模式或调试模式
- **Save_Operation**: 保存操作，将编辑后的 XML 内容保存到本地和云端

## Requirements

### Requirement 1: 调试编辑器模式切换

**User Story:** As a developer, I want to switch between normal editor and debug editor mode, so that I can view and edit raw XML data when needed.

#### Acceptance Criteria

1. WHEN a user clicks the debug mode toggle button THEN THE Debug_Editor SHALL display the raw XML content of the current note
2. WHEN a user is in debug mode and clicks the toggle button THEN THE Debug_Editor SHALL switch back to Normal_Editor mode
3. WHILE in debug mode THE Debug_Editor SHALL display a visual indicator showing the current mode is "调试模式"
4. WHEN switching from debug mode to normal mode THE Debug_Editor SHALL preserve any unsaved changes in the XML content
5. IF no note is selected THEN THE Debug_Editor toggle button SHALL be disabled

### Requirement 2: XML 内容显示

**User Story:** As a developer, I want to see the raw XML content clearly formatted, so that I can understand the note structure.

#### Acceptance Criteria

1. WHEN debug mode is activated THE Debug_Editor SHALL display the complete XML content from Note.primaryXMLContent
2. THE Debug_Editor SHALL use a monospace font for XML content display
3. THE Debug_Editor SHALL support syntax highlighting for XML tags (optional enhancement)
4. WHEN the XML content is empty THE Debug_Editor SHALL display a placeholder message "无 XML 内容"
5. THE Debug_Editor SHALL support horizontal and vertical scrolling for long content

### Requirement 3: XML 内容编辑

**User Story:** As a developer, I want to edit the raw XML content directly, so that I can fix formatting issues or test changes.

#### Acceptance Criteria

1. WHEN a user types in the debug editor THE Debug_Editor SHALL update the XML content in real-time
2. THE Debug_Editor SHALL support standard text editing operations (copy, paste, cut, undo, redo)
3. WHEN the XML content is modified THE Debug_Editor SHALL mark the note as having unsaved changes
4. THE Debug_Editor SHALL preserve line breaks and indentation in the XML content

### Requirement 4: 保存功能

**User Story:** As a developer, I want to save my XML edits, so that the changes are persisted to the note.

#### Acceptance Criteria

1. WHEN a user clicks the save button THE Debug_Editor SHALL save the edited XML content to the note
2. WHEN saving THE Debug_Editor SHALL update Note.content with the edited XML
3. WHEN saving THE Debug_Editor SHALL trigger local database save
4. WHEN saving THE Debug_Editor SHALL schedule cloud sync for the updated note
5. WHILE saving THE Debug_Editor SHALL display a "保存中..." indicator
6. WHEN save completes successfully THE Debug_Editor SHALL display "已保存" status
7. IF save fails THEN THE Debug_Editor SHALL display an error message and retain the edited content

### Requirement 5: 快捷键支持

**User Story:** As a developer, I want to use keyboard shortcuts, so that I can work efficiently in debug mode.

#### Acceptance Criteria

1. WHEN user presses Cmd+S in debug mode THE Debug_Editor SHALL trigger save operation
2. WHEN user presses Cmd+Shift+D THE Debug_Editor SHALL toggle debug mode on/off
3. THE Debug_Editor SHALL not interfere with standard text editing shortcuts (Cmd+C, Cmd+V, Cmd+Z, etc.)

### Requirement 6: 界面集成

**User Story:** As a developer, I want the debug editor to integrate seamlessly with the existing UI, so that it doesn't disrupt the normal workflow.

#### Acceptance Criteria

1. THE Debug_Editor toggle button SHALL be placed in the note detail view toolbar or menu
2. WHEN in debug mode THE Debug_Editor SHALL replace the normal editor view
3. THE Debug_Editor SHALL use consistent styling with the rest of the application
4. WHEN switching notes WHILE in debug mode THE Debug_Editor SHALL load the new note's XML content
5. THE Debug_Editor SHALL respect the application's dark/light mode settings
