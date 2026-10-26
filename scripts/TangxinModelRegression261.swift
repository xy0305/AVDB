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
        async let firstAuto: Void = m.nearBottom(tail:m.videos.last!.id)
        async let concurrentAuto: Void = m.nearBottom(tail:m.videos.last!.id)
        _ = await (firstAuto, concurrentAuto)
        precondition(m.error != nil && m.next != nil && m.videos.count == 1)
        for _ in 0..<20 { await m.nearBottom(tail:m.videos.last!.id) }
        let attempts = await state.secondCount
        precondition(attempts == 1, "Failed sentinel must not retry")
        await m.retry(); precondition(m.error == nil && m.videos.count == 2 && m.next == nil)
        await m.refresh(); precondition(m.videos.count == 1 && m.next != nil)
        await state.setWaiting(true)
        let cancelled = Task { await m.refresh() }
        try await Task.sleep(nanoseconds:30_000_000); cancelled.cancel(); await cancelled.value
        precondition(!m.loading && m.error?.contains("取消") == true)
        let stale = Task { await m.refresh() }
        try await Task.sleep(nanoseconds:30_000_000)
        await state.setWaiting(false); await m.refresh(); await stale.value
        precondition(!m.loading && m.error == nil && m.videos.count == 1)
        // Leaving during an initial load must not strand the model in loading=true.
        let reentry = TangxinListModel(root:TangxinPolicy.featured,client:client)
        await state.setWaiting(true)
        let pending = Task { await reentry.start() }
        try await Task.sleep(nanoseconds:30_000_000)
        reentry.cancel(); await pending.value
        precondition(!reentry.loading && reentry.error?.contains("取消") == true)
        await state.setWaiting(false); await reentry.start()
        precondition(reentry.videos.count == 1 && !reentry.loading)
        // No automatic scan: each empty page advances only when more() is requested.
        let sequence = TangxinClient(transport:OnlineTransport(loader:{ request in
            let path = request.url!.path
            let html: String
            if path == "/featured" || path == "/featured/" {
                html = "<div class='grid'>" + TangxinFixtures261.card("blocked",title:"未成年") + "</div><a rel='next' href='/featured/2'>Next</a>"
            } else if path == "/featured/2" {
                html = "<div class='grid'></div><a rel='next' href='/featured/3'>Next</a>"
            } else if path == "/featured/3" {
                html = "<article class='card'></article><a rel='next' href='/featured/4'>Next</a>"
            } else { html = "<div class='grid'>" + TangxinFixtures261.card("visible") + "</div>" }
            return Data(html.utf8)
        }))
        let pages = TangxinListModel(root:TangxinPolicy.featured,client:sequence)
        await pages.start()
        precondition(pages.videos.isEmpty && pages.pageState == .filtered && pages.next?.path == "/featured/2")
        for _ in 0..<20 { await pages.nearBottom(tail:TangxinPolicy.featured) }
        precondition(pages.pageState == .filtered && pages.next?.path == "/featured/2")
        await pages.more()
        precondition(pages.videos.isEmpty && pages.pageState == .sourceEmpty && pages.next?.path == "/featured/3")
        await pages.more()
        precondition(pages.videos.isEmpty && pages.pageState == .structureChanged && pages.next?.path == "/featured/4")
        await pages.more()
        precondition(pages.videos.count == 1 && pages.pageState == .content && pages.next == nil)
        let duplicates = TangxinClient(transport:OnlineTransport(loader:{ request in
            let next = request.url!.path.hasSuffix("2") ? "/featured/3" : "/featured/2"
            return Data(("<div class='grid'>" + TangxinFixtures261.card("same") + "</div><a rel='next' href='\(next)'>Next</a>").utf8)
        }))
        let duplicateModel = TangxinListModel(root:TangxinPolicy.featured,client:duplicates)
        await duplicateModel.start()
        await duplicateModel.nearBottom(tail:duplicateModel.videos.last!.id)
        precondition(duplicateModel.videos.count == 1 && !duplicateModel.canAutomaticallyAdvance)
        for _ in 0..<20 { await duplicateModel.nearBottom(tail:duplicateModel.videos.last!.id) }
        precondition(duplicateModel.next?.path == "/featured/3")
        print("PASS264 production model concurrent automatic pagination, failure latch/manual retry, duplicate-only stop, empty manual advance, cancel/generation/reentry; synthetic")
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
