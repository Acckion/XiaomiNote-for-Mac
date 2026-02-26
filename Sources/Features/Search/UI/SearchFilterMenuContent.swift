import SwiftUI

/// 搜索筛选菜单内容
struct SearchFilterMenuContent: View {
    @ObservedObject var noteListState: NoteListState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 含标签的笔记（待实现）
            Toggle(isOn: $noteListState.filterHasTags) {
                Label("含标签的笔记", systemImage: "tag")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(true) // 待实现，暂时禁用

            // 含核对清单的笔记
            Toggle(isOn: $noteListState.filterHasChecklist) {
                Label("含核对清单的笔记", systemImage: "checklist")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 含图片的笔记
            Toggle(isOn: $noteListState.filterHasImages) {
                Label("含图片的笔记", systemImage: "photo")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 含录音的笔记（待实现）
            Toggle(isOn: $noteListState.filterHasAudio) {
                Label("含录音的笔记", systemImage: "mic")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(true) // 待实现，暂时禁用

            // 私密笔记
            Toggle(isOn: $noteListState.filterIsPrivate) {
                Label("私密笔记", systemImage: "lock")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
                .padding(.vertical, 4)

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

    private func hasAnyFilter() -> Bool {
        noteListState.filterHasTags ||
            noteListState.filterHasChecklist ||
            noteListState.filterHasImages ||
            noteListState.filterHasAudio ||
            noteListState.filterIsPrivate
    }

    private func clearAllFilters() {
        noteListState.filterHasTags = false
        noteListState.filterHasChecklist = false
        noteListState.filterHasImages = false
        noteListState.filterHasAudio = false
        noteListState.filterIsPrivate = false
    }
}
