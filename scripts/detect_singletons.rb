#!/usr/bin/env ruby
require 'set'

# 检测项目中的单例使用
class SingletonDetector
  def initialize(directory)
    @directory = directory
    @singletons = []
  end

  def detect
    puts "🔍 扫描目录: #{@directory}"
    puts "=" * 60

    Dir.glob("#{@directory}/**/*.swift").each do |file|
      detect_in_file(file)
    end

    report
  end

  private

  def detect_in_file(file)
    content = File.read(file)
    line_number = 0

    content.each_line do |line|
      line_number += 1

      # 检测 .shared 模式
      if line =~ /(\w+)\.shared/
        class_name = $1
        @singletons << {
          class: class_name,
          file: file,
          line: line_number,
          code: line.strip
        }
      end
    end
  end

  def report
    puts "\n📊 检测结果"
    puts "=" * 60

    grouped = @singletons.group_by { |s| s[:class] }
    
    puts "\n总计发现 #{grouped.keys.length} 个单例类"
    puts "总计 #{@singletons.length} 次使用\n\n"

    # 按使用次数排序
    sorted = grouped.sort_by { |_, uses| -uses.length }

    sorted.each do |klass, uses|
      puts "#{klass}.shared (#{uses.length} 次使用)"
      
      # 显示前 5 个使用位置
      uses.first(5).each do |use|
        relative_path = use[:file].gsub(@directory + '/', '')
        puts "  📄 #{relative_path}:#{use[:line]}"
        puts "     #{use[:code]}"
      end

      if uses.length > 5
        puts "  ... 还有 #{uses.length - 5} 处使用"
      end
      puts ""
    end

    # 生成迁移优先级建议
    puts "\n🎯 迁移优先级建议"
    puts "=" * 60
    
    high_priority = sorted.select { |_, uses| uses.length > 20 }
    medium_priority = sorted.select { |_, uses| uses.length > 10 && uses.length <= 20 }
    low_priority = sorted.select { |_, uses| uses.length <= 10 }

    puts "\n🔴 高优先级 (使用 > 20 次):"
    high_priority.each { |klass, uses| puts "  - #{klass} (#{uses.length} 次)" }

    puts "\n🟡 中优先级 (使用 10-20 次):"
    medium_priority.each { |klass, uses| puts "  - #{klass} (#{uses.length} 次)" }

    puts "\n🟢 低优先级 (使用 < 10 次):"
    low_priority.each { |klass, uses| puts "  - #{klass} (#{uses.length} 次)" }
  end
end

# 运行检测
if ARGV.empty?
  detector = SingletonDetector.new("Sources")
else
  detector = SingletonDetector.new(ARGV[0])
end

detector.detect
