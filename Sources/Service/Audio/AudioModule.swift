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

    public init(syncModule: SyncModule, networkModule _: NetworkModule) {
        let cache = AudioCacheService()
        self.cacheService = cache

        let converter = AudioConverterService()
        self.converterService = converter

        let uploader = AudioUploadService(
            converterService: converter,
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
        self.init(syncModule: SyncModule(), networkModule: NetworkModule())
    }
}
