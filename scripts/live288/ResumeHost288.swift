// Build 288 resume-pill screenshots. AFTER = production DetailPlayPill inside the same ViewThatFits row
// (pill + 4×44 pt icon group, 18 pt side padding) as MovieDetailView.portraitControls. BEFORE = verbatim copy of
// the build-287 play label (full "续播 02:25 · 115" title, clock icon, padding 16, maxWidth ∞) for comparison.
import SwiftUI

@main
struct ResumeHost288: App { var body: some Scene { WindowGroup { ResumeScreen288() } } }

struct OldPill287: View {
    var title: String; var resume: Bool
    var body: some View {
        Label(title, systemImage: resume ? "clock.arrow.circlepath" : "play.fill")
            .font(.headline).foregroundStyle(.white).shadow(color: .black.opacity(0.65), radius: 2, y: 1)
            .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 48)
            .background(.clear, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.72), lineWidth: 1.5))
    }
}

struct Icons288: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(["arrow.down.circle", "rectangle.stack.badge.plus", "heart", "checkmark.rectangle"], id: \.self) {
                Image(systemName: $0).font(.system(size: 22)).frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .overlay(Capsule().stroke(.white.opacity(0.72), lineWidth: 1.5))
    }
}

struct Row288<P: View>: View {
    @ViewBuilder var pill: () -> P
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { pill(); Icons288() }
            VStack(spacing: 12) { pill(); Icons288().frame(maxWidth: .infinity, alignment: .trailing) }
        }
    }
}

struct AIChip288: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").font(.caption.bold())
            Text("AI 增强 · 已就绪").font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 5)
        .overlay(Capsule().stroke(.white.opacity(0.6), lineWidth: 1))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ResumeScreen288: View {
    private let args = ProcessInfo.processInfo.arguments
    private var scene: String { args.firstIndex(of: "--scene").map { args[$0 + 1] } ?? "after" }
    private func label(_ s: String) -> some View { Text(s).font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.7)).frame(maxWidth: .infinity, alignment: .leading) }

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(red: 0.25, green: 0.18, blue: 0.2), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text("JUR-853").font(.largeTitle.bold()).foregroundStyle(.white)
                Text("2026-08-01 · 120 分钟 · 4K").font(.subheadline).foregroundStyle(.white.opacity(0.8))
                AIChip288()
                switch scene {
                case "before":
                    label("BEFORE (287) 续播 02:25 · 115")
                    Row288 { OldPill287(title: "续播 02:25 · 115", resume: true) }
                    label("BEFORE (287) 续播 1:58:30 · MissAV")
                    Row288 { OldPill287(title: "续播 1:58:30 · MissAV", resume: true) }
                case "widths":
                    ForEach([339.0, 354.0, 366.0], id: \.self) { w in
                        label("AFTER 续播 1:58:30 · 行宽 \(Int(w)) pt（屏宽 \(Int(w + 36))）")
                        Row288 { DetailPlayPill(title: "续播 1:58:30", progress: 0.82).accessibilityIdentifier("pill-\(Int(w))") }
                            .frame(width: w)
                    }
                    label("AFTER 播放 · 行宽 339 pt")
                    Row288 { DetailPlayPill(title: "播放", progress: nil) }.frame(width: 339)
                default:
                    label("AFTER (288) 续播 02:25（长按：从头播放）")
                    Row288 {
                        Button {} label: { DetailPlayPill(title: "续播 02:25", progress: 0.12) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {} label: { Label("续播 02:25 · 115", systemImage: "clock.arrow.circlepath") }
                                Button {} label: { Label("从头播放", systemImage: "backward.end") }
                                Button {} label: { Label("播放 115 原画", systemImage: "play.fill") }
                            }
                            .accessibilityIdentifier("portrait-hero-play")
                    }
                    label("AFTER (288) 续播 1:58:30")
                    Row288 { DetailPlayPill(title: "续播 1:58:30", progress: 0.82) }
                    label("AFTER (288) 无历史")
                    Row288 { DetailPlayPill(title: "播放", progress: nil) }
                }
                Text("剧情简介……").font(.subheadline).foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 18).padding(.bottom, 40)
        }
        .preferredColorScheme(.dark)
    }
}
