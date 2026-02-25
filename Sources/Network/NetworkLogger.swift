import Foundation

actor NetworkLogger {
    @available(*, deprecated, message: "使用 NetworkModule 注入的实例")
    static let shared = NetworkLogger()

    private var logs: [NetworkLogEntry] = []
    private let maxLogs = 1000 // 最多保存1000条日志

    // 用于防止重复记录
    private var lastLogMessage = ""
    private var lastLogTime = Date.distantPast
    private let duplicateThreshold: TimeInterval = 0.1 // 100毫秒内相同的日志视为重复

    init() {}

    func logRequest(url: String, method: String, headers: [String: String]?, body: String?) {
        var logMessage = "请求: \(method) \(url)"
        if let body, !body.isEmpty {
            logMessage += "\n请求体: \(LogService.truncate(body, maxLength: 200))"
        }

        if shouldSkipLog(logMessage) {
            return
        }

        let entry = NetworkLogEntry(
            id: UUID(),
            timestamp: Date(),
            type: .request,
            url: url,
            method: method,
            headers: headers,
            body: body,
            statusCode: nil,
            response: nil,
            error: nil
        )

        addLog(entry)

        LogService.shared.debug(.network, logMessage)
    }

    func logResponse(url: String, method: String, statusCode: Int, headers: [String: String]?, response: String?, error: Error?) {
        var logMessage = "响应: \(method) \(url) - 状态码: \(statusCode)"
        if let response, !response.isEmpty {
            let preview = LogService.truncate(response, maxLength: 200)
            logMessage += "\n响应体: \(preview)"
        }
        if let error {
            logMessage += "\n错误: \(error.localizedDescription)"
        }

        if shouldSkipLog(logMessage) {
            return
        }

        let entry = NetworkLogEntry(
            id: UUID(),
            timestamp: Date(),
            type: .response,
            url: url,
            method: method,
            headers: headers,
            body: nil,
            statusCode: statusCode,
            response: response,
            error: error?.localizedDescription
        )

        addLog(entry)

        if statusCode >= 400 {
            LogService.shared.error(.network, logMessage)
        } else {
            LogService.shared.debug(.network, logMessage)
        }
    }

    func logError(url: String, method: String, error: Error) {
        let logMessage = "错误: \(method) \(url) - \(error.localizedDescription)"

        if shouldSkipLog(logMessage) {
            return
        }

        let entry = NetworkLogEntry(
            id: UUID(),
            timestamp: Date(),
            type: .error,
            url: url,
            method: method,
            headers: nil,
            body: nil,
            statusCode: nil,
            response: nil,
            error: error.localizedDescription
        )

        addLog(entry)

        LogService.shared.error(.network, logMessage)
    }

    private func addLog(_ entry: NetworkLogEntry) {
        logs.insert(entry, at: 0) // 最新的日志放在最前面
        if logs.count > maxLogs {
            logs.removeLast()
        }
    }

    private func shouldSkipLog(_ logMessage: String) -> Bool {
        let now = Date()
        // 如果相同的日志在短时间内被记录，跳过
        if logMessage == lastLogMessage, now.timeIntervalSince(lastLogTime) < duplicateThreshold {
            return true
        }
        lastLogMessage = logMessage
        lastLogTime = now
        return false
    }

    func addLogEntry(_ entry: NetworkLogEntry) {
        addLog(entry)
    }

    func getLogs() -> [NetworkLogEntry] {
        logs
    }

    func clearLogs() {
        logs.removeAll()
    }

    func exportLogs() -> String {
        var exportText = "小米笔记网络日志导出\n"
        exportText += "导出时间: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))\n"
        exportText += "日志数量: \(logs.count)\n\n"

        for log in logs.reversed() { // 按时间顺序导出
            exportText += "\(log.description)\n\n"
        }

        return exportText
    }
}

struct NetworkLogEntry: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let type: LogType
    let url: String
    let method: String
    let headers: [String: String]?
    let body: String?
    let statusCode: Int?
    let response: String?
    let error: String?

    enum LogType: Sendable {
        case request
        case response
        case error

        var symbol: String {
            switch self {
            case .request: "[->]"
            case .response: "[<-]"
            case .error: "[!!]"
            }
        }

        var description: String {
            switch self {
            case .request: "请求"
            case .response: "响应"
            case .error: "错误"
            }
        }
    }

    var description: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        var desc = "\(type.symbol) [\(dateFormatter.string(from: timestamp))] \(type.description): \(method) \(url)"

        if let statusCode {
            desc += "\n状态码: \(statusCode)"
        }

        if let body, !body.isEmpty {
            let bodyPreview = body.count > 500 ? String(body.prefix(500)) + "..." : body
            desc += "\n请求体: \(bodyPreview)"
        }

        if let response, !response.isEmpty {
            let responsePreview = response.count > 500 ? String(response.prefix(500)) + "..." : response
            desc += "\n响应体: \(responsePreview)"
        }

        if let error {
            desc += "\n错误: \(error)"
        }

        return desc
    }
}
