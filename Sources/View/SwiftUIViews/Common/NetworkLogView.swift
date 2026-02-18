import SwiftUI

struct NetworkLogView: View {
    @StateObject private var viewModel = NetworkLogViewModel()
    @State private var searchText = ""
    @State private var selectedLogType: NetworkLogEntry.LogType?
    @State private var showingExportSheet = false
    @State private var showingClearAlert = false

    var filteredLogs: [NetworkLogEntry] {
        var logs = viewModel.logs

        // 按类型过滤
        if let selectedType = selectedLogType {
            logs = logs.filter { $0.type == selectedType }
        }

        // 按搜索文本过滤
        if !searchText.isEmpty {
            logs = logs.filter { log in
                log.url.localizedCaseInsensitiveContains(searchText) ||
                    log.method.localizedCaseInsensitiveContains(searchText) ||
                    (log.response?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                    (log.error?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return logs
    }

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Text("网络日志")
                    .font(.headline)

                Spacer()

                // 日志类型筛选器
                Picker("日志类型", selection: $selectedLogType) {
                    Text("全部").tag(NetworkLogEntry.LogType?.none)
                    ForEach(NetworkLogEntry.LogType.allCases, id: \.self) { type in
                        Text("\(type.emoji) \(type.description)")
                            .tag(Optional(type))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)

                // 搜索框
                TextField("搜索...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 200)

                // 操作按钮
                Button(action: {
                    viewModel.refreshLogs()
                }) {
                    Image(systemName: "arrow.clockwise")
                    Text("刷新")
                }

                Button(action: {
                    showingExportSheet = true
                }) {
                    Image(systemName: "square.and.arrow.up")
                    Text("导出")
                }

                Button(action: {
                    showingClearAlert = true
                }) {
                    Image(systemName: "trash")
                    Text("清空")
                }
                .foregroundColor(.red)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            // 统计信息
            HStack {
                Text("总计: \(viewModel.logs.count) 条日志")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("请求: \(viewModel.logs.count(where: { $0.type == .request }))")
                    .font(.caption)
                    .foregroundColor(.blue)

                Text("响应: \(viewModel.logs.count(where: { $0.type == .response }))")
                    .font(.caption)
                    .foregroundColor(.green)

                Text("错误: \(viewModel.logs.count(where: { $0.type == .error }))")
                    .font(.caption)
                    .foregroundColor(.red)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            // 日志列表
            if filteredLogs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "network")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("暂无网络日志")
                        .font(.title2)
                        .foregroundColor(.secondary)

                    if !searchText.isEmpty || selectedLogType != nil {
                        Text("尝试清除筛选条件")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("清除筛选") {
                            searchText = ""
                            selectedLogType = nil
                        }
                    } else {
                        Text("执行网络操作（如同步、登录等）后，日志将显示在这里")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredLogs) { log in
                    NetworkLogRow(log: log)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .contextMenu {
                            Button(action: {
                                copyLogToClipboard(log)
                            }) {
                                Image(systemName: "doc.on.doc")
                                Text("复制日志")
                            }

                            Button(action: {
                                copyURLToClipboard(log)
                            }) {
                                Image(systemName: "link")
                                Text("复制URL")
                            }

                            Divider()

                            Button(action: {
                                viewModel.removeLog(log.id)
                            }) {
                                Image(systemName: "trash")
                                Text("删除此日志")
                            }
                        }
                }
                .listStyle(PlainListStyle())
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            viewModel.refreshLogs()
        }
        .alert("清空日志", isPresented: $showingClearAlert) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                viewModel.clearLogs()
            }
        } message: {
            Text("确定要清空所有网络日志吗？此操作不可撤销。")
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportLogView(logs: viewModel.logs)
        }
    }

    private func copyLogToClipboard(_ log: NetworkLogEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(log.description, forType: .string)

        // 显示提示
        showToast(message: "日志已复制到剪贴板")
    }

    private func copyURLToClipboard(_ log: NetworkLogEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(log.url, forType: .string)

        // 显示提示
        showToast(message: "URL已复制到剪贴板")
    }

    private func showToast(message: String) {
        // 这里可以添加一个toast提示
        // 暂时使用简单的alert
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
}

struct NetworkLogRow: View {
    let log: NetworkLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 标题行
            HStack {
                Text(log.type.emoji)
                    .font(.title3)

                VStack(alignment: .leading) {
                    Text("\(log.method) \(log.url)")
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack {
                        Text(formatDate(log.timestamp))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if let statusCode = log.statusCode {
                            StatusCodeBadge(statusCode: statusCode)
                        }
                    }
                }

                Spacer()
            }

            // 请求头
            if let headers = log.headers, !headers.isEmpty {
                DisclosureGroup("请求头") {
                    ForEach(Array(headers.keys.sorted()), id: \.self) { key in
                        HStack {
                            Text(key)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.blue)
                            Text(":")
                            Text(headers[key] ?? "")
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
                .font(.caption)
            }

            // 请求体
            if let body = log.body, !body.isEmpty {
                DisclosureGroup("请求体") {
                    Text(body)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(4)
                }
                .font(.caption)
            }

            // 响应体
            if let response = log.response, !response.isEmpty {
                DisclosureGroup("响应体") {
                    Text(response)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(4)
                }
                .font(.caption)
            }

            // 错误信息
            if let error = log.error, !error.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(4)
                .background(Color.red.opacity(0.1))
                .cornerRadius(4)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(logBackgroundColor)
        .cornerRadius(8)
    }

    private var logBackgroundColor: Color {
        switch log.type {
        case .request:
            return Color.blue.opacity(0.05)
        case .response:
            if let statusCode = log.statusCode {
                if statusCode >= 400 {
                    return Color.red.opacity(0.05)
                } else {
                    return Color.green.opacity(0.05)
                }
            }
            return Color.green.opacity(0.05)
        case .error:
            return Color.red.opacity(0.1)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

struct StatusCodeBadge: View {
    let statusCode: Int

    var body: some View {
        Text("\(statusCode)")
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusCodeColor)
            .foregroundColor(.white)
            .cornerRadius(4)
    }

    private var statusCodeColor: Color {
        switch statusCode {
        case 200 ..< 300:
            .green
        case 300 ..< 400:
            .blue
        case 400 ..< 500:
            .orange
        case 500 ..< 600:
            .red
        default:
            .gray
        }
    }
}

struct ExportLogView: View {
    let logs: [NetworkLogEntry]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("导出网络日志")
                .font(.headline)

            Text("共 \(logs.count) 条日志")
                .foregroundColor(.secondary)

            HStack(spacing: 20) {
                Button("复制到剪贴板") {
                    copyToClipboard()
                }
                .buttonStyle(.borderedProminent)

                Button("保存到文件...") {
                    saveToFile()
                }
                .buttonStyle(.bordered)

                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(width: 400, height: 200)
    }

    private func copyToClipboard() {
        let exportText = NetworkLogger.shared.exportLogs()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(exportText, forType: .string)

        showAlert(title: "导出成功", message: "日志已复制到剪贴板")
    }

    private func saveToFile() {
        let exportText = NetworkLogger.shared.exportLogs()

        let savePanel = NSSavePanel()
        savePanel.title = "保存网络日志"
        savePanel.nameFieldStringValue = "minote-network-logs-\(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium)).txt"
        savePanel.allowedContentTypes = [.plainText]

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try exportText.write(to: url, atomically: true, encoding: .utf8)
                showAlert(title: "保存成功", message: "日志已保存到文件")
                dismiss()
            } catch {
                showAlert(title: "保存失败", message: error.localizedDescription)
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
}

@MainActor
class NetworkLogViewModel: ObservableObject {
    @Published var logs: [NetworkLogEntry] = []

    func refreshLogs() {
        logs = NetworkLogger.shared.getLogs()
    }

    func clearLogs() {
        NetworkLogger.shared.clearLogs()
        refreshLogs()
    }

    func removeLog(_ id: UUID) {
        // 注意：NetworkLogger目前不支持删除单个日志
        // 这里我们可以通过过滤来实现
        var currentLogs = NetworkLogger.shared.getLogs()
        currentLogs.removeAll { $0.id == id }

        // 清空并重新添加
        NetworkLogger.shared.clearLogs()
        for logEntry in currentLogs.reversed() { // 因为addLogEntry是插入到开头
            NetworkLogger.shared.addLogEntry(logEntry)
        }
        refreshLogs()
    }
}

/// 扩展LogType使其可迭代
extension NetworkLogEntry.LogType: CaseIterable {
    public static var allCases: [NetworkLogEntry.LogType] {
        [.request, .response, .error]
    }
}
