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
                    // Native account navigation remains available with a cached profile.
                    if appState.sessionStatus == .cached {
                        Text("已恢复本机资料；网络异常不影响账户入口，连接恢复后自动同步")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 1)
                                    .frame(width: 76, height: 76)
                                JavDBImage(url: user.avatarURL)
                                    .frame(width: 64, height: 64)
                                    .clipShape(Circle())
                                    .overlay {
                                        Circle().strokeBorder(
                                            LinearGradient(
                                                colors: [.white.opacity(0.7), .white.opacity(0.15)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.5
                                        )
                                    }
                                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(user.displayName)
                                    .font(.headline)
                                HStack(spacing: 8) {
                                    if user.isVip == true {
                                        GlassChip(
                                            text: "VIP 会员",
                                            tint: .orange,
                                            font: .caption.weight(.semibold),
                                            foreground: .white,
                                            compact: false,
                                            tintStrength: 0.68
                                        )
                                    }
                                    if let n = user.wantWatchCount {
                                        GlassChip(
                                            text: "想看 \(n)",
                                            tint: .blue,
                                            font: .caption2,
                                            foreground: .secondary,
                                            compact: true,
                                            tintStrength: 0.10
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
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
                        NavigationLink { WatchLaterView() } label: {
                            Label("稍后再看", systemImage: "clock")
                        }
                        NavigationLink { UpdateNoticesView() } label: {
                            Label("新作提醒", systemImage: "bell")
                        }
                        NavigationLink { DownloadQueueView() } label: {
                            Label("下载队列", systemImage: "arrow.down.circle")
                        }
                        NavigationLink { DrawHistoryView() } label: {
                            Label("抽签历史", systemImage: "sparkles")
                        }
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
                            appState.logout()
                        }
                    }

                } else if appState.isLoggedIn {
                    Section("正在恢复账户") {
                        Label(appState.sessionStatus == .unavailable ? "账户服务暂时不可用" : "正在自动加载个人资料", systemImage: "person.crop.circle")
                        Text("系统会自动重试；本轮重试结束后，将在回到前台或连接恢复时继续，无需手动加载。")
                            .font(.footnote).foregroundStyle(.secondary)

                    }
                } else {
                    // 未登录
                    if appState.sessionStatus == .needsReauth {
                        Text("服务器已拒绝登录凭证，请重新登录")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section {
                        Button {
                            GlassHaptic.tap()
                            showLogin = true
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 1)
                                        .frame(width: 56, height: 56)
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .font(.system(size: 28, weight: .light))
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 48, height: 48)
                                        .liquidGlassCircle(tint: Color.accentColor.opacity(0.2))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("登录 / 注册")
                                        .font(.headline)
                                    Text("同步关注、收藏与观看记录")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .pressableGlass(scale: 0.98)
                    }
                }

                Section("下载") {
                    NavigationLink {
                        Pan115SettingsView()
                    } label: {
                        HStack {
                            Label("115 离线", systemImage: "icloud.and.arrow.down")
                            Spacer()
                            GlassChip(
                                text: pan115.isConfigured ? "已配置" : "未配置",
                                tint: pan115.isConfigured ? .green : .gray,
                                font: .caption2,
                                foreground: pan115.isConfigured ? .green : .secondary,
                                compact: true,
                                tintStrength: pan115.isConfigured ? 0.16 : 0.08
                            )
                        }
                    }
                }

                Section("来源") {
                    NavigationLink {
                        ExternalLibrarySettingsView()
                    } label: {
                        Label("外部数据库", systemImage: "externaldrive.badge.person.crop")
                    }
                    .accessibilityIdentifier("external-settings-entry")
                    NavigationLink {
                        JavRankingView()
                    } label: {
                        Label("JAV Ranking", systemImage: "list.number")
                    }
                }

                Section("关于") {
                    NavigationLink("关于 AVDB") {
                        AboutView()
                    }
                }
            }
            .frame(maxWidth: AdaptiveLayout.isPad ? 760 : .infinity)
            .frame(maxWidth: .infinity)
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
    @Environment(\.availableLayoutSize) private var layoutSize

    private var columns: [GridItem] {
        let count = AdaptiveLayout.columnCount(width: layoutSize.width, padding: AdaptiveLayout.gridPadding, spacing: 14)
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
                                    .liquidCover(cornerRadius: 12)
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

/// Token input is intentionally never populated from Keychain.
struct ExternalLibrarySettingsView: View {
    @ObservedObject private var settings = ExternalLibrarySettings.shared
    @State private var baseURL = ""
    @State private var enabled = false
    @State private var token = ""
    @State private var message: String?
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section("外部数据库") {
                Toggle("启用外部数据库", isOn: $enabled)
                    .accessibilityIdentifier("external-enabled")
                TextField("服务器根地址", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .accessibilityIdentifier("external-base-url")
                SecureField("新令牌（留空保留已保存令牌）", text: $token)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                    .accessibilityIdentifier("external-token")
                Text(settings.hasToken ? "令牌已保存（不显示内容）" : "未配置令牌，不会发送请求")
                    .accessibilityIdentifier("external-token-status")
                if let error = settings.storageError {
                    Text(error).foregroundStyle(.red)
                }
            }
            Section {
                Button("保存设置") {
                    do {
                        try settings.save(baseURL: baseURL, enabled: enabled, replacementToken: token)
                        token = ""
                        baseURL = settings.baseURL
                        message = "设置已保存，后续查询立即使用新设置。"
                    } catch { message = error.localizedDescription }
                }
                .accessibilityIdentifier("external-save")
                Button("清除已保存令牌", role: .destructive) { confirmClear = true }
                    .accessibilityIdentifier("external-clear")
                if let message { Text(message).font(.footnote) }
            } footer: {
                Text("令牌仅存于本机钥匙串，不会显示或复制。留空保存不会清除令牌；返回将放弃未保存的编辑。更换服务器须重新填写令牌，或先清除旧令牌。停用后不查询。")
            }
            Section("传输风险") {
                Text("HTTP 未加密：令牌与查询内容可能被网络中间人读取或篡改。默认服务器使用 HTTP；请仅在知晓风险时启用，建议改用可信的 HTTPS 服务。钥匙串保护本机存储，不会让 HTTP 变安全。")
                    .foregroundStyle(.orange)
                Text("所有重定向均拒绝。请直接填写最终服务器根地址。未配置令牌时不请求；本页不会自动验证或发送账号数据。")
                    .font(.footnote)
            }
        }
        .navigationTitle("外部数据库")
        .onAppear {
            settings.refreshStatus()
            baseURL = settings.baseURL
            enabled = settings.enabled
        }
        .onDisappear { token = "" }
        .confirmationDialog("清除后外部数据库将停止查询，直到重新保存令牌。", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清除令牌", role: .destructive) {
                do {
                    try settings.clearToken()
                    token = ""
                    message = "已清除令牌，不再发送外部数据库请求。"
                } catch { message = error.localizedDescription }
            }
            Button("取消", role: .cancel) { }
        }
    }
}
