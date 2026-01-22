#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'MiNoteMac.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# 查找 MiNoteLibrary target
target = project.targets.find { |t| t.name == 'MiNoteLibrary' }

if target.nil?
  puts "错误: 找不到 MiNoteLibrary target"
  exit 1
end

# 查找并移除 LRUCache.swift 文件引用
file_ref = project.files.find { |f| f.path == 'Sources/Core/Cache/LRUCache.swift' }

if file_ref
  puts "找到文件引用: #{file_ref.path}"
  
  # 从 target 的 source_build_phase 中移除
  target.source_build_phase.files.each do |build_file|
    if build_file.file_ref == file_ref
      puts "从 build phase 中移除: #{build_file.file_ref.path}"
      build_file.remove_from_project
    end
  end
  
  # 从项目中移除文件引用
  file_ref.remove_from_project
  puts "已从项目中移除文件引用"
else
  puts "未找到 LRUCache.swift 文件引用"
end

# 保存项目
project.save
puts "项目已保存"
