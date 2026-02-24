import Foundation

/// 音频层模块工厂
///
/// 管理音频相关的纠缠单例，不包含保留单例的 3 个音频服务
/// （AudioPlayerService、AudioRecorderService、AudioDecryptService）。
@MainActor
public struct AudioModule: Sendable {
    let cacheService: AudioCacheService
    let converterService: AudioConverterService
    let uploadService: AudioUploadService
    let panelStateManager: AudioPanelStateManager

    public init(
        syncModule: SyncModule,
        networkModule: NetworkModule
    ) {
        self.cacheService = networkModule.audioCacheService
        self.converterService = networkModule.audioConverterService

        let uploader = AudioUploadService(
            converterService: networkModule.audioConverterService,
            localStorage: syncModule.localStorage,
            unifiedQueue: syncModule.operationQueue
        )
        self.uploadService = uploader

        let panel = AudioPanelStateManager(
            recorderService: AudioRecorderService.shared,
            playerService: AudioPlayerService.shared
        )
        self.panelStateManager = panel
    }

    /// Preview 和测试用的便利构造器
    public init() {
        let nm = NetworkModule()
        let sm = SyncModule(networkModule: nm)
        self.init(syncModule: sm, networkModule: nm)
    }
}
