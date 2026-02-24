import CoreFoundation

/// 统一性能监控服务，提供耗时记录和超阈值告警
public final class PerformanceService: Sendable {
    public static let shared = PerformanceService()

    private init() {}

    /// 同步测量闭包执行耗时
    /// - Parameters:
    ///   - module: 模块标识
    ///   - operation: 操作名称
    ///   - thresholdMs: 告警阈值（毫秒）
    ///   - block: 待测量的闭包
    /// - Returns: 闭包的返回值
    @discardableResult
    public func measure<T>(
        _ module: LogModule,
        _ operation: String,
        thresholdMs: Double,
        _ block: () throws -> T
    ) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000

        if duration > thresholdMs {
            LogService.shared.warning(module, "\(operation) 耗时 \(String(format: "%.1f", duration))ms，超过阈值 \(String(format: "%.0f", thresholdMs))ms")
        } else {
            LogService.shared.debug(module, "\(operation) 完成，耗时 \(String(format: "%.1f", duration))ms")
        }

        return result
    }

    /// 异步测量闭包执行耗时
    /// - Parameters:
    ///   - module: 模块标识
    ///   - operation: 操作名称
    ///   - thresholdMs: 告警阈值（毫秒）
    ///   - block: 待测量的 async 闭包
    /// - Returns: 闭包的返回值
    @discardableResult
    public func measure<T>(
        _ module: LogModule,
        _ operation: String,
        thresholdMs: Double,
        _ block: () async throws -> T
    ) async rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try await block()
        let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000

        if duration > thresholdMs {
            LogService.shared.warning(module, "\(operation) 耗时 \(String(format: "%.1f", duration))ms，超过阈值 \(String(format: "%.0f", thresholdMs))ms")
        } else {
            LogService.shared.debug(module, "\(operation) 完成，耗时 \(String(format: "%.1f", duration))ms")
        }

        return result
    }
}
