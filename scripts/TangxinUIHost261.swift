import SwiftUI

// This host uses production ContentView, native tab bar and Tangxin views.
// Other catalog tabs and the player are inert substitutes. NO playback proof.
@main struct TangxinUIHost261: App {
    init() { UserDefaults.standard.removeObject(forKey:"tangxin.systemProxyCompatibility") }
    var body: some Scene { WindowGroup { ContentView(tangxinClient:TangxinFixtures261.client()).environmentObject(AppState()) } }
}
final class AppState: ObservableObject {}
enum JAVDBPalette { static let accent = Color.orange }
enum AdaptiveLayout { static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad } }
struct SceneLayoutReader: ViewModifier { func body(content:Content) -> some View { content } }
struct HomeView: View { var body: some View { Text("合成UI门禁 · 首页替身") } }
struct RankingsView: View { var body: some View { Text("合成排行替身") } }
struct CategoriesView: View { var body: some View { Text("合成类别替身") } }
struct ActorsView: View { var body: some View { Text("合成演员替身") } }
struct UserView: View { var body: some View { Text("合成用户替身") } }
struct KSChromePlayer: View {
    let url: URL
    var title = ""
    var subtitle = ""
    var headers: [String:String] = [:]
    var progressID: String? = nil
    var publicSubtitleQuery = ""
    var body: some View { Text("播放器替身；未播放任何真实视频") }
}
