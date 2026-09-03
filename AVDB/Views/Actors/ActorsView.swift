//
//  ActorsView.swift
//  AVDB
//
//  演员列表页 + 演员详情页。
//

import SwiftUI

struct ActorsView: View {
    @StateObject private var vm = ActorsViewModel()
    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(vm.actors) { actor in
                        NavigationLink {
                            ActorDetailView(actorID: actor.id)
                        } label: {
                            VStack(spacing: 4) {
                                JavDBImage(url: actor.avatarURL ?? actor.coverURL)
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                                Text(actor.name ?? "")
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                if vm.isLoading {
                    ProgressView().padding()
                }
            }
            .navigationTitle("演员")
            .task {
                if vm.actors.isEmpty { await vm.load() }
            }
            .refreshable { await vm.refresh() }
        }
    }
}

@MainActor
final class ActorsViewModel: ObservableObject {
    @Published var actors: [Actor] = []
    @Published var isLoading = false
    private var page = 1

    private let sdk = JavDBSDK.shared

    func load() async {
        isLoading = true
        defer { isLoading = false }
        if let list = try? await sdk.actors(page: page) {
            if list.isEmpty { return }
            actors.append(contentsOf: list)
            page += 1
        }
    }

    func refresh() async {
        page = 1
        actors = []
        await load()
    }
}

/// 演员详情
struct ActorDetailView: View {
    let actorID: String
    @StateObject private var vm: ActorDetailViewModel

    init(actorID: String) {
        self.actorID = actorID
        _vm = StateObject(wrappedValue: ActorDetailViewModel(actorID: actorID))
    }

    var body: some View {
        ScrollView {
            if let actor = vm.actor {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        JavDBImage(url: actor.avatarURL ?? actor.coverURL)
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 6) {
                            Text(actor.name ?? "演员")
                                .font(.title3.bold())
                            if let birthday = actor.birthday, !birthday.isEmpty {
                                Label(birthday, systemImage: "birthday.cake")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            HStack(spacing: 12) {
                                if let age = actor.age { info("\(age)岁") }
                                if let height = actor.height { info("\(height)cm") }
                                if let cup = actor.cup { info(cup) }
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                }
            } else if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
    }

    private func info(_ text: String) -> some View {
        Text(text).font(.caption).foregroundColor(.secondary)
    }
}

@MainActor
final class ActorDetailViewModel: ObservableObject {
    @Published var actor: Actor?
    @Published var isLoading = false
    let actorID: String

    init(actorID: String) {
        self.actorID = actorID
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        actor = try? await JavDBSDK.shared.actorDetail(actorID)
    }
}
