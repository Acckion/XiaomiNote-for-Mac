//
//  AudioAssembler.swift
//  MiNoteLibrary
//

import Foundation

/// 音频域依赖装配器
@MainActor
enum AudioAssembler {
    struct Output {
        let audioPanelViewModel: AudioPanelViewModel
        let memoryCacheManager: MemoryCacheManager
    }

    static func assemble() -> Output {
        let audioPanelViewModel = AudioPanelViewModel(
            audioService: DefaultAudioService(cacheService: DefaultCacheService()),
            noteService: DefaultNoteStorage()
        )
        let memoryCacheManager = MemoryCacheManager()

        return Output(
            audioPanelViewModel: audioPanelViewModel,
            memoryCacheManager: memoryCacheManager
        )
    }
}
