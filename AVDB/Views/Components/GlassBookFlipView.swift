//
//  GlassBookFlipView.swift
//  AVDB
//
//  立体书页翻页：封面沿书脊 3D 翻转，液态玻璃书壳。
//

import SwiftUI
import UIKit

struct MovieBookFlipView: View {
    let movies: [Movie]
    var onSelect: ((Movie) -> Void)? = nil
    var onNearEnd: (() -> Void)? = nil

    @State private var index = 0
    @State private var dragX: CGFloat = 0
    @State private var pageWidth: CGFloat = 280
    @State private var isSettling = false

    private var safeIndex: Int {
        guard !movies.isEmpty else { return 0 }
        return min(max(0, index), movies.count - 1)
    }

    private var current: Movie? {
        movies.indices.contains(safeIndex) ? movies[safeIndex] : nil
    }

    private var peekNext: Movie? {
        movies.indices.contains(safeIndex + 1) ? movies[safeIndex + 1] : nil
    }

    private var peekPrev: Movie? {
        movies.indices.contains(safeIndex - 1) ? movies[safeIndex - 1] : nil
    }

    /// -1…1，负值翻下一页。
    private var flip: CGFloat {
        (dragX / max(pageWidth, 1)).clamped(to: -1 ... 1)
    }

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let height = geo.size.height
                let width = min(geo.size.width * 0.82, height * 0.70)
                bookStage(pageSize: CGSize(width: width, height: width / 0.72))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { pageWidth = width }
                    .onChange(of: width) { _, w in pageWidth = w }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            caption
            pageIndicator
        }
        .padding(.horizontal, 10)
        .onAppear {
            if movies.count < 8 { onNearEnd?() }
        }
        .onChange(of: movies.first?.id) { _, _ in
            index = 0
            dragX = 0
        }
    }

    private func bookStage(pageSize: CGSize) -> some View {
        ZStack {
            bookBlock(pageSize: pageSize)

            if let under = revealedPage {
                bookPage(under, size: pageSize, shine: 0.08)
                    .scaleEffect(0.985)
                    .offset(x: 5)
                    .zIndex(1)
            }

            if let movie = current {
                flippingPage(movie, size: pageSize)
                    .zIndex(abs(flip) > 0.5 ? 0.5 : 3)
            }
        }
        .frame(width: pageSize.width, height: pageSize.height)
        .rotation3DEffect(.degrees(7), axis: (x: 1, y: 0, z: 0), perspective: 0.85)
        .contentShape(Rectangle())
        .highPriorityGesture(flipGesture)
        .onTapGesture {
            guard !isSettling, abs(dragX) < 8, let movie = current else { return }
            onSelect?(movie)
        }
    }

    private var revealedPage: Movie? {
        if flip < -0.02 { return peekNext }
        if flip > 0.02 { return peekPrev }
        return peekNext
    }

    private func bookBlock(pageSize: CGSize) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.clear)
                .frame(width: pageSize.width + 30, height: pageSize.height + 30)
                .liquidGlassRect(cornerRadius: 22, interactive: false)
                .offset(x: -8)
                .allowsHitTesting(false)

            HStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.58 - Double(i) * 0.1),
                                    Color.white.opacity(0.10)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 2.5, height: pageSize.height * 0.90)
                        .offset(x: CGFloat(i) * 2.6 - 12)
                }
            }
            .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.30), radius: 26, y: 18)
        .zIndex(0)
    }

    private func flippingPage(_ movie: Movie, size: CGSize) -> some View {
        let goingNext = flip <= 0
        let angle = Double(abs(flip)) * 180
        let anchor: UnitPoint = goingNext ? .leading : .trailing
        let ySign: Double = goingNext ? -1 : 1
        let showFront = angle < 90

        return ZStack {
            bookPage(movie, size: size, shine: Double(-flip) * 0.28)
                .opacity(showFront ? 1 : 0)
            glassVerso(movie, size: size)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(showFront ? 0 : 1)
        }
        .rotation3DEffect(
            .degrees(ySign * angle),
            axis: (x: 0, y: 1, z: 0),
            anchor: anchor,
            perspective: 0.72
        )
        .shadow(
            color: .black.opacity(0.16 + abs(Double(flip)) * 0.28),
            radius: 16 + abs(flip) * 12,
            x: goingNext ? 12 : -12,
            y: 8
        )
    }

    private func bookPage(_ movie: Movie, size: CGSize, shine: Double) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 4,
            bottomLeadingRadius: 4,
            bottomTrailingRadius: 16,
            topTrailingRadius: 16,
            style: .continuous
        )
        return ZStack {
            JavDBImage(url: movie.coverURL ?? movie.thumbURL)
                .frame(width: size.width, height: size.height)
                .clipped()

            LinearGradient(
                colors: [
                    Color.white.opacity(0.46 + max(0, shine)),
                    Color.white.opacity(0.05),
                    Color.cyan.opacity(0.12),
                    Color.clear
                ],
                startPoint: UnitPoint(x: 0.02 + shine, y: 0),
                endPoint: UnitPoint(x: 0.85, y: 1)
            )
            .blendMode(.softLight)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.32),
                    Color.clear,
                    Color.black.opacity(0.10)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            if let badge = movie.playBadge {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        badge.contains("中字")
                            ? JAVDBPalette.cnsubOrange
                            : JAVDBPalette.playRed,
                        in: Capsule()
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(10)
            }
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.70),
                        Color.white.opacity(0.14),
                        Color.white.opacity(0.38)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.1
            )
        }
        .overlay {
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular, in: shape)
                    .opacity(0.16)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func glassVerso(_ movie: Movie, size: CGSize) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 16,
            bottomLeadingRadius: 16,
            bottomTrailingRadius: 4,
            topTrailingRadius: 4,
            style: .continuous
        )
        return VStack(spacing: 8) {
            Text(movie.displayNumber)
                .font(.title3.weight(.bold))
            Text(movie.displayTitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 16)
        }
        .frame(width: size.width, height: size.height)
        .background {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.28),
                    Color.cyan.opacity(0.10),
                    Color.blue.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(shape)
        .liquidGlassRect(cornerRadius: 16, interactive: false)
    }

    private var caption: some View {
        VStack(spacing: 4) {
            if let movie = current {
                Text(movie.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    Text(movie.displayNumber)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                    if let date = movie.releaseDate, !date.isEmpty {
                        Text(date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .liquidGlassRect(cornerRadius: 16, interactive: false)
    }

    private var pageIndicator: some View {
        Text(movies.isEmpty ? "0 / 0" : "\(safeIndex + 1) / \(movies.count)")
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .liquidGlass(interactive: false)
    }

    private var flipGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                guard !isSettling else { return }
                // 左侧边缘留给系统侧滑返回。
                if value.startLocation.x < 22 { return }
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > abs(dy) * 0.6 else { return }
                if dx < 0, peekNext == nil { dragX = dx * 0.16; return }
                if dx > 0, peekPrev == nil { dragX = dx * 0.16; return }
                dragX = dx
            }
            .onEnded { value in
                guard !isSettling else { return }
                settle(translation: value.translation.width, velocity: value.predictedEndTranslation.width)
            }
    }

    private func settle(translation: CGFloat, velocity: CGFloat) {
        let predicted = translation + velocity * 0.35
        let goNext = (flip < -0.22 || predicted < -90) && peekNext != nil
        let goPrev = (flip > 0.22 || predicted > 90) && peekPrev != nil
        let target: CGFloat
        if goNext { target = -pageWidth }
        else if goPrev { target = pageWidth }
        else { target = 0 }

        isSettling = true
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            dragX = target
        } completion: {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                if goNext { index = min(index + 1, movies.count - 1) }
                if goPrev { index = max(index - 1, 0) }
                dragX = 0
                isSettling = false
            }
            if goNext || goPrev {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            if index >= movies.count - 4 {
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
