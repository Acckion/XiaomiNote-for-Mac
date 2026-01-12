# Requirements Document

## Introduction

统一格式菜单功能，为原生编辑器和 Web 编辑器提供一致的格式菜单体验。格式菜单需要在工具栏和菜单栏两个位置正确显示当前格式状态，并支持用户修改格式。

## Glossary

- **Format_Menu**: 格式菜单，显示和控制文本格式的用户界面组件
- **Format_State**: 格式状态，表示当前光标或选择处的文本格式信息
- **Format_Provider**: 格式提供者，统一接口，用于获取和应用格式
- **Typing_Attributes**: 输入属性，光标模式下设置的后续输入格式
- **Paragraph_Format**: 段落级格式，包括标题、列表、正文等互斥格式
- **Character_Format**: 字符级格式，包括加粗、斜体等可叠加格式
- **Alignment_Format**: 对齐格式，包括左对齐、居中、右对齐
- **Native_Editor**: 原生编辑器，基于 NSTextView 的编辑器实现
- **Web_Editor**: Web 编辑器，基于 WebKit 的编辑器实现
- **Toolbar_Menu**: 工具栏格式菜单，位于窗口工具栏的格式下拉菜单
- **MenuBar_Menu**: 菜单栏格式菜单，位于应用程序菜单栏的格式菜单

## Requirements

### Requirement 1: 格式状态显示

**User Story:** As a user, I want to see the current text format state in the format menu, so that I know what formats are applied to the selected text or cursor position.

#### Acceptance Criteria

1. WHEN the cursor is positioned in the editor without selection, THE Format_Menu SHALL display the format state of the character immediately before the cursor position
2. WHEN the cursor is at the beginning of the document, THE Format_Menu SHALL display the default format state (no formats active)
3. WHEN text is selected, THE Format_Menu SHALL display a format as active only if ALL characters in the selection have that format applied
4. WHEN text is selected and ANY character in the selection does not have a format, THE Format_Menu SHALL display that format as inactive
5. WHEN the cursor position or selection changes, THE Format_Menu SHALL update the displayed format state within 100ms

### Requirement 2: 段落级格式互斥

**User Story:** As a user, I want paragraph-level formats to be mutually exclusive, so that I can have a clear and consistent document structure.

#### Acceptance Criteria

1. THE Format_Provider SHALL treat the following formats as mutually exclusive: heading1, heading2, heading3, body, bulletList, numberedList, checkbox
2. WHEN a user applies a Paragraph_Format, THE Format_Provider SHALL automatically remove any other active Paragraph_Format
3. WHEN a list format is applied, THE Format_Provider SHALL treat the text as body style with list markers (not as heading)
4. WHEN a heading format is applied to a list item, THE Format_Provider SHALL remove the list format first

### Requirement 3: 对齐格式互斥

**User Story:** As a user, I want alignment formats to be mutually exclusive, so that text has a single clear alignment.

#### Acceptance Criteria

1. THE Format_Provider SHALL treat the following formats as mutually exclusive: alignLeft, alignCenter, alignRight
2. WHEN a user applies an Alignment_Format, THE Format_Provider SHALL automatically remove any other active Alignment_Format
3. WHEN no alignment is explicitly set, THE Format_Provider SHALL default to left alignment

### Requirement 4: 字符级格式叠加

**User Story:** As a user, I want to apply multiple character formats to the same text, so that I can create rich text with combined styles.

#### Acceptance Criteria

1. THE Format_Provider SHALL allow the following formats to be applied simultaneously: bold, italic, underline, strikethrough, highlight
2. WHEN a user applies a Character_Format, THE Format_Provider SHALL preserve any other active Character_Formats
3. WHEN a user removes a Character_Format, THE Format_Provider SHALL preserve any other active Character_Formats

### Requirement 5: 选择模式格式应用

**User Story:** As a user, I want to apply or remove formats to selected text based on the current state, so that I can efficiently format my content.

#### Acceptance Criteria

1. WHEN text is selected and a format is inactive (not all characters have it), THE Format_Provider SHALL apply the format to ALL selected characters when clicked
2. WHEN text is selected and a format is active (all characters have it), THE Format_Provider SHALL remove the format from ALL selected characters when clicked
3. WHEN applying a format to a selection with mixed states, THE Format_Provider SHALL make all characters have the format (apply to all)

### Requirement 6: 光标模式格式应用

**User Story:** As a user, I want to set the format for subsequent typing when no text is selected, so that I can type new content with the desired format.

#### Acceptance Criteria

1. WHEN no text is selected and a user clicks a format, THE Format_Provider SHALL toggle the Typing_Attributes for that format
2. WHEN Typing_Attributes include a format, THE Format_Provider SHALL apply that format to subsequently typed characters
3. WHEN the cursor position changes, THE Format_Provider SHALL reset Typing_Attributes to match the format at the new position
4. WHEN the selection changes from cursor to range, THE Format_Provider SHALL clear Typing_Attributes and use selection-based state

### Requirement 7: 统一接口设计

**User Story:** As a developer, I want a unified interface for format operations, so that both toolbar and menu bar can use the same logic.

#### Acceptance Criteria

1. THE Format_Provider SHALL expose a method to get the current Format_State for any editor type
2. THE Format_Provider SHALL expose a method to apply a format that handles all mutual exclusion rules
3. THE Format_Provider SHALL expose a method to check if a specific format is active
4. THE Format_Provider SHALL work identically for Native_Editor and Web_Editor

### Requirement 8: 工具栏和菜单栏同步

**User Story:** As a user, I want the toolbar format menu and menu bar format menu to show the same state, so that I have a consistent experience.

#### Acceptance Criteria

1. WHEN the format state changes, THE Toolbar_Menu and MenuBar_Menu SHALL both update to reflect the new state
2. WHEN a format is applied via Toolbar_Menu, THE MenuBar_Menu SHALL immediately reflect the change
3. WHEN a format is applied via MenuBar_Menu, THE Toolbar_Menu SHALL immediately reflect the change
4. WHEN switching between Native_Editor and Web_Editor, THE Format_Menu SHALL update to show the correct state for the active editor

### Requirement 9: 引用块格式

**User Story:** As a user, I want to apply quote block format independently, so that I can quote content while preserving other formats.

#### Acceptance Criteria

1. THE Format_Provider SHALL treat quote block as an independent toggle format
2. WHEN a user applies quote block, THE Format_Provider SHALL preserve the current Paragraph_Format
3. WHEN a user removes quote block, THE Format_Provider SHALL preserve the current Paragraph_Format
4. THE Format_Menu SHALL display quote block state independently from other formats

### Requirement 10: 性能要求

**User Story:** As a user, I want the format menu to respond quickly, so that I can format text without noticeable delay.

#### Acceptance Criteria

1. WHEN the cursor or selection changes, THE Format_Provider SHALL detect the new format state within 50ms
2. WHEN a format is applied, THE Format_Provider SHALL complete the operation within 100ms
3. WHEN the format menu is opened, THE Format_Menu SHALL display the current state within 50ms
4. THE Format_Provider SHALL use debouncing to prevent excessive updates during rapid cursor movement
