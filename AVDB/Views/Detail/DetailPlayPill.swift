// Build 288 — compact detail-page play pill: 「▶ 播放」 or 「▶ 续播 02:25」 (never the source suffix), with an
// optional 2 pt watched-progress underline. Its *ideal* width is small so the portrait row (pill + 4 icons)
// stays on one line on 375 pt phones even for 「续播 1:58:30」; spare width is absorbed by maxWidth.
import SwiftUI

struct DetailPlayPill: View {
    var title: String
    var progress: Double?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "play.fill").font(.system(size: 14, weight: .bold))
            Text(title).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.headline)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.65), radius: 2, y: 1)
        .padding(.horizontal, 12)
        .frame(minWidth: 96, idealWidth: 112, maxWidth: .infinity, minHeight: 48)
        // Build 335: home-style Liquid Glass capsule. Through Build 334 this
        // was intentionally a clear capsule with a white outline; the user
        // asked for the same liquid glass as the home floating chrome.
        // Build 339: the user asked for the glass itself to be more
        // transparent — .clear instead of .regular, so the backdrop colour
        // and image show through instead of the milky .regular sampling.
        .liquidGlass(interactive: true, clear: true)
        .overlay(alignment: .bottom) {
            if let p = progress {
                GeometryReader { g in
                    Capsule().fill(.white.opacity(0.25)).frame(height: 2)
                        .overlay(alignment: .leading) { Capsule().fill(.white.opacity(0.9)).frame(width: max(2, g.size.width * p), height: 2) }
                }
                .frame(height: 2).padding(.horizontal, 22).padding(.bottom, 6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .contentShape(Capsule())
    }
}
