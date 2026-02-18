#!/bin/bash
# 代码检查脚本

set -e

echo "运行 SwiftLint..."
if command -v swiftlint &> /dev/null; then
    swiftlint lint --config .swiftlint.yml
else
    echo "SwiftLint 未安装，请执行: brew install swiftlint"
    exit 1
fi

echo "运行 SwiftFormat 检查..."
if command -v swiftformat &> /dev/null; then
    swiftformat --lint Sources/ Tests/ --config .swiftformat
else
    echo "SwiftFormat 未安装，请执行: brew install swiftformat"
    exit 1
fi

echo "检查通过"
