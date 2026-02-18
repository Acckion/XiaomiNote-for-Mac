//
//  PerformanceMonitoringPropertyTests.swift
//  MiNoteLibraryTests
//
//  性能监控属性测试 - 验证性能指标监控功能
//  属性 20: 性能指标监控
//  验证需求: 8.3
//
//  Feature: format-menu-fix, Property 20: 性能指标监控
//

import AppKit
import XCTest
@testable import MiNoteLibrary

/// 性能监控属性测试
///
/// 本测试套件使用基于属性的测试方法，通过生成随机输入来验证性能监控功能。
/// 每个测试运行 100 次迭代，确保在各种输入条件下性能监控正确记录指标。
///
/// **属性 20**: 对于任何状态同步延迟的情况，系统应该记录相应的性能指标
/// **验证需求**: 8.3
@MainActor
final class PerformanceMonitoringPropertyTests: XCTestCase {

    // MARK: - Properties

    var performanceMonitor: FormatMenuPerformanceMonitor!
    var logger: NativeEditorLogger!
    var debugger: FormatMenuDebugger!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        // 获取单例并重置状态
        performanceMonitor = FormatMenuPerformanceMonitor.shared
        performanceMonitor.clearAllRecords()
        performanceMonitor.isEnabled = true

        logger = NativeEditorLogger.shared
        logger.clearAllRecords()
        logger.isDebugModeEnabled = true

        debugger = FormatMenuDebugger.shared
        debugger.clearAllRecords()
        debugger.isEnabled = true
    }

    override func tearDown() async throws {
        performanceMonitor.isEnabled = false
        performanceMonitor.clearAllRecords()
        logger.isDebugModeEnabled = false
        logger.clearAllRecords()
        debugger.isEnabled = false
        debugger.clearAllRecords()
        try await super.tearDown()
    }

    // MARK: - 属性 20: 性能指标监控

    // 验证需求: 8.3

    /// 属性测试：格式应用性能指标记录
    ///
    /// **属性**: 对于任何格式应用操作，系统应该记录相应的性能指标
    /// **验证需求**: 8.3
    ///
    /// 测试策略：
    /// 1. 生成随机格式类型
    /// 2. 生成随机持续时间
    /// 3. 记录性能指标
    /// 4. 验证指标被正确记录
    func testProperty20_FormatApplicationMetricRecording() throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 格式应用性能指标记录 (迭代次数: \(iterations))")

        let formats: [TextFormat] = [.bold, .italic, .underline, .strikethrough, .highlight]

        for iteration in 1 ... iterations {
            // 1. 生成随机测试数据
            let format = try XCTUnwrap(formats.randomElement())
            let duration = Double.random(in: 0.001 ... 0.1) // 1ms - 100ms
            let success = Bool.random()

            // 2. 记录性能指标
            performanceMonitor.recordMetric(
                type: .formatApplication,
                format: format,
                duration: duration,
                success: success
            )

            // 3. 验证指标被记录
            let records = performanceMonitor.getRecords(for: .formatApplication)
            XCTAssertGreaterThanOrEqual(
                records.count,
                iteration,
                "迭代 \(iteration): 格式应用指标应该被记录"
            )

            // 4. 验证最后一条记录的内容
            if let lastRecord = records.last {
                XCTAssertEqual(
                    lastRecord.format,
                    format,
                    "迭代 \(iteration): 记录的格式应该匹配"
                )
                XCTAssertEqual(
                    lastRecord.success,
                    success,
                    "迭代 \(iteration): 记录的成功状态应该匹配"
                )
                XCTAssertEqual(
                    lastRecord.duration,
                    duration,
                    accuracy: 0.0001,
                    "迭代 \(iteration): 记录的持续时间应该匹配"
                )
            }
        }

        // 验证总记录数
        let totalRecords = performanceMonitor.getRecords(for: .formatApplication)
        XCTAssertEqual(
            totalRecords.count,
            iterations,
            "应该记录 \(iterations) 条格式应用指标"
        )

        print("[PropertyTest] ✅ 格式应用性能指标记录测试完成")
    }

    /// 属性测试：状态同步性能指标记录
    ///
    /// **属性**: 对于任何状态同步操作，系统应该记录相应的性能指标
    /// **验证需求**: 8.3
    func testProperty20_StateSynchronizationMetricRecording() {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 状态同步性能指标记录 (迭代次数: \(iterations))")

        for iteration in 1 ... iterations {
            // 1. 生成随机测试数据
            let duration = Double.random(in: 0.001 ... 0.2) // 1ms - 200ms
            let success = Bool.random()
            let cursorPosition = Int.random(in: 0 ... 1000)

            // 2. 记录性能指标
            performanceMonitor.recordMetric(
                type: .stateSynchronization,
                format: nil,
                duration: duration,
                success: success,
                additionalInfo: ["cursorPosition": cursorPosition]
            )

            // 3. 验证指标被记录
            let records = performanceMonitor.getRecords(for: .stateSynchronization)
            XCTAssertGreaterThanOrEqual(
                records.count,
                iteration,
                "迭代 \(iteration): 状态同步指标应该被记录"
            )
        }

        // 验证总记录数
        let totalRecords = performanceMonitor.getRecords(for: .stateSynchronization)
        XCTAssertEqual(
            totalRecords.count,
            iterations,
            "应该记录 \(iterations) 条状态同步指标"
        )

        print("[PropertyTest] ✅ 状态同步性能指标记录测试完成")
    }

    /// 属性测试：阈值超出检测
    ///
    /// **属性**: 对于任何超过阈值的操作，系统应该记录警告
    /// **验证需求**: 8.3
    func testProperty20_ThresholdExceededDetection() {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 阈值超出检测 (迭代次数: \(iterations))")

        let threshold = performanceMonitor.thresholds.formatApplication
        var exceededCount = 0

        for iteration in 1 ... iterations {
            // 1. 生成随机持续时间（50% 概率超过阈值）
            let exceedThreshold = Bool.random()
            let duration: TimeInterval
            if exceedThreshold {
                duration = threshold + Double.random(in: 0.01 ... 0.1)
                exceededCount += 1
            } else {
                duration = Double.random(in: 0.001 ... threshold)
            }

            // 2. 记录性能指标
            performanceMonitor.recordMetric(
                type: .formatApplication,
                format: .bold,
                duration: duration,
                success: true
            )
        }

        // 3. 验证超过阈值的记录数
        let exceededRecords = performanceMonitor.getThresholdExceededRecords()
        XCTAssertEqual(
            exceededRecords.count,
            exceededCount,
            "超过阈值的记录数应该为 \(exceededCount)"
        )

        print("[PropertyTest] 阈值超出统计:")
        print("  - 总记录数: \(iterations)")
        print("  - 超过阈值: \(exceededCount)")
        print("  - 检测到的超出记录: \(exceededRecords.count)")

        print("[PropertyTest] ✅ 阈值超出检测测试完成")
    }

    /// 属性测试：性能统计计算
    ///
    /// **属性**: 对于任何一组性能记录，系统应该正确计算统计信息
    /// **验证需求**: 8.3
    func testProperty20_PerformanceStatisticsCalculation() throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 性能统计计算 (迭代次数: \(iterations))")

        var durations: [TimeInterval] = []
        var successCount = 0

        for _ in 1 ... iterations {
            // 1. 生成随机测试数据
            let duration = Double.random(in: 0.001 ... 0.1)
            let success = Bool.random()

            durations.append(duration)
            if success { successCount += 1 }

            // 2. 记录性能指标
            performanceMonitor.recordMetric(
                type: .formatApplication,
                format: .bold,
                duration: duration,
                success: success
            )
        }

        // 3. 获取统计信息
        guard let stats = performanceMonitor.getStatistics(for: .formatApplication) else {
            XCTFail("应该能够获取统计信息")
            return
        }

        // 4. 验证统计信息
        XCTAssertEqual(stats.count, iterations, "记录数应该正确")
        XCTAssertEqual(stats.successCount, successCount, "成功数应该正确")
        XCTAssertEqual(stats.failureCount, iterations - successCount, "失败数应该正确")

        // 验证平均值
        let expectedAvg = durations.reduce(0, +) / Double(iterations)
        XCTAssertEqual(
            stats.averageDuration,
            expectedAvg,
            accuracy: 0.0001,
            "平均持续时间应该正确"
        )

        // 验证最小值和最大值
        let sortedDurations = durations.sorted()
        XCTAssertEqual(
            stats.minDuration,
            try XCTUnwrap(sortedDurations.first),
            accuracy: 0.0001,
            "最小持续时间应该正确"
        )
        XCTAssertEqual(
            stats.maxDuration,
            try XCTUnwrap(sortedDurations.last),
            accuracy: 0.0001,
            "最大持续时间应该正确"
        )

        print("[PropertyTest] 性能统计:")
        print("  - 记录数: \(stats.count)")
        print("  - 成功率: \(String(format: "%.1f", stats.successRate))%")
        print("  - 平均时间: \(String(format: "%.2f", stats.averageMs))ms")
        print("  - 最小时间: \(String(format: "%.2f", stats.minMs))ms")
        print("  - 最大时间: \(String(format: "%.2f", stats.maxMs))ms")

        print("[PropertyTest] ✅ 性能统计计算测试完成")
    }

    /// 属性测试：日志记录完整性
    ///
    /// **属性**: 对于任何性能警告，系统应该记录完整的日志信息
    /// **验证需求**: 8.3
    func testProperty20_LogRecordingCompleteness() {
        let iterations = 50
        print("\n[PropertyTest] 开始属性测试: 日志记录完整性 (迭代次数: \(iterations))")

        let threshold = performanceMonitor.thresholds.formatApplication
        var warningCount = 0

        for _ in 1 ... iterations {
            // 1. 生成超过阈值的持续时间
            let duration = threshold + Double.random(in: 0.01 ... 0.1)
            warningCount += 1

            // 2. 记录性能指标（会触发警告日志）
            performanceMonitor.recordMetric(
                type: .formatApplication,
                format: .bold,
                duration: duration,
                success: true
            )
        }

        // 3. 验证警告日志被记录
        let warningLogs = logger.getLogs(level: .warning)
        let performanceLogs = warningLogs.filter { $0.category == LogCategory.performance.rawValue }

        XCTAssertGreaterThanOrEqual(
            performanceLogs.count,
            warningCount,
            "应该记录至少 \(warningCount) 条性能警告日志"
        )

        // 4. 验证日志内容完整性
        for log in performanceLogs {
            XCTAssertFalse(log.message.isEmpty, "日志消息不应为空")
            XCTAssertNotNil(log.additionalInfo, "日志应包含附加信息")
        }

        print("[PropertyTest] 日志记录统计:")
        print("  - 预期警告数: \(warningCount)")
        print("  - 实际性能警告日志数: \(performanceLogs.count)")

        print("[PropertyTest] ✅ 日志记录完整性测试完成")
    }

    /// 属性测试：性能报告生成
    ///
    /// **属性**: 对于任何一组性能记录，系统应该能够生成完整的性能报告
    /// **验证需求**: 8.3
    func testProperty20_PerformanceReportGeneration() throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 性能报告生成 (迭代次数: \(iterations))")

        // 1. 生成随机性能记录
        for _ in 1 ... iterations {
            let type = try XCTUnwrap(FormatMenuMetricType.allCases.randomElement())
            let duration = Double.random(in: 0.001 ... 0.2)
            let success = Bool.random()

            performanceMonitor.recordMetric(
                type: type,
                format: type == .formatApplication ? .bold : nil,
                duration: duration,
                success: success
            )
        }

        // 2. 生成性能报告
        let report = performanceMonitor.generatePerformanceReport()

        // 3. 验证报告内容
        XCTAssertFalse(report.isEmpty, "性能报告不应为空")
        XCTAssertTrue(report.contains("性能摘要"), "报告应包含性能摘要")
        XCTAssertTrue(report.contains("总记录数"), "报告应包含总记录数")
        XCTAssertTrue(report.contains("性能合规性检查"), "报告应包含合规性检查")

        // 4. 验证合规性检查
        let (passed, issues) = performanceMonitor.checkPerformanceCompliance()
        if !passed {
            XCTAssertFalse(issues.isEmpty, "如果未通过合规性检查，应该有问题列表")
            for issue in issues {
                XCTAssertTrue(
                    report.contains(issue) || report.contains("问题"),
                    "报告应包含问题信息"
                )
            }
        }

        print("[PropertyTest] 性能报告生成完成")
        print("  - 报告长度: \(report.count) 字符")
        print("  - 合规性检查: \(passed ? "通过" : "未通过")")
        if !issues.isEmpty {
            print("  - 问题数: \(issues.count)")
        }

        print("[PropertyTest] ✅ 性能报告生成测试完成")
    }

    /// 属性测试：多类型指标记录
    ///
    /// **属性**: 对于任何类型的性能指标，系统应该正确分类记录
    /// **验证需求**: 8.3
    func testProperty20_MultiTypeMetricRecording() throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 多类型指标记录 (迭代次数: \(iterations))")

        var typeCounts: [FormatMenuMetricType: Int] = [:]
        for type in FormatMenuMetricType.allCases {
            typeCounts[type] = 0
        }

        for _ in 1 ... iterations {
            // 1. 随机选择指标类型
            let type = try XCTUnwrap(FormatMenuMetricType.allCases.randomElement())
            typeCounts[type] += 1

            // 2. 记录性能指标
            performanceMonitor.recordMetric(
                type: type,
                format: nil,
                duration: Double.random(in: 0.001 ... 0.1),
                success: true
            )
        }

        // 3. 验证各类型的记录数
        for (type, expectedCount) in typeCounts {
            let records = performanceMonitor.getRecords(for: type)
            XCTAssertEqual(
                records.count,
                expectedCount,
                "\(type.displayName) 类型应该有 \(expectedCount) 条记录"
            )
        }

        // 4. 验证总记录数
        let allRecords = performanceMonitor.getAllRecords()
        XCTAssertEqual(
            allRecords.count,
            iterations,
            "总记录数应该为 \(iterations)"
        )

        print("[PropertyTest] 各类型记录统计:")
        for (type, count) in typeCounts.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            print("  - \(type.displayName): \(count)")
        }

        print("[PropertyTest] ✅ 多类型指标记录测试完成")
    }

    /// 属性测试：记录清理功能
    ///
    /// **属性**: 对于任何清理操作，系统应该正确清除指定的记录
    /// **验证需求**: 8.3
    func testProperty20_RecordCleanup() throws {
        let iterations = 50
        print("\n[PropertyTest] 开始属性测试: 记录清理功能 (迭代次数: \(iterations))")

        // 1. 生成随机性能记录
        for _ in 1 ... iterations {
            let type = try XCTUnwrap(FormatMenuMetricType.allCases.randomElement())
            performanceMonitor.recordMetric(
                type: type,
                format: nil,
                duration: Double.random(in: 0.001 ... 0.1),
                success: true
            )
        }

        // 验证记录已生成
        XCTAssertEqual(
            performanceMonitor.getAllRecords().count,
            iterations,
            "应该有 \(iterations) 条记录"
        )

        // 2. 测试按类型清理
        let typeToClean = FormatMenuMetricType.formatApplication
        let countBefore = performanceMonitor.getRecords(for: typeToClean).count
        performanceMonitor.clearRecords(for: typeToClean)
        let countAfter = performanceMonitor.getRecords(for: typeToClean).count

        XCTAssertEqual(
            countAfter,
            0,
            "\(typeToClean.displayName) 类型的记录应该被清除"
        )

        // 3. 测试全部清理
        performanceMonitor.clearAllRecords()
        XCTAssertEqual(
            performanceMonitor.getAllRecords().count,
            0,
            "所有记录应该被清除"
        )

        print("[PropertyTest] 记录清理统计:")
        print("  - 清理前 \(typeToClean.displayName) 记录数: \(countBefore)")
        print("  - 清理后 \(typeToClean.displayName) 记录数: \(countAfter)")
        print("  - 全部清理后总记录数: \(performanceMonitor.getAllRecords().count)")

        print("[PropertyTest] ✅ 记录清理功能测试完成")
    }
}
