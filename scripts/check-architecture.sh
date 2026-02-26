#!/bin/bash
#
# 架构检查脚本
#
# 用法:
#   ./scripts/check-architecture.sh           # 默认模式：报告违规，退出码始终为 0
#   ./scripts/check-architecture.sh --strict  # 严格模式：存在 error 级别违规时退出码为 1
#
# 参考: docs/adr/README.md

set -euo pipefail

STRICT=false
ERRORS=0
WARNINGS=0

# 参数解析
for arg in "$@"; do
    case "$arg" in
        --strict) STRICT=true ;;
        --help|-h)
            echo "用法: $0 [--strict]"
            echo "  --strict  存在 error 级别违规时返回非零退出码"
            exit 0
            ;;
    esac
done

# 输出违规信息
report_violation() {
    local rule="$1"
    local severity="$2"
    local file="$3"
    local line="$4"
    local message="$5"

    echo "[$rule] $file:$line - $message"

    if [ "$severity" = "error" ]; then
        ERRORS=$((ERRORS + 1))
    else
        WARNINGS=$((WARNINGS + 1))
    fi
}


# ============================================================
# RULE-001: Domain 层 import 检查
# Domain 层（Sources/Model/）禁止 import AppKit/SwiftUI
# 参考: ADR-001
# ============================================================
check_domain_imports() {
    local -a target_dirs=("Sources/Model" "Sources/Features/Notes/Domain" "Sources/Features/Editor/Domain" "Sources/Features/Sync/Domain" "Sources/Features/Auth/Domain" "Sources/Features/Folders/Domain" "Sources/Features/Search/Domain" "Sources/Features/Audio/Domain")

    for target_dir in "${target_dirs[@]}"; do
        if [ ! -d "$target_dir" ]; then
            continue
        fi

        while IFS=: read -r file line content; do
            # 跳过 arch-ignore 豁免
            if echo "$content" | grep -q "// arch-ignore"; then
                continue
            fi
            report_violation "RULE-001" "error" "$file" "$line" "Domain 层禁止 import AppKit/SwiftUI"
        done < <(grep -rn "import AppKit\|import SwiftUI" "$target_dir" 2>/dev/null || true)
    done
}

# ============================================================
# RULE-002: .shared 新增检查
# 非允许列表文件禁止声明 static let/var shared
# 参考: ADR-004
# ============================================================

# 允许保留 .shared 的文件列表
ALLOWED_SHARED=(
    "Sources/Shared/Kernel/LogService.swift"
    "Sources/Shared/Kernel/Store/DatabaseService.swift"
    "Sources/Shared/Kernel/EventBus/EventBus.swift"
    "Sources/Features/Audio/Infrastructure/AudioPlayerService.swift"
    "Sources/Features/Audio/Infrastructure/AudioRecorderService.swift"
    "Sources/Features/Audio/Infrastructure/AudioDecryptService.swift"
    "Sources/Features/Auth/Infrastructure/PrivateNotesPasswordManager.swift"
    "Sources/Shared/Kernel/ViewOptionsManager.swift"
    "Sources/Shared/Kernel/PerformanceService.swift"
)

check_shared_singletons() {
    while IFS=: read -r file line content; do
        # 跳过 arch-ignore 豁免
        if echo "$content" | grep -q "// arch-ignore"; then
            continue
        fi

        # 跳过允许列表中的文件
        local allowed=false
        for allowed_file in "${ALLOWED_SHARED[@]}"; do
            if [ "$file" = "$allowed_file" ]; then
                allowed=true
                break
            fi
        done

        if [ "$allowed" = true ]; then
            continue
        fi

        report_violation "RULE-002" "warning" "$file" "$line" "非允许列表文件禁止声明 .shared 单例"
    done < <(grep -rn "static let shared\|static var shared" Sources/ 2>/dev/null || true)
}

# ============================================================
# RULE-003: EventBus 生命周期检查
# EventBus 订阅需有生命周期管理（Task 或 Cancellable）
# 参考: ADR-002
# ============================================================
check_eventbus_lifecycle() {
    while IFS=: read -r file line content; do
        # 跳过 arch-ignore 豁免
        if echo "$content" | grep -q "// arch-ignore"; then
            continue
        fi

        # 检查同一文件中是否有 Task/Cancellable 管理
        # 简单启发式：如果文件中包含 eventTask 或 cancellables 或 Task { 则认为有管理
        local has_lifecycle
        has_lifecycle=$(grep -c "eventTask\|cancellables\|Task {" "$file" 2>/dev/null || echo "0")

        if [ "$has_lifecycle" -eq 0 ]; then
            report_violation "RULE-003" "warning" "$file" "$line" "EventBus 订阅缺少生命周期管理"
        fi
    done < <(grep -rn "eventBus.*\.on(\|EventBus.*\.on(" Sources/ 2>/dev/null || true)
}

# ============================================================
# RULE-004: 网络主干检查
# 非 Network/ 目录禁止直接使用 URLSession
# 参考: ADR-003
# ============================================================
check_network_backbone() {
    while IFS=: read -r file line content; do
        # 跳过 Network/ 目录
        if echo "$file" | grep -q "Sources/Network/"; then
            continue
        fi

        # 跳过 arch-ignore 豁免
        if echo "$content" | grep -q "// arch-ignore"; then
            continue
        fi

        # 跳过测试和参考代码
        if echo "$file" | grep -q "Tests/\|References/"; then
            continue
        fi

        # 跳过已知的合理 URLSession 使用
        # PassTokenManager: Cookie 刷新需独立于 NetworkModule，避免循环依赖
        # ImageAttachment: 图片异步加载
        # DefaultAudioService: 音频流播放
        if echo "$file" | grep -q "PassTokenManager\|ImageAttachment\|DefaultAudioService"; then
            continue
        fi

        report_violation "RULE-004" "warning" "$file" "$line" "非 Network/ 目录禁止直接使用 URLSession"
    done < <(grep -rn "URLSession" Sources/ 2>/dev/null || true)
}


# ============================================================
# 执行所有检查
# ============================================================
echo "架构检查开始..."
echo ""

check_domain_imports
check_shared_singletons
check_eventbus_lifecycle
check_network_backbone

echo ""
TOTAL=$((ERRORS + WARNINGS))
echo "架构检查完成: $TOTAL 个违规 ($ERRORS error, $WARNINGS warning)"

# 退出码逻辑
if [ "$STRICT" = true ] && [ "$ERRORS" -gt 0 ]; then
    exit 1
fi

exit 0
