# 小米笔记 macOS 客户端 Makefile
# 提供简单的构建命令

.PHONY: help build release clean test run install dmg

# 默认目标
help:
	@echo "小米笔记 macOS 客户端构建系统"
	@echo ""
	@echo "可用命令:"
	@echo "  make build     - 编译 Debug 版本"
	@echo "  make release   - 编译 Release 版本并创建应用程序包"
	@echo "  make clean     - 清理构建文件"
	@echo "  make test      - 运行测试"
	@echo "  make run       - 运行 Debug 版本"
	@echo "  make install   - 安装应用程序到 /Applications"
	@echo "  make dmg       - 创建 DMG 安装包（需要 create-dmg）"
	@echo "  make help      - 显示此帮助信息"
	@echo ""
	@echo "快速构建:"
	@echo "  ./build_release.sh  - 使用完整构建脚本"

# 编译 Debug 版本
build:
	@echo "编译 Debug 版本..."
	swift build

# 编译 Release 版本
release: clean
	@echo "编译 Release 版本..."
	./build_release.sh

# 清理构建文件
clean:
	@echo "清理构建文件..."
	swift package clean
	rm -rf .build/release
	rm -rf .build/x86_64-apple-macosx

# 运行测试
test:
	@echo "运行测试..."
	swift test

# 运行 Debug 版本
run: build
	@echo "运行应用程序..."
	./.build/debug/MiNoteMac

# 安装应用程序到 /Applications
install: release
	@echo "安装应用程序到 /Applications..."
	@if [ -d ".build/release/小米笔记.app" ]; then \
		cp -R ".build/release/小米笔记.app" "/Applications/"; \
		echo "应用程序已安装到 /Applications/小米笔记.app"; \
	else \
		echo "错误: 应用程序包未找到，请先运行 'make release'"; \
		exit 1; \
	fi

# 创建 DMG 安装包
dmg:
	@echo "创建 DMG 安装包..."
	@if command -v create-dmg &> /dev/null; then \
		if [ -d ".build/release/小米笔记.app" ]; then \
			cd .build/release && \
			create-dmg \
				--volname "小米笔记 1.0.0" \
				--window-pos 200 120 \
				--window-size 600 400 \
				--icon-size 100 \
				--icon "小米笔记.app" 175 190 \
				--hide-extension "小米笔记.app" \
				--app-drop-link 425 190 \
				--no-internet-enable \
				"小米笔记-1.0.0.dmg" \
				"小米笔记.app" && \
			echo "DMG 已创建: .build/release/小米笔记-1.0.0.dmg"; \
		else \
			echo "错误: 应用程序包未找到，请先运行 'make release'"; \
			exit 1; \
		fi \
	else \
		echo "错误: create-dmg 未安装，请使用 'brew install create-dmg' 安装"; \
		exit 1; \
	fi

# 检查构建状态
status:
	@echo "检查构建状态..."
	@if [ -d ".build/release/小米笔记.app" ]; then \
		echo "✓ Release 版本已构建"; \
		ls -la ".build/release/"; \
	else \
		echo "✗ Release 版本未构建"; \
	fi
	@if [ -f ".build/debug/MiNoteMac" ]; then \
		echo "✓ Debug 版本已构建"; \
	else \
		echo "✗ Debug 版本未构建"; \
	fi
