//
//  UserView.swift
//  AVDB
//
//  我的页：登录/用户信息/收藏/VIP 会员/钱包/关于。
//

import SwiftUI

struct UserView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var pan115 = Pan115Settings.shared
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            List {
                if let user = appState.currentUser {
                    // 已登录
                    Section {
                        HStack(spacing: 16) {
                            JavDBImage(url: user.avatarURL)
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.displayName)
                                    .font(.headline)
                                if user.isVip == true {
                                    Text("VIP 会员")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(.orange, in: Capsule())
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section("我的") {
                        NavigationLink {
                            ReviewMoviesView(title: "我想看", status: "want_watch")
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("我想看")
                                    if let n = user.wantWatchCount {
                                        Text("我想看 \(n) 部影片")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } icon: {
                                Image(systemName: "heart")
                            }
                        }
                        NavigationLink {
                            ReviewMoviesView(title: "我看過的", status: "watched")
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("我看過的")
                                    if let n = user.watchedCount {
                                        Text("我已看過 \(n) 部影片")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } icon: {
                                Image(systemName: "heart.fill")
                            }
                        }
                        NavigationLink { MyListsView() } label: {
                            Label("我的清單", systemImage: "bookmark.fill")
                        }
                    }

                    Section {
                        NavigationLink {
                            FollowingTagsView()
                        } label: {
                            Label("我的關注", systemImage: "eye")
                        }
                        NavigationLink {
                            FavoritesHubView()
                        } label: {
                            Label("我的收藏", systemImage: "plus.circle")
                        }
                        NavigationLink {
                            RecentViewedView()
                        } label: {
                            Label("近期瀏覽", systemImage: "clock")
                        }
                    }

                    Section("会员") {
                        NavigationLink("开通/续费 VIP") {
                            PlansView()
                        }
                        NavigationLink("我的钱包") {
                            WalletView()
                        }
                    }

                    Section {
                        Button("退出登录", role: .destructive) {
                            JavDBSDK.shared.logout()
                            appState.isLoggedIn = false
                            appState.currentUser = nil
                        }
                    }

                } else {
                    // 未登录
                    Section {
                        Button {
                            showLogin = true
                        } label: {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.plus")
                                Text("登录 / 注册")
                            }
                        }
                    }
                }

                Section("下载") {
                    NavigationLink {
                        Pan115SettingsView()
                    } label: {
                        HStack {
                            Text("115 离线")
                            Spacer()
                            Text(pan115.isConfigured ? "已配置" : "未配置")
                                .font(.caption)
                                .foregroundColor(pan115.isConfigured ? .green : .secondary)
                        }
                    }
                }

                Section("关于") {
                    NavigationLink("关于 AVDB") {
                        AboutView()
                    }
                }
            }
            .navigationTitle("我的")
            .liquidGlassList()
            .sheet(isPresented: $showLogin) {
                LoginView()
            }
        }
    }
}

/// 收藏视图
struct FavoritesHubView: View {
    var body: some View {
        List {
            NavigationLink("收藏的演员") { CollectedView(kind: .actor) }
            NavigationLink("收藏的片商") { CollectedView(kind: .maker) }
            NavigationLink("收藏的系列") { CollectedView(kind: .series) }
            NavigationLink("收藏的导演") { CollectedView(kind: .director) }
            NavigationLink("收藏的番号") { CollectedView(kind: .code) }
            NavigationLink("收藏的清单") { CollectedListsView() }
        }
        .navigationTitle("我的收藏")
        .liquidGlassList()
    }
}

struct CollectedView: View {
    enum Kind: String {
        case actor = "演员"
        case maker = "片商"
        case series = "系列"
        case director = "导演"
        case code = "番号"
    }
    let kind: Kind
    @StateObject private var vm = CollectedViewModel()
    @State private var actorType: String = "all"
    @State private var isEditing = false
    @State private var selectedActors: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            if kind == .actor {
                actorTypeTab
            }
            content
        }
        .navigationTitle("收藏的\(kind.rawValue)")
        .liquidGlassPage()
        .toolbar {
            if kind == .actor {
                ToolbarItem(placement: .topBarTrailing) {
                    if isEditing {
                        HStack(spacing: 16) {
                            Button("取消") {
                                isEditing = false
                                selectedActors.removeAll()
                            }
                            Button("删除") {
                                Task { await deleteSelected() }
                            }
                            .disabled(selectedActors.isEmpty)
                        }
                    } else {
                        Button("编辑") {
                            isEditing = true
                        }
                    }
                }
            }
        }
        .task { await vm.load(kind, type: actorType) }
        .onChange(of: actorType) { _, newValue in
            Task { await vm.load(kind, type: newValue) }
        }
    }

    private var actorTypeTab: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach([("all", "全部"), ("0", "有码"), ("1", "无码"), ("2", "欧美")], id: \.0) { type, title in
                    LiquidFilterChip(
                        title: title,
                        isSelected: actorType == type
                    ) {
                        actorType = type
                    }
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 48)
    }

    @ViewBuilder
    private var content: some View {
        if kind == .actor {
            actorGrid
        } else {
            listView
        }
    }

    private var actorGrid: some View {
        ScrollView {
            CollectedActorGrid(vm: vm, isEditing: isEditing, selectedActors: $selectedActors)
            if vm.isLoading { ProgressView().padding() }
            if let err = vm.errorMessage {
                Text(err).foregroundColor(.red).padding()
            }
        }
    }

    private var listView: some View {
        List {
            switch kind {
            case .maker, .director:
                ForEach(vm.people) { person in
                    NavigationLink(person.name ?? "") { ActorDetailView(actorID: person.id) }
                }
            case .code:
                ForEach(vm.codes) { code in
                    if let id = code.id {
                        NavigationLink(code.number ?? code.title ?? "") { MovieDetailView(movieID: id) }
                    } else { Text(code.number ?? code.title ?? "") }
                }
            case .series:
                ForEach(vm.series) { movie in
                    NavigationLink(movie.displayNumber) {
                        MovieDetailView(movieID: movie.id)
                    }
                }
            case .actor:
                EmptyView()
            }
            if vm.isLoading { ProgressView() }
            if let err = vm.errorMessage {
                Text(err).foregroundColor(.red).padding()
            }
        }
    }

    private func deleteSelected() async {
        // TODO: 调用批量取消收藏接口
        for actorID in selectedActors {
            _ = try? await JavDBSDK.shared.collectActor(actorID, collect: false)
        }
        selectedActors.removeAll()
        isEditing = false
        await vm.load(kind, type: actorType)
    }
}

/// 收藏演员网格（自适应列数）
private struct CollectedActorGrid: View {
    @ObservedObject var vm: CollectedViewModel
    var isEditing: Bool
    @Binding var selectedActors: Set<String>
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var columns: [GridItem] {
        let count = sizeClass == .regular ? 5 : 3
        return Array(repeating: GridItem(.flexible()), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(vm.actors) { actor in
                Button {
                    if isEditing {
                        if selectedActors.contains(actor.id) {
                            selectedActors.remove(actor.id)
                        } else {
                            selectedActors.insert(actor.id)
                        }
                    }
                } label: {
                    NavigationLink {
                        ActorDetailView(actorID: actor.id)
                    } label: {
                        VStack(spacing: 8) {
                            ZStack(alignment: .topTrailing) {
                                JavDBImage(url: actor.avatarURL, contentMode: .fill)
                                    .frame(width: 110, height: 110)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                if isEditing {
                                    Image(systemName: selectedActors.contains(actor.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedActors.contains(actor.id) ? .blue : .gray)
                                        .padding(6)
                                }
                            }
                            Text(actor.displayName)
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundColor(.primary)
                        }
                        .frame(width: 110)
                    }
                    .disabled(isEditing)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }
}

@MainActor
final class CollectedViewModel: ObservableObject {
    @Published var actors: [Actor] = []
    @Published var people: [Actor] = []
    @Published var codes: [Code] = []
    @Published var series: [Movie] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(_ kind: CollectedView.Kind, type: String = "all") async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let sdk = JavDBSDK.shared
        do {
            switch kind {
            case .actor:
                actors = try await sdk.collectedActors(page: 1, limit: 200, type: type)
            case .maker:
                people = try await sdk.collectedMakers(page: 1, limit: 24)
            case .director:
                people = try await sdk.collectedDirectors(page: 1, limit: 24)
            case .code:
                codes = try await sdk.collectedCodes(page: 1, limit: 24)
            case .series:
                series = try await sdk.collectedSeries(page: 1, limit: 24)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 最近浏览（接口一次返回全部，page/limit 无效）
struct RecentViewedView: View {
    @StateObject private var vm: MovieListViewModel = MovieListViewModel { page in
        if page > 1 { return [] }
        return try await JavDBSDK.shared.recentViewed()
    }

    var body: some View {
        MovieGridView(title: "近期瀏覽", viewModel: vm)
    }
}

/// 会员计划
struct PlansView: View {
    @StateObject private var vm = PlansViewModel()
    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(vm.plans) { plan in
                    VStack(spacing: 8) {
                        Text(plan.name ?? plan.title ?? "VIP")
                            .font(.headline)
                        if let price = plan.price {
                            Text(String(format: "¥%.2f", price))
                                .font(.title2.bold())
                                .foregroundColor(.orange)
                        }
                        if let days = plan.days {
                            Text("\(days)天")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let desc = plan.description {
                            Text(desc)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        Button("购买") {
                            Task { await vm.purchase(plan) }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding()
        }
        .navigationTitle("VIP 会员")
        .liquidGlassList()
        .task { await vm.load() }
    }
}

@MainActor
final class PlansViewModel: ObservableObject {
    @Published var plans: [Plan] = []

    func load() async {
        if let p = try? await JavDBSDK.shared.plansV3() {
            if !p.isEmpty { plans = p; return }
        }
        plans = (try? await JavDBSDK.shared.plansV4()) ?? []
    }

    func purchase(_ plan: Plan) async {
        _ = try? await JavDBSDK.shared.paymentOrder(planID: plan.id ?? 0)
    }
}

/// 钱包
struct WalletView: View {
    @StateObject private var vm = WalletViewModel()

    var body: some View {
        List {
            Section("余额") {
                if let balance = vm.wallet.balance {
                    Text(String(format: "¥%.2f", balance))
                        .font(.title2.bold())
                }
                if let coin = vm.wallet.coin {
                    LabeledContent("金币", value: String(format: "%.2f", coin))
                }
            }
            if let total = vm.wallet.totalIncome {
                Section("累计收益") {
                    LabeledContent("总收入", value: String(format: "¥%.2f", total))
                }
            }
        }
        .navigationTitle("钱包")
        .liquidGlassList()
        .task { await vm.load() }
    }
}

@MainActor
final class WalletViewModel: ObservableObject {
    @Published var wallet = Wallet(balance: nil, coin: nil, totalIncome: nil, pendingIncome: nil)

    func load() async {
        wallet = (try? await JavDBSDK.shared.wallet()) ?? wallet
    }
}

/// 关于
struct AboutView: View {
    @State private var content: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("AVDB")
                    .font(.largeTitle.bold())
                Text("JAVDB 第三方客户端")
                    .foregroundColor(.secondary)
                if let content = content {
                    Text(content)
                        .font(.subheadline)
                        .padding(.top)
                }
            }
            .padding()
        }
        .navigationTitle("关于")
        .liquidGlassPage()
        .task {
            content = try? await JavDBSDK.shared.about()
        }
    }
}
