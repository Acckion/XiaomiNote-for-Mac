import SwiftUI

/// 搜索筛选弹出视图
struct SearchFilterPopoverView: View {
    @ObservedObject var viewModel: NotesViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("输入搜索关键词", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: NSColor.controlBackgroundColor))
            )
            
            if !viewModel.searchText.isEmpty {
                Button("清除") {
                    viewModel.searchText = ""
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            
            Divider()
            
            // 筛选选项
            Text("筛选")
                .font(.headline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 6) {
                // 含标签的笔记（待实现）
                Toggle(isOn: $viewModel.searchFilterHasTags) {
                    HStack {
                        Image(systemName: "tag")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("含标签的笔记")
                            .font(.caption)
                        Text("(待实现)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(true) // 待实现，暂时禁用
                
                // 含核对清单的笔记
                Toggle(isOn: $viewModel.searchFilterHasChecklist) {
                    HStack {
                        Image(systemName: "checklist")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("含核对清单的笔记")
                            .font(.caption)
                    }
                }
                
                // 含图片的笔记
                Toggle(isOn: $viewModel.searchFilterHasImages) {
                    HStack {
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("含图片的笔记")
                            .font(.caption)
                    }
                }
                
                // 含录音的笔记（待实现）
                Toggle(isOn: $viewModel.searchFilterHasAudio) {
                    HStack {
                        Image(systemName: "mic")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("含录音的笔记")
                            .font(.caption)
                        Text("(待实现)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(true) // 待实现，暂时禁用
                
                // 私密笔记
                Toggle(isOn: $viewModel.searchFilterIsPrivate) {
                    HStack {
                        Image(systemName: "lock")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("私密笔记")
                            .font(.caption)
                    }
                }
            }
            
            // 清除所有筛选
            if hasAnyFilter() {
                Divider()
                Button("清除所有筛选") {
                    clearAllFilters()
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .frame(width: 280)
    }
    
    /// 检查是否有任何筛选选项被启用
    private func hasAnyFilter() -> Bool {
        return viewModel.searchFilterHasTags ||
               viewModel.searchFilterHasChecklist ||
               viewModel.searchFilterHasImages ||
               viewModel.searchFilterHasAudio ||
               viewModel.searchFilterIsPrivate
    }
    
    /// 清除所有筛选选项
    private func clearAllFilters() {
        viewModel.searchFilterHasTags = false
        viewModel.searchFilterHasChecklist = false
        viewModel.searchFilterHasImages = false
        viewModel.searchFilterHasAudio = false
        viewModel.searchFilterIsPrivate = false
    }
}

