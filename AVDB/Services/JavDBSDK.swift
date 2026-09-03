//
//  JavDBSDK.swift
//  AVDB
//
//  JAVDB 官方 App 全端点 SDK 封装。
//  覆盖文档第 5 节「其它接口清单」的全部端点。
//

import Foundation

/// 排序方式枚举
public enum MovieSortBy: String {
    case relevance = "relevance"
    case release = "release"
    case rating = "rating"
    case date = "date"

    public static var `default`: MovieSortBy { .release }
}

/// 影片筛选
public enum MovieFilterBy: String {
    case all = "all"
    case cnsub = "has_cnsub"
    case playable = "can_play"
}

/// JAVDB SDK
@MainActor
public final class JavDBSDK {
    public static let shared = JavDBSDK()

    private let client: APIClient = .shared

    private init() {}

    // MARK: - 搜索类

    /// 主搜索（GET /api/v2/search）
    public func search(
        keyword: String,
        page: Int = 1,
        type: String = "movie",
        sortBy: MovieSortBy = .release,
        filterBy: MovieFilterBy = .all,
        limit: Int = 20
    ) async throws -> [Movie] {
        let query: [String: String] = [
            "q": keyword,
            "page": "\(page)",
            "type": type,
            "movie_sort_by": sortBy.rawValue,
            "movie_filter_by": filterBy.rawValue,
            "limit": "\(min(limit, 50))",
        ]
        let resp: JavDBResponse<MovieListData> = try await client.get("/api/v2/search", query: query)
        guard resp.isSuccess else {
            throw JavDBError.apiError(action: resp.action, message: resp.message)
        }
        return resp.data?.movies ?? []
    }

    /// 以图搜图（GET /api/v2/search_image）
    public func searchImage(_ imageURL: String) async throws -> [Movie] {
        let resp: JavDBResponse<MovieListData> = try await client.get(
            "/api/v2/search_image", query: ["image_url": imageURL])
        return resp.data?.movies ?? []
    }

    /// 磁力搜索（GET /api/v1/search_magnet）
    public func searchMagnet(_ keyword: String, page: Int = 1) async throws -> [Magnet] {
        let resp: JavDBResponse<MagnetListData> = try await client.get(
            "/api/v1/search_magnet", query: ["q": keyword, "page": "\(page)"])
        return resp.data?.magnets ?? []
    }

    // MARK: - 影片 / 元数据

    /// 影片详情（GET /api/v4/movies/{id}）
    public func movieDetail(_ id: String, fromRankings: Bool = false) async throws -> Movie {
        let resp: JavDBResponse<MovieDetailData> = try await client.get(
            "/api/v4/movies/\(id)", query: ["from_rankings": fromRankings ? "true" : "false"])
        guard resp.isSuccess else {
            throw JavDBError.apiError(action: resp.action, message: resp.message)
        }
        guard let movie = resp.data?.movie else {
            throw JavDBError.apiError(action: nil, message: "获取详情失败")
        }
        return movie
    }

    /// 影片详情完整数据（含相似推荐/演员影片）
    public func movieDetailFull(_ id: String, fromRankings: Bool = false) async throws -> MovieDetailData {
        let resp: JavDBResponse<MovieDetailData> = try await client.get(
            "/api/v4/movies/\(id)", query: ["from_rankings": fromRankings ? "true" : "false"])
        guard resp.isSuccess else {
            throw JavDBError.apiError(action: resp.action, message: resp.message)
        }
        guard let data = resp.data else {
            throw JavDBError.apiError(action: nil, message: "获取详情失败")
        }
        return data
    }

    /// 磁力列表（GET /api/v1/movies/{id}/magnets）
    public func movieMagnets(_ id: String, page: Int = 1) async throws -> [Magnet] {
        let resp: JavDBResponse<MagnetListData> = try await client.get(
            "/api/v1/movies/\(id)/magnets", query: ["page": "\(page)"])
        return resp.data?.magnets ?? []
    }

    /// 视频流（GET /api/v1/movies/{id}/play，需 VIP token）
    public func moviePlay(_ id: String, sourceID: Int, fromRankings: Bool = false) async throws -> PlayData {
        let resp: JavDBResponse<PlayData> = try await client.get(
            "/api/v1/movies/\(id)/play",
            query: ["source_id": "\(sourceID)", "from_rankings": fromRankings ? "true" : "false"],
            useToken: true)
        guard resp.isSuccess else {
            throw JavDBError.apiError(action: resp.action, message: resp.message)
        }
        return resp.data ?? PlayData(movies: nil, sourceID: nil, sourceName: nil)
    }

    /// 续播（GET /api/v1/movies/{id}/resume_play）
    public func movieResumePlay(_ id: String, sourceID: Int? = nil) async throws -> PlayData {
        var query: [String: String] = [:]
        if let sid = sourceID { query["source_id"] = "\(sid)" }
        let resp: JavDBResponse<PlayData> = try await client.get(
            "/api/v1/movies/\(id)/resume_play", query: query, useToken: true)
        return resp.data ?? PlayData(movies: nil, sourceID: nil, sourceName: nil)
    }

    /// 影评列表（GET /api/v1/movies/{id}/reviews）
    public func movieReviews(_ id: String, page: Int = 1, sortBy: String = "hotly", limit: Int = 24) async throws -> [Review] {
        let resp: JavDBResponse<ReviewListData> = try await client.get(
            "/api/v1/movies/\(id)/reviews",
            query: ["page": "\(page)", "sort_by": sortBy, "limit": "\(limit)"])
        return resp.data?.reviews ?? []
    }

    /// 最新发布（GET /api/v1/movies/latest）
    /// type: all / 0有码 1无码 2欧美 3 FC2 4动漫
    public func latestMovies(
        page: Int = 1,
        limit: Int = 20,
        type: String? = nil,
        filterBy: String? = nil,
        sortBy: String? = nil
    ) async throws -> [Movie] {
        var query = ["page": "\(page)", "limit": "\(min(limit, 50))"]
        if let type { query["type"] = type }
        if let filterBy { query["filter_by"] = filterBy }
        if let sortBy { query["sort_by"] = sortBy }
        let resp: JavDBResponse<MovieListData> = try await client.get("/api/v1/movies/latest", query: query)
        return resp.data?.movies ?? []
    }

    /// TOP250（GET /api/v1/movies/top）
    /// type: all | video_type | year；type_value: 空 / 0有码 1无码 2欧美 3FC2 / 年份
    public func topMovies(
        startRank: Int = 1,
        type: String = "all",
        typeValue: String = "",
        ignoreWatched: Bool = false,
        page: Int = 1,
        limit: Int = 25
    ) async throws -> [Movie] {
        let query: [String: String] = [
            "start_rank": "\(startRank)",
            "type": type,
            "type_value": typeValue,
            "ignore_watched": ignoreWatched ? "true" : "false",
            "page": "\(page)",
            "limit": "\(min(limit, 50))",
        ]
        let resp: JavDBResponse<MovieListData> = try await client.get(
            "/api/v1/movies/top", query: query, useToken: true)
        return resp.data?.movies ?? []
    }

    /// 按标签筛影片（GET /api/v1/movies/tags）
    public func moviesByTag(filterBy: String, type: String? = nil, page: Int = 1) async throws -> [Movie] {
        var query = ["filter_by": filterBy, "page": "\(page)"]
        if let type { query["type"] = type }
        let resp: JavDBResponse<MovieListData> = try await client.get("/api/v1/movies/tags", query: query)
        return resp.data?.movies ?? []
    }

    /// 标签/分类（兼容旧调用）
    public func movieTags() async throws -> [Tag] {
        let groups = try await tagGroups(type: "0")
        return groups.flatMap { $0.tags ?? [] }
    }

    /// 推荐（GET /api/v1/movies/recommend）
    public func recommendMovies(page: Int = 1, period: Int? = nil) async throws -> [Movie] {
        var query = ["page": "\(page)"]
        if let period { query["period"] = "\(period)" }
        else { query["period"] = "-1" }
        let resp: JavDBResponse<RecommendMoviesData> = try await client.get(
            "/api/v1/movies/recommend", query: query)
        return resp.data?.movies ?? []
    }

    /// 推荐时间段（GET /api/v1/movies/recommend_periods）
    public func recommendPeriods() async throws -> [RecommendPeriod] {
        let resp: JavDBResponse<RecommendPeriodListData> = try await client.get("/api/v1/movies/recommend_periods")
        return resp.data?.periods ?? []
    }

    /// 相似推荐（GET /api/v1/movies/may_also_like）
    public func mayAlsoLike(_ id: String) async throws -> [Movie] {
        let resp: JavDBResponse<MovieListData> = try await client.get(
            "/api/v1/movies/may_also_like", query: ["id": id, "limit": "9"])
        return resp.data?.movies ?? []
    }

    // MARK: - 演员 / 导演 / 系列 / 片商 / 发行商

    /// 演员列表（GET /api/v1/actors）
    /// type: 0有码 1无码 2欧美 3 FC2；gender: 0女 1男
    public func actors(page: Int = 1, type: String = "0", gender: String? = nil) async throws -> [Actor] {
        var query = ["page": "\(page)", "type": type]
        if let gender { query["gender"] = gender }
        let resp: JavDBResponse<ActorListData> = try await client.get("/api/v1/actors", query: query)
        return resp.data?.actors ?? []
    }

    /// 演员详情（GET /api/v1/actors/{id}）
    public func actorDetail(_ id: String) async throws -> Actor {
        struct ActorDetailData: Decodable { let actor: Actor? }
        let resp: JavDBResponse<ActorDetailData> = try await client.get("/api/v1/actors/\(id)")
        guard let actor = resp.data?.actor else {
            throw JavDBError.apiError(action: nil, message: "获取演员失败")
        }
        return actor
    }

    /// 演员推荐（GET /api/v1/actors/recommend）
    public func recommendActors() async throws -> ActorRecommendData {
        let resp: JavDBResponse<ActorRecommendData> = try await client.get("/api/v1/actors/recommend")
        return resp.data ?? ActorRecommendData(newActors: nil, monthlyActors: nil, recommendActors: nil)
    }

    /// 导演详情（GET /api/v1/directors/{id}）
    public func directorDetail(_ id: String) async throws -> Movie? {
        let resp: JavDBResponse<MovieDetailData> = try await client.get("/api/v1/directors/\(id)")
        return resp.data?.movie
    }

    /// 系列详情（GET /api/v1/series/{id}）
    public func seriesDetail(_ id: String) async throws -> Movie? {
        let resp: JavDBResponse<MovieDetailData> = try await client.get("/api/v1/series/\(id)")
        return resp.data?.movie
    }

    /// 系列字母索引（GET /api/v1/series/letters）
    public func seriesLetters() async throws -> [String] {
        let resp: JavDBResponse<StringListData> = try await client.get("/api/v1/series/letters")
        return resp.data?.items ?? []
    }

    /// 片商列表（GET /api/v1/makers）
    public func makers() async throws -> [Actor] {
        let resp: JavDBResponse<ActorListData> = try await client.get("/api/v1/makers")
        return resp.data?.actors ?? []
    }

    /// 片商详情（GET /api/v1/makers/{id}）
    public func makerDetail(_ id: String) async throws -> Movie? {
        let resp: JavDBResponse<MovieDetailData> = try await client.get("/api/v1/makers/\(id)")
        return resp.data?.movie
    }

    /// 发行商详情（GET /api/v1/publishers/{id}）
    public func publisherDetail(_ id: String) async throws -> Movie? {
        let resp: JavDBResponse<MovieDetailData> = try await client.get("/api/v1/publishers/\(id)")
        return resp.data?.movie
    }

    /// 排行榜（GET /api/v1/rankings）
    /// type: 0有码 1无码 2欧美 3 FC2；period: daily/weekly/monthly
    public func rankings(type: String, period: String, page: Int = 1) async throws -> [Movie] {
        let resp: JavDBResponse<MovieListData> = try await client.get(
            "/api/v1/rankings",
            query: ["type": type, "period": period, "page": "\(page)"])
        return resp.data?.movies ?? []
    }

    /// 演员排行榜（GET /api/v1/rankings/actors）
    public func actorRankings(type: String = "0", period: String = "monthly", page: Int = 1) async throws -> [Actor] {
        let resp: JavDBResponse<ActorListData> = try await client.get(
            "/api/v1/rankings/actors",
            query: ["type": type, "period": period, "page": "\(page)"])
        return resp.data?.actors ?? []
    }

    /// 热播排行（GET /api/v1/rankings/playback）
    public func playbackRankings(filterBy: String = "all", period: String = "daily", page: Int = 1) async throws -> [Movie] {
        let resp: JavDBResponse<MovieListData> = try await client.get(
            "/api/v1/rankings/playback",
            query: ["filter_by": filterBy, "period": period, "page": "\(page)"])
        return resp.data?.movies ?? []
    }

    /// 筛选项（GET /api/v2/tags）type: 0有码 1无码 2欧美 3 FC2
    public func tagGroups(type: String) async throws -> [TagGroup] {
        let resp: JavDBResponse<TagGroupListData> = try await client.get("/api/v2/tags", query: ["type": type])
        return resp.data?.tags ?? []
    }

    /// 广告（GET /api/v1/ads）
    public func adsPayload() async throws -> AdsData {
        let resp: JavDBResponse<AdsData> = try await client.get("/api/v1/ads")
        return resp.data ?? AdsData(enabled: nil, ads: nil)
    }

    // MARK: - 片单 / 标签 / 影评 / 文章

    /// 片单列表（GET /api/v1/lists）
    public func lists(page: Int = 1) async throws -> [MovieList] {
        struct ListData: Decodable { let lists: [MovieList]? }
        let resp: JavDBResponse<ListData> = try await client.get("/api/v1/lists", query: ["page": "\(page)"])
        return resp.data?.lists ?? []
    }

    /// 简单片单（GET /api/v1/lists/simple）
    public func simpleLists() async throws -> [MovieList] {
        struct ListData: Decodable { let lists: [MovieList]? }
        let resp: JavDBResponse<ListData> = try await client.get("/api/v1/lists/simple")
        return resp.data?.lists ?? []
    }

    /// 相关片单（GET /api/v1/lists/related?movie_id=）
    public func relatedLists(_ movieID: String, page: Int = 1, limit: Int = 24) async throws -> [MovieList] {
        struct ListData: Decodable {
            let lists: [MovieList]?
            let currentPage: Int?
            enum CodingKeys: String, CodingKey {
                case lists
                case currentPage = "current_page"
            }
        }
        let resp: JavDBResponse<ListData> = try await client.get(
            "/api/v1/lists/related",
            query: ["movie_id": movieID, "page": "\(page)", "limit": "\(limit)"])
        return resp.data?.lists ?? []
    }

    /// 片单元数据（GET /api/v1/lists/{id}）只有名称/计数，没有影片。
    public func listInfo(_ id: String) async throws -> MovieList? {
        struct Wrap: Decodable { let list: MovieList? }
        let resp: JavDBResponse<Wrap> = try await client.get("/api/v1/lists/\(id)")
        return resp.data?.list
    }

    /// 片单影片（GET /api/v1/lists/{id}/movies）
    public func listMovies(_ id: String, page: Int = 1, limit: Int = 21) async throws -> [Movie] {
        let resp: JavDBResponse<MovieListData> = try await client.get(
            "/api/v1/lists/\(id)/movies",
            query: ["page": "\(page)", "limit": "\(limit)"])
        if let movies = resp.data?.movies, !movies.isEmpty { return movies }
        let fallback: JavDBResponse<MovieListData> = try await client.get(
            "/api/v1/lists/\(id)",
            query: ["page": "\(page)", "limit": "\(limit)"])
        return fallback.data?.movies ?? []
    }

    /// 兼容旧调用
    public func listDetail(_ id: String) async throws -> [Movie] {
        try await listMovies(id)
    }

    /// 关注的标签（GET /api/v1/following_tags）
    public func followingTags() async throws -> [Tag] {
        let resp: JavDBResponse<TagListData> = try await client.get("/api/v1/following_tags", useToken: true)
        return resp.data?.tags ?? []
    }

    /// 标签（GET /api/v2/tags）
    public func tags() async throws -> [Tag] {
        let resp: JavDBResponse<TagListData> = try await client.get("/api/v2/tags")
        return resp.data?.tags ?? []
    }

    /// 热门影评（GET /api/v1/reviews/hotly）
    public func hotReviews() async throws -> [Review] {
        let resp: JavDBResponse<ReviewListData> = try await client.get("/api/v1/reviews/hotly")
        return resp.data?.reviews ?? []
    }

    /// 文章列表（GET /api/v1/articles）
    public func articles(page: Int = 1) async throws -> [Article] {
        struct ArticleData: Decodable { let articles: [Article]? }
        let resp: JavDBResponse<ArticleData> = try await client.get("/api/v1/articles", query: ["page": "\(page)"])
        return resp.data?.articles ?? []
    }

    // MARK: - 登录 / 用户

    /// 登录（POST /api/v1/sessions）
    public func login(username: String, password: String) async throws -> User {
        let deviceUUID = UUID().uuidString
        let form: [String: String] = [
            "username": username,
            "password": password,
            "device_uuid": deviceUUID,
            "device_name": "AVDB",
            "device_model": "iPhone",
            "platform": "ios",
            "system_version": "18.0",
            "app_channel": "official",
            "app_version": "official",
            "app_version_number": "1.9.28",
        ]
        let resp: JavDBResponse<SessionData> = try await client.post("/api/v1/sessions", form: form)
        guard resp.isSuccess, let token = resp.data?.token, let user = resp.data?.user else {
            throw JavDBError.apiError(action: resp.action, message: resp.message ?? "登录失败")
        }
        client.setToken(token)
        client.currentUser = user
        return user
    }

    /// 登出
    public func logout() {
        client.setToken(nil)
        client.currentUser = nil
    }

    /// 用户信息（GET /api/v1/users，需 token）
    public func userInfo() async throws -> User {
        let resp: JavDBResponse<UserData> = try await client.get("/api/v1/users", useToken: true)
        guard resp.isSuccess, let user = resp.data?.user else {
            throw JavDBError.apiError(action: resp.action, message: resp.message)
        }
        client.currentUser = user
        return user
    }

    /// 最近浏览（GET /api/v1/users/recent_viewed）
    public func recentViewed() async throws -> [Movie] {
        let resp: JavDBResponse<MovieListData> = try await client.get(
            "/api/v1/users/recent_viewed", useToken: true)
        return resp.data?.movies ?? []
    }

    /// 收藏的演员/番号/导演/片商/系列/片单（GET /api/v1/users/collected_*）
    public func collectedActors() async throws -> [Actor] {
        let resp: JavDBResponse<ActorListData> = try await client.get(
            "/api/v1/users/collected_actors", useToken: true)
        return resp.data?.actors ?? []
    }
    public func collectedCodes() async throws -> [Code] {
        struct CodeData: Decodable { let codes: [Code]? }
        let resp: JavDBResponse<CodeData> = try await client.get(
            "/api/v1/users/collected_codes", useToken: true)
        return resp.data?.codes ?? []
    }
    public func collectedDirectors() async throws -> [Actor] {
        let resp: JavDBResponse<ActorListData> = try await client.get(
            "/api/v1/users/collected_directors", useToken: true)
        return resp.data?.actors ?? []
    }
    public func collectedMakers() async throws -> [Actor] {
        let resp: JavDBResponse<ActorListData> = try await client.get(
            "/api/v1/users/collected_makers", useToken: true)
        return resp.data?.actors ?? []
    }
    public func collectedSeries() async throws -> [Movie] {
        let resp: JavDBResponse<MovieListData> = try await client.get(
            "/api/v1/users/collected_series", useToken: true)
        return resp.data?.movies ?? []
    }
    public func collectedLists() async throws -> [MovieList] {
        struct ListData: Decodable { let lists: [MovieList]? }
        let resp: JavDBResponse<ListData> = try await client.get(
            "/api/v1/users/collected_lists", useToken: true)
        return resp.data?.lists ?? []
    }

    /// 用户反馈（POST /api/v1/users/feedback）
    public func submitFeedback(content: String) async throws -> Bool {
        let resp: JavDBResponse<EmptyData> = try await client.post(
            "/api/v1/users/feedback", form: ["content": content], useToken: true)
        return resp.isSuccess
    }

    /// 用户的影评影片（GET /api/v2/users/review_movies）
    public func reviewMovies() async throws -> [Movie] {
        let resp: JavDBResponse<MovieListData> = try await client.get(
            "/api/v2/users/review_movies", useToken: true)
        return resp.data?.movies ?? []
    }

    /// 某用户的影评（GET /api/v2/users/{id}/reviews）
    public func userReviews(_ userID: Int) async throws -> [Review] {
        let resp: JavDBResponse<ReviewListData> = try await client.get(
            "/api/v2/users/\(userID)/reviews")
        return resp.data?.reviews ?? []
    }

    // MARK: - 上报 / 广告 / 其它

    /// 启动配置（GET /api/v1/startup）
    public func startup() async throws -> StartupData {
        let resp: JavDBResponse<StartupData> = try await client.get("/api/v1/startup")
        return resp.data ?? StartupData(splashAd: nil, user: nil, backupDomainsData: nil, recentKeywords: nil)
    }

    /// 关于（GET /api/v1/about）
    public func about() async throws -> String? {
        struct AboutData: Decodable { let content: String? }
        let resp: JavDBResponse<AboutData> = try await client.get("/api/v1/about")
        return resp.data?.content
    }

    /// 帮助（GET /api/v1/helps）
    public func helps() async throws -> [Article] {
        struct HelpData: Decodable { let helps: [Article]? }
        let resp: JavDBResponse<HelpData> = try await client.get("/api/v1/helps")
        return resp.data?.helps ?? []
    }

    /// 广告（GET /api/v1/ads）
    public func ads() async throws -> StartupData.SplashAd.AdInfo? {
        struct AdData: Decodable { let ad: StartupData.SplashAd.AdInfo? }
        let resp: JavDBResponse<AdData> = try await client.get("/api/v1/ads")
        return resp.data?.ad
    }

    /// 上报影片播放（POST /api/v1/logs/movie_played）
    public func reportMoviePlayed(movieID: String, sourceID: Int? = nil) async throws -> Bool {
        var form = ["movie_id": movieID]
        if let sid = sourceID { form["source_id"] = "\(sid)" }
        let resp: JavDBResponse<EmptyData> = try await client.post("/api/v1/logs/movie_played", form: form, useToken: true)
        return resp.isSuccess
    }

    /// 上报激活（POST /api/v2/logs/activated）
    public func reportActivated() async throws -> Bool {
        let resp: JavDBResponse<EmptyData> = try await client.post("/api/v2/logs/activated", form: [:], useToken: true)
        return resp.isSuccess
    }

    /// 磁力应用（GET /api/v1/magnet_apps）
    public func magnetApps() async throws -> [MagnetApp] {
        struct AppData: Decodable { let apps: [MagnetApp]? }
        let resp: JavDBResponse<AppData> = try await client.get("/api/v1/magnet_apps")
        return resp.data?.apps ?? []
    }

    /// 番号详情（GET /api/v1/codes/{id}）
    public func codeDetail(_ id: String) async throws -> Code? {
        struct CodeData: Decodable { let code: Code? }
        let resp: JavDBResponse<CodeData> = try await client.get("/api/v1/codes/\(id)")
        return resp.data?.code
    }

    /// 番号收藏动作（GET /api/v1/codes/{id}/collect_actions）
    public func codeCollectActions(_ id: String) async throws -> Bool {
        let resp: JavDBResponse<EmptyData> = try await client.get(
            "/api/v1/codes/\(id)/collect_actions", useToken: true)
        return resp.isSuccess
    }

    // MARK: - 会员 / 钱包

    /// 会员计划 v3（GET /api/v3/plans）
    public func plansV3() async throws -> [Plan] {
        struct PlanData: Decodable { let plans: [Plan]? }
        let resp: JavDBResponse<PlanData> = try await client.get("/api/v3/plans")
        return resp.data?.plans ?? []
    }

    /// 会员计划 v4（GET /api/v4/plans）
    public func plansV4() async throws -> [Plan] {
        struct PlanData: Decodable { let plans: [Plan]? }
        let resp: JavDBResponse<PlanData> = try await client.get("/api/v4/plans")
        return resp.data?.plans ?? []
    }

    /// 支付订单（GET /api/v2/plans/payment_order）
    public func paymentOrder(planID: Int) async throws -> String? {
        struct OrderData: Decodable { let orderID: String? }
        let resp: JavDBResponse<OrderData> = try await client.get(
            "/api/v2/plans/payment_order", query: ["plan_id": "\(planID)"], useToken: true)
        return resp.data?.orderID
    }

    /// 钱包（GET /api/v1/wallets）
    public func wallet() async throws -> Wallet {
        let resp: JavDBResponse<Wallet> = try await client.get("/api/v1/wallets", useToken: true)
        return resp.data ?? Wallet(balance: nil, coin: nil, totalIncome: nil, pendingIncome: nil)
    }

    /// 提现（GET /api/v2/wallets/withdraw）
    public func withdraw(amount: Double) async throws -> Bool {
        let resp: JavDBResponse<EmptyData> = try await client.get(
            "/api/v2/wallets/withdraw", query: ["amount": "\(amount)"], useToken: true)
        return resp.isSuccess
    }

    /// 提现记录（GET /api/v1/wallets/withdraw_logs）
    public func withdrawLogs() async throws -> [[String: String]] {
        struct LogsData: Decodable { let logs: [[String: String]]? }
        let resp: JavDBResponse<LogsData> = try await client.get(
            "/api/v1/wallets/withdraw_logs", useToken: true)
        return resp.data?.logs ?? []
    }
}

// MARK: - 辅助响应 data 结构

/// 标签列表
public struct TagListData: Decodable {
    public let tags: [Tag]?
}

/// 演员列表
public struct ActorListData: Decodable {
    public let actors: [Actor]?
}

/// 影评列表
public struct ReviewListData: Decodable {
    public let reviews: [Review]?
}

/// 字符串列表
public struct StringListData: Codable {
    public let items: [String]?

    enum CodingKeys: String, CodingKey {
        case items
    }
}
