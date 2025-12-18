import Foundation
import OSLog

final class NetworkLogger: @unchecked Sendable {
    static let shared = NetworkLogger()
    
    private let logger = Logger(subsystem: "com.xiaomi.minote.mac", category: "network")
    private var logs: [NetworkLogEntry] = []
    private let maxLogs = 1000 // 最多保存1000条日志
    private let queue = DispatchQueue(label: "com.xiaomi.minote.mac.networklogger", qos: .utility)
    
    private init() {}
    
    func logRequest(url: String, method: String, headers: [String: String]?, body: String?) {
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
        
        // 使用系统日志记录
        var logMessage = "📤 请求: \(method) \(url)"
        if let headers = headers, !headers.isEmpty {
            logMessage += "\n请求头: \(headers)"
        }
        if let body = body, !body.isEmpty {
            logMessage += "\n请求体: \(body)"
        }
        logger.info("\(logMessage)")
        
        // 同时输出到控制台，便于Xcode调试
        print("[NETWORK] \(logMessage)")
    }
    
    func logResponse(url: String, method: String, statusCode: Int, headers: [String: String]?, response: String?, error: Error?) {
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
        
        // 使用系统日志记录
        var logMessage = "📥 响应: \(method) \(url) - 状态码: \(statusCode)"
        if let headers = headers, !headers.isEmpty {
            logMessage += "\n响应头: \(headers)"
        }
        if let response = response, !response.isEmpty {
            let preview = response.count > 500 ? String(response.prefix(500)) + "..." : response
            logMessage += "\n响应体: \(preview)"
        }
        if let error = error {
            logMessage += "\n错误: \(error.localizedDescription)"
        }
        
        if statusCode >= 400 {
            logger.error("\(logMessage)")
        } else {
            logger.info("\(logMessage)")
        }
        
        // 同时输出到控制台，便于Xcode调试
        print("[NETWORK] \(logMessage)")
    }
    
    func logError(url: String, method: String, error: Error) {
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
        
        let logMessage = "❌ 错误: \(method) \(url) - \(error.localizedDescription)"
        logger.error("\(logMessage)")
        
        // 同时输出到控制台，便于Xcode调试
        print("[NETWORK] \(logMessage)")
    }
    
    private func addLog(_ entry: NetworkLogEntry) {
        queue.sync {
            logs.insert(entry, at: 0) // 最新的日志放在最前面
            if logs.count > maxLogs {
                logs.removeLast()
            }
        }
    }
    
    func addLogEntry(_ entry: NetworkLogEntry) {
        addLog(entry)
    }
    
    func getLogs() -> [NetworkLogEntry] {
        return queue.sync {
            return logs
        }
    }
    
    func clearLogs() {
        queue.sync {
            logs.removeAll()
        }
    }
    
    func exportLogs() -> String {
        return queue.sync {
            var exportText = "小米笔记网络日志导出\n"
            exportText += "导出时间: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))\n"
            exportText += "日志数量: \(logs.count)\n\n"
            
            for log in logs.reversed() { // 按时间顺序导出
                exportText += "\(log.description)\n\n"
            }
            
            return exportText
        }
    }
}

struct NetworkLogEntry: Identifiable {
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
    
    enum LogType {
        case request
        case response
        case error
        
        var emoji: String {
            switch self {
            case .request: return "📤"
            case .response: return "📥"
            case .error: return "❌"
            }
        }
        
        var description: String {
            switch self {
            case .request: return "请求"
            case .response: return "响应"
            case .error: return "错误"
            }
        }
    }
    
    var description: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        var desc = "\(type.emoji) [\(dateFormatter.string(from: timestamp))] \(type.description): \(method) \(url)"
        
        if let statusCode = statusCode {
            desc += "\n状态码: \(statusCode)"
        }
        
        if let headers = headers, !headers.isEmpty {
            desc += "\n请求头: \(headers)"
        }
        
        if let body = body, !body.isEmpty {
            let bodyPreview = body.count > 500 ? String(body.prefix(500)) + "..." : body
            desc += "\n请求体: \(bodyPreview)"
        }
        
        if let response = response, !response.isEmpty {
            let responsePreview = response.count > 500 ? String(response.prefix(500)) + "..." : response
            desc += "\n响应体: \(responsePreview)"
        }
        
        if let error = error {
            desc += "\n错误: \(error)"
        }
        
        return desc
    }
}
