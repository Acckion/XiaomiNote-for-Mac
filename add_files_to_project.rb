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

# 需要添加的文件列表
files_to_add = [
  # 依赖注入
  'Sources/Core/DependencyInjection/DIContainer.swift',
  'Sources/Core/DependencyInjection/ServiceLocator.swift',

  # 服务协议
  'Sources/Service/Protocols/NoteServiceProtocol.swift',
  'Sources/Service/Protocols/NoteStorageProtocol.swift',
  'Sources/Service/Protocols/SyncServiceProtocol.swift',
  'Sources/Service/Protocols/AuthenticationServiceProtocol.swift',
  'Sources/Service/Protocols/NetworkMonitorProtocol.swift',
  'Sources/Service/Protocols/ImageServiceProtocol.swift',
  'Sources/Service/Protocols/AudioServiceProtocol.swift',
  'Sources/Service/Protocols/CacheServiceProtocol.swift',

  # 服务实现
  'Sources/Service/Network/Core/NetworkClient.swift',
  'Sources/Service/Network/Implementation/DefaultNoteService.swift',
  'Sources/Service/Network/Implementation/DefaultNetworkMonitor.swift',
  'Sources/Service/Storage/Implementation/DefaultNoteStorage.swift',
  'Sources/Service/Sync/Implementation/DefaultSyncService.swift',
  'Sources/Service/Authentication/Implementation/DefaultAuthenticationService.swift',
  'Sources/Service/Image/Implementation/DefaultImageService.swift',
  'Sources/Service/Audio/Implementation/DefaultAudioService.swift',
  'Sources/Service/Cache/Implementation/DefaultCacheService.swift',

  # ViewModel 基类
  'Sources/Presentation/ViewModels/Base/BaseViewModel.swift',
  'Sources/Presentation/ViewModels/Base/LoadableViewModel.swift',
  'Sources/Presentation/ViewModels/Base/PageableViewModel.swift',

  # ViewModel 实现
  'Sources/Presentation/ViewModels/NoteList/NoteListViewModel.swift',
  'Sources/Presentation/ViewModels/NoteEditor/NoteEditorViewModel.swift',
  'Sources/Presentation/ViewModels/Authentication/AuthenticationViewModel.swift',
  'Sources/Presentation/ViewModels/Folder/FolderViewModel.swift',
  'Sources/Presentation/Coordinators/SyncCoordinator.swift',
  'Sources/Presentation/Coordinators/AppCoordinator.swift',

  # 性能优化
  'Sources/Core/Concurrency/BackgroundTaskManager.swift',
  'Sources/Core/Pagination/Pageable.swift',
  'Sources/Core/Cache/LRUCache.swift',

  # 测试支持
  'Tests/TestSupport/BaseTestCase.swift',
  'Tests/Mocks/MockNoteService.swift',
  'Tests/Mocks/MockNoteStorage.swift',
  'Tests/Mocks/MockSyncService.swift',
  'Tests/Mocks/MockAuthenticationService.swift',
  'Tests/Mocks/MockNetworkMonitor.swift'
]

added_count = 0
skipped_count = 0

files_to_add.each do |file_path|
  # 检查文件是否存在
  unless File.exist?(file_path)
    puts "跳过: #{file_path} (文件不存在)"
    skipped_count += 1
    next
  end

  # 检查文件是否已经在项目中
  file_ref = project.files.find { |f| f.path == file_path }

  if file_ref.nil?
    # 添加文件到项目
    file_ref = project.new_file(file_path)
    target.add_file_references([file_ref])
    puts "添加: #{file_path}"
    added_count += 1
  else
    puts "已存在: #{file_path}"
    skipped_count += 1
  end
end

# 保存项目
project.save

puts "\n完成!"
puts "添加了 #{added_count} 个文件"
puts "跳过了 #{skipped_count} 个文件"
