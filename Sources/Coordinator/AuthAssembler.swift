//
//  AuthAssembler.swift
//  MiNoteLibrary
//

import Foundation

/// 认证域依赖装配器
@MainActor
enum AuthAssembler {
    struct Output {
        let passTokenManager: PassTokenManager
        let authState: AuthState
        let searchState: SearchState
    }

    static func assemble(
        eventBus: EventBus,
        networkModule: NetworkModule,
        syncModule: SyncModule,
        noteStore: NoteStore
    ) -> Output {
        let passTokenManager = PassTokenManager(apiClient: networkModule.apiClient)

        let authState = AuthState(
            eventBus: eventBus,
            apiClient: networkModule.apiClient,
            userAPI: networkModule.userAPI,
            onlineStateManager: syncModule.onlineStateManager,
            passTokenManager: passTokenManager
        )

        let searchState = SearchState(noteStore: noteStore)

        return Output(
            passTokenManager: passTokenManager,
            authState: authState,
            searchState: searchState
        )
    }
}
