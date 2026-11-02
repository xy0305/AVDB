import SwiftUI
import UIKit

// Build 298 simulator host. Production MoviePosterGrid + visible upgrade.
// Transport is a neutral generated raster; no remote host is contacted.
@main
struct HomeHQHostApp: App {
    init() {
        ImageLoader.resetTestTransport()
        ListHQCoverCache.resetForTests()
        ImageLoader.testTransport = { url, pixels in
            try? await Task.sleep(nanoseconds: 250_000_000)
            try Task.checkCancellation()
            let side = min(pixels, VisibleHQPosterPolicy.maxPixelCap)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
                UIColor.systemTeal.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
                UIColor.systemOrange.setFill()
                ctx.fill(CGRect(x: side / 2, y: 0, width: side / 2, height: side))
            }
        }
    }
    var body: some Scene {
        WindowGroup { HomeHQFixture().accessibilityIdentifier("home-hq-root") }
    }
}

struct HomeHQFixture: View {
    private let movies: [Movie] = (0..<9).map { i in
        Movie(id: "neutral-\(i)", type: "0", number: "NEUTRAL-\(i)",
              thumbURL: "fixture://poster/thumb-\(i)", coverURL: "fixture://poster/cover-\(i)")
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                MoviePosterGrid(upgradesVisibleHQ: true, movies: movies)
                    .accessibilityIdentifier("home-hq-grid")
            }
        }
    }
}
