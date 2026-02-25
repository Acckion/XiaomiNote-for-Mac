# spec-132：关键链路回归测试 — 任务清单

参考文档：
- 需求：`.kiro/specs/132-regression-tests/requirements.md`
- 设计：`.kiro/specs/132-regression-tests/design.md`

---

## 任务 1：Command 链路测试

- [ ] 1. 创建 Command 调度测试
  - [ ] 1.1 创建 `Tests/CommandTests/CommandDispatcherTests.swift`
  - [ ] 1.2 测试 CommandDispatcher 能正确调度 SyncCommand（不崩溃、context 传递正确）
  - [ ] 1.3 测试 CommandDispatcher 能正确调度 CreateNoteCommand
  - [ ] 1.4 编译并运行测试验证

## 任务 2：导入流程测试

- [ ] 2. 创建导入内容转换测试
  - [ ] 2.1 创建 `Tests/ImportTests/ImportContentConverterTests.swift`
  - [ ] 2.2 测试 `plainTextToXML`：输入纯文本，输出包含 `<text indent="1">` 和原始文本
  - [ ] 2.3 测试 `markdownToXML`：输入 Markdown 标题，输出包含对应 XML 标签
  - [ ] 2.4 测试 `markdownToXML`：输入 Markdown 列表，输出包含列表 XML 标签
  - [ ] 2.5 编译并运行测试验证

## 任务 3：同步队列测试

- [ ] 3. 创建同步队列关键路径测试
  - [ ] 3.1 创建 `Tests/SyncTests/OperationQueueTests.swift`
  - [ ] 3.2 测试 nextRetryAt 门控：未到重试时间的操作被跳过
  - [ ] 3.3 测试失败操作重新入队后 retryCount 递增
  - [ ] 3.4 编译并运行测试验证

## 任务 4：组合根冒烟测试

- [ ] 4. 创建装配器冒烟测试
  - [ ] 4.1 创建 `Tests/CoordinatorTests/AssemblerSmokeTests.swift`
  - [ ] 4.2 测试 `AppCoordinatorAssembler.buildDependencies()` 产出的关键服务均非 nil
  - [ ] 4.3 编译并运行测试验证

## 任务 5：项目配置与提交

- [ ] 5. 更新项目配置
  - [ ] 5.1 执行 `xcodegen generate` 确保新测试文件被包含
  - [ ] 5.2 运行全量测试：`xcodebuild test -project MiNoteMac.xcodeproj -scheme MiNoteMac -destination 'platform=macOS'`
  - [ ] 5.3 提交所有变更
