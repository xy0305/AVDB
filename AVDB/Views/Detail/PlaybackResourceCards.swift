import SwiftUI

/// Stable resource-card inputs. Constructed once by the detail screen so vertical
/// scrolling does not allocate a new card tree or an online session model.
struct PlaybackResourceCardState {
    var model: OnlinePlaybackModel?
    var showsOnline = false
    var showsExternal = false
}

/// Restored 257 resource row plus a peer card for the existing online sheet.
/// The card only opens that sheet; it never queries a source.
struct PlaybackResourceCards: View, Equatable {
    var state: PlaybackResourceCardState
    let configured115: Bool
    let play115: () -> Void
    let openOnline: () -> Void
    let openExternal: () -> Void
    init(state: PlaybackResourceCardState, configured115: Bool, onlineAvailable: Bool,
         externalAvailable: Bool, play115: @escaping () -> Void, openOnline: @escaping () -> Void,
         openExternal: @escaping () -> Void) {
        var state = state
        state.showsOnline = onlineAvailable
        state.showsExternal = externalAvailable
        self.state = state
        self.configured115 = configured115
        self.play115 = play115
        self.openOnline = openOnline
        self.openExternal = openExternal
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.configured115 == rhs.configured115 && lhs.state.showsOnline == rhs.state.showsOnline
            && lhs.state.showsExternal == rhs.state.showsExternal
    }
    var body: some View {
        let caption = configured115 ? "打开 115 匹配资源" : "需先在「我的」配置 115"
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text("播放资源:").font(.system(size: 17, weight: .bold))
                Button("115 原画") { play115() }
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .overlay(Capsule().stroke(.white.opacity(0.22)))
                    .accessibilityIdentifier("detail.resource.header.115")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                PlaybackResourceCardRow(configured115: configured115, caption115: caption,
                                        showsOnline: state.showsOnline, showsExternal: state.showsExternal,
                                        play115: play115, openOnline: openOnline, openExternal: openExternal)
            }.padding(.horizontal, -18)
        }
        .equatable()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.resource.cards")
    }
}

struct PlaybackResourceCardRow: View, Equatable {
    let configured115: Bool
    let caption115: String
    let showsOnline: Bool
    let showsExternal: Bool
    let play115: () -> Void
    let openOnline: () -> Void
    let openExternal: () -> Void
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.configured115 == rhs.configured115 && lhs.caption115 == rhs.caption115
            && lhs.showsOnline == rhs.showsOnline && lhs.showsExternal == rhs.showsExternal
    }
    var body: some View {
        // One stable row. The previous dual-branch fit rebuilt both layouts during
        // every scroll pass; narrow widths wrap by the existing horizontal scroller.
        HStack(alignment: .top, spacing: 12) { cards }
            .padding(.horizontal, 18)
    }
    private var cards: some View {
        Group {
            PlaybackResourceInfoCard(title: "115 原画", caption: caption115,
                                     action: "选择播放文件", icon: "play.circle", emphasized: true,
                                     id: "detail.card.115", perform: play115)
            if showsOnline {
                PlaybackResourceInfoCard(title: "在线播放", caption: "打开在线播放，不自动查询",
                                         action: "选择来源后查询", icon: "play.rectangle", emphasized: true,
                                         id: "detail.card.online", perform: openOnline)
            }
            if showsExternal {
                PlaybackResourceInfoCard(title: "磁力与外部资源", caption: "查看可用链接后选择推送",
                                         action: "查看资源", icon: "link", emphasized: false,
                                         id: "detail.card.external", perform: openExternal)
            }
        }
    }
}

struct PlaybackResourceInfoCard: View, Equatable {
    let title: String
    let caption: String
    let action: String
    let icon: String
    let emphasized: Bool
    let id: String
    let perform: () -> Void
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title && lhs.caption == rhs.caption && lhs.action == rhs.action
            && lhs.icon == rhs.icon && lhs.emphasized == rhs.emphasized && lhs.id == rhs.id
    }
    var body: some View {
        Button(action: perform) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.title3.bold())
                Text(caption).font(.caption)
                Label(action, systemImage: icon).font(.subheadline)
            }
            .padding(16).frame(minWidth: 220, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(emphasized ? 0.45 : 0.22)))
        }
        .accessibilityIdentifier(id)
    }
}
