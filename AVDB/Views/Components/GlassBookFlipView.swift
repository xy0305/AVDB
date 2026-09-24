//
//  GlassBookFlipView.swift
//  AVDB
//
//  Cover Flow：中间封面正向最大，两侧立体侧转。
//

import SwiftUI
import UIKit

struct MovieBookFlipView: View {
    let movies: [Movie]
    var onNearEnd: (() -> Void)? = nil

    @State private var index = 0
    @State private var dragX: CGFloat = 0
    @State private var isSettling = false

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var cardW: CGFloat { sizeClass == .regular ? 240 : 168 }
    private var cardH: CGFloat { cardW / 0.72 }
    private var spacing: CGFloat { cardW * 0.58 }

    private var safeIndex: Int {
        guard !movies.isEmpty else { return 0 }
        return min(max(0, index), movies.count - 1)
    }

    private var current: Movie? {
        movies.indices.contains(safeIndex) ? movies[safeIndex] : nil
    }

    /// 跟手偏移，单位：张。右滑为正。
    private var dragOffset: CGFloat {
        dragX / max(spacing, 1)
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                ForEach(visibleRange, id: \.self) { i in
                    coverCard(movies[i], at: i)
                        .zIndex(zIndex(for: i))
                }
            }
            .frame(height: cardH + 36)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(drag)

            caption
            indicator
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if movies.count < 8 { onNearEnd?() }
        }
        .onChange(of: movies.first?.id) { _, _ in
            index = 0
            dragX = 0
        }
    }

    private var visibleRange: [Int] {
        let center = safeIndex
        return movies.indices.filter { abs($0 - center) <= 3 }
    }

    private func offset(for i: Int) -> CGFloat {
        CGFloat(i - safeIndex) + dragOffset
    }

    private func zIndex(for i: Int) -> Double {
        10 - abs(offset(for: i))
    }

    private func coverCard(_ movie: Movie, at i: Int) -> some View {
        let x = offset(for: i)
        let absX = abs(x)
        let angle = Double(x.clamped(to: -3 ... 3)) * -52
        let scale = max(0.72, 1 - absX * 0.12)
        let opacity = max(0.28, 1 - absX * 0.22)
        let lift = absX < 0.15 ? 8.0 : 0.0

        return NavigationLink {
            MovieDetailView(movieID: movie.id)
        } label: {
            poster(movie)
        }
        .buttonStyle(.plain)
        .frame(width: cardW, height: cardH)
        .scaleEffect(scale)
        .rotation3DEffect(
            .degrees(angle),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.55
        )
        .offset(x: x * spacing, y: -lift)
        .opacity(opacity)
        .shadow(
            color: .black.opacity(absX < 0.4 ? 0.28 : 0.12),
            radius: absX < 0.4 ? 18 : 8,
            y: absX < 0.4 ? 10 : 4
        )
        .allowsHitTesting(absX < 0.55)
    }

    private func poster(_ movie: Movie) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return ZStack {
            Color(white: 0.12)
            JavDBImage(url: movie.thumbURL ?? movie.coverURL)
                .frame(width: cardW, height: cardH)
                .clipped()

            LinearGradient(
                colors: [
                    Color.white.opacity(0.18),
                    Color.clear,
                    Color.black.opacity(0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)

            if let badge = movie.playBadge {
                Text(badge)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        badge.contains("中字")
                            ? JAVDBPalette.cnsubOrange
                            : JAVDBPalette.playRed,
                        in: Capsule()
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.45),
                        Color.white.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.8
            )
        }
        .contentShape(shape)
    }

    private var caption: some View {
        VStack(spacing: 3) {
            if let movie = current {
                Text(movie.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    Text(movie.displayNumber)
                        .font(.caption.weight(.semibold))
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
        .padding(.horizontal, 20)
        .animation(.easeOut(duration: 0.18), value: current?.id)
    }

    private var indicator: some View {
        Text(movies.isEmpty ? "0 / 0" : "\(safeIndex + 1) / \(movies.count)")
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .liquidGlass(interactive: false)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                guard !isSettling else { return }
                if value.startLocation.x < 16 { return }
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > abs(dy) * 0.4 else { return }
                var next = dx
                if index <= 0, dx > 0 { next = dx * 0.22 }
                if index >= movies.count - 1, dx < 0 { next = dx * 0.22 }
                dragX = next
            }
            .onEnded { value in
                guard !isSettling else { return }
                settle(translation: value.translation.width, predicted: value.predictedEndTranslation.width)
            }
    }

    private func settle(translation: CGFloat, predicted: CGFloat) {
        let projected = (translation + predicted * 0.35) / max(spacing, 1)
        let delta = -Int(projected.rounded())
        let from = index
        let target = min(max(0, from + delta), max(0, movies.count - 1))
        let remain = CGFloat(from - target) * spacing

        isSettling = true
        withAnimation(.interpolatingSpring(stiffness: 210, damping: 26)) {
            dragX = remain
        } completion: {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                index = target
                dragX = 0
                isSettling = false
            }
            if target != from {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            if target >= movies.count - 4 {
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
