//
//  Pan115SettingsView.swift
//  AVDB
//
//  115 离线设置：Cookie（UID/CID/SEID）+ 离线目录 CID。
//

import SwiftUI

struct Pan115SettingsView: View {
    @ObservedObject private var settings = Pan115Settings.shared
    @State private var cookieDraft = ""
    @State private var cidDraft = ""
    @State private var status: String?
    @State private var statusOK = false
    @State private var testing = false

    var body: some View {
        Form {
            Section {
                Text("从 115 网页登录后，用 Safari / 抓包复制完整 Cookie。必须包含 UID、CID、SEID。离线目录 CID 是网盘目标文件夹 ID，根目录填 0。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Cookie") {
                TextEditor(text: $cookieDraft)
                    .frame(minHeight: 120)
                    .font(.system(.caption, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("离线目录 CID") {
                TextField("例如 0 或 1234567890", text: $cidDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
            }

            Section {
                Button("保存") { save() }
                Button {
                    Task { await testPush() }
                } label: {
                    if testing {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("测试连接").frame(maxWidth: .infinity)
                    }
                }
                .disabled(testing)
            }

            if let status {
                Section {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(statusOK ? .green : .red)
                }
            }

            Section("状态") {
                LabeledContent("Cookie") {
                    Text(cookieReady ? "已填写" : "未填写")
                        .foregroundColor(cookieReady ? .green : .secondary)
                }
                LabeledContent("目录 CID") {
                    Text(cidDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未填写" : cidDraft)
                        .foregroundColor(cidDraft.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                }
            }
        }
        .navigationTitle("115 离线")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            cookieDraft = settings.cookie
            cidDraft = settings.folderCID
        }
    }

    private var cookieReady: Bool {
        let c = Pan115Settings.normalizeCookie(cookieDraft)
        return c.contains("UID=") && c.contains("CID=") && c.contains("SEID=")
    }

    private func save() {
        settings.cookie = Pan115Settings.normalizeCookie(cookieDraft)
        settings.folderCID = cidDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        cookieDraft = settings.cookie
        cidDraft = settings.folderCID
        statusOK = settings.isConfigured
        status = settings.isConfigured ? "已保存，详情页点磁力即可推送" : settings.missingHint
    }

    private func testPush() async {
        save()
        guard settings.isConfigured else { return }
        testing = true
        defer { testing = false }
        // 用一条无效短链探测鉴权，不真正下任务：只走签名接口
        do {
            let result = try await Pan115Client.shared.addOfflineTask(
                url: "magnet:?xt=urn:btih:0000000000000000000000000000000000000000",
                cookie: settings.cookie,
                folderCID: settings.folderCID
            )
            switch result {
            case .success, .exists:
                statusOK = true
                status = "连接正常（\(result.message)）"
            case .failed(let msg):
                // 假 hash 失败但能通到业务层，也算 Cookie 有效
                if msg.contains("Cookie") || msg.contains("登录") || msg.contains("过期") {
                    statusOK = false
                    status = msg
                } else {
                    statusOK = true
                    status = "Cookie 有效：" + msg
                }
            }
        } catch {
            statusOK = false
            status = error.localizedDescription
        }
    }
}
