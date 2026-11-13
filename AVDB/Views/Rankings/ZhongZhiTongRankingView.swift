import SwiftUI

/// Build 313: 中指通每月作品精選 — month picker (newest first), the video's order kept.
/// Each code is matched through the normal AVDB exact-code lookup, so tapping opens the
/// usual MovieDetailView; unmatched codes still show 番号 + 女优 and the manual-check route.
struct ZhongZhiTongRankingView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var metadata = MissAVMetadata(sourceName: "中指通", generation: { 0 }, enrichMissAV: false)
    @State private var catalog: ZZTCatalog?
    @State private var selectedMonth = ""
    @State private var loading = false
    @State private var remoteNote = ""
    @State private var attempt = 0
    private let store = ZZTCatalogStore()

    private var months: [ZZTMonth] { catalog?.months ?? [] }
    private var current: ZZTMonth? { months.first { $0.month == selectedMonth } ?? months.first }
    private var currentYearMonths: [ZZTMonth] { months.filter { $0.year == current?.year } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if let current {
                    monthInfo(current)
                    let videos = current.entries.enumerated().map { index, entry in Self.video(entry, month: current.month, index: index) }
                    MissAVGrid(videos: videos, metadata: metadata, sourceName: "中指通",
                               ranks: Dictionary(uniqueKeysWithValues: videos.enumerated().map { ($1.path, $0 + 1) }),
                               identityPrefix: "zzt")
                        .id(current.month)
                } else if loading {
                    ProgressView("载入中指通月度精選…").frame(maxWidth: .infinity)
                } else {
                    ContentUnavailableView {
                        Label("暂无中指通榜单", systemImage: "list.number")
                    } description: { Text(ZZTError.missingBundle.localizedDescription) }
                    actions: { Button("重试") { attempt += 1 }.buttonStyle(.bordered) }
                }
            }.padding(.vertical, 8)
        }
        .navigationTitle("中指通月度精選")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { attempt += 1 }
        .task(id: attempt) { await load() }
        .task(id: selectedMonth) {
            // Build 349: seed this month's server feed matches, if any.
            if !selectedMonth.isEmpty,
               let feed = await RankingFeedState.shared.ensure(board: "zhongzhitong", term: selectedMonth) {
                metadata.applyFeed(feed)
            }
        }
        .onChange(of: selectedMonth) { _, _ in metadata.suspend() }
        .onDisappear { metadata.suspend() }
        .onChange(of: appState.currentUser?.id) { _, _ in metadata.reset() }
        .onChange(of: appState.isLoggedIn) { _, _ in metadata.reset() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            // Build 314: many months now (history back-filled) — pick a year, then a month in it.
            Picker("年份", selection: Binding(get: { current?.year ?? "" }, set: { year in
                selectedMonth = catalog?.years.first(where: { $0.year == year })?.months.first?.month ?? selectedMonth
            })) {
                ForEach(catalog?.years ?? []) { year in Text("\(year.label)（\(year.months.count)）").tag(year.year) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("zzt-year-picker")
            Picker("月份", selection: Binding(get: { current?.month ?? "" }, set: { selectedMonth = $0 })) {
                ForEach(currentYearMonths) { month in Text(month.monthLabel).tag(month.month) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("zzt-month-picker")
            Spacer(minLength: 0)
            if loading { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func monthInfo(_ month: ZZTMonth) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(month.label).font(.subheadline.weight(.semibold))
            Text(month.title).font(.footnote.weight(.semibold)).lineLimit(3)
            Text("\(month.entries.count) 部 · 依影片介绍顺序 · \(Self.sourceLabel(month.sourceType))")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                if let video = month.video, let url = URL(string: video) {
                    Link(destination: url) { Label("YouTube 原片", systemImage: "play.rectangle") }
                }
                if let source = month.source, let url = URL(string: source) {
                    Link(destination: url) { Label("番号来源", systemImage: "link") }
                }
            }.font(.caption)
            if !remoteNote.isEmpty {
                Text(remoteNote).font(.caption2).foregroundStyle(.secondary)
            }
            RankingFeedNote(board: "zhongzhitong", term: month.month)
        }
        .padding(.horizontal)
    }

    static func sourceLabel(_ type: String) -> String {
        switch type {
        case "forum_list": return "番号来自网友整理清单"
        case "youtube_transcript": return "番号来自影片字幕，已用资料库发行日期核对"
        case "video_title": return "仅影片标题提到的作品（本月清单不完整）"
        case "video_ocr": return "番号来自影片画面/字幕文字辨识，已用资料库核对（可能不完整）"
        default: return "来源未标注"
        }
    }

    static func video(_ entry: ZZTEntry, month: String, index: Int) -> JRVideo {
        let actresses = entry.actresses.joined(separator: "、")
        return JRVideo(path: "zzt:\(month):\(index):\(entry.code)", code: entry.code,
                       title: actresses.isEmpty ? entry.code : actresses, image: nil,
                       subtitle: entry.note ?? "")
    }

    @MainActor private func load() async {
        if catalog == nil { catalog = store.local() }
        loading = true
        defer { loading = false }
        let result = await store.refresh(current: catalog)
        guard !Task.isCancelled else { return }
        catalog = result.catalog
        remoteNote = result.remoteOK ? "资料更新：\(catalog?.updatedAt ?? "")" : "使用安装包内资料（\(catalog?.updatedAt ?? "未知")），线上更新暂不可用"
        if selectedMonth.isEmpty || !months.contains(where: { $0.month == selectedMonth }) {
            selectedMonth = months.first?.month ?? ""
        }
        // Build 349: feed matches are the primary source for this month;
        // the bundled catalog still provides the code list itself, and
        // any code the feed does not cover falls back to the metadata
        // queue (MissAVMetadata with the shared VerificationThrottle).
        if let month = current?.month,
           let feed = await RankingFeedState.shared.ensure(board: "zhongzhitong", term: month) {
            metadata.applyFeed(feed)
        }
    }
}
