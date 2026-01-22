#!/usr/bin/env ruby

require 'xcodeproj'

# 打开项目
project_path = 'MiNoteMac.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# 获取 MiNoteLibrary 目标
target = project.targets.find { |t| t.name == 'MiNoteLibrary' }

if target.nil?
  puts "错误: 找不到 MiNoteLibrary 目标"
  exit 1
end

# 需要从 MiNoteLibrary 移除的测试文件
test_files = [
  'Tests/TestSupport/BaseTestCase.swift',
  'Tests/Mocks/MockNoteService.swift',
  'Tests/Mocks/MockNoteStorage.swift',
  'Tests/Mocks/MockSyncService.swift',
  'Tests/Mocks/MockAuthenticationService.swift',
  'Tests/Mocks/MockNetworkMonitor.swift'
]

removed_count = 0

test_files.each do |file_path|
  file_ref = project.files.find { |f| f.path == file_path }

  if file_ref
    # 从目标中移除文件引用
    target.source_build_phase.files.each do |build_file|
      if build_file.file_ref == file_ref
        target.source_build_phase.files.delete(build_file)
        puts "移除: #{file_path}"
        removed_count += 1
        break
      end
    end
  end
end

# 保存项目
project.save

puts "\n完成!"
puts "移除了 #{removed_count} 个测试文件"
