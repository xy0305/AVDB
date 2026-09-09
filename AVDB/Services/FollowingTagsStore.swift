//
//  FollowingTagsStore.swift
//  AVDB
//
//  本地存储关注标签（因为服务器没有GET接口返回列表）
//

import Foundation

@MainActor
final class FollowingTagsStore: ObservableObject {
    static let shared = FollowingTagsStore()
    
    @Published private(set) var tags: [FollowingTag] = []
    
    private let userDefaultsKey = "avdb.following_tags"
    
    private init() {
        load()
    }
    
    /// 从 UserDefaults 加载
    func load() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([FollowingTag].self, from: data) else {
            tags = []
            return
        }
        tags = decoded.sorted { ($0.priority ?? 0) > ($1.priority ?? 0) }
        print("📍 FollowingTagsStore: loaded \(tags.count) tags from local storage")
    }
    
    /// 保存到 UserDefaults
    private func save() {
        guard let encoded = try? JSONEncoder().encode(tags) else { return }
        UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        print("📍 FollowingTagsStore: saved \(tags.count) tags to local storage")
    }
    
    /// 添加关注（POST 成功后调用）
    func add(_ tag: FollowingTag) {
        // 去重
        if tags.contains(where: { $0.id == tag.id }) {
            print("⚠️ FollowingTagsStore: tag \(tag.id) already exists")
            return
        }
        tags.append(tag)
        save()
    }
    
    /// 删除关注（DELETE 成功后调用）
    func remove(_ id: Int) {
        tags.removeAll { $0.id == id }
        save()
    }
    
    /// 批量删除
    func remove(at offsets: IndexSet) {
        tags.remove(atOffsets: offsets)
        save()
    }
    
    /// 移动排序
    func move(from: IndexSet, to: Int) {
        tags.move(fromOffsets: from, toOffset: to)
        // 更新 priority
        for (index, tag) in tags.enumerated() {
            var updatedTag = tag
            updatedTag.priority = Double(tags.count - index)
            tags[index] = updatedTag
        }
        save()
    }
    
    /// 清空（登出时调用）
    func clear() {
        tags = []
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}
