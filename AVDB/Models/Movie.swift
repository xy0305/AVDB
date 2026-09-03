//
//  Movie.swift
//  AVDB
//
//  影片及相关数据模型（snake_case 字段，兼容 API 返回值）。
//

import Foundation

/// 影片通用模型
public struct Movie: Codable, Identifiable, Hashable {
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
    public let previewImages: [PreviewImage]?
    public let playSources: [PlaySource]?
    public let previewVideoURL: String?

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
    }
}

/// 标签
public struct Tag: Codable, Identifiable, Hashable {
    public let id: String
    public let name: String?
    public let coverURL: String?
    public let count: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, count
        case coverURL = "cover_url"
    }
}

/// 演员
public struct Actor: Codable, Identifiable, Hashable {
    public let id: String
    public let name: String?
    public let avatarURL: String?
    public let coverURL: String?
    public let birthday: String?
    public let age: Int?
    public let height: Int?
    public let cup: String?
    public let bloodType: String?
    public let hobby: String?
    public let heightText: String?

    enum CodingKeys: String, CodingKey {
        case id, name, age, height, cup, hobby
        case avatarURL = "avatar_url"
        case coverURL = "cover_url"
        case birthday
        case bloodType = "blood_type"
        case heightText = "height_text"
    }
}

/// 磁力链接
public struct Magnet: Codable, Identifiable, Hashable {
    public let id: String?
    public let link: String?
    public let name: String?
    public let title: String?
    public let size: String?
    public let sizeByte: Int64?
    public let magnet: String?
    public let fileCount: Int?
    public let isHd: Bool?
    public let hasCnsub: Bool?
    public let sourceType: String?
    public let provider: String?
    public let number: String?
    public let date: String?
    public let isFavorite: Bool?

    enum CodingKeys: String, CodingKey {
        case id, link, name, title, size, magnet, number, date, provider
        case sizeByte = "size_byte"
        case fileCount = "file_count"
        case isHd = "is_hd"
        case hasCnsub = "has_cnsub"
        case sourceType = "source_type"
        case isFavorite = "is_favorite"
    }

    public var displayName: String {
        return name ?? title ?? "磁力链接"
    }
}

/// 预览图/剧照
public struct PreviewImage: Codable, Identifiable, Hashable {
    public let id: String?
    public let thumbURL: String?
    public let largeURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case thumbURL = "thumb_url"
        case largeURL = "large_url"
    }

    public var identifier: String {
        return largeURL ?? thumbURL ?? UUID().uuidString
    }
}

/// 播放源
public struct PlaySource: Codable, Identifiable, Hashable {
    public let id: Int
    public let name: String?
}

/// 影片搜索/列表响应 data
public struct MovieListData: Codable {
    public let currentPage: Int?
    public let movies: [Movie]?

    enum CodingKeys: String, CodingKey {
        case movies
        case currentPage = "current_page"
    }
}

/// 影片详情响应 data
public struct MovieDetailData: Codable {
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
public struct MagnetListData: Codable {
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
public struct RankingItem: Codable, Identifiable {
    public let id: String?
    public let rank: Int?
    public let movie: Movie?
    public let actor: Actor?

    public var identifier: String { id ?? movie?.id ?? actor?.id ?? UUID().uuidString }
}

/// 片单
public struct MovieList: Codable, Identifiable {
    public let id: String?
    public let name: String?
    public let title: String?
    public let description: String?
    public let coverURL: String?
    public let movieCount: Int?
    public let userID: Int?
    public let userName: String?
    public let isFavorite: Bool?
    public let isPrivate: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, title, description
        case coverURL = "cover_url"
        case movieCount = "movie_count"
        case userID = "user_id"
        case userName = "user_name"
        case isFavorite = "is_favorite"
        case isPrivate = "is_private"
    }
}

/// 影评
public struct Review: Codable, Identifiable {
    public let id: String?
    public let movieID: String?
    public let userID: Int?
    public let userName: String?
    public let content: String?
    public let score: Int?
    public let createdAt: String?
    public let likeCount: Int?
    public let isLiked: Bool?

    enum CodingKeys: String, CodingKey {
        case id, content, score
        case movieID = "movie_id"
        case userID = "user_id"
        case userName = "user_name"
        case createdAt = "created_at"
        case likeCount = "like_count"
        case isLiked = "is_liked"
    }
}

/// 文章
public struct Article: Codable, Identifiable {
    public let id: String?
    public let title: String?
    public let content: String?
    public let coverURL: String?
    public let createdAt: String?
    public let authorName: String?

    enum CodingKeys: String, CodingKey {
        case id, title, content
        case coverURL = "cover_url"
        case createdAt = "created_at"
        case authorName = "author_name"
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
