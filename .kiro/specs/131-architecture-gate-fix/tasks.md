# spec-131：架构门禁补全 — 任务清单

参考文档：
- 需求：`.kiro/specs/131-architecture-gate-fix/requirements.md`
- 设计：`.kiro/specs/131-architecture-gate-fix/design.md`

---

## 任务 1：扩展 RULE-001 扫描范围

- [ ] 1. 修改 check-architecture.sh 的 RULE-001 扫描逻辑
  - [ ] 1.1 修改 `check_domain_imports` 函数，扫描 `Sources/Model` + `Sources/Features/*/Domain`（glob 展开）
  - [ ] 1.2 更新函数头部注释，反映新的扫描范围
  - [ ] 1.3 运行 `./scripts/check-architecture.sh` 验证能检测到 `Note.swift` 的 `import AppKit` 违规

## 任务 2：修复现存 Domain 违规

- [ ] 2. 修复 Note.swift
  - [ ] 2.1 移除 `Sources/Features/Notes/Domain/Note.swift` 中的 `import AppKit`
  - [ ] 2.2 编译验证：`xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -30`
  - [ ] 2.3 运行 `./scripts/check-architecture.sh --strict` 确认 0 error

## 任务 3：增加架构脚本自检用例

- [ ] 3. 实现 --self-test 模式
  - [ ] 3.1 在 `check-architecture.sh` 中增加 `--self-test` 参数解析
  - [ ] 3.2 实现自检函数：创建临时目录，写入 RULE-001 正/反样本，运行检查，验证结果，清理
  - [ ] 3.3 运行 `./scripts/check-architecture.sh --self-test` 验证通过

## 任务 4：清理文档残留

- [ ] 4. 更新过时文档
  - [ ] 4.1 更新 `docs/architecture-next.md`：将 MenuActionHandler 相关描述标记为已完成（第 2.2 节、第 6.3 节、第 7.4 节）
  - [ ] 4.2 检查 `docs/refactor_all.md`，更新或移除 MenuActionHandler 相关描述
  - [ ] 4.3 提交所有变更
