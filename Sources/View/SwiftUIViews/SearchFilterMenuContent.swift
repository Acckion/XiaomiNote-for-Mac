import SwiftUI

/// 搜索筛选菜单内容
struct SearchFilterMenuContent: View {
    @ObservedObject var viewModel: NotesViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 含标签的笔记（待实现）
            Toggle(isOn: $viewModel.searchFilterHasTags) {
                Label("含标签的笔记", systemImage: "tag")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(true) // 待实现，暂时禁用
            
            // 含核对清单的笔记
            Toggle(isOn: $viewModel.searchFilterHasChecklist) {
                Label("含核对清单的笔记", systemImage: "checklist")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // 含图片的笔记
            Toggle(isOn: $viewModel.searchFilterHasImages) {
                Label("含图片的笔记", systemImage: "photo")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // 含录音的笔记（待实现）
            Toggle(isOn: $viewModel.searchFilterHasAudio) {
                Label("含录音的笔记", systemImage: "mic")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(true) // 待实现，暂时禁用
            
            // 私密笔记
            Toggle(isOn: $viewModel.searchFilterIsPrivate) {
                Label("私密笔记", systemImage: "lock")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // 分割线
            Divider()
                .padding(.vertical, 4)
            
            // 清除所有筛选（一直显示，无筛选时设为灰色）
            Button {
                clearAllFilters()
            } label: {
                Label("清除所有筛选", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(!hasAnyFilter())
            .foregroundColor(hasAnyFilter() ? .primary : .gray)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minWidth: 200, minHeight: 190)
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

// MARK: - 筛选标签扩展
extension NotesViewModel {
    /// 获取筛选标签文本
    var filterTagsText: String {
        var tags: [String] = []
        
        if searchFilterHasChecklist {
            tags.append("核对清单")
        }
        if searchFilterHasImages {
            tags.append("图片")
        }
        if searchFilterIsPrivate {
            tags.append("私密")
        }
        if searchFilterHasTags {
            tags.append("标签")
        }
        if searchFilterHasAudio {
            tags.append("录音")
        }
        
        return tags.isEmpty ? "" : "筛选: " + tags.joined(separator: ", ")
    }
    
    /// 检查是否有筛选选项
    var hasSearchFilters: Bool {
        return searchFilterHasTags ||
               searchFilterHasChecklist ||
               searchFilterHasImages ||
               searchFilterHasAudio ||
               searchFilterIsPrivate
    }
}
