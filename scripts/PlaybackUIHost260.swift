import SwiftUI

extension Notification.Name { static let avdbCatalogAccountChanged = Notification.Name("NeutralAccount260") }
// The fixture never instantiates the real player or contacts any source.
struct KSChromePlayer: View {
    let url: URL
    let title: String
    let subtitle: String
    let headers: [String: String]
    var onlineQuality: OnlineQualityChoice? = nil
    let progressID: String
    let supportsFramePreview: Bool
    let publicSubtitleQuery: String
    var body: some View { Text("Neutral player stub — no media loaded") }
}

@main struct PlaybackUIHost260: App {
    var body: some Scene { WindowGroup { NeutralDetail260() } }
}

struct NeutralDetail260: View {
    @StateObject private var model: OnlinePlaybackModel
    @State private var online = false
    @State private var versions = false
    @State private var panOpened = false
    @State private var externalOpened = false
    @State private var narrow = false
    init() {
        let prefs = UserDefaults(suiteName: "org.avdb.neutral260.preferences")!
        prefs.removePersistentDomain(forName: "org.avdb.neutral260.preferences")
        let transport = OnlineTransport(loader: { _ in
            throw OnlineFailure.safe(PlaybackDiagnostic(stage: .discovery, category: .tls, host: "fixture.example.test"))
        })
        _model = StateObject(wrappedValue: OnlinePlaybackModel(provider: OnlineProvider(transport: transport), preferences: prefs))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("中性资源布局").font(.title2.bold())
                    Text("TEST-001").accessibilityIdentifier("fixture.number")
                    PlaybackResourceCards(configured115: true, onlineAvailable: true, externalAvailable: true,
                                           play115: { panOpened = true },
                                           openOnline: { online = true },
                                           openExternal: { externalOpened = true })
                        .frame(maxWidth: narrow ? 250 : .infinity, alignment: .leading)
                    Text(panOpened ? "115 callback retained" : "115 ready").accessibilityIdentifier("fixture.115")
                    Text(externalOpened ? "external opened" : "external ready").accessibilityIdentifier("fixture.external")
                    Button(narrow ? "恢复宽度" : "模拟窄屏") { narrow.toggle() }
                        .accessibilityIdentifier("fixture.width")
                    Text("打开在线卡片只显示既有面板；查询按钮不会被自动点击。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: 760)
            }
            .navigationTitle("资源卡片")
        }
        .sheet(isPresented: $online, onDismiss: { model.cancelPending() }) {
            OnlinePlaybackSheet(number: "TEST-001", model: model, versions: $versions)
        }
    }
}
