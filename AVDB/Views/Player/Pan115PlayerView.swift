//
//  Pan115PlayerView.swift
//  AVDB
//
//  推送磁力到 115 离线，按番号匹配完成后用 KSPlayer 播原画。
//

import SwiftUI
import KSPlayer

struct Pan115PlayerView: View {
    let movie: Movie
    var magnetURL: String? = nil
    @StateObject private var vm = Pan115PlayerViewModel()

    var body: some View {
        Group {
            if let url = vm.playURL, vm.errorMessage == nil, !vm.isLoading {
                KSChromePlayer(
                    url: url,
                    title: movie.displayNumber,
                    subtitle: vm.fileName,
                    headers: vm.headers
                )
            } else if vm.isLoading {
                ContentUnavailableView {
                    ProgressView()
                } description: {
                    Text(vm.status)
                }
            } else if let err = vm.errorMessage {
                ContentUnavailableView {
                    Label("无法播放", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(err)
                } actions: {
                    Button("重试") {
                        Task { await vm.start(movie: movie, magnetURL: magnetURL) }
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("115 原画")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.start(movie: movie, magnetURL: magnetURL) }
    }
}

@MainActor
final class Pan115PlayerViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var status = "准备中…"
    @Published var errorMessage: String?
    @Published var fileName = ""
    @Published var playURL: URL?

    var headers: [String: String] {
        [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "Referer": "https://115.com/",
            "Cookie": Pan115Settings.shared.cookie,
        ]
    }

    func start(movie: Movie, magnetURL: String?) async {
        let settings = Pan115Settings.shared
        guard settings.isConfigured else {
            errorMessage = settings.missingHint
            return
        }
        isLoading = true
        errorMessage = nil
        playURL = nil
        defer { isLoading = false }

        let cookie = settings.cookie
        let cid = settings.folderCID
        let keyword = movie.displayNumber
        let magnet = magnetURL
            ?? Pan115PlaybackCache.magnet(for: movie.id)
            ?? ""

        do {
            status = "正在目录中查找 \(keyword)…"
            if let existing = try? await Pan115Client.shared.findLatestVideo(
                in: cid, cookie: cookie, keyword: keyword, requireMatch: true
            ) {
                fileName = existing.name
                status = "获取 115 原画地址…"
                playURL = try await Pan115Client.shared.originalPlayURL(
                    pickCode: existing.pickCode, cookie: cookie, filename: existing.name)
                return
            }

            if magnet.isEmpty {
                throw Pan115Error.fileNotFound
            }

            status = "正在推送到 115 离线…"
            let result = try await Pan115Client.shared.addOfflineTask(
                url: magnet, cookie: cookie, folderCID: cid)
            Pan115PlaybackCache.save(movieID: movie.id, magnet: magnet)
            status = result.message + "，等待离线完成…"

            let task = try await Pan115Client.shared.waitOfflineReady(
                keyword: keyword, cookie: cookie, timeout: 90)
            status = "离线完成：\(task.name)"

            let searchCID = task.dirID.isEmpty ? cid : task.dirID
            let file = try await Pan115Client.shared.findLatestVideo(
                in: searchCID, cookie: cookie, keyword: keyword, requireMatch: true)
            fileName = file.name
            status = "获取 115 原画地址…"
            playURL = try await Pan115Client.shared.originalPlayURL(
                pickCode: file.pickCode, cookie: cookie, filename: file.name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum Pan115PlaybackCache {
    private static func key(_ movieID: String) -> String { "avdb.115.lastMagnet.\(movieID)" }

    static func save(movieID: String, magnet: String) {
        UserDefaults.standard.set(magnet, forKey: key(movieID))
    }

    static func magnet(for movieID: String) -> String? {
        UserDefaults.standard.string(forKey: key(movieID))
    }
}
