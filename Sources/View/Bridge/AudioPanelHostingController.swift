//
//  AudioPanelHostingController.swift
//  MiNoteMac
//
//  音频面板托管控制器 - 托管 AudioPanelView
//  将 SwiftUI 的 AudioPanelView 嵌入 NSSplitViewController 作为第四栏
//
//

import AppKit
import Combine
import SwiftUI

/// 音频面板托管控制器
///
/// 将 AudioPanelView 嵌入 NSSplitViewController 作为第四栏。
/// 负责管理音频面板的显示和与主窗口的交互。
///
/// - 1.1: 在主窗口右侧显示第四栏音频面板
/// - 1.2: 保持侧边栏、笔记列表和编辑器的原有布局
class AudioPanelHostingController: NSViewController {

    // MARK: - 属性

    /// 音频面板状态管理器
    private let stateManager: AudioPanelStateManager

    /// 笔记视图模型
    private let viewModel: NotesViewModel

    /// 录制服务
    private let recorderService: AudioRecorderService

    /// 播放服务
    private let playerService: AudioPlayerService

    /// 托管视图
    private var hostingView: NSHostingView<AudioPanelView>?

    /// Combine 订阅集合
    private var cancellables = Set<AnyCancellable>()

    /// 录制完成回调
    var onRecordingComplete: ((URL) -> Void)?

    /// 关闭回调
    var onClose: (() -> Void)?

    // MARK: - 初始化

    /// 初始化方法
    ///
    /// - Parameters:
    ///   - stateManager: 音频面板状态管理器
    ///   - viewModel: 笔记视图模型
    ///   - recorderService: 录制服务（默认使用共享实例）
    ///   - playerService: 播放服务（默认使用共享实例）
    init(
        stateManager: AudioPanelStateManager,
        viewModel: NotesViewModel,
        recorderService: AudioRecorderService = .shared,
        playerService: AudioPlayerService = .shared
    ) {
        self.stateManager = stateManager
        self.viewModel = viewModel
        self.recorderService = recorderService
        self.playerService = playerService
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 视图生命周期

    override func loadView() {
        // 创建 SwiftUI 视图
        let audioPanelView = AudioPanelView(
            stateManager: stateManager,
            recorderService: recorderService,
            playerService: playerService,
            onRecordingComplete: { [weak self] url in
                self?.handleRecordingComplete(url: url)
            },
            onClose: { [weak self] in
                self?.handleClose()
            }
        )

        // 创建 NSHostingView
        let hostingView = NSHostingView(rootView: audioPanelView)
        self.hostingView = hostingView

        // 设置视图
        view = hostingView

        // 设置视图约束
        view.translatesAutoresizingMaskIntoConstraints = false
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // 设置状态监听
        setupStateObservers()

    }

    override func viewDidLayout() {
        super.viewDidLayout()

        // 确保 hostingView 填充整个视图
        hostingView?.frame = view.bounds
    }

    override func viewWillAppear() {
        super.viewWillAppear()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
    }

    // MARK: - 键盘事件处理

    /// 处理 Escape 键
    ///
    /// 当用户按下 Escape 键时，如果面板处于空闲状态（非录制中），则关闭面板。
    /// 如果正在录制，则不响应 Escape 键，需要用户通过确认对话框关闭。
    ///
    override func cancelOperation(_: Any?) {

        // 检查是否可以安全关闭
        if stateManager.canClose() {
            handleClose()
        } else {
            // 正在录制时，发出提示音
            NSSound.beep()
        }
    }

    /// 使视图控制器成为第一响应者
    override var acceptsFirstResponder: Bool {
        true
    }

    /// 视图成为第一响应者时调用
    override func becomeFirstResponder() -> Bool {
        true
    }

    // MARK: - 私有方法

    /// 设置状态监听
    private func setupStateObservers() {
        // 监听状态管理器的模式变化
        stateManager.$mode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.refreshView()
            }
            .store(in: &cancellables)

        // 监听文件 ID 变化
        stateManager.$currentFileId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] fileId in
                self?.refreshView()
            }
            .store(in: &cancellables)
    }

    /// 处理录制完成
    ///
    /// - Parameter url: 录制文件的 URL
    private func handleRecordingComplete(url: URL) {
        onRecordingComplete?(url)
    }

    /// 处理关闭
    private func handleClose() {
        onClose?()
    }

    // MARK: - 公共方法

    /// 刷新 SwiftUI 视图
    func refreshView() {
        let audioPanelView = AudioPanelView(
            stateManager: stateManager,
            recorderService: recorderService,
            playerService: playerService,
            onRecordingComplete: { [weak self] url in
                self?.handleRecordingComplete(url: url)
            },
            onClose: { [weak self] in
                self?.handleClose()
            }
        )
        hostingView?.rootView = audioPanelView
    }

    /// 获取首选宽度
    ///
    /// - Returns: 首选宽度（320 像素）
    func preferredWidth() -> CGFloat {
        320
    }

    /// 获取最小宽度
    ///
    /// - Returns: 最小宽度（280 像素）
    func minimumWidth() -> CGFloat {
        280
    }

    /// 获取最大宽度
    ///
    /// - Returns: 最大宽度（400 像素）
    func maximumWidth() -> CGFloat {
        400
    }
}
