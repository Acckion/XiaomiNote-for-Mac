#!/bin/bash

# 创建 Xcode 项目文件的脚本
# 使用方法: ./create_xcode_project.sh

set -e

PROJECT_NAME="MiNoteMac"
PACKAGE_PATH="."
PROJECT_DIR="${PROJECT_NAME}.xcodeproj"

echo "正在创建 Xcode 项目..."

# 检查是否已存在项目文件
if [ -d "${PROJECT_DIR}" ]; then
    echo "警告: ${PROJECT_DIR} 已存在"
    read -p "是否要删除并重新创建? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "${PROJECT_DIR}"
    else
        echo "取消操作"
        exit 1
    fi
fi

# 使用 xcodebuild 生成项目（如果可用）
if command -v xcodebuild &> /dev/null; then
    echo "使用 xcodebuild 生成项目..."
    # 注意：xcodebuild 不能直接从 Package.swift 创建项目
    # 我们需要使用 Xcode 的 GUI 或者手动创建
    echo "请使用以下方法之一："
    echo "1. 在 Xcode 中: File → New → Project → macOS → App"
    echo "2. 或者直接打开 Package.swift (Xcode 会自动识别为 Swift Package)"
else
    echo "xcodebuild 未找到，请使用 Xcode GUI 创建项目"
fi

echo ""
echo "推荐方法："
echo "1. 打开 Xcode"
echo "2. 选择 File → Open..."
echo "3. 选择 Package.swift 文件"
echo "4. Xcode 会自动识别为 Swift Package"
echo ""
echo "然后在 Xcode 中："
echo "1. 选择 MiNoteMac 目标"
echo "2. Build Settings → 添加 ENABLE_DEBUG_DYLIB = YES (Debug 配置)"
echo "3. 现在可以正常使用预览功能了"

