# spec-131：架构门禁补全 — 设计

## 技术方案

### 1. RULE-001 扫描范围扩展

修改 `scripts/check-architecture.sh` 中的 `check_domain_imports` 函数：

```bash
check_domain_imports() {
    local dirs=("Sources/Model" "Sources/Features/*/Domain")
    for pattern in "${dirs[@]}"; do
        for target_dir in $pattern; do
            [ -d "$target_dir" ] || continue
            while IFS=: read -r file line content; do
                if echo "$content" | grep -q "// arch-ignore"; then
                    continue
                fi
                report_violation "RULE-001" "error" "$file" "$line" "Domain 层禁止 import AppKit/SwiftUI"
            done < <(grep -rn "import AppKit\|import SwiftUI" "$target_dir" 2>/dev/null || true)
        done
    done
}
```

关键点：使用 glob 展开 `Sources/Features/*/Domain`，遍历所有域的 Domain 目录。

### 2. Note.swift 修复

直接移除 `import AppKit`。该文件只使用 Foundation 类型（String、Date、Int、JSONSerialization）和 LogService。LogService 不依赖 AppKit。

### 3. 自检模式

在脚本中增加 `--self-test` 参数处理：
- 创建临时目录，写入正/反样本文件
- 运行 `check_domain_imports` 对临时目录
- 验证反样本产生 error，正样本不产生 error
- 清理临时目录

### 4. 文档清理

更新 `architecture-next.md` 中已完成事项的描述，将 MenuActionHandler 相关内容标记为已完成。

## 影响范围

- `scripts/check-architecture.sh`
- `Sources/Features/Notes/Domain/Note.swift`
- `docs/architecture-next.md`
- `docs/refactor_all.md`（如有相关内容）
