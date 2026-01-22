#!/usr/bin/env ruby

# 迁移进度追踪工具
# 自动更新迁移进度文档

class MigrationProgressTracker
  def initialize(progress_file = 'docs/迁移进度追踪.md')
    @progress_file = progress_file
    @content = File.read(progress_file) if File.exist?(progress_file)
  end

  # 标记任务为完成
  def mark_complete(task_pattern)
    unless @content
      puts "❌ 进度文件不存在: #{@progress_file}"
      return false
    end

    original_content = @content.dup
    
    # 将 [ ] 替换为 [x]
    @content.gsub!(/^(\s*)- \[ \] (.*#{Regexp.escape(task_pattern)}.*)$/, '\1- [x] \2')
    
    if @content == original_content
      puts "ℹ️  未找到匹配的任务: #{task_pattern}"
      return false
    end

    File.write(@progress_file, @content)
    puts "✅ 已标记完成: #{task_pattern}"
    true
  end

  # 标记任务为进行中
  def mark_in_progress(task_pattern)
    unless @content
      puts "❌ 进度文件不存在: #{@progress_file}"
      return false
    end

    original_content = @content.dup
    
    # 将 [ ] 替换为 [-]
    @content.gsub!(/^(\s*)- \[ \] (.*#{Regexp.escape(task_pattern)}.*)$/, '\1- [-] \2')
    
    if @content == original_content
      puts "ℹ️  未找到匹配的任务: #{task_pattern}"
      return false
    end

    File.write(@progress_file, @content)
    puts "🔄 已标记进行中: #{task_pattern}"
    true
  end

  # 显示当前进度
  def show_progress
    unless @content
      puts "❌ 进度文件不存在: #{@progress_file}"
      return
    end

    puts "\n📊 迁移进度统计"
    puts "=" * 60

    # 统计各个阶段的进度
    phases = extract_phases

    phases.each do |phase|
      puts "\n#{phase[:name]}"
      puts "  完成: #{phase[:completed]}/#{phase[:total]} (#{phase[:percentage]}%)"
      puts "  进行中: #{phase[:in_progress]}"
    end

    # 总体进度
    total_tasks = phases.sum { |p| p[:total] }
    completed_tasks = phases.sum { |p| p[:completed] }
    percentage = total_tasks > 0 ? (completed_tasks * 100.0 / total_tasks).round(1) : 0

    puts "\n" + "=" * 60
    puts "总体进度: #{completed_tasks}/#{total_tasks} (#{percentage}%)"
    puts "=" * 60
  end

  # 生成进度报告
  def generate_report(output_file = 'docs/迁移进度报告.md')
    unless @content
      puts "❌ 进度文件不存在: #{@progress_file}"
      return
    end

    phases = extract_phases
    
    report = <<~REPORT
      # 架构迁移进度报告

      **生成时间**: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}

      ## 📊 总体进度

    REPORT

    total_tasks = phases.sum { |p| p[:total] }
    completed_tasks = phases.sum { |p| p[:completed] }
    percentage = total_tasks > 0 ? (completed_tasks * 100.0 / total_tasks).round(1) : 0

    report += "- 总任务数: #{total_tasks}\n"
    report += "- 已完成: #{completed_tasks}\n"
    report += "- 完成率: #{percentage}%\n\n"

    report += "## 📋 各阶段进度\n\n"

    phases.each do |phase|
      report += "### #{phase[:name]}\n\n"
      report += "- 完成: #{phase[:completed]}/#{phase[:total]} (#{phase[:percentage]}%)\n"
      report += "- 进行中: #{phase[:in_progress]}\n\n"
    end

    File.write(output_file, report)
    puts "✅ 进度报告已生成: #{output_file}"
  end

  private

  def extract_phases
    phases = []
    current_phase = nil

    @content.each_line do |line|
      # 检测阶段标题
      if line =~ /^## .* Phase (\d+\.\d+): (.+) \((\d+)\/(\d+)\)/
        phase_num = $1
        phase_name = $2
        completed = $3.to_i
        total = $4.to_i
        
        current_phase = {
          number: phase_num,
          name: "Phase #{phase_num}: #{phase_name}",
          completed: completed,
          total: total,
          in_progress: 0,
          percentage: total > 0 ? (completed * 100.0 / total).round(1) : 0
        }
        phases << current_phase
      end

      # 统计进行中的任务
      if current_phase && line =~ /^- \[-\]/
        current_phase[:in_progress] += 1
      end
    end

    phases
  end
end

# 使用示例和帮助
def show_usage
  puts <<~USAGE
    📖 迁移进度追踪工具使用说明
    =" * 60

    用法:
      ruby scripts/track_migration_progress.rb [命令] [参数]

    命令:
      complete <任务关键词>    标记任务为完成
      progress <任务关键词>    标记任务为进行中
      show                     显示当前进度
      report                   生成进度报告

    示例:
      # 标记任务完成
      ruby scripts/track_migration_progress.rb complete "ServiceLocator 配置"

      # 标记任务进行中
      ruby scripts/track_migration_progress.rb progress "核心服务迁移"

      # 显示进度
      ruby scripts/track_migration_progress.rb show

      # 生成报告
      ruby scripts/track_migration_progress.rb report
  USAGE
end

# 主程序
if ARGV.empty? || ARGV.include?('--help')
  show_usage
  exit 0
end

tracker = MigrationProgressTracker.new

command = ARGV[0]
case command
when 'complete'
  if ARGV[1]
    tracker.mark_complete(ARGV[1])
  else
    puts "❌ 请提供任务关键词"
  end
when 'progress'
  if ARGV[1]
    tracker.mark_in_progress(ARGV[1])
  else
    puts "❌ 请提供任务关键词"
  end
when 'show'
  tracker.show_progress
when 'report'
  tracker.generate_report
else
  puts "❌ 未知命令: #{command}"
  show_usage
  exit 1
end
