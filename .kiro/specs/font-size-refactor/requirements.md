# Requirements Document

## Introduction

本文档定义了原生编辑器字体大小管理系统的重构需求。当前系统中字体大小的定义分散在多个文件中，存在不一致的问题，需要统一管理以确保：
1. 各级标题和正文的字体大小符合设计规范
2. 标题默认不加粗
3. 格式菜单能正确显示和修改字体大小
4. 字体大小作为行级属性，一行内不能混合不同大小

## Glossary

- **Font_Size_Manager**: 字体大小管理器，负责统一管理所有字体大小常量和相关逻辑
- **Heading_Level**: 标题级别，包括大标题（H1）、二级标题（H2）、三级标题（H3）
- **Body_Text**: 正文文本，默认的文本格式
- **Line_Range**: 行范围，指一行文本从行首到行尾（包含换行符前）的范围
- **Format_Menu**: 格式菜单，包括菜单栏中的"格式"菜单和工具栏中的格式按钮
- **Cursor_Position**: 光标位置，当前编辑插入点的位置
- **Native_Editor**: 原生编辑器，使用 NSTextView 实现的富文本编辑器

## Requirements

### Requirement 1: 统一字体大小常量定义

**User Story:** 作为开发者，我希望所有字体大小常量在一个地方定义，以便于维护和修改。

#### Acceptance Criteria

1. THE Font_Size_Manager SHALL define heading1Size as 23 points
2. THE Font_Size_Manager SHALL define heading2Size as 20 points
3. THE Font_Size_Manager SHALL define heading3Size as 17 points
4. THE Font_Size_Manager SHALL define bodySize as 14 points
5. WHEN any component needs font size values, THE component SHALL retrieve them from Font_Size_Manager

### Requirement 2: 标题格式不默认加粗

**User Story:** 作为用户，我希望标题格式默认不加粗，以便我可以自由选择是否为标题添加加粗效果。

#### Acceptance Criteria

1. WHEN applying heading1 format, THE Native_Editor SHALL use regular font weight (not bold)
2. WHEN applying heading2 format, THE Native_Editor SHALL use regular font weight (not bold)
3. WHEN applying heading3 format, THE Native_Editor SHALL use regular font weight (not bold)
4. WHEN user explicitly applies bold format to a heading, THE Native_Editor SHALL preserve both heading size and bold weight

### Requirement 3: 格式菜单正确显示字体大小状态

**User Story:** 作为用户，我希望格式菜单能正确显示当前光标位置的字体大小状态，以便我了解当前文本的格式。

#### Acceptance Criteria

1. WHEN cursor is positioned in heading1 text, THE Format_Menu SHALL show heading1 as active
2. WHEN cursor is positioned in heading2 text, THE Format_Menu SHALL show heading2 as active
3. WHEN cursor is positioned in heading3 text, THE Format_Menu SHALL show heading3 as active
4. WHEN cursor is positioned in body text, THE Format_Menu SHALL show body as active
5. WHEN cursor position changes, THE Format_Menu SHALL update within 50 milliseconds

### Requirement 4: 格式菜单正确应用字体大小

**User Story:** 作为用户，我希望通过格式菜单能正确修改当前行的字体大小。

#### Acceptance Criteria

1. WHEN user selects heading1 from Format_Menu, THE Native_Editor SHALL apply 23pt font size to the entire current line
2. WHEN user selects heading2 from Format_Menu, THE Native_Editor SHALL apply 20pt font size to the entire current line
3. WHEN user selects heading3 from Format_Menu, THE Native_Editor SHALL apply 17pt font size to the entire current line
4. WHEN user selects body from Format_Menu, THE Native_Editor SHALL apply 14pt font size to the entire current line
5. WHEN applying font size, THE Native_Editor SHALL preserve existing character formats (bold, italic, underline, etc.)

### Requirement 5: 字体大小作为行级属性

**User Story:** 作为用户，我希望字体大小应用于整行，以保持文档格式的一致性。

#### Acceptance Criteria

1. WHEN applying any heading format, THE Native_Editor SHALL apply the font size to the entire Line_Range
2. WHEN applying body format, THE Native_Editor SHALL apply the font size to the entire Line_Range
3. THE Native_Editor SHALL NOT allow different font sizes within the same line
4. WHEN user attempts to apply font size to a selection within a line, THE Native_Editor SHALL extend the application to the entire line

### Requirement 6: 字体大小检测逻辑统一

**User Story:** 作为开发者，我希望字体大小检测逻辑统一，以确保格式状态检测的准确性。

#### Acceptance Criteria

1. WHEN detecting font size at a position, THE Font_Size_Manager SHALL use consistent threshold values
2. THE Font_Size_Manager SHALL detect heading1 when font size is greater than or equal to 23 points
3. THE Font_Size_Manager SHALL detect heading2 when font size is greater than or equal to 20 points and less than 23 points
4. THE Font_Size_Manager SHALL detect heading3 when font size is greater than or equal to 17 points and less than 20 points
5. THE Font_Size_Manager SHALL detect body when font size is less than 17 points

### Requirement 7: XML 格式转换兼容性

**User Story:** 作为用户，我希望字体大小能正确保存到小米笔记 XML 格式并正确加载。

#### Acceptance Criteria

1. WHEN converting heading1 to XML, THE XiaoMiFormatConverter SHALL output `<size>` tag
2. WHEN converting heading2 to XML, THE XiaoMiFormatConverter SHALL output `<mid-size>` tag
3. WHEN converting heading3 to XML, THE XiaoMiFormatConverter SHALL output `<h3-size>` tag
4. WHEN parsing `<size>` tag from XML, THE XiaoMiFormatConverter SHALL apply 23pt font size
5. WHEN parsing `<mid-size>` tag from XML, THE XiaoMiFormatConverter SHALL apply 20pt font size
6. WHEN parsing `<h3-size>` tag from XML, THE XiaoMiFormatConverter SHALL apply 17pt font size
7. FOR ALL valid heading formats, parsing then converting SHALL produce equivalent XML (round-trip property)

### Requirement 8: 新行继承规则

**User Story:** 作为用户，我希望在标题行末尾按回车时，新行恢复为正文格式。

#### Acceptance Criteria

1. WHEN user presses Enter at the end of a heading line, THE Native_Editor SHALL create a new line with body format (14pt)
2. WHEN user presses Enter in the middle of a heading line, THE Native_Editor SHALL preserve heading format for both lines
3. WHEN user presses Enter at the end of a body line, THE Native_Editor SHALL create a new line with body format (14pt)

