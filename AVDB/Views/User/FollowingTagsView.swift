//
//  FollowingTagsView.swift
//  AVDB
//
//  我的关注：POST /following_tags/batch_push 拉列表。
//

import SwiftUI

struct FollowingTagsView: View {
    @StateObject private var store = FollowingTagsStore.shared
    @State private var editMode: EditMode = .inactive
    // Build 352: official tag presets (fail-soft — empty/failure hides the section).
    @State private var presets: [FollowingTag] = []

    /// Presets the user has not followed yet (matched by name+value).
    private var visiblePresets: [FollowingTag] {
        presets.filter { preset in
            !store.tags.contains { $0.name == preset.name && $0.value == preset.value }
        }
    }

    @ViewBuilder
    private var presetsSection: some View {
        if !visiblePresets.isEmpty {
            Section("官方預設") {
                ForEach(visiblePresets) { preset in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.displayName)
                                .font(.body)
                            if let typeText = preset.typeText {
                                Text(typeText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("關注") {
                            Task { await followPreset(preset) }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func followPreset(_ preset: FollowingTag) async {
        guard let name = preset.name, let value = preset.value,
              !name.isEmpty, !value.isEmpty else { return }
        if (try? await JavDBSDK.shared.followTag(name: name, value: value)) != nil {
            presets.removeAll { $0.id == preset.id }
            await store.refreshFromServer()
        }
    }

    var body: some View {
        Group {
            if store.tags.isEmpty && store.isLoading {
                ProgressView()
            } else if store.tags.isEmpty {
                if visiblePresets.isEmpty {
                    GlassEmptyView(
                        icon: "eye.slash",
                        title: "暫無關注",
                        subtitle: "在演員 / 類別 / 清單頁可以加入關注"
                    )
                    if let err = store.errorMessage {
                        Text(err).font(.caption).foregroundColor(.red)
                    }
                } else {
                    List {
                        Section {
                            Text("暫無關注，在演員 / 類別 / 清單頁可以加入關注")
                                .foregroundStyle(.secondary)
                        }
                        presetsSection
                    }
                }
            } else {
                List {
                    presetsSection
                    ForEach(Array(store.tags.enumerated()), id: \.element.id) { idx, tag in
                        NavigationLink {
                            FollowingTagDestination(tag: tag)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "eye.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 34, height: 34)
                                    .liquidGlassCircle(tint: Color.accentColor.opacity(0.2))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(tag.displayName)
                                        .font(.body.weight(.medium))
                                    if let typeText = tag.typeText {
                                        GlassChip(
                                            text: typeText,
                                            tint: .blue,
                                            font: .caption2,
                                            foreground: .secondary,
                                            compact: true,
                                            tintStrength: 0.10
                                        )
                                    }
                                }
                            }
                            .padding(.vertical, 3)
                        }
                        .staggerAppear(index: idx % 10)
                    }
                    .onDelete { indexSet in
                        Task { await deleteTagsRemote(at: indexSet) }
                    }
                }
            }
        }
        .navigationTitle("我的關注")
        .liquidGlassList()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !store.tags.isEmpty {
                    EditButton()
                }
            }
        }
        .environment(\.editMode, $editMode)
        .task {
            await store.refreshFromServer()
            presets = (try? await JavDBSDK.shared.followingTagPresets()) ?? []
        }
        .refreshable {
            await store.refreshFromServer()
        }
    }

    private func deleteTagsRemote(at indexSet: IndexSet) async {
        let ids = indexSet.map { store.tags[$0].id }
        for id in ids {
            _ = try? await JavDBSDK.shared.unfollowTag(id)
            store.remove(id)
        }
    }
}

/// 点进关注项：演员走详情，片单走 ListDetail，其它走 movies/tags filter_by。
struct FollowingTagDestination: View {
    let tag: FollowingTag

    var body: some View {
        if let actorID = tag.parsedActorID {
            ActorDetailView(actorID: actorID)
        } else if tag.name == "list", let listID = tag.value, !listID.isEmpty {
            ListDetailView(listID: listID, title: tag.displayName)
        } else if let filter = tag.moviesFilterBy {
            FollowingTagMoviesView(title: tag.displayName, filterBy: filter)
        } else {
            Text("無法打開此關注")
                .foregroundColor(.secondary)
                .navigationTitle(tag.displayName)
        }
    }
}

struct FollowingTagMoviesView: View {
    let title: String
    let filterBy: String
    @StateObject private var vm: MovieListViewModel

    init(title: String, filterBy: String) {
        self.title = title
        self.filterBy = filterBy
        _vm = StateObject(wrappedValue: MovieListViewModel { page, sort in
            try await JavDBSDK.shared.moviesByTag(
                filterBy: filterBy,
                type: nil,
                page: page,
                limit: 21,
                sortBy: sort.sortBy,
                orderBy: sort.orderBy
            )
        })
    }

    var body: some View {
        MovieGridView(title: title, viewModel: vm)
    }
}

struct ReviewMoviesView: View {
    let title: String
    let status: String
    @StateObject private var vm: MovieListViewModel

    init(title: String, status: String) {
        self.title = title
        self.status = status
        _vm = StateObject(wrappedValue: MovieListViewModel { page in
            try await JavDBSDK.shared.reviewMovies(status: status, page: page, limit: 24)
        })
    }

    var body: some View {
        MovieGridView(title: title, viewModel: vm)
    }
}
