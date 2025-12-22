# 使用 CKEditor 库的可行性分析

## 执行摘要

**结论**：技术上可行，但需要大量定制工作，**不推荐**。

**推荐方案**：继续优化当前实现，解决光标管理和状态管理问题。

---

## 1. 当前实现的问题分析

### 1.1 光标管理问题

**当前问题**：
- 格式切换时光标位置处理不完善
- 在格式元素边界处光标行为异常
- 取消格式后新输入内容可能继承格式

**影响**：
- 用户体验不佳
- 格式状态不一致

### 1.2 状态管理问题

**当前问题**：
- 格式状态检测可能不准确
- 状态同步延迟
- 嵌套格式处理不完善

**影响**：
- 格式菜单状态不准确
- 格式应用/取消不一致

---

## 2. CKEditor 5 的优势

### 2.1 成熟的光标管理

✅ **自动光标管理**
- 格式切换时自动优化光标位置
- 处理各种边界情况
- 经过大量测试和优化

### 2.2 完善的状态管理

✅ **准确的状态检测**
- 基于数据模型，状态检测准确
- 自动同步到工具栏
- 支持嵌套格式

### 2.3 丰富的功能

✅ **内置功能**
- 撤销/重做
- 粘贴处理
- 键盘快捷键
- 跨浏览器兼容

---

## 3. 使用 CKEditor 的挑战

### 3.1 小米笔记格式的特殊性 ⚠️

#### 问题 1：自定义 XML 格式

**小米笔记格式特点**：
```xml
<text indent="1">普通文本</text>
<bullet indent="1" />无序列表
<order indent="1" inputNumber="0" />有序列表
<input type="checkbox" indent="1" level="3" />checkbox
<quote><text indent="1">引用</text></quote>
<text indent="1"><size>大标题</size></text>
<text indent="1"><mid-size>二级标题</mid-size></text>
<text indent="1"><h3-size>三级标题</h3-size></text>
<text indent="1"><background color="#9affe8af">高亮</background></text>
<text indent="1"><center>居中</center></text>
<text indent="1"><right>居右</right></text>
```

**CKEditor 默认格式**：
- 使用标准 HTML（`<p>`, `<h1>`, `<ul>`, `<ol>` 等）
- 不支持自定义 XML 标签（`<text>`, `<bullet>`, `<order>` 等）
- 不支持自定义属性（`indent`, `inputNumber`, `level` 等）

**需要的定制工作**：
1. 创建自定义数据格式转换器
2. 实现 XML ↔ HTML 双向转换
3. 自定义插件支持小米笔记格式
4. 估计工作量：**2-3 周**

#### 问题 2：有序列表的特殊规则

**小米笔记规则**：
- `inputNumber` 属性控制起始编号
- 连续列表的后续项 `inputNumber="0"`
- 需要自动计算显示编号

**CKEditor 默认行为**：
- 使用标准 HTML `<ol start="...">`
- 不支持 `inputNumber` 属性
- 需要自定义插件

**需要的定制工作**：
1. 自定义有序列表插件
2. 处理 `inputNumber` 逻辑
3. 估计工作量：**1 周**

#### 问题 3：Checkbox 的特殊格式

**小米笔记格式**：
```xml
<input type="checkbox" indent="1" level="3" />checkbox文本
```

**CKEditor 默认行为**：
- 有 `todoList` 插件，但格式不同
- 不支持 `indent` 和 `level` 属性
- 需要自定义插件

**需要的定制工作**：
1. 自定义 checkbox 插件
2. 处理 `indent` 和 `level` 属性
3. 估计工作量：**1 周**

### 3.2 与 Swift 的集成 ⚠️

#### 当前集成方式

```javascript
// 当前实现
window.MiNoteWebEditor = {
    loadContent: function(xmlContent) { ... },
    getContent: function() { return xmlContent; },
    executeFormatAction: function(action, value) { ... },
    // ...
};

// Swift 通信
window.webkit.messageHandlers.editorBridge.postMessage({
    type: 'contentChanged',
    content: xmlContent
});
```

#### CKEditor 集成方式

**需要的适配工作**：
1. 包装 CKEditor API 为 `window.MiNoteWebEditor` 接口
2. 实现 XML ↔ HTML 转换层
3. 适配事件系统（`change:data` → Swift 消息）
4. 估计工作量：**1 周**

### 3.3 许可证问题 ⚠️

**GPL 许可证要求**：
- 如果项目是闭源商业软件，需要购买商业许可证
- 商业许可证费用（需要查询当前价格）

**替代方案**：
- 使用其他开源编辑器（Quill.js, TinyMCE 等）
- 继续使用当前实现

---

## 4. 技术实现方案

### 4.1 方案 A：完全使用 CKEditor（不推荐）

#### 实现步骤

1. **引入 CKEditor 5**
   ```html
   <script src="https://cdn.ckeditor.com/ckeditor5/41.1.0/super-build/ckeditor.js"></script>
   ```

2. **创建自定义数据格式转换器**
   ```javascript
   // 需要实现
   class MiNoteDataProcessor {
       toData(html) {
           // HTML → XML 转换
           // 使用现有的 html-to-xml.js 逻辑
       }
       
       toView(xml) {
           // XML → HTML 转换
           // 使用现有的 xml-to-html.js 逻辑
       }
   }
   ```

3. **创建自定义插件**
   - Checkbox 插件（支持 `indent`, `level`）
   - 有序列表插件（支持 `inputNumber`）
   - 标题插件（支持 `<size>`, `<mid-size>`, `<h3-size>`）
   - 对齐插件（支持 `<center>`, `<right>`）
   - 高亮插件（支持 `<background color="...">`）

4. **集成 Swift 通信**
   ```javascript
   editor.model.document.on('change:data', () => {
       const xmlContent = miNoteDataProcessor.toData(editor.getData());
       window.webkit.messageHandlers.editorBridge.postMessage({
           type: 'contentChanged',
           content: xmlContent
       });
   });
   ```

#### 工作量估算

| 任务 | 工作量 | 难度 |
|------|--------|------|
| 数据格式转换器 | 1 周 | 中 |
| Checkbox 插件 | 1 周 | 中 |
| 有序列表插件 | 1 周 | 中 |
| 标题插件 | 3 天 | 低 |
| 对齐插件 | 2 天 | 低 |
| 高亮插件 | 2 天 | 低 |
| Swift 集成 | 1 周 | 中 |
| 测试和调试 | 1 周 | 高 |
| **总计** | **6-7 周** | **高** |

#### 风险

- ⚠️ CKEditor 插件开发学习曲线陡峭
- ⚠️ 自定义格式可能与其他功能冲突
- ⚠️ 需要深入理解 CKEditor 架构
- ⚠️ 维护成本高（需要跟随 CKEditor 更新）

### 4.2 方案 B：混合方案（部分推荐）

#### 实现思路

- 使用 CKEditor 处理**标准格式**（加粗、斜体、下划线等）
- 保留当前实现处理**小米笔记特殊格式**（checkbox、列表、XML 转换）

#### 实现步骤

1. **引入 CKEditor 5（仅用于标准格式）**
2. **禁用不需要的功能**（列表、标题等）
3. **保留当前实现**处理：
   - XML ↔ HTML 转换
   - Checkbox
   - 小米笔记特殊格式
4. **集成两者**：
   - CKEditor 处理标准格式
   - 当前实现处理特殊格式

#### 工作量估算

| 任务 | 工作量 | 难度 |
|------|--------|------|
| CKEditor 集成 | 3 天 | 中 |
| 功能分离 | 1 周 | 高 |
| 集成测试 | 1 周 | 高 |
| **总计** | **2-3 周** | **高** |

#### 风险

- ⚠️ 两套系统可能冲突
- ⚠️ 维护复杂度增加
- ⚠️ 用户体验可能不一致

### 4.3 方案 C：优化当前实现（推荐）⭐

#### 实现思路

- 不引入 CKEditor
- 优化当前实现的光标管理和状态管理
- 参考 CKEditor 的实现方式，改进现有代码

#### 改进重点

1. **改进光标管理**
   - 参考 CKEditor 的光标处理逻辑
   - 使用更可靠的方法（如 `removeFormat` 命令）
   - 优化边界情况处理

2. **改进状态管理**
   - 改进格式状态检测算法
   - 添加状态缓存机制
   - 优化状态同步时机

3. **添加测试**
   - 覆盖各种边界情况
   - 确保格式切换正确

#### 工作量估算

| 任务 | 工作量 | 难度 |
|------|--------|------|
| 光标管理优化 | 1 周 | 中 |
| 状态管理优化 | 1 周 | 中 |
| 测试和调试 | 1 周 | 中 |
| **总计** | **3 周** | **中** |

#### 优势

- ✅ 无许可证问题
- ✅ 完全可控
- ✅ 已适配小米笔记格式
- ✅ 维护成本低
- ✅ 工作量相对较少

---

## 5. 对比分析

| 方案 | 工作量 | 难度 | 风险 | 维护成本 | 推荐度 |
|------|--------|------|------|---------|--------|
| **方案 A：完全使用 CKEditor** | 6-7 周 | 高 | 高 | 高 | ⭐⭐ |
| **方案 B：混合方案** | 2-3 周 | 高 | 中 | 中 | ⭐⭐⭐ |
| **方案 C：优化当前实现** | 3 周 | 中 | 低 | 低 | ⭐⭐⭐⭐⭐ |

---

## 6. 推荐方案

### 推荐：方案 C（优化当前实现）

#### 理由

1. **工作量最少**：3 周 vs 6-7 周
2. **风险最低**：不需要引入新框架
3. **维护成本低**：代码完全可控
4. **已适配格式**：不需要重新实现 XML 转换
5. **无许可证问题**：完全自主

#### 实施步骤

1. **第 1 周：优化光标管理**
   - 改进 `clearFormatAtCursor` 方法
   - 使用 `removeFormat` 命令
   - 优化边界情况处理

2. **第 2 周：优化状态管理**
   - 改进 `checkFormatState` 方法
   - 添加状态缓存
   - 优化同步时机

3. **第 3 周：测试和调试**
   - 覆盖各种场景
   - 修复发现的问题
   - 性能优化

---

## 7. 如果必须使用 CKEditor

### 前提条件

1. **确认许可证**：如果是闭源商业软件，需要购买商业许可证
2. **评估成本**：许可证费用 + 开发成本 + 维护成本
3. **准备时间**：至少 6-7 周开发时间

### 实施建议

1. **分阶段实施**：
   - 阶段 1：基础集成（2 周）
   - 阶段 2：自定义插件（3 周）
   - 阶段 3：测试和优化（2 周）

2. **保留现有代码**：
   - 作为参考和备份
   - 可以复用 XML 转换逻辑

3. **充分测试**：
   - 覆盖所有小米笔记格式
   - 测试各种边界情况

---

## 8. 总结

### 关键结论

1. **CKEditor 技术上可行**，但需要大量定制工作
2. **不推荐完全使用 CKEditor**，因为：
   - 工作量太大（6-7 周）
   - 需要深度定制
   - 许可证问题
   - 维护成本高

3. **推荐优化当前实现**，因为：
   - 工作量较少（3 周）
   - 风险低
   - 已适配小米笔记格式
   - 无许可证问题

### 最终建议

**优先选择方案 C（优化当前实现）**，如果 3 周后问题仍未解决，再考虑方案 B（混合方案）。

