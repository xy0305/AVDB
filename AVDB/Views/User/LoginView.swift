//
//  LoginView.swift
//  AVDB
//
//  登录页。
//

import SwiftUI

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var username = ""
    @State private var password = ""
    @State private var token = ""
    @State private var loginMethod: LoginMethod = .credentials
    @State private var isLoading = false
    @State private var errorMessage: String?

    enum LoginMethod {
        case credentials
        case token
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("登录方式", selection: $loginMethod) {
                        Text("账号密码").tag(LoginMethod.credentials)
                        Text("Token").tag(LoginMethod.token)
                    }
                    .pickerStyle(.segmented)
                }

                if loginMethod == .credentials {
                    Section {
                        TextField("用户名", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("密码", text: $password)
                    }
                } else {
                    Section {
                        TextField("粘贴 Token", text: $token, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .lineLimit(3...6)
                    } footer: {
                        Text("从官方 App 或其他客户端获取登录 Token，格式通常为 Bearer eyJ... 或直接 eyJ...")
                            .font(.caption)
                    }
                }

                Section {
                    Button {
                        Task { await login() }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("登录")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isLoginDisabled || isLoading)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private var isLoginDisabled: Bool {
        if loginMethod == .credentials {
            return username.isEmpty || password.isEmpty
        } else {
            return token.isEmpty
        }
    }

    private func login() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if loginMethod == .credentials {
                let user = try await JavDBSDK.shared.login(username: username, password: password)
                appState.currentUser = user
                appState.isLoggedIn = true
            } else {
                // Token 登录
                var cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
                // 移除各种可能的前缀
                for prefix in ["AUTHORIZATION=Bearer ", "Bearer ", "AUTHORIZATION="] {
                    if cleanToken.hasPrefix(prefix) {
                        cleanToken = String(cleanToken.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                        break
                    }
                }
                JavDBSDK.shared.setToken(cleanToken)
                // 验证 Token 并获取用户信息
                let user = try await JavDBSDK.shared.userInfo()
                appState.currentUser = user
                appState.isLoggedIn = true
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
