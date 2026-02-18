#!/bin/bash
# 代码格式化脚本

set -e

echo "运行 SwiftFormat..."
if command -v swiftformat &> /dev/null; then
    swiftformat Sources/ Tests/ --config .swiftformat
    echo "格式化完成"
else
    echo "SwiftFormat 未安装，请执行: brew install swiftformat"
    exit 1
fi
