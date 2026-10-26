import Foundation
import SwiftUI

actor TangxinModelFixture261 {
    var firstCount = 0
    var secondCount = 0
    var waiting = false
    func fetch(_ url:URL) async throws -> Data {
        if url.path == "/featured" || url.path == "/featured/" {
            firstCount += 1
            if waiting { try await Task.sleep(nanoseconds:2_000_000_000) }
            return Data(TangxinFixtures261.first.utf8)
        }
        secondCount += 1
        if secondCount == 1 { throw TangxinError.structure }
        return Data(TangxinFixtures261.second.utf8)
    }
    func setWaiting(_ value:Bool) { waiting = value }
}
@main struct TangxinModelRegression261 {
    @MainActor static func main() async throws {
        let state = TangxinModelFixture261()
        let client = TangxinClient(transport:OnlineTransport(loader:{ request in try await state.fetch(request.url!) }))
        let m = TangxinListModel(root:TangxinPolicy.featured,client:client)
        await m.start(); precondition(m.videos.count == 1 && m.next != nil && !m.loading)
        await m.more(); precondition(m.error != nil && m.next != nil && m.videos.count == 1)
        await m.retry(); precondition(m.error == nil && m.videos.count == 2 && m.next == nil)
        await m.refresh(); precondition(m.videos.count == 1 && m.next != nil)
        await state.setWaiting(true)
        let cancelled = Task { await m.refresh() }
        try await Task.sleep(nanoseconds:30_000_000); cancelled.cancel(); await cancelled.value
        precondition(!m.loading && m.error == nil)
        let stale = Task { await m.refresh() }
        try await Task.sleep(nanoseconds:30_000_000)
        await state.setWaiting(false); await m.refresh(); await stale.value
        precondition(!m.loading && m.error == nil && m.videos.count == 1)
        print("PASS261 production MainActor model pagination retry/dedup/refresh/cancel/stale generation; synthetic")
    }
}
// Compile the production view graph for ABI coverage without real media playback.
struct KSChromePlayer: View {
    let url:URL
    var title = ""
    var subtitle = ""
    var headers:[String:String] = [:]
    var progressID:String? = nil
    var publicSubtitleQuery = ""
    var body:some View { Text("inert fixture player") }
}
