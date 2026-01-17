import SwiftUI

/// 离线操作处理进度视图
/// 
/// 显示离线操作的处理进度、状态和错误信息
@available(macOS 14.0, *)
struct OfflineOperationsProgressView: View {
    let processor: OperationProcessor
    var onClose: (() -> Void)? = nil
    
    @State private var pendingCount = 0
    
    var body: some View {
        VStack(spacing: 16) {
            Divider()
            
            // 进度信息
            if pendingCount > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("正在处理离线操作...")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    ProgressView()
                        .progressViewStyle(.linear)
                    
                    Text("待处理: \(pendingCount) 个操作")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("没有待处理的操作")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // 操作按钮
            HStack {
                Button("关闭") {
                    onClose?()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400, height: 200)
        .task {
            // 定期更新待处理数量
            while !Task.isCancelled {
                let operations = await UnifiedOperationQueue.shared.getPendingOperations()
                pendingCount = operations.count
                
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            }
        }
    }
}
