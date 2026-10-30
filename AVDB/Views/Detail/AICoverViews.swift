import SwiftUI
import UIKit

/// Build 285: 「AI 增强」 chrome for the detail hero cover and the fullscreen cover viewer.
/// Standalone (only the enhancer model), so the simulator screenshot host can compile it as is.
enum AICoverStyle {
    static let gradient = tinted(1)
    static func tinted(_ alpha: Double) -> LinearGradient {
        LinearGradient(colors: [Color(red: 0.62, green: 0.45, blue: 1.0).opacity(alpha), Color(red: 0.28, green: 0.78, blue: 1.0).opacity(alpha)],
                       startPoint: .leading, endPoint: .trailing)
    }
}

/// Small 「AI 增强」 badge shown whenever the displayed raster is the AI result.
struct AICoverBadge: View {
    var compact = false
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles").font(.system(size: compact ? 10 : 11, weight: .bold))
            Text("AI 增强").font(.system(size: compact ? 11 : 12, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 8 : 10).padding(.vertical, compact ? 4 : 5)
        .background(AICoverStyle.tinted(0.92), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AI 增强")
        .accessibilityIdentifier("ai-cover-badge")
    }
}

/// Circular determinate progress ring.
struct AICoverProgressRing: View {
    let value: Double
    var size: CGFloat = 16
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 2.2)
            Circle().trim(from: 0, to: max(0.02, value))
                .stroke(AICoverStyle.gradient, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: value)
        }
        .frame(width: size, height: size)
    }
}

/// Hold-to-compare: while pressed, the original raster is shown.
struct AICoverHoldToCompare: ViewModifier {
    @ObservedObject var model: AICoverEnhanceModel
    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if model.isEnhanced && !model.showingOriginal { model.showingOriginal = true; UIImpactFeedbackGenerator(style: .light).impactOccurred() } }
                .onEnded { _ in if model.isEnhanced { model.showingOriginal = false } }
        )
    }
}

/// Top-trailing control on the portrait hero.
struct AICoverHeroControl: View {
    @ObservedObject var model: AICoverEnhanceModel
    let openViewer: () -> Void

    var body: some View {
        Group {
            switch model.phase {
            case .ineligible:
                EmptyView()
            case .idle:
                if model.canEnhance {
                    Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); model.toggle() } label: {
                        capsule { Image(systemName: "sparkles").font(.system(size: 12, weight: .bold)); Text("AI 增强").font(.system(size: 13, weight: .semibold)) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ai-cover-enhance-button")
                }
            case .running(let p):
                Button { model.cancel() } label: {
                    capsule {
                        AICoverProgressRing(value: p)
                        Text(verbatim: "AI 增强中 \(Int((p * 100).rounded()))%").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ai-cover-progress")
                .accessibilityHint("轻点取消")
            case .done:
                HStack(spacing: 6) {
                    Button(action: openViewer) {
                        if model.showingOriginal {
                            capsule { Text("原图").font(.system(size: 12, weight: .semibold)) }
                        } else { AICoverBadge() }
                    }
                    .buttonStyle(.plain)
                    Image(systemName: "rectangle.lefthalf.inset.filled")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.5))
                        .contentShape(Circle())
                        .modifier(AICoverHoldToCompare(model: model))
                        .accessibilityLabel("按住对比原图")
                        .accessibilityIdentifier("ai-cover-compare")
                }
            case .failed(let text):
                Button { model.toggle() } label: {
                    capsule { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)); Text(text).font(.system(size: 12, weight: .medium)).lineLimit(1) }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ai-cover-failed")
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.phase)
    }

    private func capsule<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 6, content: content)
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .background(Color.black.opacity(0.18), in: Capsule())
            .overlay(Capsule().stroke(AICoverStyle.tinted(0.75), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
    }
}

/// Fullscreen cover viewer: pinch / double-tap zoom, 「AI 增强」 action, hold-to-compare.
struct AICoverViewer: View {
    let image: UIImage
    @ObservedObject var model: AICoverEnhanceModel
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: model.display(image))
                .resizable().scaledToFit()
                .scaleEffect(zoom).offset(offset)
                .gesture(MagnificationGesture()
                    .onChanged { zoom = min(6, max(1, lastZoom * $0)) }
                    .onEnded { _ in lastZoom = zoom; if zoom <= 1.01 { withAnimation(.spring()) { offset = .zero; lastOffset = .zero } } })
                .simultaneousGesture(DragGesture()
                    .onChanged { v in guard zoom > 1 else { return }; offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height) }
                    .onEnded { _ in lastOffset = offset })
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        if zoom > 1 { zoom = 1; lastZoom = 1; offset = .zero; lastOffset = .zero } else { zoom = 2.5; lastZoom = 2.5 }
                    }
                }
                .accessibilityIdentifier("ai-cover-viewer-image")
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 38, height: 38).background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain).accessibilityLabel("关闭").accessibilityIdentifier("ai-cover-viewer-close")
                    Spacer()
                    if model.isEnhanced {
                        if model.showingOriginal {
                            Text("原图").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 5).background(.ultraThinMaterial, in: Capsule())
                        } else { AICoverBadge() }
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8)
                Spacer()
                toolbar.padding(.horizontal, 16).padding(.bottom, 14)
            }
        }
        .statusBarHidden()
    }

    private var sizeText: String {
        let n = model.nativeSize
        guard n.width > 0 else { return "" }
        let native = "\(Int(n.width))×\(Int(n.height))"
        if let o = model.outputSize, model.isEnhanced { return "原图 \(native)  →  AI \(Int(o.width))×\(Int(o.height))" }
        return "原图 \(native)"
    }

    @ViewBuilder private var toolbar: some View {
        VStack(spacing: 10) {
            if !sizeText.isEmpty {
                Text(sizeText).font(.system(size: 12, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
                    .accessibilityIdentifier("ai-cover-viewer-size")
            }
            switch model.phase {
            case .done:
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill").font(.system(size: 14, weight: .semibold))
                    Text(model.showingOriginal ? "松开显示 AI 增强" : "按住对比原图").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(AICoverStyle.gradient, lineWidth: 1.2))
                .contentShape(Capsule())
                .modifier(AICoverHoldToCompare(model: model))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("ai-cover-viewer-compare")
            case .running(let p):
                VStack(spacing: 8) {
                    HStack {
                        AICoverProgressRing(value: p, size: 18)
                        Text("AI 增强中…").font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text(verbatim: "\(Int((p * 100).rounded()))%").font(.system(size: 15, weight: .semibold)).monospacedDigit()
                        Button { model.cancel() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 18)) }
                            .buttonStyle(.plain).accessibilityLabel("取消")
                    }
                    ProgressView(value: p).tint(Color(red: 0.45, green: 0.62, blue: 1.0))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("ai-cover-viewer-progress")
            case .idle, .failed:
                if model.canEnhance {
                    Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); model.toggle() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles").font(.system(size: 15, weight: .bold))
                            Text(failedText ?? "AI 增强").font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(AICoverStyle.gradient, in: Capsule())
                        .shadow(color: Color(red: 0.4, green: 0.5, blue: 1).opacity(0.45), radius: 12, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ai-cover-viewer-enhance")
                }
            case .ineligible:
                Text("已是高清原图，无需 AI 增强").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                    .accessibilityIdentifier("ai-cover-viewer-hq")
            }
        }
    }

    private var failedText: String? { if case .failed(let t) = model.phase { return t + "，轻点重试" }; return nil }
}

/// Build 285: 「AI 画质增强」 mode (自动 / 仅手动 / 关) and the persistent result cache.
struct AICoverSettingsSection: View {
    @AppStorage(AICoverEnhanceMode.defaultsKey) private var mode = AICoverEnhanceMode.auto.rawValue
    @State private var cacheBytes = 0

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(AICoverStyle.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Text("AI 封面画质增强").font(.body.weight(.medium))
                }
                Picker("AI 封面画质增强", selection: $mode) {
                    ForEach(AICoverEnhanceMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("ai-cover-mode-setting")
            }
            .padding(.vertical, 4)
            HStack {
                Text("增强结果缓存")
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: Int64(cacheBytes), countStyle: .file)).foregroundStyle(.secondary).monospacedDigit()
            }
            Button("清除增强缓存", role: .destructive) {
                AICoverDiskCache.shared.clear(); cacheBytes = 0
            }
            .disabled(cacheBytes == 0)
        } header: {
            Text("AI 画质增强")
        } footer: {
            Text("内置超分辨率模型，在本机运行，不上传图片。只处理低清封面（如 800px 封套裁切、MGS 小图、JavDB 兜底图），DMM 等高清原图永不增强。自动：打开详情时自动增强（设备过热、低电量模式或电量低于 20% 时暂停）；仅手动：点封面右上角「AI 增强」；关：不显示。增强结果会缓存到本机，按住对比按钮可查看原图。")
        }
        .onAppear { cacheBytes = AICoverDiskCache.shared.totalBytes() }
    }
}
