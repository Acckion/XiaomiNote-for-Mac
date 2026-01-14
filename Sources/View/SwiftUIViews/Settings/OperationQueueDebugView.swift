//
//  OperationQueueDebugView.swift
//  MiNoteMac
//
//  操作队列调试面板 - 用于监控和调试统一操作队列
//

import SwiftUI

/// 操作队列调试面板
public struct OperationQueueDebugView: View {
    
    // MARK: - State
    
    @State private var pendingUploads: [PendingUploadEntry] = []
    @State private var offlineOperations: [OfflineOperation] = []
    @State private var activeEditingNoteId: String?
    @State private var isRefreshing = false
    @State private var autoRefresh = true
    @State private var refreshTimer: Timer?
    @State private var lastRefreshTime: Date?
    
    // 过滤和排序
    @State private var operationFilter: OperationFilterType = .all
    @State private var searchText = ""
    
    // 操作确认
    @State private var showClearConfirmation = false
    @State private var showRetryConfirmation = false
    @State private var operationToDelete: OfflineOperation?
    
    public init() {}
    
    // MARK: - Body
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // 顶部工具栏
                toolbarSection
                
                // 状态概览卡片
                statusOverviewSection
                
                // 活跃编辑状态
                activeEditingSection
                
                // 待上传注册表
                pendingUploadsSection
                
                // 离线操作队列
                offlineOperationsSection
            }
            .padding(12)
        }
        .navigationTitle("操作队列调试")
        .onAppear { startAutoRefresh() }
        .onDisappear { stopAutoRefresh() }
        .alert("清空所有操作", isPresented: $showClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { clearAllOperations() }
        } message: {
            Text("确定要清空所有离线操作吗？此操作不可撤销。")
        }
        .alert("重试失败操作", isPresented: $showRetryConfirmation) {
            Button("取消", role: .cancel) {}
            Button("重试", role: .none) { retryFailedOperations() }
        } message: {
            Text("确定要重试所有失败的操作吗？")
        }
    }
    
    // MARK: - Toolbar Section
    
    private var toolbarSection: some View {
        VStack(spacing: 8) {
            // 搜索和过滤
            HStack(spacing: 8) {
                // 搜索框
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    TextField("搜索...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                
                // 过滤器
                Picker("", selection: $operationFilter) {
                    ForEach(OperationFilterType.allCases, id: \.self) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 80)
            }
            
            // 刷新控制
            HStack(spacing: 8) {
                Toggle("自动刷新", isOn: $autoRefresh)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: autoRefresh) { _, newValue in
                        if newValue {
                            startAutoRefresh()
                        } else {
                            stopAutoRefresh()
                        }
                    }
                
                Button(action: { refreshData() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRefreshing)
                
                Spacer()
                
                if let lastRefresh = lastRefreshTime {
                    Text(lastRefresh, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    
    // MARK: - Status Overview Section
    
    private var statusOverviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("状态概览")
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack(spacing: 8) {
                StatusCard(
                    title: "待上传",
                    value: "\(pendingUploads.count)",
                    icon: "arrow.up.circle",
                    color: pendingUploads.isEmpty ? .green : .orange
                )
                
                StatusCard(
                    title: "离线操作",
                    value: "\(offlineOperations.count)",
                    icon: "tray.full",
                    color: offlineOperations.isEmpty ? .green : .blue
                )
                
                StatusCard(
                    title: "待处理",
                    value: "\(pendingOperationsCount)",
                    icon: "clock",
                    color: pendingOperationsCount == 0 ? .green : .yellow
                )
                
                StatusCard(
                    title: "失败",
                    value: "\(failedOperationsCount)",
                    icon: "exclamationmark.triangle",
                    color: failedOperationsCount == 0 ? .green : .red
                )
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var pendingOperationsCount: Int {
        offlineOperations.filter { $0.status == .pending || $0.status == .processing }.count
    }
    
    private var failedOperationsCount: Int {
        offlineOperations.filter { $0.status == .failed }.count
    }
    
    // MARK: - Active Editing Section
    
    private var activeEditingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("活跃编辑")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if activeEditingNoteId != nil {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("编辑中")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            
            if let noteId = activeEditingNoteId {
                HStack(spacing: 8) {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text(noteId)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("复制") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(noteId, forType: .string)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            } else {
                HStack {
                    Image(systemName: "pencil.slash")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("无")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(6)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    // MARK: - Pending Uploads Section
    
    private var pendingUploadsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("待上传")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("(\(pendingUploads.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if !pendingUploads.isEmpty {
                    Button("全部注销") {
                        clearAllPendingUploads()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
            
            if pendingUploads.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("无待上传笔记")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(6)
            } else {
                ForEach(filteredPendingUploads, id: \.noteId) { entry in
                    PendingUploadRow(entry: entry) {
                        unregisterPendingUpload(noteId: entry.noteId)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var filteredPendingUploads: [PendingUploadEntry] {
        if searchText.isEmpty {
            return pendingUploads
        }
        return pendingUploads.filter { $0.noteId.localizedCaseInsensitiveContains(searchText) }
    }

    
    // MARK: - Offline Operations Section
    
    private var offlineOperationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("离线队列")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("(\(offlineOperations.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                
                if failedOperationsCount > 0 {
                    Button("重试") {
                        showRetryConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                
                if !offlineOperations.isEmpty {
                    Button("清空") {
                        showClearConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .foregroundColor(.red)
                }
            }
            
            if offlineOperations.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("队列为空")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(6)
            } else {
                ForEach(filteredOfflineOperations) { operation in
                    OfflineOperationRow(operation: operation) {
                        deleteOperation(operation)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var filteredOfflineOperations: [OfflineOperation] {
        var operations = offlineOperations
        
        // 应用状态过滤
        switch operationFilter {
        case .all:
            break
        case .pending:
            operations = operations.filter { $0.status == .pending }
        case .processing:
            operations = operations.filter { $0.status == .processing }
        case .completed:
            operations = operations.filter { $0.status == .completed }
        case .failed:
            operations = operations.filter { $0.status == .failed }
        }
        
        // 应用搜索过滤
        if !searchText.isEmpty {
            operations = operations.filter { $0.noteId.localizedCaseInsensitiveContains(searchText) }
        }
        
        return operations
    }
    
    // MARK: - Data Operations
    
    private func refreshData() {
        isRefreshing = true
        
        Task {
            // 获取待上传注册表数据
            let registry = PendingUploadRegistry.shared
            let pendingIds = registry.getAllPendingNoteIds()
            var entries: [PendingUploadEntry] = []
            for noteId in pendingIds {
                if let timestamp = registry.getLocalSaveTimestamp(noteId) {
                    entries.append(PendingUploadEntry(noteId: noteId, localSaveTimestamp: timestamp))
                }
            }
            
            // 获取离线操作队列数据
            let queue = OfflineOperationQueue.shared
            let operations = queue.getAllOperations()
            
            // 获取活跃编辑笔记 ID
            let coordinator = NoteOperationCoordinator.shared
            let activeNoteId = await coordinator.getActiveEditingNoteId()
            
            await MainActor.run {
                self.pendingUploads = entries.sorted { $0.localSaveTimestamp > $1.localSaveTimestamp }
                self.offlineOperations = operations
                self.activeEditingNoteId = activeNoteId
                self.lastRefreshTime = Date()
                self.isRefreshing = false
            }
        }
    }
    
    private func startAutoRefresh() {
        refreshData()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                self.refreshData()
            }
        }
    }
    
    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func clearAllPendingUploads() {
        let registry = PendingUploadRegistry.shared
        for entry in pendingUploads {
            registry.unregister(noteId: entry.noteId)
        }
        refreshData()
    }
    
    private func unregisterPendingUpload(noteId: String) {
        PendingUploadRegistry.shared.unregister(noteId: noteId)
        refreshData()
    }
    
    private func clearAllOperations() {
        try? OfflineOperationQueue.shared.clearAll()
        refreshData()
    }
    
    private func deleteOperation(_ operation: OfflineOperation) {
        try? OfflineOperationQueue.shared.removeOperation(operation.id)
        refreshData()
    }
    
    private func retryFailedOperations() {
        Task {
            await OfflineOperationProcessor.shared.retryFailedOperations()
            await MainActor.run {
                refreshData()
            }
        }
    }
}


// MARK: - Supporting Types

/// 操作过滤类型
enum OperationFilterType: String, CaseIterable {
    case all = "全部"
    case pending = "待处理"
    case processing = "处理中"
    case completed = "已完成"
    case failed = "失败"
    
    var displayName: String { rawValue }
}

// MARK: - Supporting Views

/// 状态卡片
struct StatusCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }
}

/// 待上传条目行
struct PendingUploadRow: View {
    let entry: PendingUploadEntry
    let onUnregister: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.circle")
                .foregroundColor(.orange)
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.noteId)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(entry.localSaveTimestamp, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("复制") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.noteId, forType: .string)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            
            Button("注销") {
                onUnregister()
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(6)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(6)
    }
}

/// 离线操作行
struct OfflineOperationRow: View {
    let operation: OfflineOperation
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            statusIcon
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(operation.type.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(operation.noteId)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                HStack(spacing: 6) {
                    Text(operation.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if operation.retryCount > 0 {
                        Text("重试:\(operation.retryCount)")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                
                if let error = operation.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            statusBadge
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(6)
        .background(statusBackgroundColor.opacity(0.05))
        .cornerRadius(6)
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch operation.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundColor(.yellow)
        case .processing:
            ProgressView()
                .scaleEffect(0.7)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
        }
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        Text(operation.status.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusBackgroundColor.opacity(0.2))
            .foregroundColor(statusBackgroundColor)
            .cornerRadius(4)
    }
    
    private var statusBackgroundColor: Color {
        switch operation.status {
        case .pending: return .yellow
        case .processing: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
}

// MARK: - Extensions

extension OfflineOperationType {
    var displayName: String {
        switch self {
        case .createNote: return "创建笔记"
        case .updateNote: return "更新笔记"
        case .deleteNote: return "删除笔记"
        case .uploadImage: return "上传图片"
        case .createFolder: return "创建文件夹"
        case .renameFolder: return "重命名文件夹"
        case .deleteFolder: return "删除文件夹"
        }
    }
}

extension OfflineOperationStatus {
    var displayName: String {
        switch self {
        case .pending: return "待处理"
        case .processing: return "处理中"
        case .completed: return "已完成"
        case .failed: return "失败"
        }
    }
}
