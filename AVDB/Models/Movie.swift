//
//  Movie.swift
//  AVDB
//
//  影片及相关数据模型（snake_case 字段，兼容 API 返回值）。
//

import Foundation

/// 影片通用模型
public struct Movie: Decodable, Identifiable, Hashable {
    public let id: String
    public let type: String?
    public let number: String?
    public let numberLetter: String?
    public let title: String?
    public let originTitle: String?
    public let summary: String?
    public let desc: String?
    public let thumbURL: String?
    public let coverURL: String?
    public let duration: Int?
    public let score: Double?
    public let rating: Double?
    public let releaseDate: String?

    public let magnetsCount: Int?
    public let canPlay: Bool?
    public let playSubtitle: String?
    public let hasPreviewVideo: Bool?
    public let hasCnsub: Bool?
    public let hasPreviewImages: Bool?

    public let tags: [Tag]?
    public let category: String?
    public let actors: [Actor]?
    public let actorNames: [String]?

    public let makerID: String?
    public let makerName: String?
    public let directorID: String?
    public let directorName: String?
    public let publisherID: String?
    public let publisherName: String?
    public let seriesID: String?
    public let seriesName: String?

    public let fileSize: Int?
    public let reviewsCount: Int?
    public let commentsCount: Int?
    public let wantWatchCount: Int?
    public let watchedCount: Int?

    public let newMagnets: [Magnet]?
    public let hasNewMagnets: Bool
    public let previewImages: [PreviewImage]?
    public let playSources: [PlaySource]?
    public let previewVideoURL: String?
    public let relativeMovies: [Movie]?
    public let actorMovies: [Movie]?

    // 派生字段
    public var displayTitle: String { title ?? number ?? "未知影片" }
    public var displayNumber: String { number ?? id }
    public var scoreText: String {
        guard let s = score, s > 0 else { return "N/A" }
        return String(format: "%.2f", s)
    }

    enum CodingKeys: String, CodingKey {
        case id, type, number, title, summary, desc, duration, score, rating, category
        case numberLetter = "number_letter"
        case originTitle = "origin_title"
        case thumbURL = "thumb_url"
        case coverURL = "cover_url"
        case releaseDate = "release_date"
        case magnetsCount = "magnets_count"
        case canPlay = "can_play"
        case playSubtitle = "play_subtitle"
        case hasPreviewVideo = "has_preview_video"
        case hasCnsub = "has_cnsub"
        case hasPreviewImages = "has_preview_images"
        case tags, actors
        case actorNames = "actor_names"
        case makerID = "maker_id"
        case makerName = "maker_name"
        case directorID = "director_id"
        case directorName = "director_name"
        case publisherID = "publisher_id"
        case publisherName = "publisher_name"
        case seriesID = "series_id"
        case seriesName = "series_name"
        case fileSize = "file_size"
        case reviewsCount = "reviews_count"
        case commentsCount = "comments_count"
        case wantWatchCount = "want_watch_count"
        case watchedCount = "watched_count"
        case newMagnets = "new_magnets"
        case previewImages = "preview_images"
        case playSources = "play_sources"
        case previewVideoURL = "preview_video_url"
        case relativeMovies = "relative_movies"
        case actorMovies = "actor_movies"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = JSONFlex.string(c, .id) ?? ""
        type = JSONFlex.string(c, .type)
        number = JSONFlex.string(c, .number)
        numberLetter = JSONFlex.string(c, .numberLetter)
        title = try? c.decode(String.self, forKey: .title)
        originTitle = try? c.decode(String.self, forKey: .originTitle)
        summary = try? c.decode(String.self, forKey: .summary)
        desc = try? c.decode(String.self, forKey: .desc)
        thumbURL = try? c.decode(String.self, forKey: .thumbURL)
        coverURL = try? c.decode(String.self, forKey: .coverURL)
        duration = JSONFlex.int(c, .duration)
        score = JSONFlex.double(c, .score)
        rating = JSONFlex.double(c, .rating)
        releaseDate = JSONFlex.string(c, .releaseDate)
        magnetsCount = JSONFlex.int(c, .magnetsCount)
        canPlay = JSONFlex.bool(c, .canPlay)
        playSubtitle = JSONFlex.string(c, .playSubtitle)
        hasPreviewVideo = JSONFlex.bool(c, .hasPreviewVideo)
        hasCnsub = JSONFlex.bool(c, .hasCnsub)
        hasPreviewImages = JSONFlex.bool(c, .hasPreviewImages)
        tags = try? c.decode([Tag].self, forKey: .tags)
        category = JSONFlex.string(c, .category)
        actors = try? c.decode([Actor].self, forKey: .actors)
        actorNames = try? c.decode([String].self, forKey: .actorNames)
        makerID = JSONFlex.string(c, .makerID)
        makerName = try? c.decode(String.self, forKey: .makerName)
        directorID = JSONFlex.string(c, .directorID)
        directorName = try? c.decode(String.self, forKey: .directorName)
        publisherID = JSONFlex.string(c, .publisherID)
        publisherName = try? c.decode(String.self, forKey: .publisherName)
        seriesID = JSONFlex.string(c, .seriesID)
        seriesName = try? c.decode(String.self, forKey: .seriesName)
        fileSize = JSONFlex.int(c, .fileSize)
        reviewsCount = JSONFlex.int(c, .reviewsCount)
        commentsCount = JSONFlex.int(c, .commentsCount)
        wantWatchCount = JSONFlex.int(c, .wantWatchCount)
        watchedCount = JSONFlex.int(c, .watchedCount)
        if let flag = JSONFlex.bool(c, .newMagnets) {
            newMagnets = nil
            hasNewMagnets = flag
        } else if let list = try? c.decode([Magnet].self, forKey: .newMagnets) {
            newMagnets = list
            hasNewMagnets = !list.isEmpty
        } else {
            newMagnets = nil
            hasNewMagnets = false
        }
        previewImages = try? c.decode([PreviewImage].self, forKey: .previewImages)
        playSources = try? c.decode([PlaySource].self, forKey: .playSources)
        previewVideoURL = try? c.decode(String.self, forKey: .previewVideoURL)
        relativeMovies = try? c.decode([Movie].self, forKey: .relativeMovies)
        actorMovies = try? c.decode([Movie].self, forKey: .actorMovies)
    }

    /// 播放角标。官方 `play_subtitle` 经常是 1/0，不是文案。
    public var playBadge: String? {
        if let s = playSubtitle, !s.isEmpty,
           s != "0", s != "1", s != "true", s != "false" {
            return s
        }
        if canPlay == true || playSubtitle == "1" || playSubtitle == "true" {
            return hasCnsub == true ? "中字可播放" : "可播放"
        }
        return nil
    }

    public var magnetStatusText: String? {
        let count = magnetsCount ?? 0
        if count <= 0 { return nil }
        if hasCnsub == true { return "含中字磁鏈" }
        return "含磁鏈"
    }

    public var isNewMagnet: Bool { hasNewMagnets }
}

/// 标签
public struct Tag: Decodable, Identifiable, Hashable {
    public let id: String
    public let name: String?
    public let coverURL: String?
    public let count: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, count
        case coverURL = "cover_url"
        case videosCount = "videos_count"
    }

    public init(id: String, name: String?, coverURL: String? = nil, count: Int? = nil) {
        self.id = id
        self.name = name
        self.coverURL = coverURL
        self.count = count
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = JSONFlex.string(c, .id) ?? ""
        name = try? c.decode(String.self, forKey: .name)
        coverURL = try? c.decode(String.self, forKey: .coverURL)
        count = JSONFlex.int(c, .count) ?? JSONFlex.int(c, .videosCount)
    }
}

/// v2/tags 分组（基本 / 年份 / 月份 / 主题…）
public struct TagGroup: Decodable, Identifiable, Hashable {
    public let category: String?
    public let categoryID: String?
    public let tags: [Tag]?

    public var id: String { categoryID ?? category ?? "taggroup" }

    enum CodingKeys: String, CodingKey {
        case category, tags
        case categoryID = "category_id"
    }
}

public struct TagGroupListData: Decodable {
    public let tags: [TagGroup]?
}

/// 演员
public struct Actor: Decodable, Identifiable, Hashable {
    public let id: String
    public let name: String?
    public let otherName: String?
    public let avatarURL: String?
    public let coverURL: String?
    public let birthday: String?
    public let age: Int?
    public let height: Int?
    public let cup: String?
    public let bloodType: String?
    public let hobby: String?
    public let heightText: String?
    public let gender: Int?
    public let type: Int?
    public let videosCount: Int?
    public let nameZht: String?
    public let twitterID: String?
    public let instagramID: String?
    public let bust: String?
    public let waist: String?
    public let hips: String?
    public let birthplace: String?
    public let cons: String?

    public var displayName: String {
        if let z = nameZht, !z.isEmpty { return z }
        if let other = otherName, !other.isEmpty { return other }
        return name ?? id
    }

    enum CodingKeys: String, CodingKey {
        case id, name, age, height, cup, hobby, gender, type, birthday, cons
        case otherName = "other_name"
        case avatarURL = "avatar_url"
        case coverURL = "cover_url"
        case bloodType = "blood_type"
        case heightText = "height_text"
        case videosCount = "videos_count"
        case nameZht = "name_zht"
        case twitterID = "twitter_id"
        case instagramID = "instagram_id"
        case bust, waist, hips, birthplace
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = JSONFlex.string(c, .id) ?? ""
        name = try? c.decode(String.self, forKey: .name)
        otherName = try? c.decode(String.self, forKey: .otherName)
        avatarURL = try? c.decode(String.self, forKey: .avatarURL)
        coverURL = try? c.decode(String.self, forKey: .coverURL)
        birthday = JSONFlex.string(c, .birthday)
        age = JSONFlex.int(c, .age)
        height = JSONFlex.int(c, .height)
        cup = JSONFlex.string(c, .cup)
        bloodType = try? c.decode(String.self, forKey: .bloodType)
        hobby = try? c.decode(String.self, forKey: .hobby)
        heightText = try? c.decode(String.self, forKey: .heightText)
        gender = JSONFlex.int(c, .gender)
        type = JSONFlex.int(c, .type)
        videosCount = JSONFlex.int(c, .videosCount)
        nameZht = try? c.decode(String.self, forKey: .nameZht)
        twitterID = try? c.decode(String.self, forKey: .twitterID)
        instagramID = try? c.decode(String.self, forKey: .instagramID)
        bust = JSONFlex.string(c, .bust)
        waist = JSONFlex.string(c, .waist)
        hips = JSONFlex.string(c, .hips)
        birthplace = try? c.decode(String.self, forKey: .birthplace)
        cons = try? c.decode(String.self, forKey: .cons)
    }
}

/// 演员详情（嵌套 actor + 筛选标签）
public struct ActorDetailPayload: Decodable {
    public let actor: Actor?
    public let filterTags: [Tag]?
    public let tags: [Tag]?
    public let shareInfo: String?
    public let hasCollected: Bool?

    enum CodingKeys: String, CodingKey {
        case actor, tags
        case filterTags = "filter_tags"
        case shareInfo = "share_info"
        case hasCollected = "has_collected"
    }
}

/// 演员推荐（新人 / 月排名 / 推荐）
public struct ActorRecommendData: Decodable {
    public let newActors: [Actor]?
    public let monthlyActors: [Actor]?
    public let recommendActors: [Actor]?

    enum CodingKeys: String, CodingKey {
        case newActors = "new_actors"
        case monthlyActors = "monthly_actors"
        case recommendActors = "recommend_actors"
    }
}

/// 佳片推荐时间段
public struct RecommendPeriod: Codable, Identifiable, Hashable {
    public let period: Int?
    public let moviesCount: Int?
    public let viewsCount: Int?
    public let createdAt: String?

    public var id: Int { period ?? 0 }

    public var titleText: String { "第\(period ?? 0)期" }

    public var dateText: String {
        guard let createdAt, createdAt.count >= 10 else { return "" }
        return String(createdAt.prefix(10))
    }

    enum CodingKeys: String, CodingKey {
        case period
        case moviesCount = "movies_count"
        case viewsCount = "views_count"
        case createdAt = "created_at"
    }
}

public struct RecommendPeriodListData: Codable {
    public let periods: [RecommendPeriod]?
    public let currentPage: Int?
    enum CodingKeys: String, CodingKey {
        case periods
        case currentPage = "current_page"
    }
}

public struct RecommendMoviesData: Decodable {
    public let period: Int?
    public let movies: [Movie]?
}

/// 广告
public struct AdItem: Codable, Identifiable, Hashable {
    public let id: Int?
    public let imageURL: String?
    public let url: String?
    public let md5: String?

    enum CodingKeys: String, CodingKey {
        case id, url, md5
        case imageURL = "image_url"
    }
}

public struct AdsData: Codable {
    public let enabled: Bool?
    public let ads: [String: [AdItem]]?
}

/// 磁力链接（API：name/hash/size/cnsub/hd/files_count/created_at/pikpak_url）
public struct Magnet: Decodable, Identifiable, Hashable {
    public let name: String?
    public let hash: String?
    public let size: Int64?
    public let cnsub: Bool?
    public let hd: Bool?
    public let filesCount: Int?
    public let createdAt: String?
    public let pikpakURL: String?

    public var id: String { hash ?? name ?? "magnet" }
    public var isHd: Bool? { hd }
    public var hasCnsub: Bool? { cnsub }
    public var date: String? { createdAt }

    enum CodingKeys: String, CodingKey {
        case name, hash, size, cnsub, hd
        case filesCount = "files_count"
        case createdAt = "created_at"
        case pikpakURL = "pikpak_url"
        case link, magnet, id
        case isHd = "is_hd"
        case hasCnsub = "has_cnsub"
        case fileCount = "file_count"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try? c.decode(String.self, forKey: .name)
        hash = JSONFlex.string(c, .hash)
            ?? JSONFlex.string(c, .id)
        size = JSONFlex.int(c, .size).map(Int64.init)
        cnsub = JSONFlex.bool(c, .cnsub) ?? JSONFlex.bool(c, .hasCnsub)
        hd = JSONFlex.bool(c, .hd) ?? JSONFlex.bool(c, .isHd)
        filesCount = JSONFlex.int(c, .filesCount) ?? JSONFlex.int(c, .fileCount)
        createdAt = JSONFlex.string(c, .createdAt)
        pikpakURL = try? c.decode(String.self, forKey: .pikpakURL)
    }

    public var displayName: String { name ?? "磁力链接" }

    public var stableID: String { hash ?? name ?? displayName }

    public var magnetURL: String? {
        if let hash, !hash.isEmpty {
            return "magnet:?xt=urn:btih:\(hash)"
        }
        return nil
    }

    public var sizeText: String? {
        guard let size, size > 0 else { return nil }
        // 实测磁力 size 多为 MB（如 5294 ≈ 5.29 GB）；更大则按字节。
        if size < 100_000 {
            if size >= 1000 {
                return String(format: "%.2f GB", Double(size) / 1000.0)
            }
            return String(format: "%.0f MB", Double(size))
        }
        let gb = Double(size) / 1_000_000_000
        if gb >= 1 { return String(format: "%.2f GB", gb) }
        return String(format: "%.1f MB", Double(size) / 1_000_000)
    }
}

/// 预览图/剧照（API 无 id，用 URL 作稳定标识）
public struct PreviewImage: Decodable, Identifiable, Hashable {
    public let thumbURL: String?
    public let largeURL: String?

    public var id: String { largeURL ?? thumbURL ?? "preview" }

    enum CodingKeys: String, CodingKey {
        case thumbURL = "thumb_url"
        case largeURL = "large_url"
    }
}

/// 播放源
public struct PlaySource: Codable, Identifiable, Hashable {
    public let id: Int
    public let name: String?
}

/// 影片搜索/列表响应 data
public struct MovieListData: Decodable {
    public let currentPage: Int?
    public let movies: [Movie]?

    enum CodingKeys: String, CodingKey {
        case movies
        case currentPage = "current_page"
    }
}

/// 影片详情响应 data
public struct MovieDetailData: Decodable {
    public let movie: Movie?
    public let relativeMovies: [Movie]?
    public let actorMovies: [Movie]?

    enum CodingKeys: String, CodingKey {
        case movie
        case relativeMovies = "relative_movies"
        case actorMovies = "actor_movies"
    }
}

/// 磁力列表响应 data
public struct MagnetListData: Decodable {
    public let magnets: [Magnet]?
    public let currentPage: Int?
    public let totalPages: Int?

    enum CodingKeys: String, CodingKey {
        case magnets
        case currentPage = "current_page"
        case totalPages = "total_pages"
    }
}

/// 播放响应 data（多集 + 多清晰度）
public struct PlayData: Codable {
    public struct Episode: Codable, Identifiable {
        public let index: Int
        public let name: String?
        public let urls: [String: StreamURL]?

        public var id: Int { index }
    }
    public struct StreamURL: Codable {
        public let url: String?
        public let size: Int64?
        public let duration: Int?
    }
    public let movies: [Episode]?
    public let sourceID: Int?
    public let sourceName: String?

    enum CodingKeys: String, CodingKey {
        case movies
        case sourceID = "source_id"
        case sourceName = "source_name"
    }
}

/// 排行榜条目
public struct RankingItem: Decodable, Identifiable {
    public let id: String?
    public let rank: Int?
    public let movie: Movie?
    public let actor: Actor?

    public var identifier: String { id ?? movie?.id ?? actor?.id ?? UUID().uuidString }
}

/// 片单（官方 related：name / movies_count / collections_count / views_count）
public struct MovieList: Decodable, Identifiable, Hashable {
    public let id: String
    public let name: String?
    public let title: String?
    public let description: String?
    public let coverURL: String?
    public let movieCount: Int?
    public let collectionsCount: Int?
    public let viewsCount: Int?
    public let createdAt: String?
    public let shareInfo: String?
    public let isDefault: Bool?
    public let userID: Int?
    public let userName: String?
    public let isFavorite: Bool?
    public let isPrivate: Bool?

    public var displayName: String { name ?? title ?? "片单" }

    enum CodingKeys: String, CodingKey {
        case id, name, title, description
        case coverURL = "cover_url"
        case movieCount = "movie_count"
        case moviesCount = "movies_count"
        case collectionsCount = "collections_count"
        case viewsCount = "views_count"
        case createdAt = "created_at"
        case shareInfo = "share_info"
        case isDefault = "is_default"
        case userID = "user_id"
        case userName = "user_name"
        case isFavorite = "is_favorite"
        case isPrivate = "is_private"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = JSONFlex.string(c, .id) ?? ""
        name = try? c.decode(String.self, forKey: .name)
        title = try? c.decode(String.self, forKey: .title)
        description = try? c.decode(String.self, forKey: .description)
        coverURL = try? c.decode(String.self, forKey: .coverURL)
        movieCount = JSONFlex.int(c, .movieCount) ?? JSONFlex.int(c, .moviesCount)
        collectionsCount = JSONFlex.int(c, .collectionsCount)
        viewsCount = JSONFlex.int(c, .viewsCount)
        createdAt = JSONFlex.string(c, .createdAt)
        shareInfo = try? c.decode(String.self, forKey: .shareInfo)
        isDefault = JSONFlex.bool(c, .isDefault)
        userID = JSONFlex.int(c, .userID)
        userName = try? c.decode(String.self, forKey: .userName)
        isFavorite = JSONFlex.bool(c, .isFavorite)
        isPrivate = JSONFlex.bool(c, .isPrivate)
    }
}

/// 影评
public struct Review: Decodable, Identifiable, Hashable {
    public let id: String?
    public let movieID: String?
    public let userID: Int?
    public let userName: String?
    public let content: String?
    public let score: Int?
    public let createdAt: String?
    public let likeCount: Int?
    public let isLiked: Bool?

    public var identifier: String { stableReviewID }
    public var stableReviewID: String {
        id ?? "\(userID ?? 0)-\(content ?? "")-\(createdAt ?? "")"
    }

    enum CodingKeys: String, CodingKey {
        case id, content, score
        case movieID = "movie_id"
        case userID = "user_id"
        case userName = "user_name"
        case createdAt = "created_at"
        case likeCount = "like_count"
        case isLiked = "is_liked"
        case likesCount = "likes_count"
        case liked
        case username
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = JSONFlex.string(c, .id)
        movieID = JSONFlex.string(c, .movieID)
        userID = JSONFlex.int(c, .userID)
        userName = (try? c.decode(String.self, forKey: .userName))
            ?? (try? c.decode(String.self, forKey: .username))
        content = try? c.decode(String.self, forKey: .content)
        score = JSONFlex.int(c, .score)
        createdAt = JSONFlex.string(c, .createdAt)
        likeCount = JSONFlex.int(c, .likeCount) ?? JSONFlex.int(c, .likesCount)
        isLiked = JSONFlex.bool(c, .isLiked) ?? JSONFlex.bool(c, .liked)
    }
}

/// 文章
public struct Article: Decodable, Identifiable, Hashable {
    public let id: String?
    public let title: String?
    public let content: String?
    public let coverURL: String?
    public let createdAt: String?
    public let authorName: String?

    public var identifier: String { stableArticleID }
    public var stableArticleID: String { id ?? title ?? createdAt ?? "article" }

    enum CodingKeys: String, CodingKey {
        case id, title, content, author
        case coverURL = "cover_url"
        case createdAt = "created_at"
        case authorName = "author_name"
        case releasedAt = "released_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = JSONFlex.string(c, .id)
        title = try? c.decode(String.self, forKey: .title)
        content = try? c.decode(String.self, forKey: .content)
        coverURL = try? c.decode(String.self, forKey: .coverURL)
        createdAt = JSONFlex.string(c, .createdAt) ?? JSONFlex.string(c, .releasedAt)
        if let name = try? c.decode(String.self, forKey: .authorName) {
            authorName = name
        } else if let author = try? c.decode([String: JSONValue].self, forKey: .author) {
            authorName = author["name"]?.stringValue
        } else {
            authorName = nil
        }
    }
}

private enum JSONValue: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        self = .null
    }
    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        default: return nil
        }
    }
}

/// 分类/标签（首页展示）
public struct Category: Codable, Identifiable {
    public let id: String
    public let name: String?
    public let coverURL: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case coverURL = "cover_url"
    }
}

/// 磁力应用（magnet_apps 接口）
public struct MagnetApp: Codable, Identifiable {
    public let id: String?
    public let name: String?
    public let iconURL: String?
    public let scheme: String?

    enum CodingKeys: String, CodingKey {
        case id, name, scheme
        case iconURL = "icon_url"
    }
}

/// 番号
public struct Code: Codable, Identifiable {
    public let id: String?
    public let number: String?
    public let title: String?
    public let coverURL: String?

    enum CodingKeys: String, CodingKey {
        case id, number, title
        case coverURL = "cover_url"
    }
}
