//
//  GlassBookFlipView.swift
//  AVDB
//
//  Cover Flow：中间封面正向最大，两侧立体侧转。
//  用连续 progress 跟手，停稳吸附，避免换页跳变。
//

import SwiftUI
import UIKit

struct MovieBookFlipView: View {
    let movies: [Movie]
    var onNearEnd: (() -> Void)? = nil

    @State private var progress: CGFloat = 0
    @State private var gestureStart: CGFloat?
    @State private var lastHapticIndex: Int = 0

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var cardW: CGFloat { sizeClass == .regular ? 248 : 176 }
    private var cardH: CGFloat { cardW / 0.72 }
    private var spacing: CGFloat { cardW * 0.52 }

    private var maxIndex: CGFloat {
        CGFloat(max(movies.count - 1, 0))
    }

    private var currentIndex: Int {
        guard !movies.isEmpty else { return 0 }
        return min(max(0, Int(progress.rounded())), movies.count - 1)
    }

    private var current: Movie? {
        movies.indices.contains(currentIndex) ? movies[currentIndex] : nil
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                ambientGlow

                ForEach(visibleMovies) { movie in
                    if let i = movies.firstIndex(where: { $0.id == movie.id }) {
                        coverCard(movie, at: i)
                            .zIndex(zIndex(for: i))
                    }
                }
            }
            .frame(height: cardH + 48)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(drag)

            caption
            indicator
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            lastHapticIndex = currentIndex
            if movies.count < 8 { onNearEnd?() }
        }
        .onChange(of: movies.first?.id) { _, _ in
            progress = 0
            gestureStart = nil
        }
        .onChange(of: currentIndex) { _, idx in
            if idx >= movies.count - 4 { onNearEnd?() }
        }
    }

    private var visibleMovies: [Movie] {
        movies.enumerated().compactMap { i, movie in
            abs(CGFloat(i) - progress) <= 3.6 ? movie : nil
        }
    }

    private func slot(for i: Int) -> CGFloat {
        CGFloat(i) - progress
    }

    private func zIndex(for i: Int) -> Double {
        20 - abs(slot(for: i))
    }

    private var ambientGlow: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.22),
                        Color.cyan.opacity(0.08),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 8,
                    endRadius: cardW * 1.15
                )
            )
            .frame(width: cardW * 1.8, height: 36)
            .offset(y: cardH * 0.48)
            .blur(radius: 12)
            .allowsHitTesting(false)
    }

    private func coverCard(_ movie: Movie, at i: Int) -> some View {
        let x = slot(for: i)
        let absX = abs(x)
        let turn = Double(x.clamped(to: -2.4 ... 2.4))
        let angle = -turn * 58
        let scale = 1 - min(absX, 2.2) * 0.11
        let opacity = max(0.18, 1 - absX * 0.18)
        let lift = max(0, 12 - absX * 16)

        return NavigationLink {
            MovieDetailView(movieID: movie.id)
        } label: {
            poster(movie, tilt: x)
        }
        .buttonStyle(.plain)
        .frame(width: cardW, height: cardH)
        .scaleEffect(scale)
        .rotation3DEffect(
            .degrees(angle),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.62
        )
        .offset(x: x * spacing, y: -lift)
        .opacity(opacity)
        .shadow(
            color: .black.opacity(0.10 + max(0, 0.26 - absX * 0.16)),
            radius: 8 + max(0, 16 - absX * 8),
            y: 6 + max(0, 8 - absX * 4)
        )
        .allowsHitTesting(absX < 0.62)
    }

    private func poster(_ movie: Movie, tilt: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let facing = tilt.clamped(to: -1 ... 1)
        return ZStack {
            Color(white: 0.10)

            JavDBImage(url: movie.thumbURL ?? movie.coverURL)
                .frame(width: cardW, height: cardH)
                .clipped()

            // 玻璃釉：随侧转把高光推到朝向镜头的那条棱
            LinearGradient(
                colors: [
                    Color.white.opacity(0.28 - abs(facing) * 0.08),
                    Color.white.opacity(0.04),
                    Color.clear,
                    Color.cyan.opacity(0.08)
                ],
                startPoint: UnitPoint(x: 0.12 - facing * 0.35, y: 0),
                endPoint: UnitPoint(x: 0.88 - facing * 0.25, y: 1)
            )
            .blendMode(.softLight)
            .allowsHitTesting(false)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.22 * abs(facing)),
                    Color.clear,
                    Color.black.opacity(0.10)
                ],
                startPoint: facing >= 0 ? .leading : .trailing,
                endPoint: facing >= 0 ? .trailing : .leading
            )
            .allowsHitTesting(false)

            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular, in: shape)
                    .opacity(0.16 + (1 - min(abs(tilt), 1)) * 0.10)
                    .allowsHitTesting(false)
            }

            if let badge = movie.playBadge {
                GlassChip(
                    text: badge,
                    tint: badge.contains("中字") ? JAVDBPalette.cnsubOrange : JAVDBPalette.playRed
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(8)
                .allowsHitTesting(false)
            }
        }
        .clipShape(shape)
        .overlay { GlassRim(shape: shape, lineWidth: 1.15) }
        .contentShape(shape)
    }

    private var caption: some View {
        VStack(spacing: 4) {
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
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .glassSurface(
            in: RoundedRectangle(cornerRadius: 16, style: .continuous),
            tint: .white,
            tintStrength: 0.06,
            elevation: 0.8
        )
        .padding(.horizontal, 28)
        .animation(.easeOut(duration: 0.16), value: current?.id)
    }

    private var indicator: some View {
        Text(movies.isEmpty ? "0 / 0" : "\(currentIndex + 1) / \(movies.count)")
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .liquidGlass(interactive: false)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { value in
                if value.startLocation.x < 16 { return }
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > abs(dy) * 0.28 else { return }
                if gestureStart == nil { gestureStart = progress }
                let raw = (gestureStart ?? progress) - dx / max(spacing, 1)
                progress = rubberBand(raw)
                hapticIfNeeded()
            }
            .onEnded { value in
                let start = gestureStart ?? progress
                gestureStart = nil
                let predicted = value.translation.width + value.predictedEndTranslation.width * 0.38
                let raw = start - predicted / max(spacing, 1)
                let target = rubberBand(raw).rounded().clamped(to: 0 ... maxIndex)
                withAnimation(.interpolatingSpring(stiffness: 180, damping: 24)) {
                    progress = target
                }
                if Int(target) != lastHapticIndex {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    lastHapticIndex = Int(target)
                }
            }
    }

    private func rubberBand(_ raw: CGFloat) -> CGFloat {
        if movies.isEmpty { return 0 }
        if raw < 0 { return raw * 0.18 }
        if raw > maxIndex { return maxIndex + (raw - maxIndex) * 0.18 }
        return raw
    }

    private func hapticIfNeeded() {
        let idx = currentIndex
        if idx != lastHapticIndex {
            UISelectionFeedbackGenerator().selectionChanged()
            lastHapticIndex = idx
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
