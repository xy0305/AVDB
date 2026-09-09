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

    var body: some View {
        Group {
            if store.tags.isEmpty && store.isLoading {
                ProgressView()
            } else if store.tags.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("暫無關注")
                        .font(.headline)
                    Text("在演員 / 類別 / 清單頁可以加入關注")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    if let err = store.errorMessage {
                        Text(err).font(.caption).foregroundColor(.red)
                    }
                }
            } else {
                List {
                    ForEach(store.tags) { tag in
                        NavigationLink {
                            FollowingTagDestination(tag: tag)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tag.displayName)
                                    .font(.body)
                                if let typeText = tag.typeText {
                                    Text(typeText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { indexSet in
                        Task { await deleteTagsRemote(at: indexSet) }
                    }
                }
            }
        }
        .navigationTitle("我的關注")
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
