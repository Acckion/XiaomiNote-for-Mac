import SwiftUI

/// 私密笔记密码输入对话框
struct PrivateNotesPasswordInputDialogView: View {
    @ObservedObject var viewModel: NotesViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var password: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isAuthenticating: Bool = false
    
    private let passwordManager = PrivateNotesPasswordManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Text("访问私密笔记")
                .font(.headline)
            
            Text("请输入私密笔记密码以继续")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Touch ID 按钮（如果启用且设备支持）
            if passwordManager.isTouchIDEnabled() && passwordManager.isBiometricAvailable() {
                Button {
                    authenticateWithTouchID()
                } label: {
                    HStack {
                        Image(systemName: "touchid")
                            .font(.title2)
                        Text("使用 \(passwordManager.getBiometricType() ?? "Touch ID")")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAuthenticating)
                
                Divider()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("密码")
                    .font(.caption)
                    .foregroundColor(.secondary)
                SecureField("请输入密码", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        verifyPassword()
                    }
            }
            
            if showError {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            HStack {
                Button("取消") {
                    // 用户取消验证，通知视图模型
                    viewModel.handlePrivateNotesPasswordCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("确定") {
                    verifyPassword()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty || isAuthenticating)
            }
        }
        .padding(20)
        .frame(width: 400)
        .task {
            // 如果启用了 Touch ID，自动尝试使用 Touch ID 验证
            if passwordManager.isTouchIDEnabled() && passwordManager.isBiometricAvailable() {
                // 延迟一小段时间，让对话框先显示
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3秒
                authenticateWithTouchID()
            }
        }
        .onDisappear {
            // 当对话框消失时，如果用户没有验证成功，需要处理取消逻辑
            if !viewModel.isPrivateNotesUnlocked {
                viewModel.handlePrivateNotesPasswordCancel()
            }
        }
    }
    
    private func authenticateWithTouchID() {
        guard !isAuthenticating else { return }
        
        isAuthenticating = true
        showError = false
        
        Task {
            do {
                let success = try await passwordManager.authenticateWithTouchID()
                
                await MainActor.run {
                    isAuthenticating = false
                    if success {
                        // Touch ID 验证成功，解锁私密笔记
                        viewModel.unlockPrivateNotes()
                        dismiss()
                    }
                }
            } catch let error as PasswordError {
                await MainActor.run {
                    isAuthenticating = false
                    switch error {
                    case .biometricCancelled:
                        // 用户取消，不显示错误
                        break
                    case .biometricFallback:
                        // 用户选择使用密码，不显示错误
                        break
                    default:
                        errorMessage = error.localizedDescription ?? "Touch ID 验证失败"
                        showError = true
                    }
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    private func verifyPassword() {
        if password.isEmpty {
            errorMessage = "密码不能为空"
            showError = true
        } else if viewModel.verifyPrivateNotesPassword(password) {
            // 密码正确，关闭对话框
            dismiss()
        } else {
            // 密码错误
            errorMessage = "密码不正确，请重试"
            showError = true
            password = "" // 清空密码输入框
        }
    }
}
