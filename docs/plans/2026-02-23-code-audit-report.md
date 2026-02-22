# 代码审计报告 2026-02-23

## 审计背景

在完成以下大规模重构后，对项目代码质量进行全面审计：
- spec 98：状态管理重构（NotesViewModel -> State 对象）
- spec 100：架构重构（EventBus 驱动 + State 对象）
- spec 101：Cookie 自动刷新重构
- spec 102：MiNoteService 拆分（APIClient/NoteAPI/FolderAPI/FileAPI/SyncAPI/UserAPI）
- spec 103：编辑器桥接层重构（NativeEditorView + NativeEditorContext 拆分）
- spec 104：文件上传操作队列

## 整体评价

项目架构良好，评分 8.5/10。经过多轮重构，核心模块（网络层、状态管理、同步引擎、编辑器）已经具备清晰的职责划分。

## 需要重构的模块

### P1：MainWindowController.swift（3,239 行）

路径：`Sources/Window/Controllers/MainWindowController.swift`

问题：8+ 职责混杂在一个文件中：
1. 核心窗口管理（属性 + 初始化 + 生命周期 + 分割视图 + 窗口状态）~600 行
2. NSToolbarDelegate（toolbar 方法 + 工具栏项构建）~500 行
3. 动作方法（格式/编辑/视图选项/笔记操作/离线操作/查找/附件）~1,200 行
4. 音频面板管理（显示/隐藏/录制完成/播放）~300 行
5. 状态监听（setupStateObservers）~150 行
6. 搜索功能（NSSearchFieldDelegate + 搜索筛选菜单）~200 行
7. 其他代理（NSWindowDelegate / NSMenuDelegate / NSUserInterfaceValidations）~300 行

建议：按职责拆分为 extension 文件（方案 A，参考 spec 103 模式）。

### P2：MenuActionHandler.swift（1,345 行）

路径：`Sources/App/MenuActionHandler.swift`

问题：107 个菜单方法集中在一个文件中，按功能域拆分可提高可维护性。

### P3：FormatManager.swift（1,189 行）

路径：`Sources/View/NativeEditor/Format/FormatManager.swift`

问题：格式逻辑混杂，inline 格式和 block 格式处理交织。

## 小问题

- `WindowManager.swift` 和 `MemoryCacheManager.swift` 中有 `print()` 残留，应替换为 `LogService.shared`
