#!/bin/bash

# Phase 7.3 新架构测试脚本
# 用于测试 NotesViewModelAdapter 和新的 ViewModel 架构

echo "=========================================="
echo "Phase 7.3 新架构测试"
echo "=========================================="
echo ""

# 1. 启用新架构
echo "1. 启用新架构..."
defaults write com.minote.MiNoteMac useNewArchitecture -bool true
echo "   ✅ 已设置 useNewArchitecture = true"
echo ""

# 2. 清理构建
echo "2. 清理构建..."
xcodebuild clean -project MiNoteMac.xcodeproj -scheme MiNoteMac > /dev/null 2>&1
echo "   ✅ 构建已清理"
echo ""

# 3. 编译项目
echo "3. 编译项目..."
if xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build > /dev/null 2>&1; then
    echo "   ✅ 编译成功"
else
    echo "   ❌ 编译失败"
    exit 1
fi
echo ""

# 4. 提示手动测试
echo "4. 手动测试步骤:"
echo "   - 启动应用 (open build/Debug/MiNoteMac.app)"
echo "   - 检查控制台输出,确认使用新架构"
echo "   - 测试笔记列表加载"
echo "   - 测试笔记选择"
echo "   - 测试笔记编辑"
echo "   - 测试文件夹切换"
echo "   - 测试同步功能"
echo ""

# 5. 恢复旧架构 (可选)
echo "5. 测试完成后,可以运行以下命令恢复旧架构:"
echo "   defaults write com.minote.MiNoteMac useNewArchitecture -bool false"
echo ""

echo "=========================================="
echo "测试准备完成!"
echo "=========================================="
