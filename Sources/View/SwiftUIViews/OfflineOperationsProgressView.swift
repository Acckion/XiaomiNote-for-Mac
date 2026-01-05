import SwiftUI

/// 离线操作处理进度视图
/// 
/// 显示离线操作的处理进度、状态和错误信息
@available(macOS 14.0, *)
struct OfflineOperationsProgressView: View {
    @ObservedObject var processor: OfflineOperationProcessor
    var onClose: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 16) {
            // 标题
            HStack {
                Text("处理离线操作")
                    .font(.headline)
                Spacer()
                if processor.isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            Divider()
            
            // 进度信息
            if processor.isProcessing {
                VStack(alignment: .leading, spacing: 8) {
                    // 进度条
                    ProgressView(value: processor.progress) {
                        HStack {
                            Text("进度")
                                .font(.caption)
                            Spacer()
                            Text("\(processor.processedCount) / \(processor.totalCount)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // 状态消息
                    if !processor.statusMessage.isEmpty {
                        Text(processor.statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // 当前操作
                    if let currentOperation = processor.currentOperation {
                        HStack {
                            Text("正在处理:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(currentOperation.type.rawValue)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                }
            } else {
                // 处理完成或未开始
                if processor.processedCount > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        let successCount = processor.processedCount - processor.failedOperations.count
                        Text("处理完成")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            Text("成功: \(successCount)")
                                .foregroundColor(.green)
                            if processor.failedOperations.count > 0 {
                                Text("失败: \(processor.failedOperations.count)")
                                    .foregroundColor(.red)
                            }
                        }
                        .font(.caption)
                    }
                } else {
                    Text("没有待处理的操作")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            // 失败操作列表
            if !processor.failedOperations.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("失败的操作")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(processor.failedOperations) { operation in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(operation.type.rawValue)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                        if let error = operation.lastError {
                                            Text(error)
                                                .font(.caption2)
                                                .foregroundColor(.red)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(4)
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                }
            }
            
            Divider()
            
            // 操作按钮
            HStack {
                if processor.isProcessing {
                    Button("取消") {
                        processor.cancelProcessing()
                        onClose?()
                    }
                    .disabled(!processor.isProcessing)
                } else {
                    if processor.failedOperations.count > 0 {
                        Button("重试失败操作") {
                            Task {
                                await processor.retryFailedOperations()
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                    
                    Button("关闭") {
                        onClose?()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding()
        .frame(width: 400, height: processor.failedOperations.isEmpty ? 200 : 400)
    }
}
