#!/bin/bash

# 测试新架构脚本
# 用于验证 NotesViewModelAdapter 和新架构的基本功能

echo "========================================="
echo "测试新架构 (AppCoordinator + 7 个 ViewModel)"
echo "========================================="
echo ""

# 1. 编译项目
echo "1. 编译项目..."
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✅ 编译成功"
else
    echo "❌ 编译失败"
    exit 1
fi

echo ""

# 2. 检查关键文件是否存在
echo "2. 检查关键文件..."

files=(
    "Sources/Presentation/Coordinators/App/AppCoordinator.swift"
    "Sources/Presentation/Coordinators/App/NotesViewModelAdapter.swift"
    "Sources/Presentation/ViewModels/NoteList/NoteListViewModel.swift"
    "Sources/Presentation/ViewModels/NoteEditor/NoteEditorViewModel.swift"
    "Sources/Presentation/ViewModels/Folder/FolderViewModel.swift"
    "Sources/Presentation/ViewModels/Search/SearchViewModel.swift"
    "Sources/Presentation/ViewModels/AudioPanel/AudioPanelViewModel.swift"
    "Sources/Presentation/ViewModels/Authentication/AuthenticationViewModel.swift"
    "Sources/Presentation/Coordinators/Sync/SyncCoordinator.swift"
)

all_exist=true
for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ $file"
    else
        echo "❌ $file (不存在)"
        all_exist=false
    fi
done

if [ "$all_exist" = false ]; then
    echo ""
    echo "❌ 部分文件缺失"
    exit 1
fi

echo ""

# 3. 统计代码行数
echo "3. 统计代码行数..."

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        lines=$(wc -l < "$file" | tr -d ' ')
        filename=$(basename "$file")
        echo "  $filename: $lines 行"
    fi
done

echo ""

# 4. 检查 FeatureFlags
echo "4. 检查 FeatureFlags..."
if grep -q "useNewArchitecture" Sources/Core/FeatureFlags.swift; then
    echo "✅ FeatureFlags.useNewArchitecture 存在"
else
    echo "❌ FeatureFlags.useNewArchitecture 不存在"
    exit 1
fi

echo ""

# 5. 检查 AppDelegate 集成
echo "5. 检查 AppDelegate 集成..."
if grep -q "appCoordinator" Sources/App/AppDelegate.swift; then
    echo "✅ AppDelegate 已集成 AppCoordinator"
else
    echo "❌ AppDelegate 未集成 AppCoordinator"
    exit 1
fi

if grep -q "NotesViewModelAdapter" Sources/App/AppDelegate.swift; then
    echo "✅ AppDelegate 已集成 NotesViewModelAdapter"
else
    echo "❌ AppDelegate 未集成 NotesViewModelAdapter"
    exit 1
fi

echo ""

# 6. 总结
echo "========================================="
echo "测试总结"
echo "========================================="
echo ""
echo "✅ 所有基本检查通过"
echo ""
echo "下一步:"
echo "1. 设置 FeatureFlags.useNewArchitecture = true"
echo "2. 启动应用进行手动测试"
echo "3. 验证笔记列表、编辑、同步等核心功能"
echo ""
echo "启动应用:"
echo "  open /Users/acckion/Library/Developer/Xcode/DerivedData/MiNoteMac-*/Build/Products/Debug/MiNoteMac.app"
echo ""
