# 编辑器重写计划

## 项目概述

基于 `new_editor.html` 的简洁实现方式，完全重写 `editor.html`，将格式转换逻辑提取到独立的 JS 文件中，实现核心的格式转换和渲染功能。

## 文件结构

### 1. `editor.html` - 主编辑器文件
- **基础**: 基于 `new_editor.html` 的 CKEditor 5 实现
- **UI**: 保持 `new_editor.html` 的简洁界面，移除 toolbar
- **功能**: 
  - 集成 CKEditor 5（无 toolbar 模式）
  - 实现 `window.MiNoteWebEditor` 接口
  - 深色模式支持
  - 内容变化监听和通知

### 2. `format-converter.js` - 格式转换模块
- **功能**: 实现小米笔记 XML 格式与 HTML 之间的双向转换
- **类/函数结构**:
  - `XMLToHTMLConverter` - XML 到 HTML 转换器类
  - `HTMLToXMLConverter` - HTML 到 XML 转换器类
  - 辅助函数（解析、转义等）

## 详细实现计划

### 文件 1: `format-converter.js`

#### 1.1 XMLToHTMLConverter 类

**职责**: 将小米笔记 XML 格式转换为 HTML，用于在编辑器中渲染

**主要方法**:
- `convert(xmlContent: string): string` - 主转换方法
- `parseTextElement(line: string): string` - 解析 `<text>` 元素
- `parseBulletElement(line: string): string` - 解析 `<bullet>` 元素
- `parseOrderElement(line: string, currentNumber: number): {html: string, nextNumber: number}` - 解析 `<order>` 元素
- `parseCheckboxElement(line: string): string` - 解析 `<input type="checkbox">` 元素
- `parseHRElement(line: string): string` - 解析 `<hr>` 元素
- `parseImageElement(line: string): string` - 解析 `<img>` 元素
- `parseQuoteElement(quoteContent: string): string` - 解析 `<quote>` 元素
- `extractRichTextContent(xmlText: string): string` - 提取富文本内容（处理 `<b>`, `<i>`, `<u>`, `<delete>`, `<background>`, `<size>`, `<mid-size>`, `<h3-size>`, `<center>`, `<right>` 等标签）

**实现细节**:
- 逐行解析 XML
- 处理有序列表的连续性和序号递增
- 处理引用块的多行内容
- 将 XML 标签转换为对应的 HTML 结构和 CSS 类

#### 1.2 HTMLToXMLConverter 类

**职责**: 将编辑器中的 HTML 内容转换为小米笔记 XML 格式，用于保存

**主要方法**:
- `convert(htmlContent: string): string` - 主转换方法
- `processNode(node: Node, context: ConversionContext): string | null` - 处理单个 DOM 节点
- `convertNodeToXML(node: Node, context: ConversionContext): string | null` - 将节点转换为 XML 行
- `extractContentWithRichText(node: Node): string` - 提取节点内容并保留富文本格式
- `getIndentFromClass(className: string): string | null` - 从 CSS 类提取缩进级别
- `getAlignFromClass(className: string): string` - 从 CSS 类提取对齐方式
- `escapeXML(text: string): string` - XML 转义

**实现细节**:
- 遍历 DOM 树，识别不同类型的元素
- 处理有序列表的连续性（第一行 inputNumber 为实际值，后续为 0）
- 处理嵌套结构（引用块、列表等）
- 将 HTML 标签和 CSS 类映射回 XML 标签

#### 1.3 辅助函数

- `escapeXML(text: string): string` - XML 转义（`<`, `>`, `&`, `"`, `'`）
- `unescapeXML(text: string): string` - XML 反转义
- `parseIndent(indent: string): number` - 解析缩进值
- `formatIndent(level: number): string` - 格式化缩进值

### 文件 2: `editor.html`

#### 2.1 HTML 结构

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="color-scheme" content="light dark">
    <title>小米笔记编辑器</title>
    <style>
        /* 基于 new_editor.html 的样式，添加深色模式支持 */
    </style>
</head>
<body>
    <div id="container">
        <div id="editor"></div>
    </div>
    <script src="https://cdn.ckeditor.com/ckeditor5/41.1.0/super-build/ckeditor.js"></script>
    <script src="format-converter.js"></script>
    <script>
        /* 编辑器初始化代码 */
    </script>
</body>
</html>
```

#### 2.2 CSS 样式

**基于 `new_editor.html` 的样式**:
- 容器样式
- 编辑器区域样式
- 深色模式支持（使用 CSS 变量）

**新增样式**:
- 小米笔记特定元素的样式（列表、引用、复选框等）
- 深色模式变量定义

#### 2.3 JavaScript 实现

##### 2.3.1 CKEditor 初始化

```javascript
ClassicEditor
    .create(document.getElementById('editor'), {
        // 移除 toolbar 配置
        toolbar: {
            items: [] // 空工具栏
        },
        // 其他配置...
    })
    .then(editor => {
        // 初始化 window.MiNoteWebEditor
        initializeEditor(editor);
    })
    .catch(error => {
        console.error(error);
    });
```

##### 2.3.2 window.MiNoteWebEditor 接口实现

**必需方法**:
- `loadContent(xmlContent: string): string` - 加载 XML 内容到编辑器
- `getContent(): string` - 获取当前内容并转换为 XML
- `setColorScheme(scheme: 'light' | 'dark'): string` - 设置颜色方案
- `forceSaveContent(): string` - 强制保存当前内容

**可选方法**（保留接口，但不实现功能）:
- `executeFormatAction(action: string, value?: string): string` - 格式操作（暂不实现）
- `insertImage(imageUrl: string, altText?: string): string` - 插入图片（暂不实现）

##### 2.3.3 内容变化监听

```javascript
editor.model.document.on('change:data', () => {
    // 延迟通知，避免频繁触发
    debounceNotifyContentChanged();
});
```

##### 2.3.4 深色模式支持

```javascript
function setColorScheme(scheme) {
    const root = document.documentElement;
    root.setAttribute('data-color-scheme', scheme);
    // 通知 CKEditor 更新主题（如果需要）
}
```

## 小米笔记 XML 格式规范

### 基本元素

1. **普通文本**: `<text indent="1">内容</text>\n`
2. **大标题**: `<text indent="1"><size>标题</size></text>\n`
3. **二级标题**: `<text indent="1"><mid-size>标题</mid-size></text>\n`
4. **三级标题**: `<text indent="1"><h3-size>标题</h3-size></text>\n`
5. **加粗**: `<text indent="1"><b>加粗</b></text>\n`
6. **斜体**: `<text indent="1"><i>斜体</i></text>\n`
7. **下划线**: `<text indent="1"><u>下划线</u></text>\n`
8. **删除线**: `<text indent="1"><delete>删除线</delete></text>\n`
9. **高亮**: `<text indent="1"><background color="#9affe8af">高亮</background></text>\n`
10. **无序列表**: `<bullet indent="1" />内容\n`
11. **有序列表**: `<order indent="1" inputNumber="0" />内容\n`
    - 第一行 inputNumber 为实际值（0-based），后续行为 0
12. **复选框**: `<input type="checkbox" indent="1" level="3" />内容\n`
13. **分割线**: `<hr />\n`
14. **引用块**: `<quote><text indent="1">内容1</text>\n<text indent="1">内容2</text></quote>\n`
15. **对齐方式**: 
    - 居左（默认）: `<text indent="1">内容</text>\n`
    - 居中: `<text indent="1"><center>内容</center></text>\n`
    - 居右: `<text indent="1"><right>内容</right></text>\n`

## 实现步骤

### 步骤 1: 创建 format-converter.js
1. 实现 `XMLToHTMLConverter` 类
2. 实现 `HTMLToXMLConverter` 类
3. 实现辅助函数
4. 导出转换器类供外部使用

### 步骤 2: 重写 editor.html
1. 复制 `new_editor.html` 的基础结构
2. 移除 toolbar 配置
3. 引入 `format-converter.js`
4. 实现 `window.MiNoteWebEditor` 接口
5. 添加深色模式支持
6. 实现内容变化监听

### 步骤 3: 测试和验证
1. 测试 XML 到 HTML 的转换
2. 测试 HTML 到 XML 的转换
3. 测试与 Swift 的交互
4. 测试深色模式切换
5. 测试各种格式的渲染和转换

## 注意事项

1. **有序列表处理**: 需要正确处理连续有序列表的 inputNumber 规则
2. **引用块处理**: 引用块可能包含多行，需要正确处理开始和结束标签
3. **富文本嵌套**: 支持多种格式的嵌套（如加粗+斜体+高亮）
4. **性能优化**: 对于大量内容，考虑使用缓存或批量处理
5. **错误处理**: 添加适当的错误处理和日志记录
6. **兼容性**: 确保与现有 Swift 代码的接口兼容

## 文件清单

- `Sources/MiNoteLibrary/Web/editor.html` - 重写后的主编辑器文件
- `Sources/MiNoteLibrary/Web/format-converter.js` - 格式转换模块（新建）




