import SwiftUI

/// Restored 257 resource row plus a peer card for the existing online sheet.
/// The card only opens that sheet; it never queries a source.
struct PlaybackResourceCards: View {
    let configured115: Bool
    let onlineAvailable: Bool
    let externalAvailable: Bool
    let play115: () -> Void
    let openOnline: () -> Void
    let openExternal: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text("播放资源:").font(.system(size: 17, weight: .bold))
                Button("115 原画") { play115() }
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .overlay(Capsule().stroke(.white.opacity(0.22)))
                    .accessibilityIdentifier("detail.resource.header.115")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                PlaybackResourceCardRow(configured115: configured115, onlineAvailable: onlineAvailable,
                                        externalAvailable: externalAvailable, play115: play115,
                                        openOnline: openOnline, openExternal: openExternal)
            }.padding(.horizontal, -18)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.resource.cards")
    }
}

struct PlaybackResourceCardRow: View {
    let configured115: Bool
    let onlineAvailable: Bool
    let externalAvailable: Bool
    let play115: () -> Void
    let openOnline: () -> Void
    let openExternal: () -> Void
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) { cards }
            VStack(alignment: .leading, spacing: 12) { cards }
        }
        .padding(.horizontal, 18)
    }
    private var cards: some View {
        Group {
            infoCard(title: "115 原画",
                     caption: configured115 ? "打开 115 匹配资源" : "需先在「我的」配置 115",
                     action: "选择播放文件", icon: "play.circle", emphasized: true,
                     id: "detail.card.115", perform: play115)
            if onlineAvailable {
                infoCard(title: "在线播放", caption: "打开在线播放，不自动查询",
                         action: "选择来源后查询", icon: "play.rectangle", emphasized: true,
                         id: "detail.card.online", perform: openOnline)
            }
            if externalAvailable {
                infoCard(title: "磁力与外部资源", caption: "查看可用链接后选择推送",
                         action: "查看资源", icon: "link", emphasized: false,
                         id: "detail.card.external", perform: openExternal)
            }
        }
    }
    private func infoCard(title: String, caption: String, action: String, icon: String, emphasized: Bool, id: String, perform: @escaping () -> Void) -> some View {
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

