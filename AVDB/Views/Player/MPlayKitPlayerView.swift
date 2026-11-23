//
//  MPlayKitPlayerView.swift
//  AVDB
//
//  Build 353：MPlayKit（mpv 内核）播放页，与 KSPlayer 路径并行。
//  Pan115PlayerView 按 PlaybackKernelSettings.current 决定走哪条内核；
//  本视图只负责单个 URL 的播放，换 URL 由上层 .id(url) 重建视图完成。
//  字幕由 mpv + libass 在内核内直接渲染，本视图不做任何字幕处理。
//

import SwiftUI
import UIKit

struct MPlayKitPlayerView: View {
    let url: URL
    var title: String = ""
    var subtitle: String? = nil
    var headers: [String: String] = [:]
    var startSeconds: Double = 0
    var onPlaybackFailure: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var player: MPlayPlayer?
    @State private var phase = "preparing"
    @State private var position: Double = 0
    @State private var duration: Double = 0
    @State private var isPaused = false
    @State private var failureText: String?
    @State private var failureReported = false
    @State private var chromeVisible = true
    @State private var seekValue: Double = 0
    @State private var isScrubbing = false
    @State private var hideTask: Task<Void, Never>?

    private var displayPosition: Double { isScrubbing ? seekValue : position }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MPlayVideoSurface(player: player)
                .ignoresSafeArea()
                .accessibilityIdentifier("mplaykit.player")
                .onTapGesture { toggleChrome() }

            if phase == "preparing", failureText == nil {
                ProgressView()
                    .tint(.white)
            }

            if let failureText {
                Text(failureText)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if chromeVisible {
                chrome
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: chromeVisible)
        .task {
            startPlayerIfNeeded()
            pokeChrome()
            await pollState()
        }
        .onDisappear {
            hideTask?.cancel()
            hideTask = nil
            player?.close()
            player = nil
        }
    }

    // MARK: - Chrome（极简：顶部关闭 + 标题，底部播放/进度）

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mplaykit.close")

                VStack(alignment: .leading, spacing: 2) {
                    if !title.isEmpty {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                .padding(.top, 10)

                Spacer()
            }
            .padding(.horizontal, 12)
            .background(Color.black.opacity(0.45))

            Spacer()

            HStack(spacing: 12) {
                Button {
                    let target = !isPaused
                    _ = player?.setPaused(target)
                    isPaused = target
                    pokeChrome()
                } label: {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mplaykit.playpause")

                Text(PlaybackResumePolicy.clock(displayPosition))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: true, vertical: false)

                Slider(value: $seekValue, in: 0...max(duration, 1)) { editing in
                    if editing {
                        isScrubbing = true
                        pokeChrome()
                    } else {
                        isScrubbing = false
                        player?.seek(to: seekValue)
                        pokeChrome()
                    }
                }
                .tint(.white)
                .accessibilityIdentifier("mplaykit.seek")

                Text(PlaybackResumePolicy.clock(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.45))
        }
    }

    // MARK: - Player lifecycle & state polling

    private func startPlayerIfNeeded() {
        guard player == nil else { return }
        do {
            let created = try MPlayPlayer()
            player = created
            created.open(url: url.absoluteString, startSeconds: startSeconds, headers: headers)
        } catch {
            failureText = "播放器初始化失败：\(error.localizedDescription)"
            reportFailureOnce()
        }
    }

    private func pollState() async {
        while !Task.isCancelled {
            if let player {
                let state = player.state()
                phase = state.phase
                isPaused = state.paused
                duration = state.duration
                if !isScrubbing {
                    position = state.position
                    seekValue = state.position
                }
                if state.phase == "failed" {
                    if !state.failure.isEmpty {
                        failureText = state.failure
                    } else if !state.surfaceError.isEmpty {
                        failureText = state.surfaceError
                    } else {
                        failureText = "播放失败"
                    }
                    reportFailureOnce()
                }
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    private func reportFailureOnce() {
        guard !failureReported else { return }
        failureReported = true
        onPlaybackFailure?()
    }

    // MARK: - Chrome auto-hide（4 秒无操作隐藏，点按画面切换）

    private func toggleChrome() {
        if chromeVisible {
            hideTask?.cancel()
            hideTask = nil
            chromeVisible = false
        } else {
            pokeChrome()
        }
    }

    private func pokeChrome() {
        chromeVisible = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            chromeVisible = false
        }
    }
}

/// UIViewRepresentable 包装 MPlayVideoView：player 就绪（@State 赋值触发刷新）后才 attach，
/// 同一 player 重复 attach 跳过；视图拆解时 detach。
private struct MPlayVideoSurface: UIViewRepresentable {
    let player: MPlayPlayer?

    final class Coordinator {
        var attached: MPlayPlayer?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MPlayVideoView {
        let view = MPlayVideoView()
        view.backgroundColor = .black
        if let player {
            view.attach(player: player)
            context.coordinator.attached = player
        }
        return view
    }

    func updateUIView(_ uiView: MPlayVideoView, context: Context) {
        guard let player else {
            if context.coordinator.attached != nil {
                uiView.detach()
                context.coordinator.attached = nil
            }
            return
        }
        if context.coordinator.attached !== player {
            uiView.attach(player: player)
            context.coordinator.attached = player
        }
    }

    static func dismantleUIView(_ uiView: MPlayVideoView, coordinator: Coordinator) {
        uiView.detach()
        coordinator.attached = nil
    }
}
