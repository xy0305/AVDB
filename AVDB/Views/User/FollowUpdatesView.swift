//
//  FollowUpdatesView.swift
//  AVDB
//
//  Build 280 追更提醒 UI：关注按钮、我的 › 关注更新（未读角标）、关注管理。
//

import SwiftUI

/// Toolbar 关注 button for series / maker pages (local follow, works signed-out).
struct FollowToggleButton: View {
    let kind: FollowKind
    let tagID: String
    let name: String
    var type: String = "0"
    @ObservedObject private var store = FollowStore.shared
    var body: some View {
        let following = store.isFollowing(kind, tagID: tagID, type: type)
        Button {
            GlassHaptic.tap()
            store.toggle(kind, tagID: tagID, name: name, type: type)
        } label: {
            Image(systemName: following ? "bell.fill" : "bell")
        }
        .accessibilityLabel(following ? "已关注" + kind.label + "，点按取消" : "关注" + kind.label + "，有新作时提醒")
        .accessibilityIdentifier("follow.toggle.\(kind.rawValue)")
    }
}

/// 我的: 关注更新 (badge) + 关注管理. Placed next to each PlaybackHistorySection.
struct FollowUpdatesSection: View {
    @ObservedObject private var feed = ReleaseFeedStore.shared
    @ObservedObject private var follows = FollowStore.shared
    var body: some View {
        Section {
            NavigationLink { ReleaseFeedView() } label: {
                Label("关注更新", systemImage: "bell.badge")
            }
            .badge(feed.unreadCount)
            .accessibilityIdentifier("me.follow.feed")
            NavigationLink { FollowManageView() } label: {
                HStack {
                    Label("关注管理", systemImage: "person.2.badge.gearshape")
                    Spacer()
                    Text(follows.targets.isEmpty ? "未关注" : "\(follows.targets.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("me.follow.manage")
        } footer: {
            Text("关注女优 / 系列 / 片商后，打开 App 时和系统允许的后台时段会检查新作，并发本地通知。")
        }
    }
}

struct ReleaseFeedView: View {
    @ObservedObject private var feed = ReleaseFeedStore.shared
    @ObservedObject private var checker = FollowUpdateChecker.shared
    @ObservedObject private var follows = FollowStore.shared
    @State private var permission = ""
    var body: some View {
        List {
            Section {
                if let status = checker.status { Text(status).font(.footnote).foregroundStyle(.secondary) }
                if let last = checker.lastRunAt {
                    Text("上次检查：" + last.formatted(date: .abbreviated, time: .shortened)).font(.footnote).foregroundStyle(.secondary)
                }
                if !permission.isEmpty { Text(permission).font(.footnote).foregroundStyle(.secondary) }
            }
            if feed.items.isEmpty {
                Text(follows.targets.isEmpty ? "还没有关注。在女优、系列或片商页面点「关注」即可。" : "暂时没有新作。首次检查只记录现有作品，之后的新作会出现在这里。")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("follow.feed.empty")
            } else {
                ForEach(feed.items) { item in
                    NavigationLink {
                        MovieDetailView(movieID: item.movieID, seed: Movie(id: item.movieID, number: item.number, title: item.title, coverURL: item.coverURL))
                    } label: {
                        HStack(spacing: 12) {
                            JavDBImage(url: item.coverURL, contentMode: .fill)
                                .frame(width: 96, height: 64).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    if !item.read { Circle().fill(.red).frame(width: 7, height: 7) }
                                    Text(item.number).font(.subheadline.weight(.semibold))
                                }
                                Text(item.title).font(.caption).lineLimit(2)
                                Text(item.kind.label + " · " + item.followName + (item.releaseDate.map { " · " + $0 } ?? ""))
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .swipeActions { Button("删除", role: .destructive) { feed.remove(item.id) } }
                    .accessibilityIdentifier("follow.feed.item.\(item.movieID)")
                }
            }
        }
        .navigationTitle("关注更新")
        .refreshable { _ = await checker.run(.manual) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { Task { _ = await checker.run(.manual) } } label: { Label("立即检查", systemImage: "arrow.clockwise") }
                        .disabled(checker.isRunning || follows.targets.isEmpty)
                    Button { feed.markAllRead() } label: { Label("全部已读", systemImage: "checkmark.circle") }
                    Button(role: .destructive) { feed.clear() } label: { Label("清空", systemImage: "trash") }
                } label: { Image(systemName: checker.isRunning ? "hourglass" : "ellipsis.circle") }
                .accessibilityIdentifier("follow.feed.menu")
            }
        }
        .task {
            permission = await FollowNotifier.authorizationText()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            feed.markAllRead()
        }
    }
}

struct FollowManageView: View {
    @ObservedObject private var store = FollowStore.shared
    var body: some View {
        List {
            if store.targets.isEmpty {
                Text("还没有关注。在女优、系列或片商页面点「关注」，有新作时会提醒。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(FollowKind.allCases, id: \.self) { kind in
                let rows = store.targets.filter { $0.kind == kind }
                if !rows.isEmpty {
                    Section(kind.label) {
                        ForEach(rows) { target in
                            NavigationLink { destination(target) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Label(target.name, systemImage: kind.symbol)
                                    Text(target.lastChecked.map { "上次检查 " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "等待首次检查")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions { Button("取消关注", role: .destructive) { store.remove(target.id) } }
                            .accessibilityIdentifier("follow.manage.\(target.id)")
                        }
                    }
                }
            }
            Section {
                Text("后台检查由 iOS 决定是否执行（低电量、很少打开、或自签安装都可能不运行）；每次打开 App 也会检查。每个关注 6 小时最多请求一次。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("关注管理")
    }
    @ViewBuilder private func destination(_ target: FollowTarget) -> some View {
        switch target.kind {
        case .actor: ActorDetailView(actorID: target.tagID)
        case .series: SeriesMoviesView(seriesID: target.tagID, title: target.name, type: target.type)
        case .maker: MakerMoviesView(makerID: target.tagID, title: target.name, type: target.type)
        }
    }
}
