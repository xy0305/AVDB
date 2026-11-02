import SwiftUI
import UIKit

// Simulator host for the production upgrade view. Neutral rasters only.
@main
struct HomeHQHostApp: App {
    var body: some Scene { WindowGroup { Color.clear.accessibilityIdentifier("home-hq-root") } }
}

struct VisibleHQPosterUpgrade: View {
    let movie: Movie
    var body: some View {
        GeometryReader { geometry in
            let pixels = VisibleHQPosterPolicy.targetPixels(displayPoints: geometry.size, scale: UIScreen.main.scale)
            Color.clear.accessibilityIdentifier("visible-hq-upgrade")
                .task(id: pixels) {
                    guard let url = VisibleHQPosterPolicy.upgradeURL(movie: movie) else { return }
                    _ = await VisibleHQPosterScheduler.shared.upgrade(movie: movie, url: url, maxPixelSize: pixels)
                }
        }
    }
}
