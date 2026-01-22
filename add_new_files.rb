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

# 要添加的新文件
new_files = [
  'Sources/Model/AuthUser.swift',
  'Sources/Service/Network/NetworkClientProtocol.swift',
  'Sources/Service/Network/NetworkClient.swift'
]

new_files.each do |file_path|
  # 检查文件是否存在
  unless File.exist?(file_path)
    puts "警告: 文件不存在: #{file_path}"
    next
  end
  
  # 检查文件是否已经在项目中
  existing_file = project.files.find { |f| f.path == file_path }
  if existing_file
    puts "文件已存在于项目中: #{file_path}"
    next
  end
  
  # 添加文件到项目
  file_ref = project.new_file(file_path)
  target.add_file_references([file_ref])
  puts "已添加文件: #{file_path}"
end

# 保存项目
project.save
puts "项目已保存"
puts "成功添加 #{new_files.length} 个文件"
