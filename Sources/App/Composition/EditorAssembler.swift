//
//  EditorAssembler.swift
//  MiNoteLibrary
//

import Foundation

/// 编辑器域依赖装配器
@MainActor
enum EditorAssembler {
    /// 将 EditorModule 和 AudioModule 的组件注入到 NativeEditorContext
    static func wireContext(
        noteEditorState: NoteEditorState,
        editorModule: EditorModule,
        audioModule: AudioModule
    ) {
        let context = noteEditorState.nativeEditorContext
        context.customRenderer = editorModule.customRenderer
        context.imageStorageManager = editorModule.imageStorageManager
        context.formatStateManager = editorModule.formatStateManager
        context.unifiedFormatManager = editorModule.unifiedFormatManager
        context.formatConverter = editorModule.formatConverter
        context.attachmentSelectionManager = editorModule.attachmentSelectionManager
        context.xmlNormalizer = editorModule.xmlNormalizer
        context.cursorFormatManager = editorModule.cursorFormatManager
        context.specialElementFormatHandler = editorModule.specialElementFormatHandler
        context.performanceCache = editorModule.performanceCache
        context.typingOptimizer = editorModule.typingOptimizer
        context.attachmentKeyboardHandler = editorModule.attachmentKeyboardHandler
        context.editorConfigurationManager = editorModule.editorConfigurationManager
        context.audioPanelStateManager = audioModule.panelStateManager
    }
}
