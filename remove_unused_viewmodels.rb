#!/usr/bin/env ruby
require 'xcodeproj'

# 打开项目
project_path = 'MiNoteMac.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# 要移除的文件列表（Phase 4 创建的新 ViewModel/Coordinator 层）
files_to_remove = [
  'Sources/Presentation/ViewModels/Base/PageableViewModel.swift',
  'Sources/Presentation/ViewModels/NoteList/NoteListViewModel.swift',
  'Sources/Presentation/ViewModels/NoteEditor/NoteEditorViewModel.swift',
  'Sources/Presentation/ViewModels/Folder/FolderViewModel.swift',
  'Sources/Presentation/ViewModels/Authentication/AuthenticationViewModel.swift',
  'Sources/Presentation/Coordinators/SyncCoordinator.swift',
  'Sources/Presentation/Coordinators/AppCoordinator.swift',
  'Sources/Core/Concurrency/BackgroundTaskManager.swift',
  'Sources/Core/Pagination/Pageable.swift'
]

# 获取主 target
main_target = project.targets.find { |t| t.name == 'MiNoteMac' }

puts "从 Xcode 项目中移除未使用的 ViewModel/Coordinator 文件..."
puts "=" * 60

removed_count = 0

files_to_remove.each do |file_path|
  # 查找文件引用
  file_ref = project.files.find { |f| f.path == file_path }
  
  if file_ref
    puts "移除: #{file_path}"
    
    # 从 target 的 sources build phase 中移除
    if main_target
      main_target.source_build_phase.files.each do |build_file|
        if build_file.file_ref == file_ref
          main_target.source_build_phase.files.delete(build_file)
        end
      end
    end
    
    # 从项目中移除文件引用
    file_ref.remove_from_project
    removed_count += 1
  else
    puts "未找到: #{file_path}"
  end
end

puts "=" * 60
puts "总计移除 #{removed_count} 个文件引用"
puts ""
puts "注意: 文件仍保留在磁盘上,只是从 Xcode 项目中移除了引用"
puts "将来可以重新添加这些文件"

# 保存项目
project.save

puts ""
puts "✅ 项目已保存"
