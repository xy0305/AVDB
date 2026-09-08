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
                    Task {
                        do {
                            guard try await JavDBSDK.shared.listMovieAction(list.id, movieID: movieID, add: true) else { throw JavDBError.apiError(action: nil, message: "加入清單失敗") }
                            message = "已存入「\(list.displayName)」"
                        } catch { message = error.localizedDescription }
                    }
                } label: {
                    Label(list.displayName, systemImage: "bookmark")
                }
            } else {
                NavigationLink { ListDetailView(listID: list.id, title: list.displayName) } label: {
                    Label(list.displayName, systemImage: "bookmark")
                }
            }
        }
        .navigationTitle(movieID == nil ? "我的清單" : "存入清單")
        .task { await vm.load() }
        .alert("清單", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("確定", role: .cancel) {} } message: { Text(message ?? "") }
    }
}
@MainActor final class MyListsViewModel: ObservableObject {
    @Published var lists: [MovieList] = []
    func load() async { lists = (try? await JavDBSDK.shared.lists(page: 1, limit: 24)) ?? [] }
}

struct CollectedListsView: View {
    @StateObject private var vm = CollectedListsViewModel()
    var body: some View {
        List(vm.lists) { list in
            NavigationLink { ListDetailView(listID: list.id, title: list.displayName) } label: {
                Label(list.displayName, systemImage: "bookmark")
            }
        }
        .navigationTitle("收藏的清單")
        .task { await vm.load() }
    }
}

@MainActor final class CollectedListsViewModel: ObservableObject {
    @Published var lists: [MovieList] = []
    func load() async {
        lists = (try? await JavDBSDK.shared.collectedLists(page: 1, limit: 24)) ?? []
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
