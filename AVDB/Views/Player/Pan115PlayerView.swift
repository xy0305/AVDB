//
//  Pan115PlayerView.swift
//  AVDB
//
//  推送磁力到 115 离线，等待完成后用 pickcode 播原画。
//

import SwiftUI
import AVKit

struct Pan115PlayerView: View {
    let movie: Movie
    var magnetURL: String? = nil
    @StateObject private var vm = Pan115PlayerViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if vm.player.currentItem != nil && vm.errorMessage == nil && !vm.isLoading {
                VideoPlayer(player: vm.player)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 240)
                    .background(Color.black)
                if !vm.fileName.isEmpty {
                    Text(vm.fileName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                Spacer()
            } else if vm.isLoading {
                VStack(spacing: 14) {
                    ProgressView()
                    Text(vm.status)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxHeight: .infinity)
            } else if let err = vm.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text(err)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("重试") {
                        Task { await vm.start(movie: movie, magnetURL: magnetURL) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .navigationTitle("115 原画")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.start(movie: movie, magnetURL: magnetURL) }
        .onDisappear { vm.player.pause() }
    }
}

@MainActor
final class Pan115PlayerViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var status = "准备中…"
    @Published var errorMessage: String?
    @Published var fileName = ""
    @Published var player = AVPlayer()

    func start(movie: Movie, magnetURL: String?) async {
        let settings = Pan115Settings.shared
        guard settings.isConfigured else {
            errorMessage = settings.missingHint
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let cookie = settings.cookie
        let cid = settings.folderCID
        let keyword = movie.displayNumber
        let magnet = magnetURL
            ?? Pan115PlaybackCache.magnet(for: movie.id)
            ?? ""

        do {
            // 已离线过的直接播
            status = "正在目录中查找 \(keyword)…"
            if let existing = try? await Pan115Client.shared.findLatestVideo(in: cid, cookie: cookie, keyword: keyword) {
                fileName = existing.name
                status = "获取 115 原画地址…"
                let url = try await Pan115Client.shared.originalPlayURL(
                    pickCode: existing.pickCode, cookie: cookie, filename: existing.name)
                play(url: url, cookie: cookie)
                return
            }

            if magnet.isEmpty {
                throw Pan115Error.fileNotFound
            }

            status = "正在推送到 115 离线…"
            let result = try await Pan115Client.shared.addOfflineTask(
                url: magnet, cookie: cookie, folderCID: cid)
            Pan115PlaybackCache.save(movieID: movie.id, magnet: magnet)
            status = result.message + "，等待离线完成（通常几秒）…"

            let task = try await Pan115Client.shared.waitOfflineReady(
                keyword: keyword, cookie: cookie, timeout: 90)
            status = "离线完成：\(task.name)"

            status = "正在目录中查找视频…"
            let searchCID = task.dirID.isEmpty ? cid : task.dirID
            let file = try await Pan115Client.shared.findLatestVideo(
                in: searchCID, cookie: cookie, keyword: keyword)
            fileName = file.name

            status = "获取 115 原画地址…"
            let url = try await Pan115Client.shared.originalPlayURL(
                pickCode: file.pickCode, cookie: cookie, filename: file.name)
            play(url: url, cookie: cookie)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func play(url: URL, cookie: String) {
        let headers: [String: String] = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "Referer": "https://115.com/",
            "Cookie": cookie,
        ]
        let options = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let asset = AVURLAsset(url: url, options: options)
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        player.play()
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
