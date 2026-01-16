//
//  EditorSettingsView.swift
//  MiNoteMac
//
//  编辑器设置界面 - 配置原生编辑器
//

import SwiftUI

/// 编辑器设置视图
public struct EditorSettingsView: View {
    
    // MARK: - Properties
    
    // 使用 @ObservedObject 而不是 @StateObject，因为这些是单例
    @ObservedObject private var preferencesService = EditorPreferencesService.shared
    @ObservedObject private var configurationManager = EditorConfigurationManager.shared
    
    @State private var showCompatibilityInfo = false
    
    public init() {}
    
    // MARK: - Body
    
    public var body: some View {
        Form {
            // 编辑器信息部分
            editorInfoSection
            
            // 编辑器配置部分
            editorConfigurationSection
            
            // 系统兼容性部分
            systemCompatibilitySection
        }
        .formStyle(.grouped)
        .navigationTitle("编辑器设置")
        .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
        .toolbarBackgroundVisibility(.automatic, for: .windowToolbar)
        .frame(minWidth: 500, minHeight: 600)
    }
    
    // MARK: - Sections
    
    /// 编辑器信息部分
    private var editorInfoSection: some View {
        Section("编辑器") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    // 编辑器图标
                    Image(systemName: EditorType.native.icon)
                        .font(.title)
                        .foregroundColor(.accentColor)
                        .frame(width: 32, height: 32)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(EditorType.native.displayName)
                            .font(.headline)
                        
                        Text(EditorType.native.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
                
                if !preferencesService.isNativeEditorAvailable {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("原生编辑器需要 macOS 13.0 或更高版本")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    /// 编辑器配置部分
    private var editorConfigurationSection: some View {
        Section("编辑器配置") {
            VStack(alignment: .leading, spacing: 16) {
                EditorConfigurationView(configuration: $configurationManager.currentConfiguration)
            }
        }
    }
    
    /// 系统兼容性部分
    private var systemCompatibilitySection: some View {
        Section("系统兼容性") {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: { showCompatibilityInfo.toggle() }) {
                    HStack {
                        Text("查看系统兼容性信息")
                        Spacer()
                        Image(systemName: showCompatibilityInfo ? "chevron.up" : "chevron.down")
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                
                if showCompatibilityInfo {
                    SystemCompatibilityView()
                        .transition(.opacity.combined(with: .slide))
                }
                
                Button("重新检查兼容性") {
                    preferencesService.recheckNativeEditorAvailability()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

/// 编辑器配置视图
struct EditorConfigurationView: View {
    @Binding var configuration: EditorConfiguration
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 字体设置
            fontSettingsSection
            
            // 编辑器行为设置
            behaviorSettingsSection
            
            // 外观设置
            appearanceSettingsSection
            
            // 重置按钮
            HStack {
                Spacer()
                Button("重置为默认") {
                    configuration = EditorConfiguration.defaultConfiguration()
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    private var fontSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("字体设置")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            HStack {
                Text("字体大小")
                Spacer()
                Slider(value: $configuration.fontSize, in: 10...24, step: 1) {
                    Text("字体大小")
                } minimumValueLabel: {
                    Text("10")
                } maximumValueLabel: {
                    Text("24")
                }
                .frame(width: 120)
                Text("\(Int(configuration.fontSize))pt")
                    .frame(width: 30)
            }
            
            HStack {
                Text("行间距")
                Spacer()
                Slider(value: $configuration.lineSpacing, in: 1.0...2.5, step: 0.1) {
                    Text("行间距")
                } minimumValueLabel: {
                    Text("1.0")
                } maximumValueLabel: {
                    Text("2.5")
                }
                .frame(width: 120)
                Text(String(format: "%.1f", configuration.lineSpacing))
                    .frame(width: 30)
            }
        }
    }
    
    private var behaviorSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("编辑器行为")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Toggle("启用自动保存", isOn: $configuration.autoSaveEnabled)
            
            if configuration.autoSaveEnabled {
                HStack {
                    Text("自动保存间隔")
                    Spacer()
                    Picker("", selection: $configuration.autoSaveInterval) {
                        Text("3秒").tag(3.0)
                        Text("5秒").tag(5.0)
                        Text("10秒").tag(10.0)
                        Text("30秒").tag(30.0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 80)
                }
            }
            
            Toggle("启用拼写检查", isOn: $configuration.spellCheckEnabled)
            Toggle("启用语法高亮", isOn: $configuration.syntaxHighlightEnabled)
        }
    }
    
    private var appearanceSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("外观设置")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Toggle("适配暗色模式", isOn: $configuration.darkModeEnabled)
            Toggle("显示行号", isOn: $configuration.showLineNumbers)
            Toggle("启用代码折叠", isOn: $configuration.codeFoldingEnabled)
            
            HStack {
                Text("缩进大小")
                Spacer()
                Stepper(value: $configuration.indentSize, in: 2...8, step: 1) {
                    Text("\(configuration.indentSize) 空格")
                }
            }
            
            Toggle("使用制表符缩进", isOn: $configuration.useTabsForIndentation)
        }
    }
}

/// 系统兼容性视图
struct SystemCompatibilityView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("系统兼容性信息")
                .font(.headline)
                .padding(.bottom, 4)
            
            VStack(alignment: .leading, spacing: 8) {
                compatibilityRow(
                    title: "当前系统版本",
                    value: ProcessInfo.processInfo.operatingSystemVersionString,
                    status: .info
                )
                
                compatibilityRow(
                    title: "原生编辑器支持",
                    value: EditorFactory.isEditorAvailable(.native) ? "支持" : "不支持",
                    status: EditorFactory.isEditorAvailable(.native) ? .success : .warning
                )
                
                compatibilityRow(
                    title: "NSTextAttachment 可用性",
                    value: NSClassFromString("NSTextAttachment") != nil ? "可用" : "不可用",
                    status: NSClassFromString("NSTextAttachment") != nil ? .success : .error
                )
            }
        }
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
    
    private func compatibilityRow(title: String, value: String, status: CompatibilityStatus) -> some View {
        HStack {
            Text(title)
                .font(.caption)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: status.icon)
                    .foregroundColor(status.color)
                Text(value)
                    .font(.caption)
                    .foregroundColor(status.color)
            }
        }
    }
}

/// 兼容性状态
enum CompatibilityStatus {
    case success
    case warning
    case error
    case info
    
    var icon: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.circle.fill"
        case .info:
            return "info.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        case .info:
            return .blue
        }
    }
}

#Preview {
    NavigationView {
        EditorSettingsView()
    }
    .frame(width: 600, height: 700)
}
