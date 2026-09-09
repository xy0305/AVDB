//
//  FollowingTagsView.swift
//  AVDB
//
//  管理我的标签（关注的标签列表）
//

import SwiftUI

struct FollowingTagsView: View {
    @StateObject private var store = FollowingTagsStore.shared
    @State private var editMode: EditMode = .inactive
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            if store.tags.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "heart.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("暂无关注")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("在清单详情页点击眼睛图标可以关注清单更新")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else {
                List {
                    ForEach(store.tags) { tag in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tag.displayName)
                                    .font(.body)
                                if let typeText = tag.typeText {
                                    Text(typeText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(.secondary)
                        }
                    }
                    .onMove { from, to in
                        store.move(from: from, to: to)
                    }
                    .onDelete { indexSet in
                        Task {
                            await deleteTagsRemote(at: indexSet)
                        }
                    }
                }
            }
        }
        .navigationTitle("管理我的標籤")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !store.tags.isEmpty {
                    EditButton()
                }
            }
        }
        .environment(\.editMode, $editMode)
    }
    
    /// 删除标签（调用远程API + 本地删除）
    private func deleteTagsRemote(at indexSet: IndexSet) async {
        for index in indexSet {
            let tag = store.tags[index]
            do {
                _ = try await JavDBSDK.shared.unfollowTag(tag.id)
                print("✅ Deleted tag \(tag.id) from server")
            } catch {
                print("❌ Failed to delete tag \(tag.id): \(error)")
            }
        }
        store.remove(at: indexSet)
    }
}

extension FollowingTag {
    var displayName: String {
        guard let name = name, let value = value else {
            return "未知標籤"
        }
        switch name {
        case "list":
            return value // 清单 ID，后续可通过接口获取清单名称
        case "tag":
            return value // 标签名称
        default:
            return value
        }
    }
    
    var typeText: String? {
        guard let name = name else { return nil }
        switch name {
        case "list": return "清單"
        case "tag": return "標籤"
        default: return name
        }
    }
}
