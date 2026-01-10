#!/bin/bash

# 代码行数统计脚本
# 统计项目中所有源代码文件的行数

echo "=================================="
echo "       代码行数统计报告"
echo "=================================="
echo ""

# 搜索目录
SEARCH_DIR="."

# 排除目录
EXCLUDE="-path ./.git -prune -o -path ./.build -prune -o -path ./build -prune -o -path ./node_modules -prune -o -path ./vendor -prune -o -path ./Pods -prune -o -path ./DerivedData -prune -o -path ./.swiftpm -prune -o -path ./References -prune -o"

# 统计函数
count_ext() {
    local ext=$1
    local name=$2
    local files=$(find $SEARCH_DIR $EXCLUDE -name "*.$ext" -type f -print 2>/dev/null)
    
    if [ -n "$files" ]; then
        local count=$(echo "$files" | wc -l | tr -d ' ')
        if [ "$count" -gt 0 ]; then
            local lines=$(echo "$files" | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
            if [ "$lines" -gt 0 ] 2>/dev/null; then
                printf "%-28s %8s 行 %8s 个文件\n" "$name" "$lines" "$count"
                echo "$lines" >> /tmp/loc_lines.tmp
                echo "$count" >> /tmp/loc_files.tmp
            fi
        fi
    fi
}

# 清理临时文件
rm -f /tmp/loc_lines.tmp /tmp/loc_files.tmp
touch /tmp/loc_lines.tmp /tmp/loc_files.tmp

echo "📁 按文件类型统计："
echo "------------------------------------------------"

# 编程语言
count_ext "swift" "Swift"
count_ext "m" "Objective-C"
count_ext "mm" "Objective-C++"
count_ext "h" "C/C++/ObjC Header"
count_ext "c" "C"
count_ext "cpp" "C++"
count_ext "cc" "C++"
count_ext "java" "Java"
count_ext "kt" "Kotlin"
count_ext "py" "Python"
count_ext "rb" "Ruby"
count_ext "go" "Go"
count_ext "rs" "Rust"
count_ext "ts" "TypeScript"
count_ext "tsx" "TypeScript React"
count_ext "js" "JavaScript"
count_ext "jsx" "JavaScript React"
count_ext "php" "PHP"
count_ext "cs" "C#"
count_ext "scala" "Scala"
count_ext "dart" "Dart"
count_ext "vue" "Vue"
count_ext "svelte" "Svelte"

# 标记语言和样式
count_ext "html" "HTML"
count_ext "htm" "HTML"
count_ext "xml" "XML"
count_ext "css" "CSS"
count_ext "scss" "SCSS"
count_ext "sass" "Sass"
count_ext "less" "Less"

# 配置和数据
count_ext "json" "JSON"
count_ext "yaml" "YAML"
count_ext "yml" "YAML"
count_ext "toml" "TOML"
count_ext "plist" "Property List"

# Shell 脚本
count_ext "sh" "Shell"
count_ext "bash" "Bash"
count_ext "zsh" "Zsh"

# 其他
count_ext "sql" "SQL"
count_ext "graphql" "GraphQL"
count_ext "md" "Markdown"

echo "------------------------------------------------"

# 计算总数
total_lines=$(awk '{s+=$1} END {print s}' /tmp/loc_lines.tmp)
total_files=$(awk '{s+=$1} END {print s}' /tmp/loc_files.tmp)
printf "%-28s %8s 行 %8s 个文件\n" "总计" "${total_lines:-0}" "${total_files:-0}"

rm -f /tmp/loc_lines.tmp /tmp/loc_files.tmp

echo ""
echo "📂 按目录统计："
echo "------------------------------------------------"

count_dir() {
    local dir=$1
    if [ -d "$dir" ]; then
        local files=$(find "$dir" \( -name "*.swift" -o -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.java" -o -name "*.go" -o -name "*.rs" -o -name "*.c" -o -name "*.cpp" -o -name "*.h" -o -name "*.m" -o -name "*.html" -o -name "*.css" -o -name "*.json" -o -name "*.xml" -o -name "*.yaml" -o -name "*.yml" -o -name "*.sh" -o -name "*.md" \) -type f 2>/dev/null)
        if [ -n "$files" ]; then
            local count=$(echo "$files" | wc -l | tr -d ' ')
            local lines=$(echo "$files" | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
            if [ "$count" -gt 0 ] 2>/dev/null && [ "$lines" -gt 0 ] 2>/dev/null; then
                printf "%-30s %8s 行 %6s 个文件\n" "$dir" "$lines" "$count"
            fi
        fi
    fi
}

# 主目录
count_dir "Sources"
count_dir "Tests"

echo ""
echo "  子目录明细："

# 子目录
for dir in Sources/*/; do
    if [ -d "$dir" ]; then
        count_dir "${dir%/}"
    fi
done

echo ""
echo "📈 最大的 20 个源文件："
echo "------------------------------------------------"

find $SEARCH_DIR $EXCLUDE \( -name "*.swift" -o -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.java" -o -name "*.go" -o -name "*.rs" -o -name "*.c" -o -name "*.cpp" -o -name "*.h" -o -name "*.m" -o -name "*.html" -o -name "*.css" -o -name "*.json" -o -name "*.xml" -o -name "*.sh" \) -type f -print 2>/dev/null | \
    xargs wc -l 2>/dev/null | \
    sort -rn | \
    head -21 | \
    tail -20 | \
    while read lines file; do
        printf "%8s 行  %s\n" "$lines" "$file"
    done

echo ""
echo "=================================="
echo "统计完成于: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================="
