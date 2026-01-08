//
//  EditorSettingsView.swift
//  MiNoteMac
//
//  编辑器设置界面 - 允许用户选择和配置编辑器
//

import SwiftUI

/// 编辑器设置视图
public struct EditorSettingsView: View {
    
    // MARK: - Properties
    
    @StateObject private var preferencesService = EditorPreferencesService.shared
    @StateObject private var configurationManager = EditorConfigurationManager.shared
    
    @State private var showCompatibilityInfo = false
    @State private var showFeatureComparison = false
    
    // MARK: - Body
    
    public var body: some View {
        Form {
            // 编辑器选择部分
            editorSelectionSection
            
            // 编辑器特性对比部分
            editorComparisonSection
            
            // 编辑器配置部分
            editorConfigurationSection
            
            // 系统兼容性部分
            systemCompatibilitySection
        }
        .formStyle(.grouped)
        .navigationTitle("编辑器设置")
        .frame(minWidth: 500, minHeight: 600)
    }
    
    // MARK: - Sections
    
    /// 编辑器选择部分
    private var editorSelectionSection: some View {
        Section("编辑器选择") {
            VStack(alignment: .leading, spacing: 16) {
                Text("选择您偏好的编辑器类型")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                ForEach(EditorType.allCases) { editorType in
                    EditorOptionView(
                        editorType: editorType,
                        isSelected: preferencesService.selectedEditorType == editorType,
                        isAvailable: preferencesService.isEditorTypeAvailable(editorType)
                    ) {
                        selectEditor(editorType)
                    }
                }
                
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
    
    /// 编辑器特性对比部分
    private var editorComparisonSection: some View {
        Section("特性对比") {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: { showFeatureComparison.toggle() }) {
                    HStack {
                        Text("查看详细特性对比")
                        Spacer()
                        Image(systemName: showFeatureComparison ? "chevron.up" : "chevron.down")
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                
                if showFeatureComparison {
                    EditorComparisonView()
                        .transition(.opacity.combined(with: .slide))
                }
            }
        }
    }
    
    /// 编辑器配置部分
    private var editorConfigurationSection: some View {
        Section("编辑器配置") {
            VStack(alignment: .leading, spacing: 16) {
                Text("当前编辑器：\(preferencesService.selectedEditorType.displayName)")
                    .font(.headline)
                
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
    
    // MARK: - Methods
    
    /// 选择编辑器
    /// - Parameter editorType: 编辑器类型
    private func selectEditor(_ editorType: EditorType) {
        let success = preferencesService.setEditorType(editorType)
        if success {
            // 更新配置管理器的配置
            let newConfig = EditorConfiguration.defaultConfiguration(for: editorType)
            configurationManager.updateConfiguration(newConfig)
        }
    }
}

/// 编辑器选项视图
struct EditorOptionView: View {
    let editorType: EditorType
    let isSelected: Bool
    let isAvailable: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // 编辑器图标
                Image(systemName: editorType.icon)
                    .font(.title2)
                    .foregroundColor(isAvailable ? .accentColor : .secondary)
                    .frame(width: 24, height: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(editorType.displayName)
                            .font(.headline)
                            .foregroundColor(isAvailable ? .primary : .secondary)
                        
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                        
                        if !isAvailable {
                            Text("不可用")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(editorType.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                    
                    Text("最低系统要求：\(editorType.minimumSystemVersion)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
    }
}

/// 编辑器特性对比视图
struct EditorComparisonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("特性对比")
                .font(.headline)
                .padding(.bottom, 4)
            
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                // 表头
                GridRow {
                    Text("特性")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("原生编辑器")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Web 编辑器")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .padding(.bottom, 4)
                
                Divider()
                
                // 特性对比行
                ForEach(comparisonFeatures, id: \.name) { feature in
                    GridRow {
                        Text(feature.name)
                            .font(.caption)
                        
                        Image(systemName: feature.nativeSupport ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(feature.nativeSupport ? .green : .red)
                        
                        Image(systemName: feature.webSupport ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(feature.webSupport ? .green : .red)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
    
    private var comparisonFeatures: [ComparisonFeature] {
        [
            ComparisonFeature(name: "原生性能", nativeSupport: true, webSupport: false),
            ComparisonFeature(name: "系统快捷键", nativeSupport: true, webSupport: false),
            ComparisonFeature(name: "无缝复制粘贴", nativeSupport: true, webSupport: false),
            ComparisonFeature(name: "原生滚动", nativeSupport: true, webSupport: false),
            ComparisonFeature(name: "跨平台兼容", nativeSupport: false, webSupport: true),
            ComparisonFeature(name: "功能完整性", nativeSupport: true, webSupport: true),
            ComparisonFeature(name: "稳定性", nativeSupport: true, webSupport: true),
            ComparisonFeature(name: "富文本编辑", nativeSupport: true, webSupport: true),
            ComparisonFeature(name: "图片支持", nativeSupport: true, webSupport: true),
            ComparisonFeature(name: "列表和复选框", nativeSupport: true, webSupport: true)
        ]
    }
}

/// 特性对比数据模型
struct ComparisonFeature {
    let name: String
    let nativeSupport: Bool
    let webSupport: Bool
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
                    configuration = EditorConfiguration.defaultConfiguration(for: configuration.type)
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
            
            if configuration.type == .native {
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
                    title: "Web 编辑器支持",
                    value: "支持",
                    status: .success
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
