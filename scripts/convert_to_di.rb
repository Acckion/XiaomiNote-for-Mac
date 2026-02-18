#!/usr/bin/env ruby

# 依赖注入转换脚本
# 将单例调用转换为 ServiceLocator 调用

class DIConverter
  def initialize
    @conversions = []
    @dry_run = false
  end

  # 转换单个文件
  def convert_file(file_path, singleton_name, protocol_name, service_accessor)
    unless File.exist?(file_path)
      puts "❌ 文件不存在: #{file_path}"
      return false
    end

    content = File.read(file_path)
    original_content = content.dup
    
    # 替换 Singleton.shared 为 ServiceLocator.shared.service
    pattern = /#{Regexp.escape(singleton_name)}\.shared/
    replacement = "ServiceLocator.shared.#{service_accessor}"
    
    content.gsub!(pattern, replacement)
    
    if content == original_content
      puts "ℹ️  文件未发生变化: #{file_path}"
      return false
    end

    if @dry_run
      puts "🔍 [DRY RUN] 将要修改: #{file_path}"
      puts "   替换: #{singleton_name}.shared → #{replacement}"
      return true
    end

    # 写入文件
    File.write(file_path, content)
    puts "✅ 已转换: #{file_path}"
    puts "   替换: #{singleton_name}.shared → #{replacement}"
    
    @conversions << {
      file: file_path,
      singleton: singleton_name,
      protocol: protocol_name,
      accessor: service_accessor
    }
    
    true
  end

  # 批量转换目录中的所有文件
  def convert_directory(directory, singleton_name, protocol_name, service_accessor)
    puts "\n🔄 开始批量转换..."
    puts "   目录: #{directory}"
    puts "   单例: #{singleton_name}.shared"
    puts "   协议: #{protocol_name}"
    puts "   访问器: ServiceLocator.shared.#{service_accessor}"
    puts "=" * 60

    count = 0
    Dir.glob("#{directory}/**/*.swift").each do |file|
      if convert_file(file, singleton_name, protocol_name, service_accessor)
        count += 1
      end
    end

    puts "\n📊 转换完成: #{count} 个文件已修改"
  end

  # 设置为 dry run 模式
  def dry_run!
    @dry_run = true
    puts "🔍 DRY RUN 模式已启用 - 不会实际修改文件"
  end

  # 生成转换报告
  def report
    return if @conversions.empty?

    puts "\n📋 转换报告"
    puts "=" * 60
    puts "总计转换: #{@conversions.length} 个文件\n\n"

    @conversions.each do |conv|
      puts "📄 #{conv[:file]}"
      puts "   #{conv[:singleton]}.shared → ServiceLocator.shared.#{conv[:accessor]}"
    end
  end
end

# 预定义的转换映射
CONVERSION_MAP = {
  'MiNoteService' => {
    protocol: 'NoteServiceProtocol',
    accessor: 'noteService'
  },
  'DatabaseService' => {
    protocol: 'NoteStorageProtocol',
    accessor: 'noteStorage'
  },
  'SyncService' => {
    protocol: 'SyncServiceProtocol',
    accessor: 'syncService'
  },
  'NetworkMonitor' => {
    protocol: 'NetworkMonitorProtocol',
    accessor: 'networkMonitor'
  },
  'MemoryCacheManager' => {
    protocol: 'CacheServiceProtocol',
    accessor: 'cacheService'
  },
  'AudioPlayerService' => {
    protocol: 'AudioServiceProtocol',
    accessor: 'audioService'
  },
  'AudioRecorderService' => {
    protocol: 'AudioServiceProtocol',
    accessor: 'audioService'
  },
  'ImageCacheService' => {
    protocol: 'ImageServiceProtocol',
    accessor: 'imageService'
  }
}

# 使用示例和帮助
def show_usage
  puts <<~USAGE
    📖 依赖注入转换脚本使用说明
    =" * 60

    用法:
      ruby scripts/convert_to_di.rb [选项] <单例名称> [目录]

    选项:
      --dry-run    预览模式，不实际修改文件
      --help       显示此帮助信息

    参数:
      单例名称     要转换的单例类名（如 MiNoteService）
      目录         要扫描的目录（默认: Sources）

    示例:
      # 预览转换 MiNoteService
      ruby scripts/convert_to_di.rb --dry-run MiNoteService

      # 实际转换 MiNoteService
      ruby scripts/convert_to_di.rb MiNoteService

      # 转换指定目录
      ruby scripts/convert_to_di.rb MiNoteService Sources/ViewModel

    支持的单例:
  USAGE

  CONVERSION_MAP.each do |singleton, config|
    puts "      - #{singleton} → #{config[:accessor]}"
  end
end

# 主程序
if ARGV.include?('--help') || ARGV.empty?
  show_usage
  exit 0
end

converter = DIConverter.new

# 检查 dry run 模式
if ARGV.include?('--dry-run')
  converter.dry_run!
  ARGV.delete('--dry-run')
end

singleton_name = ARGV[0]
directory = ARGV[1] || 'Sources'

unless CONVERSION_MAP.key?(singleton_name)
  puts "❌ 不支持的单例: #{singleton_name}"
  puts "支持的单例:"
  CONVERSION_MAP.keys.each { |name| puts "  - #{name}" }
  exit 1
end

config = CONVERSION_MAP[singleton_name]
converter.convert_directory(directory, singleton_name, config[:protocol], config[:accessor])
converter.report
