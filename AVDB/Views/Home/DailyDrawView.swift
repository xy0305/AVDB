//
//  DailyDrawView.swift
//  AVDB
//
//  每日抽签：点击后卡牌沿中轴旋转，停在随机番号封面上。
//

import SwiftUI

struct DailyDrawView: View {
    @StateObject private var vm = DailyDrawViewModel()
    @State private var rotation = 0.0
    @State private var isSpinning = false
    @State private var selectedMovie: Movie?
    @State private var showResult = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.11, blue: 0.16),
                    Color(red: 0.18, green: 0.13, blue: 0.22)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                VStack(spacing: 6) {
                    Text("每日抽签")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                    Text(vm.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }

                drawCard
                    .rotation3DEffect(
                        .degrees(rotation),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.55
                    )

                if let movie = selectedMovie, showResult {
                    VStack(spacing: 4) {
                        Text(movie.displayNumber)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                        Text(movie.displayTitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 28)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))

                    NavigationLink {
                        MovieDetailView(movieID: movie.id)
                    } label: {
                        Text("查看详情")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.orange, in: Capsule())
                    }
                    .padding(.horizontal, 48)
                }

                Spacer(minLength: 0)

                Button {
                    Task { await draw() }
                } label: {
                    Label(isSpinning ? "抽签中" : "开始抽签", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 220, height: 54)
                        .background(
                            isSpinning ? Color.white.opacity(0.18) : Color.orange,
                            in: Capsule()
                        )
                }
                .disabled(isSpinning || vm.pool.isEmpty)
                .padding(.bottom, 24)
            }
            .padding(.top, 24)
        }
        .navigationTitle("每日抽签")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.loadPool() }
    }

    private var drawCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.86, green: 0.28, blue: 0.34), Color(red: 0.45, green: 0.12, blue: 0.28)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            VStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .semibold))
                Text("AVDB")
                    .font(.system(size: 28, weight: .black))
            }
            .foregroundStyle(.white.opacity(0.9))
            .opacity(cardFaceOpacity(front: false))

            if let movie = selectedMovie {
                JavDBImage(url: movie.coverURL ?? movie.thumbURL, maxPixelSize: 900)
                    .overlay(alignment: .bottomLeading) {
                        Text(movie.displayNumber)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(10)
                    }
                    .opacity(cardFaceOpacity(front: true))
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
        }
        .frame(width: 230, height: 322)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
    }

    private func cardFaceOpacity(front: Bool) -> Double {
        let normalized = rotation.truncatingRemainder(dividingBy: 360)
        let degrees = normalized < 0 ? normalized + 360 : normalized
        let showingFront = degrees > 90 && degrees < 270
        return (front == showingFront) ? 1 : 0
    }

    private func draw() async {
        guard !isSpinning, let movie = vm.randomMovie() else { return }
        isSpinning = true
        showResult = false
        GlassHaptic.tap()
        let spins = Double(Int.random(in: 4...6))
        withAnimation(.easeInOut(duration: 1.8)) {
            rotation += 360 * spins + 180
        }
        try? await Task.sleep(nanoseconds: 950_000_000)
        selectedMovie = movie
        try? await Task.sleep(nanoseconds: 900_000_000)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            showResult = true
        }
        GlassHaptic.success()
        isSpinning = false
    }
}

@MainActor
final class DailyDrawViewModel: ObservableObject {
    @Published var pool: [Movie] = []
    @Published var statusText = "准备今日签池"

    func loadPool() async {
        guard pool.isEmpty else { return }
        statusText = "正在准备签池"
        let sdk = JavDBSDK.shared
        let page = dailyPage()
        let latest = (try? await sdk.latestMovies(page: page, limit: 24, type: "all", sortBy: "update")) ?? []
        let next = (try? await sdk.latestMovies(page: page + 1, limit: 24, type: "all", sortBy: "update")) ?? []
        var seen = Set<String>()
        pool = (latest + next).filter { seen.insert($0.id).inserted && ($0.coverURL ?? $0.thumbURL) != nil }
        statusText = pool.isEmpty ? "签池加载失败，请稍后重试" : "今日 \(pool.count) 张卡牌"
    }

    func randomMovie() -> Movie? {
        pool.randomElement()
    }

    private func dailyPage() -> Int {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return (day % 12) + 1
    }
}
