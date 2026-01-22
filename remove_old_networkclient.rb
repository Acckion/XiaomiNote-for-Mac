#!/usr/bin/env ruby

require 'xcodeproj'

project_path = 'MiNoteMac.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# 查找并移除旧的 NetworkClient.swift 引用
file_path = 'Sources/Service/Network/Core/NetworkClient.swift'

project.targets.each do |target|
  target.source_build_phase.files.each do |build_file|
    if build_file.file_ref && build_file.file_ref.path == file_path
      puts "移除 #{target.name} 中的文件引用: #{file_path}"
      target.source_build_phase.files.delete(build_file)
    end
  end
end

# 从项目中移除文件引用
project.files.each do |file|
  if file.path == file_path
    puts "从项目中移除文件引用: #{file_path}"
    file.remove_from_project
  end
end

project.save

puts "完成！已移除旧的 NetworkClient.swift 引用"
