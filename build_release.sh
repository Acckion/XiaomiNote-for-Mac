#!/bin/bash

# 小米笔记 macOS 客户端 Release 版本构建脚本
# 自动编译并打包应用程序

set -e  # 遇到错误时退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 项目配置
PROJECT_NAME="MiNoteMac"
APP_NAME="小米笔记"
BUNDLE_ID="com.xiaomi.minote.mac"
VERSION="1.0.0"
BUILD_DIR=".build"
RELEASE_DIR="${BUILD_DIR}/release"
APP_BUNDLE="${RELEASE_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查依赖
check_dependencies() {
    print_info "检查构建依赖..."
    
    # 检查 Swift 编译器
    if ! command -v swift &> /dev/null; then
        print_error "Swift 编译器未找到，请安装 Xcode 命令行工具：xcode-select --install"
        exit 1
    fi
    
    # 检查 Swift 版本
    SWIFT_VERSION=$(swift --version | head -n 1)
    print_info "Swift 版本: $SWIFT_VERSION"
    
    # 检查 create-dmg（可选）
    if command -v create-dmg &> /dev/null; then
        CREATE_DMG_AVAILABLE=true
        print_info "create-dmg 工具可用，将创建 DMG 安装包"
    else
        CREATE_DMG_AVAILABLE=false
        print_warning "create-dmg 工具未安装，跳过 DMG 创建"
        print_info "安装 create-dmg: brew install create-dmg"
    fi
}

# 清理之前的构建
clean_build() {
    print_info "清理之前的构建..."
    rm -rf "${BUILD_DIR}/release"
    rm -rf "${BUILD_DIR}/x86_64-apple-macosx"
    swift package clean
}

# 编译 Release 版本
build_release() {
    print_info "编译 Release 版本..."
    
    # 使用 Swift Package Manager 编译
    swift build -c release --disable-sandbox
    
    # 检查编译是否成功
    if [ $? -eq 0 ]; then
        print_success "编译成功完成"
    else
        print_error "编译失败"
        exit 1
    fi
}

# 生成应用图标
generate_app_icon() {
    print_info "生成应用图标..."
    
    ICON_SOURCE="Sources/MiNoteMac/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
    ICONSET_DIR="${BUILD_DIR}/AppIcon.iconset"
    ICNS_FILE="${BUILD_DIR}/AppIcon.icns"
    
    if [ ! -f "${ICON_SOURCE}" ]; then
        print_warning "图标源文件未找到: ${ICON_SOURCE}，跳过图标生成"
        return
    fi
    
    # 创建临时 iconset 目录
    mkdir -p "${ICONSET_DIR}"
    
    # 生成不同尺寸的图标（macOS iconset 需要的文件名格式）
    print_info "生成图标尺寸..."
    sips -z 16 16     "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_16x16.png" > /dev/null 2>&1
    sips -z 32 32     "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_16x16@2x.png" > /dev/null 2>&1
    sips -z 32 32     "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_32x32.png" > /dev/null 2>&1
    sips -z 64 64     "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_32x32@2x.png" > /dev/null 2>&1
    sips -z 128 128   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_128x128.png" > /dev/null 2>&1
    sips -z 256 256   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_128x128@2x.png" > /dev/null 2>&1
    sips -z 256 256   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_256x256.png" > /dev/null 2>&1
    sips -z 512 512   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_256x256@2x.png" > /dev/null 2>&1
    sips -z 512 512   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_512x512.png" > /dev/null 2>&1
    cp "${ICON_SOURCE}" "${ICONSET_DIR}/icon_512x512@2x.png"
    
    # 使用 iconutil 生成 .icns 文件
    if iconutil -c icns "${ICONSET_DIR}" -o "${ICNS_FILE}" 2>/dev/null; then
        if [ -f "${ICNS_FILE}" ]; then
            print_success "图标生成成功: ${ICNS_FILE}"
        else
            print_warning "图标生成失败，将使用默认图标"
        fi
    else
        print_warning "iconutil 执行失败，尝试直接使用 PNG 图标"
        # 如果 iconutil 失败，直接复制 PNG 文件（虽然不推荐，但可以作为后备方案）
        cp "${ICON_SOURCE}" "${BUILD_DIR}/AppIcon.png"
    fi
    
    # 清理临时目录
    rm -rf "${ICONSET_DIR}"
}

# 创建应用程序包
create_app_bundle() {
    print_info "创建应用程序包..."
    
    # 创建目录结构
    mkdir -p "${MACOS_DIR}"
    mkdir -p "${RESOURCES_DIR}"
    
    # 生成应用图标
    generate_app_icon
    
    # 复制可执行文件
    EXECUTABLE_PATH="${BUILD_DIR}/release/${PROJECT_NAME}"
    if [ -f "${EXECUTABLE_PATH}" ]; then
        cp "${EXECUTABLE_PATH}" "${MACOS_DIR}/"
        print_info "已复制可执行文件到 ${MACOS_DIR}/"
    else
        print_error "可执行文件未找到: ${EXECUTABLE_PATH}"
        exit 1
    fi
    
    # 复制图标文件
    ICNS_FILE="${BUILD_DIR}/AppIcon.icns"
    if [ -f "${ICNS_FILE}" ]; then
        cp "${ICNS_FILE}" "${RESOURCES_DIR}/AppIcon.icns"
        print_info "已复制图标文件到 ${RESOURCES_DIR}/AppIcon.icns"
        # macOS Info.plist 中的图标文件名不需要扩展名
        ICON_FILE_NAME="AppIcon"
    else
        print_warning "图标文件未找到，将不设置应用图标"
        ICON_FILE_NAME=""
    fi
    
    # 复制 Assets.xcassets（如果存在）
    ASSETS_DIR="Sources/MiNoteMac/Resources/Assets.xcassets"
    if [ -d "${ASSETS_DIR}" ]; then
        cp -R "${ASSETS_DIR}" "${RESOURCES_DIR}/" 2>/dev/null || true
        print_info "已复制资源文件到 ${RESOURCES_DIR}/"
    fi
    
    # 创建 Info.plist
    if [ -n "${ICON_FILE_NAME}" ]; then
        ICON_PLIST="    <key>CFBundleIconFile</key>
    <string>${ICON_FILE_NAME}</string>"
    else
        ICON_PLIST=""
    fi
    
    cat > "${CONTENTS_DIR}/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleExecutable</key>
    <string>${PROJECT_NAME}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025 小米笔记. All rights reserved.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
${ICON_PLIST}
</dict>
</plist>
EOF
    
    print_success "应用程序包创建完成: ${APP_BUNDLE}"
}

# 创建 DMG 安装包（可选）
create_dmg() {
    if [ "$CREATE_DMG_AVAILABLE" = true ]; then
        print_info "创建 DMG 安装包..."
        
        # 创建临时目录用于 DMG 内容
        DMG_TEMP_DIR="${RELEASE_DIR}/dmg_temp"
        mkdir -p "${DMG_TEMP_DIR}"
        
        # 复制应用程序到临时目录
        cp -R "${APP_BUNDLE}" "${DMG_TEMP_DIR}/"
        
        # 创建 Applications 文件夹的符号链接
        ln -s /Applications "${DMG_TEMP_DIR}/Applications"
        
        # 使用 create-dmg 创建 DMG
        create-dmg \
            --volname "${APP_NAME} ${VERSION}" \
            --volicon "icon.icns" 2>/dev/null || true \
            --window-pos 200 120 \
            --window-size 600 400 \
            --icon-size 100 \
            --icon "${APP_NAME}.app" 175 190 \
            --hide-extension "${APP_NAME}.app" \
            --app-drop-link 425 190 \
            --no-internet-enable \
            "${RELEASE_DIR}/${DMG_NAME}" \
            "${DMG_TEMP_DIR}/"
        
        if [ $? -eq 0 ]; then
            print_success "DMG 安装包创建完成: ${RELEASE_DIR}/${DMG_NAME}"
        else
            print_warning "DMG 创建失败，跳过此步骤"
        fi
        
        # 清理临时目录
        rm -rf "${DMG_TEMP_DIR}"
    fi
}

# 显示构建摘要
show_summary() {
    echo ""
    echo "================================================"
    print_success "构建完成！"
    echo "================================================"
    echo ""
    echo "构建产物:"
    echo "  • 应用程序包: ${APP_BUNDLE}"
    
    if [ "$CREATE_DMG_AVAILABLE" = true ] && [ -f "${RELEASE_DIR}/${DMG_NAME}" ]; then
        echo "  • DMG 安装包: ${RELEASE_DIR}/${DMG_NAME}"
    fi
    
    echo ""
    echo "应用程序信息:"
    echo "  • 名称: ${APP_NAME}"
    echo "  • 版本: ${VERSION}"
    echo "  • Bundle ID: ${BUNDLE_ID}"
    echo ""
    echo "运行应用程序:"
    echo "  open ${APP_BUNDLE}"
    echo ""
    echo "清理构建缓存:"
    echo "  swift package clean"
    echo "================================================"
}

# 主函数
main() {
    echo ""
    echo "================================================"
    echo "  小米笔记 macOS 客户端 Release 版本构建"
    echo "================================================"
    echo ""
    
    # 检查依赖
    check_dependencies
    
    # 清理构建
    clean_build
    
    # 编译 Release 版本
    build_release
    
    # 创建应用程序包
    create_app_bundle
    
    # 创建 DMG 安装包（可选）
    create_dmg
    
    # 显示构建摘要
    show_summary
}

# 执行主函数
main
