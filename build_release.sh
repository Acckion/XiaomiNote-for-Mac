#!/bin/bash

# 构建 Release 版本脚本
# 用于编译 MiNoteMac 应用的 Release 版本

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🔨 开始构建 MiNoteMac Release 版本...${NC}"

# 检查 Xcode 是否安装
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}❌ 错误: Xcode 未安装或 xcodebuild 不在 PATH 中${NC}"
    exit 1
fi

# 检查项目文件是否存在
if [ ! -d "MiNoteMac.xcodeproj" ]; then
    echo -e "${RED}❌ 错误: MiNoteMac.xcodeproj 不存在${NC}"
    exit 1
fi

# 设置构建配置
PROJECT_NAME="MiNoteMac"
SCHEME="MiNoteMac"
CONFIGURATION="Release"
PLATFORM="macOS"
DERIVED_DATA_PATH="build/DerivedData"
OUTPUT_DIR="build/Release"

# 创建构建目录
mkdir -p "$DERIVED_DATA_PATH"
mkdir -p "$OUTPUT_DIR"

# 解析 Swift Package 依赖
echo -e "${YELLOW}📦 解析 Swift Package 依赖...${NC}"
xcodebuild -resolvePackageDependencies \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "$SCHEME" \
    2>&1 | grep -v "warning:" || true

# 清理之前的构建
echo -e "${YELLOW}🧹 清理之前的构建...${NC}"
xcodebuild clean \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    > /dev/null 2>&1 || true

# 构建 Release 版本
echo -e "${GREEN}🚀 开始构建 Release 版本...${NC}"
BUILD_RESULT=$(xcodebuild build \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -destination "platform=${PLATFORM}" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO 2>&1)

BUILD_EXIT_CODE=$?

# 检查构建结果
if [ $BUILD_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✅ 构建成功!${NC}"
    
    # 查找构建产物（尝试多个可能的位置）
    APP_PATH=""
    
    # 首先尝试最常见的路径
    if [ -d "$DERIVED_DATA_PATH/Build/Products/Release/${SCHEME}.app" ]; then
        APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/${SCHEME}.app"
    elif [ -d "$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}/${SCHEME}.app" ]; then
        APP_PATH="$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}/${SCHEME}.app"
    else
        # 使用 find 查找
        FOUND_APP=$(find "$DERIVED_DATA_PATH/Build/Products" -name "${SCHEME}.app" -type d 2>/dev/null | head -1)
        if [ -n "$FOUND_APP" ] && [ -d "$FOUND_APP" ]; then
            APP_PATH="$FOUND_APP"
        fi
    fi
    
    if [ -n "$APP_PATH" ] && [ -d "$APP_PATH" ]; then
        echo -e "${GREEN}📦 找到应用: ${APP_PATH}${NC}"
        
        # 复制到输出目录
        OUTPUT_APP="${OUTPUT_DIR}/${SCHEME}.app"
        if [ -d "$OUTPUT_APP" ]; then
            rm -rf "$OUTPUT_APP"
        fi
        cp -R "$APP_PATH" "$OUTPUT_APP"
        echo -e "${GREEN}📋 应用已复制到: ${OUTPUT_APP}${NC}"
        echo -e "${GREEN}✨ 完成! 应用已准备好: ${OUTPUT_APP}${NC}"
    else
        echo -e "${YELLOW}⚠️  未找到 .app 文件${NC}"
        echo -e "${YELLOW}   构建日志可能包含更多信息${NC}"
        # 显示构建输出的最后几行
        echo "$BUILD_RESULT" | tail -20
    fi
else
    echo -e "${RED}❌ 构建失败 (退出码: $BUILD_EXIT_CODE)${NC}"
    echo -e "${RED}构建日志:${NC}"
    echo "$BUILD_RESULT" | tail -50
    exit 1
fi

