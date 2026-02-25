//
//  NotesAssembler.swift
//  MiNoteLibrary
//

import Foundation

/// 笔记域依赖装配器
@MainActor
enum NotesAssembler {
    struct Output {
        let noteStore: NoteStore
        let noteListState: NoteListState
        let noteEditorState: NoteEditorState
        let notePreviewService: NotePreviewService
        let folderState: FolderState
    }

    static func assemble(
        eventBus: EventBus,
        networkModule: NetworkModule,
        syncModule: SyncModule
    ) -> Output {
        let noteStore = NoteStore(
            db: DatabaseService.shared,
            eventBus: eventBus,
            operationQueue: syncModule.operationQueue,
            idMappingRegistry: syncModule.idMappingRegistry,
            localStorage: syncModule.localStorage,
            operationProcessor: syncModule.operationProcessor,
            networkMonitor: networkModule.networkMonitor
        )

        let noteListState = NoteListState(
            eventBus: eventBus,
            noteStore: noteStore,
            apiClient: networkModule.apiClient,
            noteAPI: networkModule.noteAPI
        )

        let noteEditorState = NoteEditorState(
            eventBus: eventBus,
            noteStore: noteStore,
            noteAPI: networkModule.noteAPI,
            operationQueue: syncModule.operationQueue,
            localStorage: syncModule.localStorage,
            operationProcessor: syncModule.operationProcessor
        )

        let folderState = FolderState(eventBus: eventBus, noteStore: noteStore)

        let notePreviewService = NotePreviewService(localStorage: syncModule.localStorage)

        return Output(
            noteStore: noteStore,
            noteListState: noteListState,
            noteEditorState: noteEditorState,
            notePreviewService: notePreviewService,
            folderState: folderState
        )
    }
}
