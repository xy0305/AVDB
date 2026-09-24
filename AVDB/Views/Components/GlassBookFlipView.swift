//
//  GlassBookFlipView.swift
//  AVDB
//
//  摊开的立体书：左右两页同时展示，沿书脊翻页。
//

import SwiftUI
import UIKit

struct MovieBookFlipView: View {
    let movies: [Movie]
    var onNearEnd: (() -> Void)? = nil

    @State private var spread = 0
    @State private var dragX: CGFloat = 0
    @State private var isSettling = false
    @State private var pageWidth: CGFloat = 160

    private var spreadCount: Int {
        max(1, Int(ceil(Double(movies.count) / 2.0)))
    }

    private var safeSpread: Int {
        min(max(0, spread), max(0, spreadCount - 1))
    }

    private func movie(at index: Int) -> Movie? {
        movies.indices.contains(index) ? movies[index] : nil
    }

    private var leftMovie: Movie? { movie(at: safeSpread * 2) }
    private var rightMovie: Movie? { movie(at: safeSpread * 2 + 1) }
    private var nextLeft: Movie? { movie(at: (safeSpread + 1) * 2) }
    private var nextRight: Movie? { movie(at: (safeSpread + 1) * 2 + 1) }
    private var prevLeft: Movie? { movie(at: (safeSpread - 1) * 2) }
    private var prevRight: Movie? { movie(at: (safeSpread - 1) * 2 + 1) }

    private var canGoNext: Bool { safeSpread + 1 < spreadCount }
    private var canGoPrev: Bool { safeSpread > 0 }

    /// -1…1，负值翻下一跨页。
    private var progress: CGFloat {
        let raw = dragX / max(pageWidth, 1)
        if raw < 0, !canGoNext { return raw * 0.16 }
        if raw > 0, !canGoPrev { return raw * 0.16 }
        return raw.clamped(to: -1 ... 1)
    }

    var body: some View {
        GeometryReader { geo in
            let metrics = bookMetrics(in: geo.size)
            VStack(spacing: 10) {
                openBook(pageW: metrics.pageW, pageH: metrics.pageH, spine: metrics.spine)
                captions(pageW: metrics.pageW, spine: metrics.spine)
                indicator
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear { pageWidth = metrics.pageW }
            .onChange(of: metrics.pageW) { _, w in pageWidth = w }
        }
        .onAppear {
            if movies.count < 8 { onNearEnd?() }
        }
        .onChange(of: movies.first?.id) { _, _ in
            spread = 0
            dragX = 0
        }
    }

    private func bookMetrics(in size: CGSize) -> (pageW: CGFloat, pageH: CGFloat, spine: CGFloat) {
        let spine: CGFloat = 10
        let fallbackW = UIScreen.main.bounds.width
        let width = max(size.width, fallbackW) - 16
        let height = size.height > 8 ? size.height : 420
        var pageW = (width - spine) / 2
        var pageH = pageW / 0.72
        let maxH = max(height - 78, 220)
        if pageH > maxH {
            pageH = maxH
            pageW = pageH * 0.72
        }
        return (pageW, pageH, spine)
    }

    private func openBook(pageW: CGFloat, pageH: CGFloat, spine: CGFloat) -> some View {
        let bookW = pageW * 2 + spine
        let goingNext = progress < 0
        let angle = Double(progress) * 180

        return ZStack {
            bookBoard(width: bookW + 18, height: pageH + 18)

            HStack(spacing: 0) {
                spreadPage(
                    goingNext || progress == 0 ? leftMovie : prevLeft,
                    size: CGSize(width: pageW, height: pageH),
                    side: .left
                )
                spineView(height: pageH, width: spine)
                spreadPage(
                    goingNext ? (nextRight ?? rightMovie) : rightMovie,
                    size: CGSize(width: pageW, height: pageH),
                    side: .right
                )
            }
            .frame(width: bookW, height: pageH)
            .overlay(alignment: .trailing) {
                if progress < -0.002 {
                    flippingLeaf(
                        front: rightMovie,
                        back: nextLeft,
                        size: CGSize(width: pageW, height: pageH),
                        side: .right,
                        angle: angle
                    )
                }
            }
            .overlay(alignment: .leading) {
                if progress > 0.002 {
                    flippingLeaf(
                        front: leftMovie,
                        back: prevRight,
                        size: CGSize(width: pageW, height: pageH),
                        side: .left,
                        angle: angle
                    )
                }
            }
            .rotation3DEffect(.degrees(7), axis: (x: 1, y: 0, z: 0), perspective: 0.9)
        }
        .frame(width: bookW + 18, height: pageH + 22)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .highPriorityGesture(flipGesture)
    }

    private func bookBoard(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.55),
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.28)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
            .allowsHitTesting(false)
    }

    private func spineView(height: CGFloat, width: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.35),
                    Color.white.opacity(0.45),
                    Color.black.opacity(0.22)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color.clear,
                    Color.black.opacity(0.12)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }

    private enum PageSide { case left, right }

    private func spreadPage(_ movie: Movie?, size: CGSize, side: PageSide) -> some View {
        let shape = pageShape(side)
        return Group {
            if let movie {
                NavigationLink {
                    MovieDetailView(movieID: movie.id)
                } label: {
                    cover(movie, size: size, side: side)
                }
                .buttonStyle(.plain)
            } else {
                paperBlank(size: size, side: side)
            }
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
    }

    private func flippingLeaf(
        front: Movie?,
        back: Movie?,
        size: CGSize,
        side: PageSide,
        angle: Double
    ) -> some View {
        let showFront = abs(angle) < 90
        let shape = pageShape(side)
        return ZStack {
            Group {
                if let front {
                    cover(front, size: size, side: side)
                } else {
                    paperBlank(size: size, side: side)
                }
            }
            .opacity(showFront ? 1 : 0)

            Group {
                if let back {
                    cover(back, size: size, side: side == .left ? .right : .left)
                } else {
                    paperBlank(size: size, side: side == .left ? .right : .left)
                }
            }
            .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            .opacity(showFront ? 0 : 1)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.02 + abs(angle / 180) * 0.22),
                    Color.clear,
                    Color.white.opacity(0.12)
                ],
                startPoint: side == .right ? .leading : .trailing,
                endPoint: side == .right ? .trailing : .leading
            )
            .allowsHitTesting(false)
        }
        .rotation3DEffect(
            .degrees(angle),
            axis: (x: 0, y: 1, z: 0),
            anchor: side == .right ? .leading : .trailing,
            perspective: 0.62
        )
        .shadow(
            color: .black.opacity(0.18 + abs(angle / 180) * 0.25),
            radius: 10 + abs(angle / 18),
            x: side == .right ? 8 : -8,
            y: 6
        )
        .allowsHitTesting(false)
    }

    private func pageShape(_ side: PageSide) -> UnevenRoundedRectangle {
        if side == .left {
            return UnevenRoundedRectangle(
                topLeadingRadius: 12,
                bottomLeadingRadius: 12,
                bottomTrailingRadius: 2,
                topTrailingRadius: 2,
                style: .continuous
            )
        }
        return UnevenRoundedRectangle(
            topLeadingRadius: 2,
            bottomLeadingRadius: 2,
            bottomTrailingRadius: 12,
            topTrailingRadius: 12,
            style: .continuous
        )
    }

    private func cover(_ movie: Movie, size: CGSize, side: PageSide) -> some View {
        ZStack {
            JavDBImage(url: movie.coverURL ?? movie.thumbURL)
                .frame(width: size.width, height: size.height)
                .clipped()

            LinearGradient(
                colors: gutterColors(side),
                startPoint: side == .left ? .trailing : .leading,
                endPoint: side == .left ? .leading : .trailing
            )
            .allowsHitTesting(false)

            if let badge = movie.playBadge {
                Text(badge)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        badge.contains("中字")
                            ? JAVDBPalette.cnsubOrange
                            : JAVDBPalette.playRed,
                        in: Capsule()
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
    }

    private func gutterColors(_ side: PageSide) -> [Color] {
        [
            Color.black.opacity(0.28),
            Color.black.opacity(0.06),
            Color.clear
        ]
    }

    private func paperBlank(size: CGSize, side: PageSide) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.72),
                    Color(white: 0.93),
                    Color(white: 0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: gutterColors(side),
                startPoint: side == .left ? .trailing : .leading,
                endPoint: side == .left ? .leading : .trailing
            )
        }
        .frame(width: size.width, height: size.height)
    }

    private func captions(pageW: CGFloat, spine: CGFloat) -> some View {
        HStack(alignment: .top, spacing: spine) {
            caption(for: leftMovie)
                .frame(width: pageW)
            caption(for: rightMovie)
                .frame(width: pageW)
        }
        .padding(.horizontal, 8)
    }

    private func caption(for movie: Movie?) -> some View {
        VStack(spacing: 2) {
            if let movie {
                Text(movie.displayTitle)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(movie.displayNumber)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .liquidGlassRect(cornerRadius: 12, interactive: false)
    }

    private var indicator: some View {
        let start = movies.isEmpty ? 0 : safeSpread * 2 + 1
        let end = min(movies.count, safeSpread * 2 + 2)
        return Text(movies.isEmpty ? "0 / 0" : "\(start)–\(end) / \(movies.count)")
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .liquidGlass(interactive: false)
    }

    private var flipGesture: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .global)
            .onChanged { value in
                guard !isSettling else { return }
                if value.startLocation.x < 18 { return }
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > abs(dy) * 0.55 else { return }
                dragX = dx
            }
            .onEnded { value in
                guard !isSettling else { return }
                settle(translation: value.translation.width, velocity: value.predictedEndTranslation.width)
            }
    }

    private func settle(translation: CGFloat, velocity: CGFloat) {
        let predicted = translation + velocity * 0.28
        let goNext = (progress < -0.18 || predicted < -70) && canGoNext
        let goPrev = (progress > 0.18 || predicted > 70) && canGoPrev
        let target: CGFloat
        if goNext { target = -pageWidth }
        else if goPrev { target = pageWidth }
        else { target = 0 }

        isSettling = true
        withAnimation(.interpolatingSpring(stiffness: 170, damping: 22)) {
            dragX = target
        } completion: {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                if goNext { spread = min(spread + 1, spreadCount - 1) }
                if goPrev { spread = max(spread - 1, 0) }
                dragX = 0
                isSettling = false
            }
            if goNext || goPrev {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            if safeSpread >= spreadCount - 2 {
                onNearEnd?()
            }
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
