import SwiftUI

/// 搜索筛选菜单内容
struct SearchFilterMenuContent: View {
    @ObservedObject var viewModel: NotesViewModel
    
    var body: some View {
        // 含标签的笔记（待实现）
        Toggle(isOn: $viewModel.searchFilterHasTags) {
            Label("含标签的笔记", systemImage: "tag")
        }
        .disabled(true) // 待实现，暂时禁用
        
        // 含核对清单的笔记
        Toggle(isOn: $viewModel.searchFilterHasChecklist) {
            Label("含核对清单的笔记", systemImage: "checklist")
        }
        
        // 含图片的笔记
        Toggle(isOn: $viewModel.searchFilterHasImages) {
            Label("含图片的笔记", systemImage: "photo")
        }
        
        // 含录音的笔记（待实现）
        Toggle(isOn: $viewModel.searchFilterHasAudio) {
            Label("含录音的笔记", systemImage: "mic")
        }
        .disabled(true) // 待实现，暂时禁用
        
        // 私密笔记
        Toggle(isOn: $viewModel.searchFilterIsPrivate) {
            Label("私密笔记", systemImage: "lock")
        }
        
        // 清除所有筛选
        if hasAnyFilter() {
            Divider()
            Button {
                clearAllFilters()
            } label: {
                Label("清除所有筛选", systemImage: "xmark.circle")
            }
        }
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

