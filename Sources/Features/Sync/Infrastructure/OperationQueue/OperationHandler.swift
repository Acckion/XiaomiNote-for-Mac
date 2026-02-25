import Foundation

// MARK: - 操作处理协议

/// 操作处理协议
///
/// 各操作域的 handler 实现此协议，由 OperationProcessor 调度层统一调用。
protocol OperationHandler: Sendable {
    /// 处理操作
    ///
    /// - Parameter operation: 要处理的操作
    /// - Throws: 执行错误
    func handle(_ operation: NoteOperation) async throws
}

// MARK: - 响应解析工具

/// 响应解析工具结构体
///
/// 提供 API 响应解析的纯函数，供各 handler 共用。
/// 所有方法均为纯函数，不依赖任何外部状态。
struct OperationResponseParser: Sendable {

    /// 检查 API 响应是否成功
    ///
    /// 按以下规则判断：
    /// 1. 如果存在 `code` 字段，检查是否等于 0
    /// 2. 如果存在 `R` 字段，检查是否为 "ok" 或 "OK"
    /// 3. 如果两个字段都不存在，默认返回 true
    ///
    /// - Parameter response: API 响应字典
    /// - Returns: 如果成功返回 true
    func isResponseSuccess(_ response: [String: Any]) -> Bool {
        if let code = response["code"] as? Int {
            return code == 0
        }
        if let r = response["R"] as? String {
            return r == "ok" || r == "OK"
        }
        return true
    }

    /// 从响应中提取 entry
    ///
    /// 按优先级提取：`data.entry` > 顶层 `entry`
    ///
    /// - Parameter response: API 响应字典
    /// - Returns: entry 字典，如果不存在返回 nil
    func extractEntry(from response: [String: Any]) -> [String: Any]? {
        if let data = response["data"] as? [String: Any],
           let entry = data["entry"] as? [String: Any]
        {
            return entry
        }
        if let entry = response["entry"] as? [String: Any] {
            return entry
        }
        return nil
    }

    /// 从响应中提取 tag
    ///
    /// 按优先级提取：`data.entry.tag` > `entry.tag` > 顶层 `tag` > fallbackTag
    ///
    /// - Parameters:
    ///   - response: API 响应字典
    ///   - fallbackTag: 备用 tag
    /// - Returns: tag 字符串
    func extractTag(from response: [String: Any], fallbackTag: String) -> String {
        if let data = response["data"] as? [String: Any],
           let entry = data["entry"] as? [String: Any],
           let tag = entry["tag"] as? String
        {
            return tag
        }
        if let entry = response["entry"] as? [String: Any],
           let tag = entry["tag"] as? String
        {
            return tag
        }
        if let tag = response["tag"] as? String {
            return tag
        }
        return fallbackTag
    }

    /// 从响应中提取错误信息
    ///
    /// 按优先级提取：`description` > `message` > `data.message` > defaultMessage
    ///
    /// - Parameters:
    ///   - response: API 响应字典
    ///   - defaultMessage: 默认错误信息
    /// - Returns: 错误信息字符串
    func extractErrorMessage(from response: [String: Any], defaultMessage: String) -> String {
        if let description = response["description"] as? String {
            return description
        }
        if let message = response["message"] as? String {
            return message
        }
        if let data = response["data"] as? [String: Any],
           let message = data["message"] as? String
        {
            return message
        }
        return defaultMessage
    }
}
