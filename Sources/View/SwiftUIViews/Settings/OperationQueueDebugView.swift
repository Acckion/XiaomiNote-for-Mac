//
//  OperationQueueDebugView.swift
//  MiNoteMac
//
//  操作队列调试面板 - 用于监控和调试统一操作队列
//
//  需求: 6.1 - 状态可观察性
//

import SwiftUI

/// 操作队列调试面板
///
/// 显示 UnifiedOperationQueue 的状态，包括：
/// - 各状态操作数量（待处理、处理中、失败、认证失败、超过重试次数）
/// - 临时 ID 笔记数量
/// - 活跃编辑状态
/// - 待处理操作列表
///
/// _需求: 6.1_
public struct OperationQueueDebugView: View {
    
    // MARK: - State
    
    /// 统一操作队列中的操作
    @State private var unifiedOperations: [NoteOperation] = []
    /// 队列统计信息
    @State private var queueStatistics: [String: Int] = [:]
    /// 临时 ID 笔记数量
    @State private var temporaryIdNoteCount: Int = 0
    /// 临时 ID 笔记列表
    @State private var temporaryNoteIds: [String] = []
    /// ID 映射统计
    @State private var idMappingStats: [String: Int] = [:]
    /// 活跃编辑笔记 ID
    @State private var activeEditingNoteId: String?
    /// 是否正在刷新
    @State private var isRefreshing = false
    /// 是否自动刷新
    @State private var autoRefresh = true
    /// 刷新定时器
    @State private var refreshTimer: Timer?
    /// 最后刷新时间
    @State private var lastRefreshTime: Date?
    
    // 过滤和排序
    @State private var operationFilter: UnifiedOperationFilterType = .all
    @State private var searchText = ""
    
    // 操作确认
    @State private var showClearConfirmation = false
    @State private var showRetryConfirmation = false
    
    public init() {}
    
    // MARK: - Body
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // 顶部工具栏
                toolbarSection
                
                // 状态概览卡片（显示 UnifiedOperationQueue 状态）
                unifiedQueueStatusSection
                
                // 临时 ID 笔记状态
                temporaryIdNotesSection
                
                // ID 映射状态
                idMappingSection
                
                // 活跃编辑状态
                activeEditingSection
                
                // 统一操作队列
                unifiedOperationsSection
            }
            .padding(12)
        }
        .navigationTitle("操作队列调试")
        .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
        .toolbarBackgroundVisibility(.automatic, for: .windowToolbar)
        .onAppear { startAutoRefresh() }
        .onDisappear { stopAutoRefresh() }
        .alert("清空所有操作", isPresented: $showClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { clearAllOperations() }
        } message: {
            Text("确定要清空所有操作吗？此操作不可撤销。")
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
                    TextField("搜索笔记 ID...", text: $searchText)
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
                    ForEach(UnifiedOperationFilterType.allCases, id: \.self) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
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

    
    // MARK: - Unified Queue Status Section
    
    /// 统一操作队列状态概览
    /// 显示各状态操作数量
    /// _需求: 6.1_
    private var unifiedQueueStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("统一操作队列状态")
                .font(.subheadline)
                .fontWeight(.medium)
            
            // 第一行：主要状态
            HStack(spacing: 8) {
                StatusCard(
                    title: "总计",
                    value: "\(queueStatistics["total"] ?? 0)",
                    icon: "tray.full",
                    color: (queueStatistics["total"] ?? 0) == 0 ? .green : .blue
                )
                
                StatusCard(
                    title: "待处理",
                    value: "\(queueStatistics["pending"] ?? 0)",
                    icon: "clock",
                    color: (queueStatistics["pending"] ?? 0) == 0 ? .green : .yellow
                )
                
                StatusCard(
                    title: "处理中",
                    value: "\(queueStatistics["processing"] ?? 0)",
                    icon: "arrow.triangle.2.circlepath",
                    color: (queueStatistics["processing"] ?? 0) == 0 ? .green : .blue
                )
                
                StatusCard(
                    title: "失败",
                    value: "\(queueStatistics["failed"] ?? 0)",
                    icon: "exclamationmark.triangle",
                    color: (queueStatistics["failed"] ?? 0) == 0 ? .green : .red
                )
            }
            
            // 第二行：特殊状态
            HStack(spacing: 8) {
                StatusCard(
                    title: "认证失败",
                    value: "\(queueStatistics["authFailed"] ?? 0)",
                    icon: "person.crop.circle.badge.exclamationmark",
                    color: (queueStatistics["authFailed"] ?? 0) == 0 ? .green : .orange
                )
                
                StatusCard(
                    title: "超过重试",
                    value: "\(queueStatistics["maxRetryExceeded"] ?? 0)",
                    icon: "arrow.counterclockwise.circle",
                    color: (queueStatistics["maxRetryExceeded"] ?? 0) == 0 ? .green : .red
                )
                
                StatusCard(
                    title: "待上传",
                    value: "\(UnifiedOperationQueue.shared.getPendingUploadCount())",
                    icon: "arrow.up.circle",
                    color: UnifiedOperationQueue.shared.getPendingUploadCount() == 0 ? .green : .orange
                )
                
                StatusCard(
                    title: "临时 ID",
                    value: "\(temporaryIdNoteCount)",
                    icon: "number.circle",
                    color: temporaryIdNoteCount == 0 ? .green : .purple
                )
            }
            
            // 第三行：按操作类型统计
            VStack(alignment: .leading, spacing: 4) {
                Text("按操作类型")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 6) {
                    OperationTypeTag(type: "noteCreate", count: queueStatistics["noteCreate"] ?? 0)
                    OperationTypeTag(type: "cloudUpload", count: queueStatistics["cloudUpload"] ?? 0)
                    OperationTypeTag(type: "cloudDelete", count: queueStatistics["cloudDelete"] ?? 0)
                    OperationTypeTag(type: "imageUpload", count: queueStatistics["imageUpload"] ?? 0)
                }
            }
            .padding(.top, 4)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    // MARK: - Temporary ID Notes Section
    
    /// 临时 ID 笔记状态
    /// 显示离线创建的笔记数量
    /// _需求: 6.1_
    private var temporaryIdNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("临时 ID 笔记")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("(\(temporaryIdNoteCount))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if temporaryIdNoteCount > 0 {
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 6, height: 6)
                    Text("离线创建")
                        .font(.caption2)
                        .foregroundColor(.purple)
                }
            }
            
            if temporaryNoteIds.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("无临时 ID 笔记")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(6)
            } else {
                ForEach(temporaryNoteIds, id: \.self) { noteId in
                    HStack(spacing: 8) {
                        Image(systemName: "doc.badge.clock")
                            .foregroundColor(.purple)
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
                    .padding(6)
                    .background(Color.purple.opacity(0.05))
                    .cornerRadius(6)
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    // MARK: - ID Mapping Section
    
    /// ID 映射状态
    private var idMappingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ID 映射")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("(\(idMappingStats["total"] ?? 0))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            HStack(spacing: 8) {
                StatusCard(
                    title: "总映射",
                    value: "\(idMappingStats["total"] ?? 0)",
                    icon: "arrow.left.arrow.right",
                    color: .blue
                )
                
                StatusCard(
                    title: "未完成",
                    value: "\(idMappingStats["incomplete"] ?? 0)",
                    icon: "clock.arrow.circlepath",
                    color: (idMappingStats["incomplete"] ?? 0) == 0 ? .green : .orange
                )
                
                StatusCard(
                    title: "已完成",
                    value: "\(idMappingStats["completed"] ?? 0)",
                    icon: "checkmark.circle",
                    color: .green
                )
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
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
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(noteId)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        // 显示是否为临时 ID
                        if NoteOperation.isTemporaryId(noteId) {
                            Text("临时 ID（离线创建）")
                                .font(.caption2)
                                .foregroundColor(.purple)
                        }
                    }
                    
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
    
    // MARK: - Unified Operations Section
    
    /// 统一操作队列列表
    /// _需求: 6.1_
    private var unifiedOperationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("操作队列")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("(\(unifiedOperations.count))")
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
                
                if !unifiedOperations.isEmpty {
                    Button("清空") {
                        showClearConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .foregroundColor(.red)
                }
            }
            
            if unifiedOperations.isEmpty {
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
                ForEach(filteredUnifiedOperations) { operation in
                    UnifiedOperationRow(operation: operation) {
                        deleteOperation(operation)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    /// 失败操作数量
    private var failedOperationsCount: Int {
        unifiedOperations.filter { $0.status == .failed }.count
    }
    
    /// 过滤后的操作列表
    private var filteredUnifiedOperations: [NoteOperation] {
        var operations = unifiedOperations
        
        // 应用状态过滤
        switch operationFilter {
        case .all:
            break
        case .pending:
            operations = operations.filter { $0.status == .pending }
        case .processing:
            operations = operations.filter { $0.status == .processing }
        case .failed:
            operations = operations.filter { $0.status == .failed }
        case .authFailed:
            operations = operations.filter { $0.status == .authFailed }
        case .maxRetryExceeded:
            operations = operations.filter { $0.status == .maxRetryExceeded }
        case .temporaryId:
            operations = operations.filter { $0.isLocalId }
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
            // 获取统一操作队列数据
            let queue = UnifiedOperationQueue.shared
            let operations = queue.getPendingOperations()
            let stats = queue.getStatistics()
            let tempCount = queue.getTemporaryIdNoteCount()
            let tempIds = queue.getAllTemporaryNoteIds()
            
            // 获取 ID 映射统计
            let mappingRegistry = IdMappingRegistry.shared
            let mappingStats = mappingRegistry.getStatistics()
            
            // 获取活跃编辑笔记 ID
            let coordinator = NoteOperationCoordinator.shared
            let activeNoteId = await coordinator.getActiveEditingNoteId()
            
            await MainActor.run {
                self.unifiedOperations = operations
                self.queueStatistics = stats
                self.temporaryIdNoteCount = tempCount
                self.temporaryNoteIds = tempIds
                self.idMappingStats = mappingStats
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
    
    private func clearAllOperations() {
        try? UnifiedOperationQueue.shared.clearAll()
        refreshData()
    }
    
    private func deleteOperation(_ operation: NoteOperation) {
        try? UnifiedOperationQueue.shared.markCompleted(operation.id)
        refreshData()
    }
    
    private func retryFailedOperations() {
        Task {
            await OperationProcessor.shared.processRetries()
            await MainActor.run {
                refreshData()
            }
        }
    }
}


// MARK: - Supporting Types

/// 统一操作过滤类型
/// _需求: 6.1_
enum UnifiedOperationFilterType: String, CaseIterable {
    case all = "全部"
    case pending = "待处理"
    case processing = "处理中"
    case failed = "失败"
    case authFailed = "认证失败"
    case maxRetryExceeded = "超过重试"
    case temporaryId = "临时 ID"
    
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

/// 操作类型标签
struct OperationTypeTag: View {
    let type: String
    let count: Int
    
    var body: some View {
        HStack(spacing: 4) {
            Text(displayName)
                .font(.caption2)
            Text("\(count)")
                .font(.caption2)
                .fontWeight(.bold)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .cornerRadius(4)
    }
    
    private var displayName: String {
        switch type {
        case "noteCreate": return "创建"
        case "cloudUpload": return "上传"
        case "cloudDelete": return "删除"
        case "imageUpload": return "图片"
        case "folderCreate": return "文件夹创建"
        case "folderRename": return "文件夹重命名"
        case "folderDelete": return "文件夹删除"
        default: return type
        }
    }
    
    private var color: Color {
        switch type {
        case "noteCreate": return .purple
        case "cloudUpload": return .blue
        case "cloudDelete": return .red
        case "imageUpload": return .green
        default: return .gray
        }
    }
}

/// 统一操作行
/// _需求: 6.1_
struct UnifiedOperationRow: View {
    let operation: NoteOperation
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
                    
                    // 显示临时 ID 标记
                    if operation.isLocalId {
                        Text("临时")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.2))
                            .foregroundColor(.purple)
                            .cornerRadius(3)
                    }
                    
                    Text(operation.noteId)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                HStack(spacing: 6) {
                    Text(operation.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if operation.retryCount > 0 {
                        Text("重试:\(operation.retryCount)")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    
                    if let nextRetry = operation.nextRetryAt {
                        Text("下次: \(nextRetry, style: .relative)")
                            .font(.caption2)
                            .foregroundColor(.blue)
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
        case .authFailed:
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .foregroundColor(.orange)
        case .maxRetryExceeded:
            Image(systemName: "arrow.counterclockwise.circle")
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
        case .authFailed: return .orange
        case .maxRetryExceeded: return .red
        }
    }
}

// MARK: - Extensions

extension OperationType {
    var displayName: String {
        switch self {
        case .noteCreate: return "创建笔记"
        case .cloudUpload: return "上传笔记"
        case .cloudDelete: return "删除笔记"
        case .imageUpload: return "上传图片"
        case .folderCreate: return "创建文件夹"
        case .folderRename: return "重命名文件夹"
        case .folderDelete: return "删除文件夹"
        }
    }
}

extension OperationStatus {
    var displayName: String {
        switch self {
        case .pending: return "待处理"
        case .processing: return "处理中"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .authFailed: return "认证失败"
        case .maxRetryExceeded: return "超过重试"
        }
    }
}
