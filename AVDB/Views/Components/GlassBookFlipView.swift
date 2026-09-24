//
//  GlassBookFlipView.swift
//  AVDB
//
//  摊开的立体精装书：硬壳、书脊、页边厚度，左右页同时展示。
//

import SwiftUI
import UIKit

struct MovieBookFlipView: View {
    let movies: [Movie]
    var onNearEnd: (() -> Void)? = nil

    @State private var spread = 0
    @State private var dragX: CGFloat = 0
    @State private var isSettling = false
    @State private var pageWidth: CGFloat = 150

    private let coverInset: CGFloat = 11
    private let restFold: Double = 11

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
            VStack(spacing: 8) {
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
        let spine: CGFloat = 16
        let fallbackW = UIScreen.main.bounds.width
        let width = max(size.width, fallbackW) - 20
        let height = size.height > 8 ? size.height : 420
        var pageW = (width - spine - coverInset * 2) / 2
        var pageH = pageW / 0.72
        let maxH = max(height - 86, 210)
        if pageH > maxH {
            pageH = maxH
            pageW = pageH * 0.72
        }
        return (max(pageW, 96), max(pageH, 140), spine)
    }

    private func openBook(pageW: CGFloat, pageH: CGFloat, spine: CGFloat) -> some View {
        let bookW = pageW * 2 + spine
        let coverW = bookW + coverInset * 2
        let coverH = pageH + coverInset * 2
        let goingNext = progress < 0
        let leafAngle = Double(progress) * 180

        return ZStack {
            tableShadow(width: coverW)
                .offset(y: coverH * 0.46)

            hardcover(width: coverW, height: coverH, spine: spine)

            pageStack(height: pageH, onLeft: true)
                .offset(x: -(pageW + spine / 2) + 3)
            pageStack(height: pageH, onLeft: false)
                .offset(x: pageW + spine / 2 - 3)

            HStack(spacing: 0) {
                spreadPage(
                    goingNext || abs(progress) < 0.002 ? leftMovie : prevLeft,
                    size: CGSize(width: pageW, height: pageH),
                    side: .left,
                    fold: restFold
                )
                spineBlock(height: pageH, width: spine)
                spreadPage(
                    goingNext ? (nextRight ?? rightMovie) : rightMovie,
                    size: CGSize(width: pageW, height: pageH),
                    side: .right,
                    fold: restFold
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
                        angle: leafAngle
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
                        angle: leafAngle
                    )
                }
            }
        }
        .rotation3DEffect(.degrees(14), axis: (x: 1, y: 0, z: 0), perspective: 0.72)
        .frame(width: coverW, height: coverH + 18)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .highPriorityGesture(flipGesture)
    }

    private func tableShadow(width: CGFloat) -> some View {
        Ellipse()
            .fill(Color.black.opacity(0.28))
            .frame(width: width * 0.86, height: 22)
            .blur(radius: 10)
            .allowsHitTesting(false)
    }

    private func hardcover(width: CGFloat, height: CGFloat, spine: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.20, blue: 0.24),
                            Color(red: 0.28, green: 0.31, blue: 0.36),
                            Color(red: 0.16, green: 0.17, blue: 0.21)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    if #available(iOS 26.0, *) {
                        Color.clear.glassEffect(.regular, in: shape)
                            .opacity(0.55)
                    } else {
                        shape.fill(.ultraThinMaterial.opacity(0.35))
                    }
                }
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.42),
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6)
                        .padding(5)
                }
                .overlay {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.10),
                                    Color.black.opacity(0.35),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: spine + 6)
                }

            // 封面厚度：底部和外侧一圈暗边
            shape
                .stroke(Color.black.opacity(0.45), lineWidth: 3)
                .offset(y: 3)
                .opacity(0.55)
                .blendMode(.multiply)
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.38), radius: 22, y: 16)
        .allowsHitTesting(false)
    }

    private func pageStack(height: CGFloat, onLeft: Bool) -> some View {
        HStack(spacing: 0.8) {
            ForEach(0..<7, id: \.self) { i in
                let shade = 0.96 - Double(i) * 0.05
                Capsule()
                    .fill(Color(white: shade))
                    .frame(width: 1.4, height: height - CGFloat(i) * 3)
                    .overlay {
                        Capsule().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.3)
                    }
            }
        }
        .rotation3DEffect(
            .degrees(onLeft ? 18 : -18),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.6
        )
        .allowsHitTesting(false)
    }

    private func spineBlock(height: CGFloat, width: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.13, blue: 0.16),
                    Color(red: 0.38, green: 0.40, blue: 0.45),
                    Color(red: 0.14, green: 0.15, blue: 0.18)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            LinearGradient(
                colors: [
                    Color.black.opacity(0.35),
                    Color.clear,
                    Color.black.opacity(0.28)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            // 书脊高光
            Capsule()
                .fill(Color.white.opacity(0.28))
                .frame(width: 2.2)
                .blur(radius: 0.4)
            VStack(spacing: 7) {
                ForEach(0..<5, id: \.self) { _ in
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: width * 0.55, height: 2)
                }
            }
            .padding(.vertical, 16)
        }
        .frame(width: width, height: height)
        .overlay {
            Rectangle()
                .strokeBorder(Color.black.opacity(0.35), lineWidth: 0.6)
        }
        .allowsHitTesting(false)
    }

    private enum PageSide { case left, right }

    private func spreadPage(_ movie: Movie?, size: CGSize, side: PageSide, fold: Double) -> some View {
        let shape = pageShape(side)
        let yAngle: Double = side == .left ? fold : -fold
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
            shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
        }
        .overlay(alignment: side == .left ? .trailing : .leading) {
            LinearGradient(
                colors: [Color.black.opacity(0.38), Color.black.opacity(0.08), Color.clear],
                startPoint: side == .left ? .trailing : .leading,
                endPoint: side == .left ? .leading : .trailing
            )
            .frame(width: size.width * 0.22)
            .allowsHitTesting(false)
        }
        .rotation3DEffect(
            .degrees(yAngle),
            axis: (x: 0, y: 1, z: 0),
            anchor: side == .left ? .trailing : .leading,
            perspective: 0.65
        )
        .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
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
        let rest = side == .right ? -restFold : restFold
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
                    Color.black.opacity(0.04 + abs(angle / 180) * 0.28),
                    Color.clear,
                    Color.white.opacity(0.16)
                ],
                startPoint: side == .right ? .leading : .trailing,
                endPoint: side == .right ? .trailing : .leading
            )
            .allowsHitTesting(false)
        }
        .rotation3DEffect(
            .degrees(rest + angle),
            axis: (x: 0, y: 1, z: 0),
            anchor: side == .right ? .leading : .trailing,
            perspective: 0.58
        )
        .shadow(
            color: .black.opacity(0.22 + abs(angle / 180) * 0.28),
            radius: 12 + abs(angle / 16),
            x: side == .right ? 10 : -10,
            y: 8
        )
        .allowsHitTesting(false)
    }

    private func pageShape(_ side: PageSide) -> UnevenRoundedRectangle {
        if side == .left {
            return UnevenRoundedRectangle(
                topLeadingRadius: 3,
                bottomLeadingRadius: 3,
                bottomTrailingRadius: 1,
                topTrailingRadius: 1,
                style: .continuous
            )
        }
        return UnevenRoundedRectangle(
            topLeadingRadius: 1,
            bottomLeadingRadius: 1,
            bottomTrailingRadius: 3,
            topTrailingRadius: 3,
            style: .continuous
        )
    }

    private func cover(_ movie: Movie, size: CGSize, side: PageSide) -> some View {
        ZStack {
            Color(white: 0.93)
            JavDBImage(url: movie.thumbURL ?? movie.coverURL)
                .frame(width: size.width, height: size.height)
                .clipped()

            LinearGradient(
                colors: [
                    Color.white.opacity(0.16),
                    Color.clear,
                    Color.black.opacity(0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
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

    private func paperBlank(size: CGSize, side: PageSide) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.95, blue: 0.90),
                    Color(red: 0.93, green: 0.90, blue: 0.84)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            ForEach(0..<8, id: \.self) { i in
                Rectangle()
                    .fill(Color.black.opacity(0.04))
                    .frame(height: 1)
                    .padding(.horizontal, 14)
                    .offset(y: CGFloat(i - 4) * 16)
            }
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
