import SwiftUI

/// 本地“想看”列表；服务器详情页的 want_watch 动作将在后续 API 返回状态后同步。
struct LocalMovieListView: View {
    let title: String
    let ids: [String]
    @StateObject private var vm = LocalMovieListViewModel()
    var body: some View {
        MovieGridView(title: title, viewModel: vm)
            .task { await vm.load(ids: ids) }
    }
}

@MainActor final class LocalMovieListViewModel: MovieListViewModel {
    init() { super.init(fetchPage: { _ in [] }) }
    func load(ids: [String]) async {
        guard movies.isEmpty else { return }
        for id in ids {
            if let movie = try? await JavDBSDK.shared.movieDetail(id) { movies.append(movie) }
        }
    }
}

struct MyListsView: View {
    var movieID: String? = nil
    @StateObject private var vm = MyListsViewModel()
    @State private var message: String?
    var body: some View {
        List(vm.lists) { list in
            if let movieID {
                Button {
                    Task { await toggle(list, movieID: movieID) }
                } label: {
                    HStack {
                        Label(list.displayName, systemImage: list.hasMovie == true ? "bookmark.fill" : "bookmark")
                        Spacer()
                        if list.hasMovie == true {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                NavigationLink { ListDetailView(listID: list.id, title: list.displayName) } label: {
                    Label(list.displayName, systemImage: "bookmark")
                }
            }
        }
        .navigationTitle(movieID == nil ? "我的清單" : "存入清單")
        .task { await vm.load(movieID: movieID) }
        .alert("提示", isPresented: Binding(get: { message != nil || vm.errorMessage != nil }, set: { if !$0 { message = nil; vm.errorMessage = nil } })) {
            Button("確定", role: .cancel) {}
        } message: {
            Text(message ?? vm.errorMessage ?? "")
        }
    }

    private func toggle(_ list: MovieList, movieID: String) async {
        let adding = list.hasMovie != true
        do {
            _ = try await JavDBSDK.shared.listMovieAction(list.id, movieID: movieID, add: adding)
            message = adding ? "已將影片保存至清單\(list.displayName)中" : "已從清單\(list.displayName)中移除"
            await vm.load(movieID: movieID)
        } catch {
            message = error.localizedDescription
        }
    }
}
@MainActor final class MyListsViewModel: ObservableObject {
    @Published var lists: [MovieList] = []
    @Published var errorMessage: String?
    func load(movieID: String? = nil) async {
        do {
            lists = try await JavDBSDK.shared.simpleLists(movieID: movieID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CollectedListsView: View {
    @StateObject private var vm = CollectedListsViewModel()
    var body: some View {
        List {
            if vm.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let err = vm.errorMessage {
                Text(err).foregroundColor(.red).padding()
            } else if vm.lists.isEmpty {
                Text("暂无收藏的清单").foregroundColor(.secondary).padding()
            } else {
                ForEach(vm.lists) { list in
                    NavigationLink { ListDetailView(listID: list.id, title: list.displayName) } label: {
                        Label(list.displayName, systemImage: "bookmark")
                    }
                }
            }
        }
        .navigationTitle("收藏的清單")
        .task { await vm.load() }
    }
}

@MainActor final class CollectedListsViewModel: ObservableObject {
    @Published var lists: [MovieList] = []
    @Published var errorMessage: String?
    @Published var isLoading = false
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            lists = try await JavDBSDK.shared.collectedLists(page: 1, limit: 24)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum WantWatchStore {
    static var ids: [String] { UserDefaults.standard.stringArray(forKey: "avdb.want.watch.ids") ?? [] }
    static func contains(_ id: String) -> Bool { ids.contains(id) }
    static func set(_ id: String, on: Bool) {
        var values = Set(ids)
        if on { values.insert(id) } else { values.remove(id) }
        UserDefaults.standard.set(Array(values), forKey: "avdb.want.watch.ids")
    }
}
