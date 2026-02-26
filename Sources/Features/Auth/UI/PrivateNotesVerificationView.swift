import LocalAuthentication
import SwiftUI

/// 私密笔记验证视图（类似Apple Notes样式）
struct PrivateNotesVerificationView: View {
    @ObservedObject var authState: AuthState
    @State private var password = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isAuthenticating = false
    @State private var showPasswordInput = false

    private let passwordManager = PrivateNotesPasswordManager.shared

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // 锁图标和Touch ID图标
            ZStack {
                Image(systemName: "lock.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.secondary)

                if passwordManager.isTouchIDEnabled(), passwordManager.isBiometricAvailable() {
                    Image(systemName: "touchid")
                        .font(.system(size: 40))
                        .foregroundColor(.red)
                        .offset(x: 0, y: 10)
                }
            }
            .padding(.bottom, 30)

            Text("此笔记已锁定。")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.primary)
                .padding(.bottom, 8)

            Text("使用触控 ID 或输入为\"iCloud\"账户中笔记创建的密码查看此笔记。")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 30)

            Button {
                showPasswordInput = true
            } label: {
                Text("输入密码")
                    .font(.system(size: 14))
                    .frame(width: 120, height: 32)
            }
            .buttonStyle(.bordered)
            .padding(.bottom, 20)

            if passwordManager.isTouchIDEnabled(), passwordManager.isBiometricAvailable() {
                Button {
                    authenticateWithTouchID()
                } label: {
                    HStack {
                        Image(systemName: "touchid")
                            .font(.system(size: 16))
                        Text("使用 \(passwordManager.getBiometricType() ?? "Touch ID")")
                            .font(.system(size: 14))
                    }
                    .frame(width: 200, height: 32)
                }
                .buttonStyle(.bordered)
                .disabled(isAuthenticating)
                .padding(.bottom, 20)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: NSColor.textBackgroundColor))
        .sheet(isPresented: $showPasswordInput) {
            PasswordInputSheetView(
                authState: authState,
                password: $password,
                showError: $showError,
                errorMessage: $errorMessage,
                isAuthenticating: $isAuthenticating,
                onDismiss: { showPasswordInput = false }
            )
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
                    }
                }
            } catch let error as PasswordError {
                await MainActor.run {
                    isAuthenticating = false
                    switch error {
                    case .biometricCancelled:
                        break
                    case .biometricFallback:
                        showPasswordInput = true
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
}

/// 密码输入Sheet视图
struct PasswordInputSheetView: View {
    @ObservedObject var authState: AuthState
    @Binding var password: String
    @Binding var showError: Bool
    @Binding var errorMessage: String
    @Binding var isAuthenticating: Bool
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("访问私密笔记")
                .font(.headline)

            Text("请输入私密笔记密码以继续")
                .font(.subheadline)
                .foregroundColor(.secondary)

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

            HStack(spacing: 12) {
                Button("取消") {
                    password = ""
                    showError = false
                    errorMessage = ""
                    dismiss()
                    onDismiss()
                }
                .buttonStyle(.bordered)

                Button("验证") {
                    verifyPassword()
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty || isAuthenticating)
            }
        }
        .padding(30)
        .frame(width: 400)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // 自动聚焦密码输入框
            }
        }
    }

    private func verifyPassword() {
        if password.isEmpty {
            errorMessage = "请输入密码"
            showError = true
        } else if authState.verifyPrivateNotesPassword(password) {
            password = ""
            showError = false
            errorMessage = ""
            dismiss()
            onDismiss()
        } else {
            errorMessage = "密码错误，请重试"
            showError = true
            password = ""
        }
    }
}
