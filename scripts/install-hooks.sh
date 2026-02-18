#!/bin/bash
# 安装 Git hooks

HOOK_DIR=".git/hooks"

cat > "$HOOK_DIR/pre-commit" << 'EOF'
#!/bin/bash
# Pre-commit hook: 检查暂存的 Swift 文件

STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.swift$')

if [ -z "$STAGED_FILES" ]; then
    exit 0
fi

# SwiftFormat 检查
if command -v swiftformat &> /dev/null; then
    echo "$STAGED_FILES" | while read file; do
        if [ -f "$file" ]; then
            swiftformat --lint "$file" --config .swiftformat 2>/dev/null
            if [ $? -ne 0 ]; then
                echo "格式检查失败: $file"
                echo "请执行 ./scripts/format.sh 格式化代码"
                exit 1
            fi
        fi
    done
    if [ $? -ne 0 ]; then
        exit 1
    fi
fi

# SwiftLint 检查
if command -v swiftlint &> /dev/null; then
    echo "$STAGED_FILES" | xargs swiftlint lint --config .swiftlint.yml --quiet 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "Lint 检查失败，请修复后重新提交"
        exit 1
    fi
fi

exit 0
EOF

chmod +x "$HOOK_DIR/pre-commit"
echo "Git hooks 安装完成"
