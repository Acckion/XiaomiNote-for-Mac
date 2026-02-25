#!/bin/bash
#
# 架构检查脚本
#
# 用法:
#   ./scripts/check-architecture.sh              # 默认模式：报告违规，退出码始终为 0
#   ./scripts/check-architecture.sh --strict     # 严格模式：存在 error 级别违规时退出码为 1
#   ./scripts/check-architecture.sh --self-test  # 自检模式：验证规则本身的正确性
#
# 参考: docs/adr/README.md

set -euo pipefail

STRICT=false
SELF_TEST=false
ERRORS=0
WARNINGS=0

# 参数解析
for arg in "$@"; do
    case "$arg" in
        --strict) STRICT=true ;;
        --self-test) SELF_TEST=true ;;
        --help|-h)
            echo "用法: $0 [--strict] [--self-test]"
            echo "  --strict     存在 error 级别违规时返回非零退出码"
            echo "  --self-test  运行规则自检用例"
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
# Domain 层禁止 import AppKit/SwiftUI
# 扫描范围：Sources/Model + Sources/Features/*/Domain
# 参考: ADR-001
# ============================================================
check_domain_imports() {
    local patterns=("Sources/Model" "Sources/Features/*/Domain")
    for pattern in "${patterns[@]}"; do
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

# ============================================================
# RULE-002: .shared 新增检查
# 非允许列表文件禁止声明 static let/var shared
# 参考: ADR-004
# ============================================================

# 允许保留 .shared 的文件列表
ALLOWED_SHARED=(
    "Sources/Service/Core/LogService.swift"
    "Sources/Store/DatabaseService.swift"
    "Sources/Core/EventBus/EventBus.swift"
    "Sources/Service/Audio/AudioPlayerService.swift"
    "Sources/Service/Audio/AudioRecorderService.swift"
    "Sources/Service/Audio/AudioDecryptService.swift"
    "Sources/Features/Auth/Infrastructure/PrivateNotesPasswordManager.swift"
    "Sources/State/ViewOptionsManager.swift"
    "Sources/Service/Core/PerformanceService.swift"
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
# 自检模式
# ============================================================
run_self_test() {
    local test_dir
    test_dir=$(mktemp -d)
    local pass=0
    local fail=0

    echo "自检开始..."
    echo ""

    # RULE-001 反样本：Domain 目录中有 import AppKit
    mkdir -p "$test_dir/Sources/Features/TestDomain/Domain"
    echo 'import AppKit' > "$test_dir/Sources/Features/TestDomain/Domain/Bad.swift"
    echo 'import Foundation' >> "$test_dir/Sources/Features/TestDomain/Domain/Bad.swift"

    ERRORS=0
    local saved_dir
    saved_dir=$(pwd)
    cd "$test_dir"
    check_domain_imports
    cd "$saved_dir"

    if [ "$ERRORS" -gt 0 ]; then
        echo "[PASS] RULE-001 反样本：检测到 Domain 层 import AppKit 违规"
        pass=$((pass + 1))
    else
        echo "[FAIL] RULE-001 反样本：未检测到 Domain 层 import AppKit 违规"
        fail=$((fail + 1))
    fi

    # RULE-001 正样本：Domain 目录中无 AppKit/SwiftUI import
    mkdir -p "$test_dir/Sources/Features/TestClean/Domain"
    echo 'import Foundation' > "$test_dir/Sources/Features/TestClean/Domain/Good.swift"
    rm "$test_dir/Sources/Features/TestDomain/Domain/Bad.swift"

    ERRORS=0
    cd "$test_dir"
    check_domain_imports
    cd "$saved_dir"

    if [ "$ERRORS" -eq 0 ]; then
        echo "[PASS] RULE-001 正样本：合规文件未报告违规"
        pass=$((pass + 1))
    else
        echo "[FAIL] RULE-001 正样本：合规文件被误报为违规"
        fail=$((fail + 1))
    fi

    # RULE-001 arch-ignore 豁免样本
    echo 'import AppKit // arch-ignore' > "$test_dir/Sources/Features/TestDomain/Domain/Exempt.swift"

    ERRORS=0
    cd "$test_dir"
    check_domain_imports
    cd "$saved_dir"

    if [ "$ERRORS" -eq 0 ]; then
        echo "[PASS] RULE-001 豁免样本：arch-ignore 标注正确跳过"
        pass=$((pass + 1))
    else
        echo "[FAIL] RULE-001 豁免样本：arch-ignore 标注未生效"
        fail=$((fail + 1))
    fi

    # 清理
    rm -rf "$test_dir"

    echo ""
    echo "自检完成: $pass 通过, $fail 失败"

    if [ "$fail" -gt 0 ]; then
        exit 1
    fi
    exit 0
}

# ============================================================
# 执行入口
# ============================================================
if [ "$SELF_TEST" = true ]; then
    run_self_test
fi

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
