#!/bin/bash

# 构建 Xcode 项目脚本
# 使用 XcodeGen 从 project.yml 生成 Xcode 项目

set -e

echo "🔨 开始构建 Xcode 项目..."

# 检查 XcodeGen 是否安装
if ! command -v xcodegen &> /dev/null; then
    echo "❌ 错误: XcodeGen 未安装"
    echo "请运行以下命令安装:"
    echo "  brew install xcodegen"
    exit 1
fi

# 检查 project.yml 是否存在
if [ ! -f "project.yml" ]; then
    echo "❌ 错误: project.yml 文件不存在"
    exit 1
fi

# 检查 RichTextKit-1.2 是否存在
if [ ! -d "RichTextKit-1.2" ]; then
    echo "❌ 错误: RichTextKit-1.2 目录不存在"
    echo "请确保 RichTextKit-1.2 在项目根目录中"
    exit 1
fi

# 清理旧的 Xcode 项目（可选）
if [ -d "MiNoteMac.xcodeproj" ]; then
    echo "📦 备份现有项目..."
    if [ -d "MiNoteMac.xcodeproj.backup" ]; then
        rm -rf MiNoteMac.xcodeproj.backup
    fi
    mv MiNoteMac.xcodeproj MiNoteMac.xcodeproj.backup
fi

# 生成 Xcode 项目
echo "🚀 使用 XcodeGen 生成项目..."
xcodegen generate

if [ $? -eq 0 ]; then
    echo "✅ Xcode 项目生成成功!"
    echo "📂 项目文件: MiNoteMac.xcodeproj"
    
    # 先构建 RichTextKit 包（确保它可以正常编译）
    echo "🔨 构建 RichTextKit 包..."
    cd RichTextKit-1.2
    swift build 2>&1 | grep -E "(error|Build complete)" || true
    cd ..
    
    # 解析 Swift Package 依赖
    echo "📦 解析 Swift Package 依赖..."
    xcodebuild -resolvePackageDependencies -project MiNoteMac.xcodeproj 2>&1 | grep -v "warning:" || true
    
    echo ""
    echo "✨ 完成! 现在可以在 Xcode 中打开项目了"
    echo "   打开命令: open MiNoteMac.xcodeproj"
    echo ""
    echo "💡 提示: 如果编译时仍然找不到 RichTextKit 模块，请："
    echo "   1. 在 Xcode 中打开项目"
    echo "   2. File → Packages → Reset Package Caches"
    echo "   3. Product → Clean Build Folder (⇧⌘K)"
    echo "   4. 重新构建项目"
else
    echo "❌ 项目生成失败"
    exit 1
fi

