import SwiftUI

extension Notification.Name { static let avdbCatalogAccountChanged = Notification.Name("NeutralAccount258") }
// The UI fixture never instantiates the real player or downloads any media.
struct KSChromePlayer: View {
    let url: URL
    let title: String
    let subtitle: String
    let headers: [String: String]
    let progressID: String
    let supportsFramePreview: Bool
    let publicSubtitleQuery: String
    var body: some View { Text("Neutral player stub — no media loaded") }
}

@main struct PlaybackUIHost258: App {
    var body: some Scene { WindowGroup { NeutralDetail258() } }
}
struct NeutralDetail258: View {
    @StateObject private var model: OnlinePlaybackModel
    @State private var online = false
    @State private var versions = false
    @State private var number = "TEST-001"
    @State private var panOpened = false
    init() {
        let prefs = UserDefaults(suiteName: "org.avdb.neutral258.preferences")!
        if !ProcessInfo.processInfo.arguments.contains("--preserve") { prefs.removePersistentDomain(forName: "org.avdb.neutral258.preferences") }
        if ProcessInfo.processInfo.arguments.contains("--saved") { prefs.set(true, forKey: OnlinePlaybackModel.proxyPreferenceKey) }
        let transport = OnlineTransport(loader: { _ in
            throw OnlineFailure.safe(PlaybackDiagnostic(stage: .discovery, category: .tls, host: "fixture.example.test"))
        })
        _model = StateObject(wrappedValue: OnlinePlaybackModel(provider: OnlineProvider(transport: transport), preferences: prefs))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    RoundedRectangle(cornerRadius: 20).fill(.blue.gradient).frame(height: 160)
                        .overlay(Text("NEUTRAL UI FIXTURE").foregroundStyle(.white))
                    Text("示例影片 · 无网络内容").font(.title2.bold())
                    Text(number).accessibilityIdentifier("fixture.number")
                    PlaybackResourceActions(onlineAvailable: true, play115: { panOpened = true }, openOnline: { online = true })
                    Text(panOpened ? "115 action retained" : "115 ready").accessibilityIdentifier("fixture.115")
                    Button("切换示例影片") { number = number == "TEST-001" ? "TEST-002" : "TEST-001"; model.reset(); versions = false }
                        .accessibilityIdentifier("fixture.switch")
                    Text("Only explicit query buttons use an injected, failing loader. No DNS, page, image or media requests.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: 700)
            }
            .navigationTitle("通用资源布局")
        }
        .sheet(isPresented: $online, onDismiss: { model.cancelPending() }) {
            OnlinePlaybackSheet(number: number, model: model, versions: $versions)
        }
    }
}
