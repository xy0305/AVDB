//
//  FollowingTagsView.swift
//  AVDB
//
//  管理我的标签（关注的标签列表）
//

import SwiftUI

struct FollowingTagsView: View {
    @StateObject private var vm = FollowingTagsViewModel()
    @State private var editMode: EditMode = .inactive
    
    var body: some View {
        ZStack {
            if vm.isLoading && vm.tags.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("載入中...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if let err = vm.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text(err)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("重試") {
                        Task { await vm.load() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if vm.tags.isEmpty {
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
                    ForEach(vm.tags) { tag in
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
                        vm.tags.move(fromOffsets: from, toOffset: to)
                    }
                    .onDelete { indexSet in
                        Task {
                            await vm.deleteTags(at: indexSet)
                        }
                    }
                }
                .refreshable {
                    await vm.load()
                }
            }
        }
        .navigationTitle("管理我的標籤")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if vm.tags.isEmpty {
                    Button("刷新") {
                        Task { await vm.load() }
                    }
                } else {
                    EditButton()
                }
            }
        }
        .environment(\.editMode, $editMode)
        .task {
            await vm.load()
        }
    }
}

@MainActor
final class FollowingTagsViewModel: ObservableObject {
    @Published var tags: [FollowingTag] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let (_, followingTags) = try await JavDBSDK.shared.userInfo()
            print("📍 FollowingTagsViewModel: loaded \(followingTags.count) tags")
            for tag in followingTags {
                print("  - Tag ID: \(tag.id), name: \(tag.name ?? "nil"), value: \(tag.value ?? "nil")")
            }
            tags = followingTags
        } catch {
            print("❌ FollowingTagsViewModel load error: \(error)")
            errorMessage = error.localizedDescription
        }
    }
    
    func deleteTags(at indexSet: IndexSet) async {
        for index in indexSet {
            let tag = tags[index]
            _ = try? await JavDBSDK.shared.unfollowTag(tag.id)
        }
        tags.remove(atOffsets: indexSet)
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
