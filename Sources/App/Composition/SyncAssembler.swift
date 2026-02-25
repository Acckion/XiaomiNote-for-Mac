//
//  SyncAssembler.swift
//  MiNoteLibrary
//

import Foundation

/// 同步域依赖装配器
@MainActor
enum SyncAssembler {
    struct Output {
        let syncEngine: SyncEngine
        let syncState: SyncState
        let startupSequenceManager: StartupSequenceManager
        let errorRecoveryService: ErrorRecoveryService
        let networkRecoveryHandler: NetworkRecoveryHandler
    }

    static func assemble(
        eventBus: EventBus,
        networkModule: NetworkModule,
        syncModule: SyncModule,
        noteStore: NoteStore
    ) -> Output {
        let syncEngine = syncModule.createSyncEngine(noteStore: noteStore)

        let syncState = SyncState(eventBus: eventBus, operationQueue: syncModule.operationQueue)

        let startupSequenceManager = StartupSequenceManager(
            localStorage: syncModule.localStorage,
            onlineStateManager: syncModule.onlineStateManager,
            operationProcessor: syncModule.operationProcessor,
            unifiedQueue: syncModule.operationQueue,
            eventBus: eventBus,
            apiClient: networkModule.apiClient
        )

        let errorRecoveryService = ErrorRecoveryService(
            unifiedQueue: syncModule.operationQueue,
            networkErrorHandler: networkModule.networkErrorHandler,
            onlineStateManager: syncModule.onlineStateManager
        )

        let networkRecoveryHandler = NetworkRecoveryHandler(
            networkMonitor: networkModule.networkMonitor,
            onlineStateManager: syncModule.onlineStateManager,
            operationProcessor: syncModule.operationProcessor,
            unifiedQueue: syncModule.operationQueue,
            eventBus: eventBus
        )

        return Output(
            syncEngine: syncEngine,
            syncState: syncState,
            startupSequenceManager: startupSequenceManager,
            errorRecoveryService: errorRecoveryService,
            networkRecoveryHandler: networkRecoveryHandler
        )
    }
}
