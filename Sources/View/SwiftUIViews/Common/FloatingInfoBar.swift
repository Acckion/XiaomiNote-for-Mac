import SwiftUI

/// 悬浮信息栏组件
/// 
/// 显示笔记的元信息（修改日期、字数、调试模式指示器、保存状态）
/// 
/// 需求: US-2, US-3, US-5
@available(macOS 14.0, *)
struct FloatingInfoBar: View {
    // MARK: - Properties
    
    /// 笔记对象
    let note: Note
    
    /// 当前 XML 内容
    let currentXMLContent: String
    
    /// 是否处于调试模式
    let isDebugMode: Bool
    
    /// 保存状态
    let saveStatus: SaveStatusType
    
    /// 显示保存错误弹窗
    @Binding var showSaveErrorAlert: Bool
    
    /// 保存错误信息
    @Binding var saveErrorMessage: String
    
    /// 重试保存回调
    var onRetrySave: (() -> Void)?
    
    // MARK: - Computed Properties
    
    /// 格式化的更新日期字符串
    private var updateDateString: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy年MM月dd日 HH:mm"
        return dateFormatter.string(from: note.updatedAt)
    }
    
    /// 字数统计
    private var wordCount: Int {
        calculateWordCount(from: currentXMLContent.isEmpty ? note.primaryXMLContent : currentXMLContent)
    }
    
    // MARK: - Body
    
    var body: some View {
        HStack(spacing: 8) {
            // 日期和字数
            Text("\(updateDateString) · \(wordCount) 字")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            
            // 调试模式指示器
            if isDebugMode {
                debugModeIndicator
            }
            
            // 保存状态指示器
            statusIndicator
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - View Components
    
    /// 统一的状态指示器
    /// 
    /// 根据模式显示不同的保存状态
    /// 
    /// 需求: US-2, AC-2.3, AC-4.3
    @ViewBuilder
    private var statusIndicator: some View {
        switch saveStatus {
        case .normal(let status):
            normalSaveStatusView(status)
        case .debug(let status):
            debugSaveStatusView(status)
        }
    }
    
    /// 普通模式保存状态视图
    /// 
    /// 需求: US-2, AC-2.3, AC-4.3
    @ViewBuilder
    private func normalSaveStatusView(_ status: NoteDetailView.SaveStatus) -> some View {
        switch status {
        case .saved:
            // 已保存状态（绿色）
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 8))
                Text("已保存")
                    .font(.system(size: 10))
            }
            .foregroundColor(.green)
        case .saving:
            // 保存中状态（黄色）
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
                Text("保存中...")
                    .font(.system(size: 10))
            }
            .foregroundColor(.orange)
        case .unsaved:
            // 未保存状态（红色）
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 8))
                Text("未保存")
                    .font(.system(size: 10))
            }
            .foregroundColor(.red)
        case .error(let message):
            // 保存失败状态（红色，可点击查看详情和重试）
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 8))
                    Text("保存失败")
                        .font(.system(size: 10))
                }
                .foregroundColor(.red)
                .onTapGesture {
                    // 点击显示错误详情
                    saveErrorMessage = message
                    showSaveErrorAlert = true
                }
                
                // 重试按钮
                if onRetrySave != nil {
                    Button(action: {
                        onRetrySave?()
                    }) {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 8))
                            Text("重试")
                                .font(.system(size: 10))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.red.opacity(0.1))
            .cornerRadius(4)
            .help("点击查看错误详情，或点击重试按钮重新保存")
        }
    }
    
    /// 调试模式保存状态视图
    /// 
    /// 需求: US-5, AC-5.2
    @ViewBuilder
    private func debugSaveStatusView(_ status: DebugSaveStatus) -> some View {
        switch status {
        case .saved:
            Text("已保存")
                .font(.system(size: 10))
                .foregroundColor(.green)
        case .saving:
            Text("保存中...")
                .font(.system(size: 10))
                .foregroundColor(.orange)
        case .unsaved:
            Text("未保存")
                .font(.system(size: 10))
                .foregroundColor(.red)
        case .error(let message):
            Text("保存失败")
                .font(.system(size: 10))
                .foregroundColor(.red)
                .onTapGesture {
                    saveErrorMessage = message
                    showSaveErrorAlert = true
                }
        }
    }
    
    /// 调试模式指示器
    /// 
    /// 需求: US-5, AC-5.1
    private var debugModeIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 8))
            Text("调试模式")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.15))
        .cornerRadius(4)
    }
    
    // MARK: - Helper Methods
    
    /// 计算字数
    /// 
    /// 从 XML 内容中提取纯文本并计算字数
    /// 
    /// - Parameter xmlContent: XML 内容
    /// - Returns: 字数
    private func calculateWordCount(from xmlContent: String) -> Int {
        guard !xmlContent.isEmpty else { return 0 }
        let textOnly = xmlContent
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return textOnly.count
    }
}

/// 保存状态类型
/// 
/// 用于区分普通模式和调试模式的保存状态
enum SaveStatusType {
    case normal(NoteDetailView.SaveStatus)
    case debug(DebugSaveStatus)
}
