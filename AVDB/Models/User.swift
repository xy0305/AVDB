//
//  User.swift
//  AVDB
//
//  用户、登录、会员、钱包等数据模型。
//

import Foundation

/// 用户模型
public struct User: Codable, Identifiable, Hashable {
    public let id: Int
    public let username: String?
    public let email: String?
    public let isVip: Bool?
    public let vipExpiredAt: String?
    public let avatarURL: String?
    public let wantWatchCount: Int?
    public let watchedCount: Int?
    public let promotionCode: String?
    public let promotionDays: Int?
    public let checkinDays: Int?
    public let lastCheckinAt: String?
    public let bio: String?
    public let gender: String?
    public let level: Int?

    enum CodingKeys: String, CodingKey {
        case id, username, email, bio, gender, level
        case isVip = "is_vip"
        case vipExpiredAt = "vip_expired_at"
        case avatarURL = "avatar_url"
        case wantWatchCount = "want_watch_count"
        case watchedCount = "watched_count"
        case promotionCode = "promotion_code"
        case promotionDays = "promotion_days"
        case checkinDays = "checkin_days"
        case lastCheckinAt = "last_checkin_at"
    }

    public var displayName: String {
        return username?.isEmpty == false ? username! : "用户\(id)"
    }
}

/// 登录响应 data
public struct SessionData: Codable {
    public let token: String?
    public let user: User?
}

/// 用户信息响应 data
public struct UserData: Codable {
    public let user: User?
}

/// 启动配置响应 data
public struct StartupData: Codable {
    public struct SplashAd: Codable {
        public struct AdInfo: Codable {
            public let id: Int?
            public let mediaType: String?
            public let mediaURL: String?
            public let linkURL: String?

            enum CodingKeys: String, CodingKey {
                case id
                case mediaType = "media_type"
                case mediaURL = "media_url"
                case linkURL = "link_url"
            }
        }
        public let enabled: Bool?
        public let overtime: Int?
        public let ad: AdInfo?
    }
    public let splashAd: SplashAd?
    public let user: User?
    public let backupDomainsData: String?
    public let recentKeywords: [String]?

    enum CodingKeys: String, CodingKey {
        case user
        case splashAd = "splash_ad"
        case backupDomainsData = "backup_domains_data"
        case recentKeywords = "recent_keywords"
    }
}

/// 会员计划
public struct Plan: Codable, Identifiable {
    public let id: Int?
    public let name: String?
    public let title: String?
    public let price: Double?
    public let originalPrice: Double?
    public let days: Int?
    public let description: String?
    public let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, title, price, days, description
        case originalPrice = "original_price"
        case isActive = "is_active"
    }
}

/// 钱包
public struct Wallet: Codable {
    public let balance: Double?
    public let coin: Double?
    public let totalIncome: Double?
    public let pendingIncome: Double?

    enum CodingKeys: String, CodingKey {
        case balance, coin
        case totalIncome = "total_income"
        case pendingIncome = "pending_income"
    }
}

/// 磁力列表（字符串字段版本，兼容列表返回）
public struct MagnetField: Codable {
    public let key: String?
    public let value: String?
}
