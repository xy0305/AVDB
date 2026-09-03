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
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section("我的收藏") {
                        NavigationLink("收藏的演员") {
                            CollectedView(kind: .actor)
                        }
                        NavigationLink("收藏的番号") {
                            CollectedView(kind: .code)
                        }
                        NavigationLink("收藏的系列") {
                            CollectedView(kind: .series)
                        }
                        NavigationLink("最近浏览") {
                            RecentViewedView()
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
            .sheet(isPresented: $showLogin) {
                LoginView()
            }
        }
    }
}

/// 收藏视图
struct CollectedView: View {
    enum Kind: String {
        case actor = "演员"
        case code = "番号"
        case series = "系列"
    }
    let kind: Kind
    @StateObject private var vm = CollectedViewModel()

    var body: some View {
        List {
            switch kind {
            case .actor:
                ForEach(vm.actors) { actor in
                    NavigationLink(actor.name ?? "") {
                        ActorDetailView(actorID: actor.id)
                    }
                }
            case .code:
                ForEach(vm.codes) { code in
                    Text(code.number ?? code.title ?? "")
                }
            case .series:
                ForEach(vm.series) { movie in
                    NavigationLink(movie.displayNumber) {
                        MovieDetailView(movieID: movie.id)
                    }
                }
            }
            if vm.isLoading { ProgressView() }
        }
        .navigationTitle("收藏的\(kind.rawValue)")
        .task { await vm.load(kind) }
    }
}

@MainActor
final class CollectedViewModel: ObservableObject {
    @Published var actors: [Actor] = []
    @Published var codes: [Code] = []
    @Published var series: [Movie] = []
    @Published var isLoading = false

    func load(_ kind: CollectedView.Kind) async {
        isLoading = true
        defer { isLoading = false }
        let sdk = JavDBSDK.shared
        switch kind {
        case .actor:
            actors = (try? await sdk.collectedActors()) ?? []
        case .code:
            codes = (try? await sdk.collectedCodes()) ?? []
        case .series:
            series = (try? await sdk.collectedSeries()) ?? []
        }
    }
}

/// 最近浏览
struct RecentViewedView: View {
    @StateObject private var vm: MovieListViewModel = MovieListViewModel { _ in
        try await JavDBSDK.shared.recentViewed()
    }

    var body: some View {
        MovieGridView(title: "最近浏览", viewModel: vm)
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
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
        .navigationTitle("VIP 会员")
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
        .task {
            content = try? await JavDBSDK.shared.about()
        }
    }
}
