//
//  RecommendationsView.swift
//  AVDB
//
//  Build 281 「为你推荐」 UI: featured hero over a blurred cover backdrop, carousels grouped by reason,
//  tinted reason capsules, context-menu previews with feedback, lightweight skeleton shimmer,
//  cold-start state and the 「我的偏好」 page. Semantic colours only (dark-mode friendly), text styles only
//  (Dynamic Type safe). Depends on Movie / MoviePosterImage / MovieDetailView and RecommendationStore.
//

import SwiftUI
import UIKit

// MARK: - Style

enum RecStyle {
    static let corner: CGFloat = 14
    static let posterRatio: CGFloat = 0.7
    static func tint(_ kind: RecReason.Kind) -> Color {
        switch kind {
        case .actor: return Color(red: 0.93, green: 0.33, blue: 0.55)
        case .tag: return Color(red: 0.55, green: 0.38, blue: 0.95)
        case .series: return Color(red: 0.10, green: 0.62, blue: 0.68)
        case .maker: return Color(red: 0.36, green: 0.47, blue: 0.86)
        case .follow: return Color(red: 0.96, green: 0.55, blue: 0.16)
        case .similar: return Color(red: 0.33, green: 0.40, blue: 0.95)
        case .popular: return Color(red: 0.94, green: 0.32, blue: 0.24)
        case .fresh: return Color(red: 0.20, green: 0.66, blue: 0.40)
        case .taste: return Color(red: 0.86, green: 0.30, blue: 0.62)
        }
    }
    static func tint(feature kind: RecFeatureKind) -> Color {
        switch kind {
        case .actor: return tint(RecReason.Kind.actor)
        case .tag: return tint(RecReason.Kind.tag)
        case .series: return tint(RecReason.Kind.series)
        case .maker, .director: return tint(RecReason.Kind.maker)
        }
    }
    static let brand = LinearGradient(colors: [Color(red: 0.98, green: 0.36, blue: 0.52), Color(red: 0.55, green: 0.36, blue: 0.98)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
}

enum RecHaptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

/// Small tinted capsule with an icon: 「因为你常看 XX」「黑丝 · 同系列」.
struct RecReasonChip: View {
    let reason: RecReason
    var onCover = false
    var body: some View {
        let tint = RecStyle.tint(reason.kind)
        Label {
            Text(reason.text).lineLimit(1)
        } icon: {
            Image(systemName: reason.symbol).imageScale(.small)
        }
        .labelStyle(RecTightLabel())
        .font(.caption2.weight(.semibold))
        .foregroundStyle(onCover ? Color.white : tint)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background {
            if onCover { Capsule().fill(.ultraThinMaterial).overlay(Capsule().fill(tint.opacity(0.35))) }
            else { Capsule().fill(tint.opacity(0.13)) }
        }
        .accessibilityLabel("推荐理由：" + reason.text)
    }
}

struct RecTightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon; configuration.title }
    }
}

/// HQ poster with the history pipeline (MoviePosterImage), rounded, with a soft scrim.
struct RecPoster: View {
    let item: RecItem
    var maxPixelSize = 700
    var scrim = true
    var body: some View {
        Color.clear
            .aspectRatio(RecStyle.posterRatio, contentMode: .fit)
            .overlay { MoviePosterImage(movie: item.movie, maxPixelSize: maxPixelSize) }
            .overlay(alignment: .bottom) {
                if scrim {
                    LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: RecStyle.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: RecStyle.corner, style: .continuous).strokeBorder(.white.opacity(0.08)))
    }
}

struct RecRatingBadge: View {
    let rating: Double?
    var body: some View {
        if let rating, rating > 0 {
            HStack(spacing: 2) {
                Image(systemName: "star.fill").imageScale(.small)
                Text(String(format: "%.1f", rating))
            }
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(.black.opacity(0.45), in: Capsule())
        }
    }
}

// MARK: - Card

struct RecCard: View {
    let result: RecResult
    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 132
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RecPoster(item: result.item)
                .overlay(alignment: .topLeading) { RecRatingBadge(rating: result.item.rating).padding(6) }
                .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
            Text(result.item.number)
                .font(.subheadline.weight(.bold).monospaced())
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(result.item.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
            RecReasonChip(reason: result.reason)
        }
        .frame(width: min(width, 190), alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("rec.card.\(result.id)")
    }
}

/// Larger preview shown while the context menu is open.
struct RecPreviewCard: View {
    let result: RecResult
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RecPoster(item: result.item, maxPixelSize: 900, scrim: false).frame(width: 150)
            VStack(alignment: .leading, spacing: 8) {
                Text(result.item.number).font(.title3.weight(.bold).monospaced())
                Text(result.item.title).font(.subheadline).foregroundStyle(.secondary).lineLimit(4)
                RecReasonChip(reason: result.reason)
                let names = result.item.features(.actor).prefix(3).map(\.name)
                if !names.isEmpty { Text(names.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                if let date = result.item.releaseDate { Text(date).font(.caption2).foregroundStyle(.tertiary) }
            }
            .frame(width: 170, alignment: .leading)
        }
        .padding(16)
        .background(Color(.systemBackground))
    }
}

/// Feedback menu shared by every card.
struct RecFeedbackMenu: View {
    let result: RecResult
    let apply: (RecFeedbackAction, RecResult) -> Void
    var body: some View {
        Button { apply(.like, result) } label: { Label("喜欢，多推类似", systemImage: "heart") }
        Button { apply(.notInterested, result) } label: { Label("不感兴趣", systemImage: "hand.thumbsdown") }
        if let a = result.item.primaryActor {
            Button { apply(.lessActor, result) } label: { Label("少推该女优 · \(a.name)", systemImage: "person.crop.circle.badge.minus") }
        }
        if let t = RecommendationStore.topTag(result) {
            Button { apply(.lessTag, result) } label: { Label("少推该标签 · \(t.name)", systemImage: "tag.slash") }
        }
        if let s = result.item.primarySeries {
            Button { apply(.lessSeries, result) } label: { Label("少推该系列", systemImage: "square.stack.3d.down.forward") }
        }
    }
}

extension View {
    func recFeedbackMenu(_ result: RecResult, apply: @escaping (RecFeedbackAction, RecResult) -> Void) -> some View {
        contextMenu { RecFeedbackMenu(result: result, apply: apply) } preview: { RecPreviewCard(result: result) }
    }
}

// MARK: - Hero

struct RecHero: View {
    let result: RecResult
    let apply: (RecFeedbackAction, RecResult) -> Void
    var compact = false
    var body: some View {
        NavigationLink { MovieDetailView(movieID: result.id, seed: result.item.movie) } label: {
            ZStack(alignment: .bottomLeading) {
                // Blurred cover backdrop (rendered once, no animation).
                Color.clear
                    .overlay { MoviePosterImage(movie: result.item.movie, maxPixelSize: 400).scaleEffect(1.4).blur(radius: 28) }
                    .overlay(LinearGradient(colors: [.black.opacity(0.10), .black.opacity(0.62)], startPoint: .top, endPoint: .bottom))
                    .clipped()
                HStack(alignment: .bottom, spacing: 16) {
                    RecPoster(item: result.item, maxPixelSize: 1000, scrim: false)
                        .frame(width: compact ? 104 : 150)
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                    VStack(alignment: .leading, spacing: 8) {
                        Label("今日首选", systemImage: "sparkles")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(RecStyle.brand, in: Capsule())
                        Text(result.item.number)
                            .font((compact ? Font.title3 : .title).weight(.heavy).monospaced())
                            .foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(result.item.title)
                            .font(compact ? .caption : .subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(compact ? 2 : 3)
                        RecReasonChip(reason: result.reason, onCover: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(compact ? 14 : 20)
            }
            .frame(height: compact ? 190 : 300)
            .clipShape(RoundedRectangle(cornerRadius: compact ? 18 : 24, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .recFeedbackMenu(result, apply: apply)
        .accessibilityIdentifier("rec.hero")
    }
}

// MARK: - Carousel

struct RecCarousel: View {
    let group: RecGroup
    let apply: (RecFeedbackAction, RecResult) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: group.symbol)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(RecStyle.tint(group.items.first?.reason.kind ?? .taste).gradient, in: Circle())
                Text(group.title).font(.title3.weight(.bold)).lineLimit(1)
                Spacer()
                Text("\(group.items.count)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(group.items) { r in
                        NavigationLink { MovieDetailView(movieID: r.id, seed: r.item.movie) } label: { RecCard(result: r) }
                            .buttonStyle(.plain)
                            .recFeedbackMenu(r, apply: apply)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .scrollTargetBehavior(.viewAligned)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rec.group.\(group.key)")
    }
}

// MARK: - Skeleton / empty / cold start

/// One gradient sweep, only while loading; static when Reduce Motion is on.
struct RecShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.6)
                            .offset(x: phase * geo.size.width * 1.6)
                    }
                    .allowsHitTesting(false)
                    .onAppear { withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 } }
                }
            }
            .clipped()
    }
}

struct RecSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(.tertiarySystemFill)).frame(height: 260)
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    Capsule().fill(Color(.tertiarySystemFill)).frame(width: 160, height: 18)
                    HStack(spacing: 14) {
                        ForEach(0..<3, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 6) {
                                RoundedRectangle(cornerRadius: RecStyle.corner, style: .continuous).fill(Color(.tertiarySystemFill))
                                    .aspectRatio(RecStyle.posterRatio, contentMode: .fit)
                                Capsule().fill(Color(.tertiarySystemFill)).frame(width: 80, height: 10)
                                Capsule().fill(Color(.quaternarySystemFill)).frame(width: 110, height: 8)
                            }
                            .frame(width: 118)
                        }
                    }
                }
            }
        }
        .modifier(RecShimmer())
        .padding(.horizontal, 20)
        .accessibilityLabel("正在生成推荐")
        .accessibilityIdentifier("rec.skeleton")
    }
}

struct RecColdStartCard: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(RecStyle.brand, in: Circle())
                .shadow(color: Color(red: 0.7, green: 0.3, blue: 0.9).opacity(0.35), radius: 14, y: 6)
            Text("多看几部，推荐会更懂你").font(.title3.weight(.bold)).multilineTextAlignment(.center)
            Text("观看记录还不多，先为你挑了热门和新作。看完 3 部、关注女优或长按「喜欢」，就会按你的口味推荐。")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 8) {
                hint("play.fill", "看 3 部")
                hint("bell.fill", "关注女优")
                hint("heart.fill", "长按喜欢")
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("rec.coldstart")
    }
    private func hint(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).labelStyle(RecTightLabel())
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }
}

struct RecToast: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.black.opacity(0.78), in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityIdentifier("rec.toast")
    }
}

/// Feedback → haptic + store update + toast text.
@MainActor
enum RecFeedbackPresenter {
    static func apply(_ action: RecFeedbackAction, _ r: RecResult, store: RecommendationStore) -> String {
        switch action { case .like: RecHaptics.success(); default: RecHaptics.light() }
        store.feedback(action, on: r)
        switch action {
        case .like: return "已记住，会多推类似作品"
        case .notInterested: return "已移除，不再推荐这部"
        case .lessActor: return "将少推 " + (r.item.primaryActor?.name ?? "该女优")
        case .lessTag: return "将少推「" + (RecommendationStore.topTag(r)?.name ?? "该标签") + "」"
        case .lessSeries: return "将少推该系列"
        }
    }
}

// MARK: - Feed page

struct RecommendationFeedView: View {
    @ObservedObject private var store = RecommendationStore.shared
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if store.coldStart && store.hasContent { RecColdStartCard().padding(.horizontal, 20) }
                if let hero = store.hero {
                    RecHero(result: hero, apply: apply).padding(.horizontal, 20)
                } else if store.isRefreshing {
                    RecSkeleton()
                } else {
                    RecColdStartCard().padding(.horizontal, 20)
                }
                ForEach(store.groups) { RecCarousel(group: $0, apply: apply) }
                if let status = store.status {
                    Text(status).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 20)
                }
                Label("推荐完全在本机计算，不上传任何观看数据", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 24)
            }
            .padding(.top, 8)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("为你推荐")
        .refreshable { await store.refreshNow() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { PreferenceProfileView() } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("我的偏好")
                    .accessibilityIdentifier("rec.prefs.open")
            }
        }
        .overlay(alignment: .bottom) { if let toast { RecToast(text: toast).padding(.bottom, 24) } }
        .onAppear { store.refresh(manual: false) }
        .accessibilityIdentifier("rec.feed")
    }
    private func apply(_ action: RecFeedbackAction, _ r: RecResult) {
        let text = RecFeedbackPresenter.apply(action, r, store: store)
        withAnimation(.spring(duration: 0.35)) { toast = text }
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { toast = nil }
        }
    }
}

// MARK: - 我的 section

struct RecommendationSection: View {
    @ObservedObject private var store = RecommendationStore.shared
    var body: some View {
        Section {
            NavigationLink { RecommendationFeedView() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.footnote.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(RecStyle.brand, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Text("为你推荐").font(.headline)
                    Spacer()
                    if store.isRefreshing { ProgressView().controlSize(.small) }
                    else if store.coldStart { Text("热门 · 新作").font(.caption).foregroundStyle(.secondary) }
                    else { Text("全部").font(.caption).foregroundStyle(.secondary) }
                }
            }
            .accessibilityIdentifier("me.rec.all")
            if let hero = store.hero {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        RecHero(result: hero, apply: apply, compact: true).frame(width: 300)
                        ForEach(store.results.dropFirst().prefix(10)) { r in
                            NavigationLink { MovieDetailView(movieID: r.id, seed: r.item.movie) } label: { RecCard(result: r) }
                                .buttonStyle(.plain)
                                .recFeedbackMenu(r, apply: apply)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.vertical, 6)
                }
                .scrollTargetBehavior(.viewAligned)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            } else if store.isRefreshing {
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: RecStyle.corner, style: .continuous).fill(Color(.tertiarySystemFill))
                            .frame(width: 96, height: 137)
                    }
                }
                .modifier(RecShimmer())
                .listRowBackground(Color.clear)
            } else {
                Text("多看几部、关注女优后，这里会出现按你口味挑选的作品")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { store.refresh(manual: false) }
        .accessibilityIdentifier("me.rec.section")
    }
    private func apply(_ action: RecFeedbackAction, _ r: RecResult) { _ = RecFeedbackPresenter.apply(action, r, store: store) }
}

// MARK: - 我的偏好

/// Wrapping chips (iOS 16 Layout).
struct RecFlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing; row = max(row, size.height)
        }
        return CGSize(width: width, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; row = max(row, size.height)
        }
    }
}

/// 0…1 strength for display (never raw numbers).
enum RecStrength {
    static func level(_ w: Double, max m: Double) -> Double { m > 0 ? min(1, max(0.08, w / m)) : 0 }
    static func word(_ level: Double) -> String { level > 0.75 ? "非常喜欢" : level > 0.45 ? "常看" : level > 0.2 ? "感兴趣" : "偶尔" }
}

struct RecWeightedChip: View {
    let pref: RecPreference
    let level: Double
    var body: some View {
        let tint = RecStyle.tint(feature: pref.kind)
        Text(pref.name)
            .font(level > 0.6 ? .subheadline.weight(.bold) : (level > 0.3 ? .footnote.weight(.semibold) : .caption.weight(.medium)))
            .foregroundStyle(level > 0.55 ? Color.white : tint)
            .padding(.horizontal, 10 + 4 * level).padding(.vertical, 5 + 2 * level)
            .background(Capsule().fill(level > 0.55 ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.10 + 0.25 * level))))
            .accessibilityLabel(pref.name + "，" + RecStrength.word(level))
    }
}

struct RecPreferenceBar: View {
    let pref: RecPreference
    let level: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(pref.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(RecStrength.word(level)).font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule().fill(RecStyle.tint(feature: pref.kind).gradient).frame(width: max(8, geo.size.width * level))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
    }
}

struct PreferenceProfileView: View {
    @ObservedObject private var store = RecommendationStore.shared
    @State private var confirmReset = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(store.summary)
                actorsCard(store.summary)
                tagsCard(store.summary)
                communitiesCard(store.summary)
                moreCard(store.summary)
                negativesCard(store.summary)
                modelCard
                resetButton
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("我的偏好")
        .confirmationDialog("重置后将忘记所有喜欢 / 少推反馈和学到的权重，之前的观看历史不再计入推荐。", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("重置推荐偏好", role: .destructive) { RecHaptics.warning(); store.reset() }
            Button("取消", role: .cancel) {}
        }
        .accessibilityIdentifier("rec.prefs")
    }

    @ViewBuilder private func actorsCard(_ s: RecPreferenceSummary) -> some View {
        if !s.actors.isEmpty {
            card("最常看的女优", symbol: "person.crop.circle.fill", tint: RecStyle.tint(feature: .actor)) {
                bars(Array(s.actors.prefix(6)))
            }
        }
    }

    @ViewBuilder private func tagsCard(_ s: RecPreferenceSummary) -> some View {
        if !s.tags.isEmpty {
            let m = s.tags.first?.weight ?? 1
            card("口味标签", symbol: "tag.fill", tint: RecStyle.tint(feature: .tag)) {
                RecFlowLayout {
                    ForEach(s.tags, id: \.key) { pref in
                        RecWeightedChip(pref: pref, level: RecStrength.level(pref.weight, max: m))
                    }
                }
            }
        }
    }

    @ViewBuilder private func communitiesCard(_ s: RecPreferenceSummary) -> some View {
        if !s.communities.isEmpty {
            card("兴趣社区", symbol: "circle.hexagongrid.fill", tint: RecStyle.tint(RecReason.Kind.similar)) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(s.communities) { c in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(c.names.joined(separator: " · ")).font(.subheadline.weight(.semibold)).lineLimit(2)
                            RecMeter(level: min(1, c.weight * 1.6), style: AnyShapeStyle(RecStyle.brand), height: 5)
                        }
                    }
                    Text("由你看过作品的女优、标签、系列共现自动聚类（类似 X 的 SimClusters）。")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder private func moreCard(_ s: RecPreferenceSummary) -> some View {
        let more = s.series + s.makers
        if !more.isEmpty {
            card("系列与片商", symbol: "square.stack.fill", tint: RecStyle.tint(feature: .series)) {
                bars(Array(more.prefix(6)))
            }
        }
    }

    @ViewBuilder private func negativesCard(_ s: RecPreferenceSummary) -> some View {
        if !s.negatives.isEmpty {
            card("少推", symbol: "hand.raised.fill", tint: Color.secondary) {
                RecFlowLayout {
                    ForEach(s.negatives, id: \.key) { p in
                        Button { RecHaptics.light(); store.removeNegative(p.key) } label: {
                            Label(p.name, systemImage: "xmark").labelStyle(RecTightLabel())
                                .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("点按恢复推荐")
                    }
                }
            }
        }
    }

    private var modelRows: [RecModelRow] {
        let pairs = zip(RecRanker.featureNames, store.ranker.weights).dropFirst().map { RecModelRow(name: $0.0, weight: $0.1) }
        let top = pairs.sorted { abs($0.weight) > abs($1.weight) }.prefix(5)
        let m = top.map { abs($0.weight) }.max() ?? 1
        return top.map { RecModelRow(name: $0.name, weight: $0.weight, level: m > 0 ? abs($0.weight) / m : 0) }
    }

    private var modelCard: some View {
        card("排序模型学到的重点", symbol: "chart.bar.xaxis", tint: RecStyle.tint(RecReason.Kind.maker)) {
            VStack(spacing: 12) {
                ForEach(modelRows) { row in
                    HStack(spacing: 10) {
                        Text(row.name).font(.footnote).frame(width: 82, alignment: .leading).lineLimit(1)
                        RecMeter(level: row.level, style: AnyShapeStyle(RecStyle.tint(RecReason.Kind.maker).opacity(0.75)), height: 6)
                    }
                }
                Text("每次「喜欢 / 不感兴趣」和看完推荐作品都会在本机更新（已学习 \(store.ranker.updates) 次）。")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var resetButton: some View {
        Button(role: .destructive) { confirmReset = true } label: {
            Label("重置推荐偏好", systemImage: "arrow.counterclockwise")
                .font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("rec.prefs.reset")
    }

    private func bars(_ prefs: [RecPreference]) -> some View {
        let m = prefs.map(\.weight).max() ?? 1
        return VStack(spacing: 14) {
            ForEach(prefs, id: \.key) { pref in
                RecPreferenceBar(pref: pref, level: RecStrength.level(pref.weight, max: m))
            }
        }
    }

    private func header(_ s: RecPreferenceSummary) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "person.text.rectangle.fill")
                .font(.title2).foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(RecStyle.brand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(s.coldStart ? "还在了解你的口味" : "你的口味画像").font(.headline)
                Text("来自 \(s.positiveItems) 部观看 / 收藏 · \(s.explicitSignals) 条反馈 · 仅保存在本机")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func card<Content: View>(_ title: String, symbol: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(tint)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct RecModelRow: Identifiable {
    var name: String
    var weight: Double
    var level: Double = 0
    var id: String { name }
}

struct RecMeter: View {
    let level: Double
    let style: AnyShapeStyle
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule().fill(style).frame(width: max(height, geo.size.width * CGFloat(min(1, max(0, level)))))
            }
        }
        .frame(height: height)
    }
}
