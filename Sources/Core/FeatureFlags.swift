import Foundation

/// 特性开关
///
/// 用于控制新旧架构的切换,支持运行时切换
public struct FeatureFlags {
    /// 是否使用新架构
    ///
    /// - `true`: 使用新的 ViewModel 架构 (AppCoordinator + 7 个 ViewModel)
    /// - `false`: 使用旧的 NotesViewModel 架构
    ///
    /// 默认值: `false` (使用旧架构,保持向后兼容)
    public static var useNewArchitecture: Bool {
        get {
            UserDefaults.standard.bool(forKey: "useNewArchitecture")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "useNewArchitecture")
            print("[FeatureFlags] useNewArchitecture 设置为: \(newValue)")
        }
    }
}
