# spec-132：关键链路回归测试

## 背景

顶层重构后的关键链路（Command 菜单调度、导入真实写入、同步队列退避）缺少自动化回归测试，当前仍以人工回归为主。后续大规模目录迁移前必须建立自动化安全网。

## 需求

### REQ-1：Command 链路测试

验证 CommandDispatcher 能正确调度到具体 Command 的 execute 方法：
- 构造 CommandDispatcher（需要 AppCoordinator 或 mock）
- 调用 dispatch 传入具体 Command
- 断言 Command 的 execute 被调用且 context 正确传递

至少覆盖：CreateNoteCommand、SyncCommand、ShowSettingsCommand。

### REQ-2：导入流程测试

验证 ImportContentConverter 的转换产出非空且格式正确：
- `plainTextToXML`：输入纯文本，输出包含 `<text indent="1">` 的 XML
- `markdownToXML`：输入 Markdown 标题/列表，输出包含对应 XML 标签
- `rtfToXML`：输入 RTF 数据，输出非空 XML

### REQ-3：同步队列测试

验证 OperationProcessor / UnifiedOperationQueue 的关键路径：
- 文件丢失失败：操作引用的文件不存在时，操作标记为失败而非崩溃
- nextRetryAt 门控：未到重试时间的操作被跳过
- 二次入队：失败操作重新入队后 retryCount 递增

### REQ-4：组合根冒烟测试

验证 AppCoordinatorAssembler.buildDependencies() 产出的关键服务非空：
- noteStore、syncEngine、noteListState、noteEditorState、folderState、syncState、authState 均非 nil
- networkModule、syncModule、editorModule、audioModule 均非 nil

## 验收标准

1. 所有新增测试通过 `xcodebuild test`
2. 测试文件组织在 `Tests/` 对应子目录下
3. 测试不依赖网络或外部服务
