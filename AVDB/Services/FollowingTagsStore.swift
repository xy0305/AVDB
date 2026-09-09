//
//  FollowingTagsStore.swift
//  AVDB
//
//  关注列表：服务端没有 GET，登录后用 batch_push(tags=[]) 拉全量，本地缓存一份。
//

import Foundation

@MainActor
final class FollowingTagsStore: ObservableObject {
    static let shared = FollowingTagsStore()

    @Published private(set) var tags: [FollowingTag] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let userDefaultsKey = "avdb.following_tags"

    private init() {
        load()
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([FollowingTag].self, from: data) else {
            tags = []
            return
        }
        tags = decoded.sorted { ($0.priority ?? 0) < ($1.priority ?? 0) }
    }

    private func save() {
        guard let encoded = try? JSONEncoder().encode(tags) else { return }
        UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
    }

    func replace(_ newTags: [FollowingTag]) {
        tags = newTags.sorted { ($0.priority ?? 0) < ($1.priority ?? 0) }
        save()
    }

    func add(_ tag: FollowingTag) {
        if let idx = tags.firstIndex(where: { $0.id == tag.id }) {
            tags[idx] = tag
        } else {
            tags.append(tag)
        }
        tags.sort { ($0.priority ?? 0) < ($1.priority ?? 0) }
        save()
    }

    func remove(_ id: Int) {
        tags.removeAll { $0.id == id }
        save()
    }

    func remove(at offsets: IndexSet) {
        tags.remove(atOffsets: offsets)
        save()
    }

    func clear() {
        tags = []
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    @discardableResult
    func refreshFromServer() async -> [FollowingTag] {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let remote = try await JavDBSDK.shared.followingTags()
            replace(remote)
            return remote
        } catch {
            errorMessage = error.localizedDescription
            return tags
        }
    }
}
