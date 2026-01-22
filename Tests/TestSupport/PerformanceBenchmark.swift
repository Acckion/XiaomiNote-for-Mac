///
//  PerformanceBenchmark.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  性能基准测试工具
//

import XCTest
@testable import MiNoteLibrary

/// 性能基准测试
///
/// 用于测试和比较新旧实现的性能
class PerformanceBenchmark: XCTestCase {
    
    // MARK: - Benchmark Metrics
    
    /// 性能指标
    struct Metrics {
        let name: String
        let executionTime: TimeInterval
        let memoryUsage: UInt64
        let iterations: Int
        
        var averageTime: TimeInterval {
            executionTime / Double(iterations)
        }
        
        func report() -> String {
            """
            📊 性能指标: \(name)
            ⏱️  总执行时间: \(String(format: "%.3f", executionTime))s
            ⚡️ 平均时间: \(String(format: "%.3f", averageTime * 1000))ms
            🔢 迭代次数: \(iterations)
            💾 内存使用: \(memoryUsage / 1024 / 1024)MB
            """
        }
    }
    
    // MARK: - Measurement
    
    /// 测量执行时间
    /// - Parameters:
    ///   - name: 测试名称
    ///   - iterations: 迭代次数
    ///   - block: 要测量的代码块
    /// - Returns: 性能指标
    func measure(
        name: String,
        iterations: Int = 100,
        block: () throws -> Void
    ) rethrows -> Metrics {
        let startMemory = getMemoryUsage()
        let startTime = Date()
        
        for _ in 0..<iterations {
            try block()
        }
        
        let endTime = Date()
        let endMemory = getMemoryUsage()
        
        let executionTime = endTime.timeIntervalSince(startTime)
        let memoryUsage = endMemory - startMemory
        
        return Metrics(
            name: name,
            executionTime: executionTime,
            memoryUsage: memoryUsage,
            iterations: iterations
        )
    }
    
    /// 测量异步执行时间
    /// - Parameters:
    ///   - name: 测试名称
    ///   - iterations: 迭代次数
    ///   - block: 要测量的异步代码块
    /// - Returns: 性能指标
    func measureAsync(
        name: String,
        iterations: Int = 100,
        block: () async throws -> Void
    ) async rethrows -> Metrics {
        let startMemory = getMemoryUsage()
        let startTime = Date()
        
        for _ in 0..<iterations {
            try await block()
        }
        
        let endTime = Date()
        let endMemory = getMemoryUsage()
        
        let executionTime = endTime.timeIntervalSince(startTime)
        let memoryUsage = endMemory - startMemory
        
        return Metrics(
            name: name,
            executionTime: executionTime,
            memoryUsage: memoryUsage,
            iterations: iterations
        )
    }
    
    // MARK: - Comparison
    
    /// 比较两个实现的性能
    /// - Parameters:
    ///   - oldImplementation: 旧实现
    ///   - newImplementation: 新实现
    ///   - iterations: 迭代次数
    func compare(
        oldImplementation: () throws -> Void,
        newImplementation: () throws -> Void,
        iterations: Int = 100
    ) rethrows {
        print("\n🔬 开始性能对比测试")
        print(String(repeating: "=", count: 60))
        
        let oldMetrics = try measure(name: "旧实现", iterations: iterations, block: oldImplementation)
        let newMetrics = try measure(name: "新实现", iterations: iterations, block: newImplementation)
        
        print("\n" + oldMetrics.report())
        print("\n" + newMetrics.report())
        
        // 计算改进百分比
        let timeImprovement = ((oldMetrics.averageTime - newMetrics.averageTime) / oldMetrics.averageTime) * 100
        let memoryImprovement = ((Double(oldMetrics.memoryUsage) - Double(newMetrics.memoryUsage)) / Double(oldMetrics.memoryUsage)) * 100
        
        print("\n📈 性能改进")
        print(String(repeating: "=", count: 60))
        print("⏱️  时间: \(String(format: "%.1f", timeImprovement))%")
        print("💾 内存: \(String(format: "%.1f", memoryImprovement))%")
        
        if timeImprovement > 0 {
            print("✅ 新实现更快")
        } else {
            print("⚠️  新实现较慢")
        }
    }
    
    /// 比较两个异步实现的性能
    /// - Parameters:
    ///   - oldImplementation: 旧实现
    ///   - newImplementation: 新实现
    ///   - iterations: 迭代次数
    func compareAsync(
        oldImplementation: () async throws -> Void,
        newImplementation: () async throws -> Void,
        iterations: Int = 100
    ) async rethrows {
        print("\n🔬 开始异步性能对比测试")
        print(String(repeating: "=", count: 60))
        
        let oldMetrics = try await measureAsync(name: "旧实现", iterations: iterations, block: oldImplementation)
        let newMetrics = try await measureAsync(name: "新实现", iterations: iterations, block: newImplementation)
        
        print("\n" + oldMetrics.report())
        print("\n" + newMetrics.report())
        
        // 计算改进百分比
        let timeImprovement = ((oldMetrics.averageTime - newMetrics.averageTime) / oldMetrics.averageTime) * 100
        let memoryImprovement = ((Double(oldMetrics.memoryUsage) - Double(newMetrics.memoryUsage)) / Double(oldMetrics.memoryUsage)) * 100
        
        print("\n📈 性能改进")
        print(String(repeating: "=", count: 60))
        print("⏱️  时间: \(String(format: "%.1f", timeImprovement))%")
        print("💾 内存: \(String(format: "%.1f", memoryImprovement))%")
        
        if timeImprovement > 0 {
            print("✅ 新实现更快")
        } else {
            print("⚠️  新实现较慢")
        }
    }
    
    // MARK: - Baseline
    
    /// 建立性能基线
    /// - Parameters:
    ///   - name: 基线名称
    ///   - block: 要测量的代码块
    func establishBaseline(name: String, block: () throws -> Void) rethrows {
        let metrics = try measure(name: name, iterations: 1000, block: block)
        
        print("\n📊 性能基线: \(name)")
        print(String(repeating: "=", count: 60))
        print(metrics.report())
        
        // 保存基线到 UserDefaults（仅用于测试）
        let key = "PerformanceBaseline_\(name)"
        UserDefaults.standard.set(metrics.averageTime, forKey: key)
        
        print("\n✅ 基线已保存")
    }
    
    /// 与基线对比
    /// - Parameters:
    ///   - name: 基线名称
    ///   - block: 要测量的代码块
    func compareWithBaseline(name: String, block: () throws -> Void) rethrows {
        let key = "PerformanceBaseline_\(name)"
        guard let baseline = UserDefaults.standard.object(forKey: key) as? TimeInterval else {
            print("⚠️  未找到基线: \(name)")
            return
        }
        
        let metrics = try measure(name: name, iterations: 1000, block: block)
        
        print("\n📊 与基线对比: \(name)")
        print(String(repeating: "=", count: 60))
        print("📍 基线: \(String(format: "%.3f", baseline * 1000))ms")
        print("📊 当前: \(String(format: "%.3f", metrics.averageTime * 1000))ms")
        
        let improvement = ((baseline - metrics.averageTime) / baseline) * 100
        print("📈 改进: \(String(format: "%.1f", improvement))%")
        
        if improvement > 0 {
            print("✅ 性能提升")
        } else if improvement < -10 {
            print("⚠️  性能下降超过 10%")
            XCTFail("性能下降超过 10%")
        } else {
            print("ℹ️  性能基本持平")
        }
    }
    
    // MARK: - Memory
    
    /// 获取当前内存使用量
    /// - Returns: 内存使用量（字节）
    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
}

// MARK: - Performance Test Example

/// 性能测试示例
///
/// 使用此示例创建性能测试
///
/// ```swift
/// final class ServicePerformanceTests: PerformanceBenchmark {
///     func testNoteServicePerformance() throws {
///         let oldService = MiNoteService.shared
///         let newService = DefaultNoteService(client: NetworkClient())
///
///         try compare(
///             oldImplementation: {
///                 // 旧实现的代码
///             },
///             newImplementation: {
///                 // 新实现的代码
///             },
///             iterations: 100
///         )
///     }
/// }
/// ```
class PerformanceTestExample: PerformanceBenchmark {
    
    func testExample() throws {
        // 建立基线
        try establishBaseline(name: "ArrayIteration") {
            let array = Array(0..<1000)
            _ = array.map { $0 * 2 }
        }
        
        // 与基线对比
        try compareWithBaseline(name: "ArrayIteration") {
            let array = Array(0..<1000)
            _ = array.map { $0 * 2 }
        }
    }
}
