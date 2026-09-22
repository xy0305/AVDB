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
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        ZStack {
                            SoftPulseRing(color: .blue)
                                .frame(width: 88, height: 88)
                            Image(systemName: "person.crop.circle.fill.badge.checkmark")
                                .font(.system(size: 42, weight: .light))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 72, height: 72)
                                .liquidGlassCircle(tint: Color.accentColor.opacity(0.22))
                        }
                        Text("登录 AVDB")
                            .font(.title2.weight(.bold))
                        Text("同步关注、收藏与观看记录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 18)
                    .staggerAppear(index: 0)

                    VStack(spacing: 14) {
                        Picker("登录方式", selection: $loginMethod) {
                            Text("账号密码").tag(LoginMethod.credentials)
                            Text("Token").tag(LoginMethod.token)
                        }
                        .pickerStyle(.segmented)

                        if loginMethod == .credentials {
                            VStack(spacing: 10) {
                                glassField("用户名", text: $username, secure: false)
                                glassField("密码", text: $password, secure: true)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                glassField("粘贴 Token", text: $token, secure: false, multiline: true)
                                Text("从官方 App 或其他客户端获取登录 Token，格式通常为 Bearer eyJ... 或直接 eyJ...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button {
                            GlassHaptic.tap()
                            Task { await login() }
                        } label: {
                            if isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            } else {
                                Text("登录")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                        }
                        .avdbGlassButton(prominent: true)
                        .pressableGlass(scale: 0.97)
                        .disabled(isLoginDisabled || isLoading)

                        if let error = errorMessage {
                            ErrorBanner(message: error, retry: nil)
                        }
                    }
                    .padding(18)
                    .glassSurface(
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous),
                        tint: .blue,
                        tintStrength: 0.08,
                        elevation: 0.7
                    )
                    .staggerAppear(index: 1)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background { LiquidGlassBackground() }
            .navigationTitle("登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func glassField(
        _ placeholder: String,
        text: Binding<String>,
        secure: Bool,
        multiline: Bool = false
    ) -> some View {
        Group {
            if secure {
                SecureField(placeholder, text: text)
            } else if multiline {
                TextField(placeholder, text: text, axis: .vertical)
                    .lineLimit(3...6)
            } else {
                TextField(placeholder, text: text)
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: multiline ? 88 : nil, alignment: .topLeading)
        .glassSurface(
            in: RoundedRectangle(cornerRadius: 14, style: .continuous),
            elevation: 0.35
        )
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
                let (user, _) = try await JavDBSDK.shared.userInfo()
                appState.currentUser = user
                appState.isLoggedIn = true
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
