# Implementation Plan

[Overview]
优化小米笔记macOS客户端的Web编辑器光标管理，解决光标在图片、列表项、引用块等元素中意外跳动的问题，参考CKEditor 5的Selection Post-Fixer机制和Position对象管理，提供稳定可靠的光标行为。

当前编辑器使用contenteditable div直接操作DOM，光标管理依赖浏览器Selection API，存在光标位置不稳定、在特定元素（图片、列表、引用块）中意外跳动的问题。通过分析CKEditor 5的架构，我们发现其使用Model-View架构和Selection Post-Fixer机制确保光标位置始终有效。本计划将分阶段实施改进，从短期修复到长期架构优化，逐步提升光标管理的稳定性和可靠性。

[Types]  
定义光标位置表示和验证的类型系统，包括Position对象、Selection范围和Schema验证规则。

详细类型定义：

1. **Position 对象**
   ```javascript
   class Position {
       constructor(path, offset, anchorText = null) {
           this.path = path;           // 节点路径数组，如[0, 1, 2]
           this.offset = offset;       // 在文本节点中的偏移量
           this.anchorText = anchorText; // 锚点文本，用于恢复
           this.timestamp = Date.now();
       }
       
       // 转换为DOM位置
       toDOMPosition(editor) {
           // 根据path和offset找到DOM节点和位置
       }
       
       // 从DOM位置创建
       static fromDOM(domPosition, editor) {
           // 从Selection对象创建Position
       }
       
       // 验证位置是否有效
       isValid(editor) {
           // 检查路径和偏移量是否在有效范围内
       }
   }
   ```

2. **Selection 范围**
   ```javascript
   class SelectionRange {
       constructor(start, end) {
           this.start = start; // Position对象
           this.end = end;     // Position对象
           this.isCollapsed = start.path === end.path && start.offset === end.offset;
       }
       
       // 转换为DOM Selection
       toDOMSelection(editor) {
           // 创建浏览器Selection对象
       }
       
       // 验证选择范围是否有效
       isValid(editor) {
           return this.start.isValid(editor) && this.end.isValid(editor);
       }
   }
   ```

3. **Schema 验证规则**
   ```javascript
   const schema = {
       // 允许光标出现的节点类型
       allowedCursorParents: ['P', 'LI', 'BLOCKQUOTE', 'DIV', 'SPAN'],
       
       // 不允许光标出现的节点类型
       disallowedCursorNodes: ['IMG', 'HR', 'BR'],
       
       // 验证位置是否有效
       validatePosition(position, editor) {
           const node = position.getNode(editor);
           // 检查节点类型
           if (this.disallowedCursorNodes.includes(node.nodeName)) {
               return this.getNearestValidPosition(position, editor);
           }
           return position;
       },
       
       // 获取最近的有效位置
       getNearestValidPosition(position, editor) {
           // 向上或向下查找最近的允许光标的位置
       }
   };
   ```

4. **光标状态枚举**
   ```javascript
   const CursorState = {
       STABLE: 'stable',        // 光标稳定
       NEEDS_NORMALIZATION: 'needs_normalization', // 需要规范化
       INVALID: 'invalid',      // 无效位置
       RESTORING: 'restoring'   // 正在恢复
   };
   ```

[Files]
修改现有文件和创建新文件，实现光标管理优化。

详细文件修改：

1. **新文件创建**
   - `Sources/MiNoteLibrary/Web/modules/cursor/position.js` - Position对象实现
   - `Sources/MiNoteLibrary/Web/modules/cursor/selection.js` - Selection范围实现
   - `Sources/MiNoteLibrary/Web/modules/cursor/schema.js` - Schema验证规则
   - `Sources/MiNoteLibrary/Web/modules/cursor/post-fixer.js` - Selection Post-Fixer实现
   - `Sources/MiNoteLibrary/Web/modules/cursor/manager.js` - 光标管理器

2. **现有文件修改**
   - `Sources/MiNoteLibrary/Web/modules/editor/editor-core.js`
     - 集成光标管理器
     - 修改DOM操作函数，使用光标管理器保存/恢复位置
     - 添加Selection Post-Fixer调用
   
   - `Sources/MiNoteLibrary/Web/modules/editor/cursor.js`
     - 重构现有光标保存/恢复逻辑
     - 集成新的Position对象
     - 添加Schema验证
   
   - `Sources/MiNoteLibrary/Web/modules/editor/editor-api.js`
     - 暴露新的光标管理API
     - 添加光标状态事件
   
   - `Sources/MiNoteLibrary/Web/editor.html`
     - 添加光标管理模块的script标签
     - 更新初始化代码

3. **配置文件更新**
   - `Sources/MiNoteLibrary/Web/modules/core/constants.js`
     - 添加光标相关常量
     - 配置Post-Fixer参数

4. **测试文件**
   - `Sources/MiNoteLibrary/Web/test/cursor-test.html` - 光标管理测试页面
   - `Sources/MiNoteLibrary/Web/test/cursor-test.js` - 光标测试脚本

[Functions]
修改和创建函数，实现光标管理的核心功能。

详细函数修改：

1. **新函数创建**
   - `Position.fromDOM(selection, editor)` - 从DOM Selection创建Position对象
   - `Position.toDOMPosition(editor)` - 将Position转换为DOM位置
   - `SelectionRange.normalize(editor)` - 规范化选择范围
   - `CursorManager.savePosition()` - 保存当前光标位置
   - `CursorManager.restorePosition(position)` - 恢复光标位置
   - `CursorManager.normalizePosition()` - 规范化光标位置
   - `SelectionPostFixer.fix(selection)` - 修复无效的选择位置
   - `SchemaValidator.validate(position)` - 验证位置有效性

2. **修改现有函数**
   - `normalizeCursorPosition()` → 重构为使用CursorManager
     - 添加Schema验证
     - 集成Post-Fixer机制
     - 改进错误处理
   
   - `_saveCursorPosition()` → 使用Position对象
     - 支持多种位置表示（路径、文本锚点）
     - 添加位置验证
     - 改进恢复可靠性
   
   - `_restoreCursorPosition()` → 使用Position对象
     - 多级回退机制优化
     - 添加位置验证
     - 改进错误恢复
   
   - `applyFormat()` 和相关格式函数
     - 在执行格式操作前保存光标位置
     - 操作后恢复并规范化位置
     - 添加格式操作后的Post-Fixer调用

3. **事件处理函数**
   - `handleSelectionChange()` - 处理selectionchange事件
     - 添加防抖处理
     - 集成位置验证
     - 触发光标状态事件
   
   - `handleInput()` - 处理input事件
     - 在内容变化后调用Post-Fixer
     - 更新光标位置状态

4. **工具函数**
   - `getNodeByPath(path, editor)` - 根据路径获取DOM节点
   - `getPathFromNode(node, editor)` - 获取节点的路径
   - `findNearestValidPosition(position, editor)` - 查找最近的有效位置
   - `comparePositions(pos1, pos2)` - 比较两个位置

[Classes]
创建新的类来管理光标状态和位置。

详细类定义：

1. **Position 类**
   ```javascript
   class Position {
       constructor(path, offset, anchorText = null) {
           this.path = path;
           this.offset = offset;
           this.anchorText = anchorText;
           this.timestamp = Date.now();
           this._cachedNode = null;
       }
       
       // 获取对应的DOM节点
       getNode(editor) {
           if (!this._cachedNode) {
               this._cachedNode = getNodeByPath(this.path, editor);
           }
           return this._cachedNode;
       }
       
       // 验证位置有效性
       isValid(editor) {
           const node = this.getNode(editor);
           if (!node) return false;
           
           // 检查节点类型是否允许光标
           if (schema.disallowedCursorNodes.includes(node.nodeName)) {
               return false;
           }
           
           // 检查偏移量是否有效
           if (node.nodeType === Node.TEXT_NODE) {
               return this.offset >= 0 && this.offset <= node.textContent.length;
           }
           
           return this.offset >= 0 && this.offset <= node.childNodes.length;
       }
       
       // 转换为字符串表示（用于存储）
       toString() {
           return JSON.stringify({
               path: this.path,
               offset: this.offset,
               anchorText: this.anchorText,
               timestamp: this.timestamp
           });
       }
       
       // 从字符串创建
       static fromString(str) {
           const data = JSON.parse(str);
           return new Position(data.path, data.offset, data.anchorText);
       }
   }
   ```

2. **CursorManager 类**
   ```javascript
   class CursorManager {
       constructor(editor) {
           this.editor = editor;
           this.currentPosition = null;
           this.lastStablePosition = null;
           this.postFixer = new SelectionPostFixer(editor);
           this.schema = new SchemaValidator();
           this.isRestoring = false;
           
           this._setupEventListeners();
       }
       
       // 保存当前光标位置
       savePosition() {
           const selection = window.getSelection();
           if (!selection.rangeCount) return null;
           
           const range = selection.getRangeAt(0);
           this.currentPosition = Position.fromDOM(range, this.editor);
           this.lastStablePosition = this.currentPosition;
           
           return this.currentPosition;
       }
       
       // 恢复光标位置
       restorePosition(position) {
           if (!position || this.isRestoring) return false;
           
           this.isRestoring = true;
           
           try {
               // 验证位置
               if (!position.isValid(this.editor)) {
                   position = this.schema.getNearestValidPosition(position, this.editor);
               }
               
               // 转换为DOM位置并设置
               const domPosition = position.toDOMPosition(this.editor);
               if (domPosition) {
                   const selection = window.getSelection();
                   selection.removeAllRanges();
                   selection.addRange(domPosition);
                   
                   // 应用Post-Fixer确保位置有效
                   this.postFixer.fix(selection);
                   
                   this.currentPosition = position;
                   this.lastStablePosition = position;
                   
                   return true;
               }
           } catch (error) {
               console.error('Failed to restore cursor position:', error);
           } finally {
               this.isRestoring = false;
           }
           
           return false;
       }
       
       // 规范化当前光标位置
       normalizePosition() {
           const selection = window.getSelection();
           if (!selection.rangeCount) return;
           
           this.postFixer.fix(selection);
           this.savePosition();
       }
       
       // 设置事件监听器
       _setupEventListeners() {
           this.editor.addEventListener('selectionchange', () => {
               if (this.isRestoring) return;
               
               this.savePosition();
           });
           
           this.editor.addEventListener('input', () => {
               // 在内容变化后延迟调用Post-Fixer
               setTimeout(() => {
                   this.normalizePosition();
               }, 10);
           });
       }
   }
   ```

3. **SelectionPostFixer 类**
   ```javascript
   class SelectionPostFixer {
       constructor(editor) {
           this.editor = editor;
           this.schema = new SchemaValidator();
       }
       
       // 修复选择位置
       fix(selection) {
           if (!selection.rangeCount) return;
           
           const range = selection.getRangeAt(0);
           const position = Position.fromDOM(range, this.editor);
           
           // 验证位置
           if (!position.isValid(this.editor)) {
               // 获取最近的有效位置
               const validPosition = this.schema.getNearestValidPosition(position, this.editor);
               
               // 恢复有效位置
               const validRange = validPosition.toDOMPosition(this.editor);
               if (validRange) {
                   selection.removeAllRanges();
                   selection.addRange(validRange);
               }
           }
           
           // 特殊处理：图片元素
           this._fixImageCursor(selection);
           
           // 特殊处理：列表项
           this._fixListItemCursor(selection);
           
           // 特殊处理：引用块
           this._fixBlockquoteCursor(selection);
       }
       
       // 修复图片光标位置
       _fixImageCursor(selection) {
           const range = selection.getRangeAt(0);
           const startContainer = range.startContainer;
           
           // 如果光标在图片内部或紧邻图片，调整到合适位置
           if (startContainer.nodeName === 'IMG' || 
               (startContainer.parentNode && startContainer.parentNode.nodeName === 'IMG')) {
               // 将光标移动到图片前面或后面
               this._moveCursorBesideImage(selection, startContainer);
           }
       }
       
       // 修复列表项光标位置
       _fixListItemCursor(selection) {
           const range = selection.getRangeAt(0);
           const startContainer = range.startContainer;
           
           // 检查是否在列表项中
           let li = startContainer;
           while (li && li.nodeName !== 'LI') {
               li = li.parentNode;
           }
           
           if (li) {
               // 确保光标在列表项文本内容中，不在列表标记上
               this._ensureCursorInListItemText(selection, li);
           }
       }
       
       // 修复引用块光标位置
       _fixBlockquoteCursor(selection) {
           const range = selection.getRangeAt(0);
           const startContainer = range.startContainer;
           
           // 检查是否在引用块中
           let blockquote = startContainer;
           while (blockquote && blockquote.nodeName !== 'BLOCKQUOTE') {
               blockquote = blockquote.parentNode;
           }
           
           if (blockquote) {
               // 确保光标在引用内容中
               this._ensureCursorInBlockquoteContent(selection, blockquote);
           }
       }
   }
   ```

4. **SchemaValidator 类**
   ```javascript
   class SchemaValidator {
       constructor() {
           this.allowedCursorParents = ['P', 'LI', 'BLOCKQUOTE', 'DIV', 'SPAN', 'B', 'I', 'U', 'S'];
           this.disallowedCursorNodes = ['IMG', 'HR', 'BR'];
           this.specialHandlingNodes = ['UL', 'OL', 'BLOCKQUOTE'];
       }
       
       // 验证位置有效性
       validate(position, editor) {
           const node = position.getNode(editor);
           if (!node) return false;
           
           // 检查节点类型
           if (this.disallowedCursorNodes.includes(node.nodeName)) {
               return false;
           }
           
           // 检查父节点类型
           let parent = node.parentNode;
           while (parent && parent !== editor) {
               if (this.specialHandlingNodes.includes(parent.nodeName)) {
                   // 需要特殊处理的节点类型
                   return this._validateSpecialNode(position, parent, editor);
               }
               parent = parent.parentNode;
           }
           
           return true;
       }
       
       // 获取最近的有效位置
       getNearestValidPosition(position, editor) {
           const node = position.getNode(editor);
           if (!node) return this._getDefaultPosition(editor);
           
           // 如果节点不允许光标，查找相邻的允许节点
           if (this.disallowedCursorNodes.includes(node.nodeName)) {
               return this._findAdjacentValidPosition(node, editor);
           }
           
           // 如果位置无效但节点有效，调整偏移量
           if (!this._validateOffset(position, node)) {
               return this._adjustOffset(position, node);
           }
           
           return position;
       }
       
       // 验证特殊节点中的位置
       _validateSpecialNode(position, specialNode, editor) {
           switch (specialNode.nodeName) {
               case 'UL':
               case 'OL':
                   // 在列表中的位置必须是在LI元素内
                   return this._validateInListItem(position, specialNode);
               case 'BLOCKQUOTE':
                   // 在引用块中的位置必须是在内容元素内
                   return this._validateInBlockquote(position, specialNode);
               default:
                   return true;
           }
       }
   }
   ```

[Dependencies]
添加新的依赖关系和更新现有依赖。

依赖修改详情：

1. **新依赖**
   - 无外部依赖，所有功能内置实现
   - 使用现代浏览器API：MutationObserver, Selection API, TreeWalker

2. **现有依赖更新**
   - `Sources/MiNoteLibrary/Web/modules/editor/editor-core.js` 依赖新的光标模块
   - `Sources/MiNoteLibrary/Web/modules/editor/cursor.js` 重构为使用新的类
   - 更新模块加载顺序，确保光标模块在编辑器初始化前加载

3. **配置依赖**
   - 更新Web编辑器配置，启用光标管理功能
   - 添加光标管理参数配置：
     ```javascript
     cursorManagement: {
         enabled: true,
         usePostFixer: true,
         postFixerDelay: 10, // ms
         validatePositions: true,
         maxRecoveryAttempts: 3
     }
     ```

[Testing]
测试光标管理功能的正确性和稳定性。

测试计划详情：

1. **单元测试**
   - Position对象创建和转换测试
   - Selection范围验证测试
   - Schema验证规则测试
   - Post-Fixer修复逻辑测试

2. **集成测试**
   - 光标保存/恢复测试
   - 图片元素光标行为测试
   - 列表项光标行为测试
   - 引用块光标行为测试
   - 格式操作后光标位置测试

3. **场景测试**
   - 在图片前输入文字测试
   - 在格式文本中切换格式测试
   - 列表项内光标移动测试
   - 复杂文档结构中的光标行为测试

4. **性能测试**
   - Post-Fixer性能影响测试
   - 光标保存/恢复性能测试
   - 大文档中的光标管理性能测试

[Implementation Order]
分阶段实施光标管理优化，从核心功能到完整集成，确保每个阶段都可测试和验证。

实施顺序详情：

1. **阶段1：核心类型和工具（1-2天）**
   - 创建Position类和SelectionRange类
   - 实现路径计算工具函数（getNodeByPath, getPathFromNode）
   - 创建基本测试验证核心功能

2. **阶段2：Schema验证系统（1-2天）**
   - 实现SchemaValidator类
   - 定义允许和不允许光标位置的规则
   - 实现特殊节点处理（图片、列表、引用块）
   - 添加Schema验证测试

3. **阶段3：Selection Post-Fixer（2-3天）**
   - 实现SelectionPostFixer类
   - 实现图片光标修复逻辑
   - 实现列表项光标修复逻辑
   - 实现引用块光标修复逻辑
   - 添加Post-Fixer测试

4. **阶段4：光标管理器（2-3天）**
   - 实现CursorManager类
   - 集成Position、SchemaValidator和Post-Fixer
   - 实现光标保存/恢复机制
   - 添加事件监听器集成
   - 添加光标管理器测试

5. **阶段5：现有代码集成（2-3天）**
   - 修改editor-core.js集成光标管理器
   - 重构cursor.js使用新的光标系统
   - 更新editor-api.js暴露新API
   - 修改editor.html加载新模块
   - 集成测试确保向后兼容

6. **阶段6：测试和优化（2-3天）**
   - 执行完整测试套件
   - 性能测试和优化
   - 修复发现的问题
   - 文档更新和代码清理

7. **阶段7：部署和监控（1天）**
   - 部署到测试环境
   - 监控光标行为改进
   - 收集用户反馈
   - 准备生产部署

每个阶段完成后都应进行测试，确保功能正确且不会破坏现有功能。阶段之间可以重叠进行，但核心依赖关系必须按顺序处理。
