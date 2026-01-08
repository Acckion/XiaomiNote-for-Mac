# 原生富文本编辑器需求文档

## 简介

本文档定义了使用 SwiftUI TextEditor、NSTextView 和自定义渲染技术实现原生富文本编辑器的需求，以 1:1 复刻 Apple Notes 的原生体验，包括复选框、分割线、引用块等所有功能，同时保持与小米笔记的同步兼容性。用户可以在设置中选择使用原生编辑器或 Web 编辑器。

## 术语表

- **Native_Editor**: 基于 SwiftUI TextEditor、NSTextView 和自定义渲染的原生编辑器
- **Web_Editor**: 当前基于 WKWebView 的 Web 编辑器
- **XiaoMi_XML**: 小米笔记使用的 XML 格式
- **AttributedString**: iOS 15+ 引入的 Swift 原生富文本格式
- **NSTextAttachment**: 用于在文本中嵌入自定义对象的 AppKit/UIKit 类
- **Custom_Renderer**: 自定义渲染器，用于绘制复选框、分割线等特殊元素
- **Format_Converter**: 负责 XiaoMi_XML 与 AttributedString 之间转换的组件
- **Editor_Context**: 管理编辑器状态和操作的上下文对象
- **Editor_Preference**: 用户在设置中选择的编辑器偏好

## 需求

### 需求 1：编辑器选择和设置

**用户故事：** 作为用户，我希望能够在设置中选择使用原生编辑器或 Web 编辑器，并且我的选择能够被记住和应用。

#### 验收标准

1. WHEN 用户打开设置页面 THEN THE System SHALL 显示编辑器选择选项
2. WHEN 用户选择原生编辑器 THEN THE System SHALL 保存 Editor_Preference 并应用到所有笔记编辑
3. WHEN 用户选择 Web 编辑器 THEN THE System SHALL 保存 Editor_Preference 并应用到所有笔记编辑
4. WHEN 系统版本不支持原生编辑器功能 THEN THE System SHALL 禁用原生编辑器选项并显示说明
5. WHEN 用户首次使用应用 THEN THE System SHALL 根据系统版本设置默认编辑器偏好

### 需求 2：基础富文本编辑

**用户故事：** 作为用户，我希望在原生编辑器中进行完整的富文本编辑，严格按照小米笔记的格式规范。

#### 验收标准

1. WHEN 用户选择文本并按 Cmd+B THEN THE Native_Editor SHALL 切换文本的加粗状态并使用 `<b>` 标签包裹
2. WHEN 用户选择文本并按 Cmd+I THEN THE Native_Editor SHALL 切换文本的斜体状态并使用 `<i>` 标签包裹
3. WHEN 用户选择文本并按 Cmd+U THEN THE Native_Editor SHALL 切换文本的下划线状态并使用 `<u>` 标签包裹
4. WHEN 用户应用删除线格式 THEN THE Native_Editor SHALL 使用 `<delete>` 标签包裹文本
5. WHEN 用户应用高亮格式 THEN THE Native_Editor SHALL 使用 `<background color="#9affe8af">` 标签包裹文本
6. WHEN 用户设置居中对齐 THEN THE Native_Editor SHALL 使用 `<center>` 标签包裹整行内容
7. WHEN 用户设置右对齐 THEN THE Native_Editor SHALL 使用 `<right>` 标签包裹整行内容
8. WHEN 用户设置文本缩进 THEN THE Native_Editor SHALL 修改 `<text>` 标签的 indent 属性值

### 需求 3：复选框列表实现

**用户故事：** 作为用户，我希望在原生编辑器中创建和编辑复选框列表，严格按照小米笔记的格式规范。

#### 验收标准

1. WHEN 用户点击复选框按钮或输入特定语法 THEN THE Native_Editor SHALL 创建复选框列表项
2. WHEN 用户点击复选框 THEN THE Native_Editor SHALL 切换复选框的选中状态（仅在编辑器中显示，不保存到 XML）
3. WHEN 用户在复选框列表项中按回车 THEN THE Native_Editor SHALL 创建新的复选框列表项
4. WHEN 复选框被选中 THEN THE Custom_Renderer SHALL 显示选中状态的复选框图标
5. WHEN 复选框未选中 THEN THE Custom_Renderer SHALL 显示未选中状态的复选框图标
6. WHEN 转换为 XML THEN THE Format_Converter SHALL 生成 `<input type="checkbox" indent="1" level="3" />内容` 格式（不包含选中状态）

### 需求 4：分割线实现

**用户故事：** 作为用户，我希望在原生编辑器中插入分割线来分隔内容，就像在 Apple Notes 中一样。

#### 验收标准

1. WHEN 用户点击分割线按钮或输入特定语法 THEN THE Native_Editor SHALL 插入分割线
2. WHEN 分割线需要显示 THEN THE Custom_Renderer SHALL 绘制水平分割线
3. WHEN 用户选择分割线 THEN THE Native_Editor SHALL 允许删除分割线
4. WHEN 分割线在不同主题下显示 THEN THE Custom_Renderer SHALL 适配深色和浅色模式
5. WHEN 分割线周围有文本 THEN THE Native_Editor SHALL 正确处理行间距和布局

### 需求 5：引用块实现

**用户故事：** 作为用户，我希望在原生编辑器中创建引用块来突出显示重要内容，严格按照小米笔记的格式规范。

#### 验收标准

1. WHEN 用户点击引用按钮或输入特定语法 THEN THE Native_Editor SHALL 创建引用块
2. WHEN 引用块需要显示 THEN THE Custom_Renderer SHALL 绘制左侧边框和背景样式
3. WHEN 用户在引用块中编辑 THEN THE Native_Editor SHALL 保持引用格式并支持多行内容
4. WHEN 用户在引用块末尾按回车 THEN THE Native_Editor SHALL 继续引用格式或退出引用
5. WHEN 转换为 XML THEN THE Format_Converter SHALL 生成 `<quote><text indent="1">内容</text></quote>` 格式并支持多行引用
6. WHEN 引用块包含富文本 THEN THE Native_Editor SHALL 正确处理引用内的格式标签

### 需求 6：列表和标题实现

**用户故事：** 作为用户，我希望在原生编辑器中创建各种类型的列表和标题，严格按照小米笔记的格式规范。

#### 验收标准

1. WHEN 用户创建无序列表 THEN THE Native_Editor SHALL 使用自定义 NSTextAttachment 渲染项目符号并生成 `<bullet indent="1" />内容` 格式
2. WHEN 用户创建有序列表 THEN THE Native_Editor SHALL 自动编号并正确处理连续列表的 inputNumber 规则（第一行使用实际值，后续行使用 0）
3. WHEN 用户设置大标题 THEN THE Native_Editor SHALL 应用大字体样式并生成 `<text indent="1"><size>标题</size></text>` 格式
4. WHEN 用户设置二级标题 THEN THE Native_Editor SHALL 应用中等字体样式并生成 `<text indent="1"><mid-size>标题</mid-size></text>` 格式
5. WHEN 用户设置三级标题 THEN THE Native_Editor SHALL 应用小标题字体样式并生成 `<text indent="1"><h3-size>标题</h3-size></text>` 格式
6. WHEN 用户在列表项中按回车 THEN THE Native_Editor SHALL 创建新的列表项或退出列表
7. WHEN 列表项嵌套 THEN THE Native_Editor SHALL 正确处理缩进（通过修改 indent 属性值）

### 需求 7：格式转换和同步

**用户故事：** 作为用户，我希望在原生编辑器中编辑的内容能够完美同步到小米笔记服务器，严格遵循小米笔记的 XML 格式规范。

#### 验收标准

1. WHEN 转换普通文本 THEN THE Format_Converter SHALL 生成 `<text indent="1">内容</text>` 格式
2. WHEN 转换大标题 THEN THE Format_Converter SHALL 生成 `<text indent="1"><size>标题</size></text>` 格式
3. WHEN 转换二级标题 THEN THE Format_Converter SHALL 生成 `<text indent="1"><mid-size>标题</mid-size></text>` 格式
4. WHEN 转换三级标题 THEN THE Format_Converter SHALL 生成 `<text indent="1"><h3-size>标题</h3-size></text>` 格式
5. WHEN 转换无序列表 THEN THE Format_Converter SHALL 生成 `<bullet indent="1" />内容` 格式（不使用 text 包裹）
6. WHEN 转换有序列表 THEN THE Format_Converter SHALL 生成 `<order indent="1" inputNumber="0" />内容` 格式并正确处理连续列表的 inputNumber 规则
7. WHEN 转换复选框 THEN THE Format_Converter SHALL 生成 `<input type="checkbox" indent="1" level="3" />内容` 格式（不使用 text 包裹）
8. WHEN 转换分割线 THEN THE Format_Converter SHALL 生成 `<hr />` 格式
9. WHEN 转换引用块 THEN THE Format_Converter SHALL 生成 `<quote><text indent="1">内容</text></quote>` 格式并支持多行引用
10. WHEN 转换居中对齐 THEN THE Format_Converter SHALL 生成 `<text indent="1"><center>内容</center></text>` 格式
11. WHEN 转换右对齐 THEN THE Format_Converter SHALL 生成 `<text indent="1"><right>内容</right></text>` 格式
12. WHEN 转换缩进文本 THEN THE Format_Converter SHALL 正确设置 indent 属性值（1=不缩进，2=缩进一格，以此类推）

### 需求 8：自定义渲染系统

**用户故事：** 作为开发者，我希望有一个灵活的自定义渲染系统来实现 Apple Notes 风格的特殊元素。

#### 验收标准

1. WHEN 需要渲染复选框 THEN THE Custom_Renderer SHALL 使用 NSTextAttachment 创建交互式复选框
2. WHEN 需要渲染分割线 THEN THE Custom_Renderer SHALL 使用自定义绘制创建水平线
3. WHEN 需要渲染引用块 THEN THE Custom_Renderer SHALL 使用 NSLayoutManager 自定义绘制背景和边框
4. WHEN 主题变化 THEN THE Custom_Renderer SHALL 自动适配深色和浅色模式
5. WHEN 用户交互 THEN THE Custom_Renderer SHALL 正确处理点击、选择和编辑事件

### 需求 9：编辑器状态管理

**用户故事：** 作为用户，我希望编辑器能够正确跟踪和显示当前的格式状态，包括特殊元素的状态。

#### 验收标准

1. WHEN 光标位置改变 THEN THE Editor_Context SHALL 更新当前位置的格式状态
2. WHEN 用户选择包含特殊元素的文本 THEN THE Editor_Context SHALL 正确识别元素类型
3. WHEN 格式状态改变 THEN THE System SHALL 更新工具栏按钮的激活状态
4. WHEN 用户在复选框列表中 THEN THE Editor_Context SHALL 显示复选框相关的工具栏选项
5. WHEN 编辑器获得焦点 THEN THE System SHALL 同步编辑器上下文状态

### 需求 10：图片和媒体支持

**用户故事：** 作为用户，我希望在原生编辑器中能够插入和查看图片，就像在 Apple Notes 中一样。

#### 验收标准

1. WHEN 用户粘贴图片 THEN THE Native_Editor SHALL 将图片保存到本地存储
2. WHEN 图片保存成功 THEN THE Native_Editor SHALL 使用 NSTextAttachment 在文档中显示图片
3. WHEN 显示图片 THEN THE Native_Editor SHALL 使用 minote:// URL 方案加载本地图片
4. WHEN 图片加载失败 THEN THE Native_Editor SHALL 显示占位符图标
5. WHEN 用户调整图片大小 THEN THE Native_Editor SHALL 支持图片缩放和布局调整

### 需求 11：性能和用户体验

**用户故事：** 作为用户，我希望原生编辑器提供流畅的编辑体验和快速的响应速度，特别是在处理复杂格式时。

#### 验收标准

1. WHEN 编辑器初始化 THEN THE Native_Editor SHALL 在 100ms 内完成加载
2. WHEN 用户输入文本 THEN THE Native_Editor SHALL 提供实时的格式反馈
3. WHEN 处理包含大量特殊元素的文档 THEN THE Native_Editor SHALL 保持流畅的滚动和编辑
4. WHEN 切换编辑器模式 THEN THE System SHALL 保持光标位置和选择状态
5. WHEN 自定义渲染元素较多 THEN THE Custom_Renderer SHALL 优化绘制性能

### 需求 8：开发者工具和调试

**用户故事：** 作为开发者，我希望能够调试和监控原生编辑器的运行状态。

#### 验收标准

1. WHEN 启用调试模式 THEN THE System SHALL 输出详细的格式转换日志
2. WHEN 格式转换发生 THEN THE System SHALL 记录转换前后的数据对比
3. WHEN 性能问题出现 THEN THE System SHALL 提供性能指标和瓶颈分析
4. WHEN 用户反馈问题 THEN THE System SHALL 生成包含上下文信息的错误报告
5. WHEN 测试新功能 THEN THE System SHALL 提供 A/B 测试框架支持编辑器切换

### 需求 12：错误处理和回退机制

**用户故事：** 作为用户，我希望当原生编辑器遇到问题时，系统能够优雅地处理错误并提供解决方案。

#### 验收标准

1. WHEN Native_Editor 初始化失败 THEN THE System SHALL 显示错误信息并提供切换到 Web_Editor 的选项
2. WHEN 自定义渲染失败 THEN THE System SHALL 回退到基础文本显示并记录错误
3. WHEN 格式转换出现错误 THEN THE System SHALL 保留原始内容并提示用户
4. WHEN 发生崩溃或异常 THEN THE System SHALL 自动保存用户数据并重启编辑器
5. WHEN 用户报告渲染问题 THEN THE System SHALL 提供详细的错误日志和诊断信息

### 需求 13：开发者工具和调试

**用户故事：** 作为开发者，我希望能够调试和监控原生编辑器的运行状态，特别是自定义渲染的性能。

#### 验收标准

1. WHEN 启用调试模式 THEN THE System SHALL 输出详细的渲染和格式转换日志
2. WHEN 自定义渲染发生 THEN THE System SHALL 记录渲染性能指标
3. WHEN 格式转换发生 THEN THE System SHALL 记录转换前后的数据对比
4. WHEN 用户反馈问题 THEN THE System SHALL 生成包含渲染状态的错误报告
5. WHEN 测试新的自定义元素 THEN THE System SHALL 提供渲染预览和调试工具