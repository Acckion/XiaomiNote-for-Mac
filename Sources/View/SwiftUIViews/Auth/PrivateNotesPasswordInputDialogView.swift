import SwiftUI

/// 私密笔记密码输入对话框
struct PrivateNotesPasswordInputDialogView: View {
    @ObservedObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isAuthenticating = false

    private let passwordManager = PrivateNotesPasswordManager.shared

    var body: some View {
        VStack(spacing: 20) {
            Text("访问私密笔记")
                .font(.headline)

            Text("请输入私密笔记密码以继续")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Touch ID 按钮（如果启用且设备支持）
            if passwordManager.isTouchIDEnabled(), passwordManager.isBiometricAvailable() {
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
                    authState.handlePrivateNotesPasswordCancel()
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
            if passwordManager.isTouchIDEnabled(), passwordManager.isBiometricAvailable() {
                try? await Task.sleep(nanoseconds: 300_000_000)
                authenticateWithTouchID()
            }
        }
        .onDisappear {
            if !authState.isPrivateNotesUnlocked {
                authState.handlePrivateNotesPasswordCancel()
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
                        authState.unlockPrivateNotes()
                        dismiss()
                    }
                }
            } catch let error as PasswordError {
                await MainActor.run {
                    isAuthenticating = false
                    switch error {
                    case .biometricCancelled:
                        break
                    case .biometricFallback:
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
        } else if authState.verifyPrivateNotesPassword(password) {
            dismiss()
        } else {
            errorMessage = "密码不正确，请重试"
            showError = true
            password = ""
        }
    }
}
