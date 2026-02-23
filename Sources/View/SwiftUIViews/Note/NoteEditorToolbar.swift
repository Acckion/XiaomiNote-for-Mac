//
//  NoteEditorToolbar.swift
//  MiNoteMac
//
//  从 NoteDetailView 提取的编辑器工具栏
//

import AppKit
import SwiftUI

/// 笔记编辑器工具栏
@available(macOS 14.0, *)
struct NoteEditorToolbar: ToolbarContent {
    @ObservedObject var noteListState: NoteListState
    @ObservedObject var noteEditorState: NoteEditorState
    let nativeEditorContext: NativeEditorContext
    let isDebugMode: Bool
    let selectedNote: Note?
    let onToggleDebugMode: () -> Void
    let onInsertImage: () -> Void
    @Binding var showingHistoryView: Bool
    @Binding var showTrashView: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            newNoteButton
        }
        ToolbarItemGroup(placement: .automatic) {
            undoButton
            redoButton
        }
        ToolbarItemGroup(placement: .automatic) {
            formatMenu
            checkboxButton
            horizontalRuleButton
            imageButton
        }
        ToolbarItemGroup(placement: .automatic) {
            indentButtons
            Spacer()
            debugModeToggleButton
            if let note = selectedNote {
                shareAndMoreButtons(for: note)
            }
        }
    }

    // MARK: - 工具栏按钮

    private var undoButton: some View {
        Button {
            NSApp.sendAction(#selector(UndoManager.undo), to: nil, from: nil)
        } label: { Label("撤销", systemImage: "arrow.uturn.backward") }
    }

    private var redoButton: some View {
        Button {
            NSApp.sendAction(#selector(UndoManager.redo), to: nil, from: nil)
        } label: { Label("重做", systemImage: "arrow.uturn.forward") }
    }

    private var formatMenu: some View {
        NoteEditorToolbarFormatButton(nativeEditorContext: nativeEditorContext)
    }

    private var checkboxButton: some View {
        Button {
            nativeEditorContext.insertCheckbox()
        } label: { Label("插入待办", systemImage: "checklist") }
    }

    private var horizontalRuleButton: some View {
        Button {
            nativeEditorContext.insertHorizontalRule()
        } label: { Label("插入分割线", systemImage: "minus") }
    }

    private var imageButton: some View {
        Button { onInsertImage() } label: { Label("插入图片", systemImage: "paperclip") }
    }

    @ViewBuilder
    private var indentButtons: some View {
        Button {
            nativeEditorContext.increaseIndent()
        } label: { Label("增加缩进", systemImage: "increase.indent") }

        Button {
            nativeEditorContext.decreaseIndent()
        } label: { Label("减少缩进", systemImage: "decrease.indent") }
    }

    private var debugModeToggleButton: some View {
        Button {
            onToggleDebugMode()
        } label: {
            Label(
                isDebugMode ? "退出调试" : "调试模式",
                systemImage: isDebugMode ? "xmark.circle" : "chevron.left.forwardslash.chevron.right"
            )
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])
        .disabled(selectedNote == nil)
        .help(isDebugMode ? "退出 XML 调试模式 (Cmd+Shift+D)" : "进入 XML 调试模式 (Cmd+Shift+D)")
    }

    @ViewBuilder
    private func shareAndMoreButtons(for note: Note) -> some View {
        Button {
            let picker = NSSharingServicePicker(items: [note.content])
            if let window = NSApplication.shared.keyWindow, let view = window.contentView {
                picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
            }
        } label: { Label("分享", systemImage: "square.and.arrow.up") }

        Button { showingHistoryView = true } label: { Label("历史记录", systemImage: "clock.arrow.circlepath") }

        Menu {
            Button {
                Task { await noteListState.toggleStar(note) }
            } label: { Label(note.isStarred ? "取消置顶" : "置顶", systemImage: "pin") }
            Divider()
            Button { showTrashView = true } label: { Label("回收站", systemImage: "trash") }
            Button(role: .destructive) {
                Task { await noteListState.deleteNote(note) }
            } label: { Label("删除", systemImage: "trash") }
        } label: { Label("更多", systemImage: "ellipsis.circle") }
    }

    private var newNoteButton: some View {
        Button {
            Task { await noteListState.createNewNote(inFolder: "0") }
        } label: { Label("新建笔记", systemImage: "square.and.pencil") }
    }
}

// MARK: - 格式菜单按钮（内部管理 popover 状态）

@available(macOS 14.0, *)
private struct NoteEditorToolbarFormatButton: View {
    @ObservedObject var nativeEditorContext: NativeEditorContext
    @State private var showFormatMenu = false

    var body: some View {
        Button { showFormatMenu.toggle() } label: { Label("格式", systemImage: "textformat") }
            .popover(isPresented: $showFormatMenu, arrowEdge: .top) {
                FormatMenuPopoverContent(
                    nativeEditorContext: nativeEditorContext,
                    onDismiss: { showFormatMenu = false }
                )
            }
    }
}
