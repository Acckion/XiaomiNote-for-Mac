# 小米笔记 macOS 客户端构建指南

本文档介绍如何构建和打包小米笔记 macOS 客户端。

## 构建系统概述

项目提供了两种构建方式：

1. **Shell 脚本** (`build_release.sh`) - 完整的构建脚本，包含依赖检查、编译、打包和 DMG 创建
2. **Makefile** - 简单的命令接口，提供常用构建命令

## 系统要求

- macOS 14.0 或更高版本
- Xcode 命令行工具
- Swift 5.9 或更高版本
- （可选）create-dmg 用于创建 DMG 安装包

## 安装依赖

### 1. 安装 Xcode 命令行工具

```bash
xcode-select --install
```

### 2. （可选）安装 create-dmg

用于创建 DMG 安装包：

```bash
brew install create-dmg
```

## 构建命令

### 使用 Makefile（推荐）

```bash
# 显示所有可用命令
make help

# 编译 Debug 版本
make build

# 编译 Release 版本并创建应用程序包
make release

# 运行 Debug 版本
make run

# 安装应用程序到 /Applications
make install

# 创建 DMG 安装包
make dmg

# 清理构建文件
make clean

# 检查构建状态
make status
```

### 使用 Shell 脚本

```bash
# 直接运行完整构建脚本
./build_release.sh
```

## 构建产物

构建完成后，产物位于 `.build/release/` 目录：

- `小米笔记.app` - 完整的 macOS 应用程序包
- `小米笔记-1.0.0.dmg` - DMG 安装包（如果安装了 create-dmg）

## 应用程序信息

- **应用程序名称**: 小米笔记
- **Bundle ID**: `com.xiaomi.minote.mac`
- **版本**: 1.0.0
- **最低系统要求**: macOS 14.0

## 手动构建步骤

如果您想手动构建，可以按照以下步骤：

1. **编译 Release 版本**:
   ```bash
   swift build -c release
   ```

2. **创建应用程序包结构**:
   ```bash
   mkdir -p "小米笔记.app/Contents/MacOS"
   mkdir -p "小米笔记.app/Contents/Resources"
   ```

3. **复制可执行文件**:
   ```bash
   cp .build/release/MiNoteMac "小米笔记.app/Contents/MacOS/"
   ```

4. **创建 Info.plist**:
   ```bash
   cat > "小米笔记.app/Contents/Info.plist" << EOF
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>CFBundleName</key>
       <string>小米笔记</string>
       <key>CFBundleDisplayName</key>
       <string>小米笔记</string>
       <key>CFBundleIdentifier</key>
       <string>com.xiaomi.minote.mac</string>
       <key>CFBundleVersion</key>
       <string>1.0.0</string>
       <key>CFBundleShortVersionString</key>
       <string>1.0</string>
       <key>CFBundlePackageType</key>
       <string>APPL</string>
       <key>CFBundleSignature</key>
       <string>????</string>
       <key>CFBundleExecutable</key>
       <string>MiNoteMac</string>
       <key>LSMinimumSystemVersion</key>
       <string>14.0</string>
       <key>NSHumanReadableCopyright</key>
       <string>Copyright © 2025 小米笔记. All rights reserved.</string>
       <key>NSPrincipalClass</key>
       <string>NSApplication</string>
       <key>NSHighResolutionCapable</key>
       <true/>
   </dict>
   </plist>
   EOF
   ```

## 故障排除

### 1. Swift 编译器未找到

错误信息：
```
Swift 编译器未找到，请安装 Xcode 命令行工具
```

解决方案：
```bash
xcode-select --install
```

### 2. 权限被拒绝

错误信息：
```
Permission denied
```

解决方案：
```bash
chmod +x build_release.sh
```

### 3. 构建失败

如果构建失败，尝试清理后重新构建：

```bash
make clean
make release
```

### 4. create-dmg 未安装

错误信息：
```
create-dmg 工具未安装
```

解决方案：
```bash
brew install create-dmg
```

或者跳过 DMG 创建，直接使用应用程序包。

## 项目结构

```
SwiftUI-MiNote-for-Mac/
├── Sources/                    # 源代码
│   └── MiNoteMac/             # 主目标
│       ├── App.swift          # 应用程序入口
│       ├── Model/             # 数据模型
│       ├── View/              # SwiftUI 视图
│       ├── ViewModel/         # 视图模型
│       └── Service/           # 服务层
├── Package.swift              # Swift Package Manager 配置
├── build_release.sh           # 自动构建脚本
├── Makefile                   # Make 构建系统
├── BUILD.md                   # 本文档
└── .build/                    # 构建输出目录
    └── release/               # Release 构建产物
        ├── 小米笔记.app       # 应用程序包
        └── 小米笔记-1.0.0.dmg # DMG 安装包
```

## 开发工作流

1. **开发调试**:
   ```bash
   make run
   ```

2. **测试**:
   ```bash
   make test
   ```

3. **发布构建**:
   ```bash
   make release
   ```

4. **安装测试**:
   ```bash
   make install
   ```

5. **创建分发包**:
   ```bash
   make dmg
   ```

## 版本管理

当前版本：1.0.0

要更新版本号，需要修改以下文件：
1. `build_release.sh` 中的 `VERSION` 变量
2. `Makefile` 中相关命令的版本号
3. 应用程序包中的 `Info.plist`

## 许可证

版权所有 © 2025 小米笔记。保留所有权利。
