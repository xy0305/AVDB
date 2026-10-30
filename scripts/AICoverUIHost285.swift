import SwiftUI
import UIKit

// Build 285 screenshot host: the production AICoverHeroControl / AICoverViewer / AICoverSettingsSection
// + AICoverEnhanceModel + the bundled Core ML model on a NEUTRAL synthetic 378×538 cover
// (simulator → Core ML CPU only; timings here are not device timings).
@main
struct AICoverHostApp: App {
    init() {
        let a = ProcessInfo.processInfo.arguments
        if a.contains("--clear-ai-cache") { AICoverDiskCache.shared.clear() }
        if let i = a.firstIndex(of: "--mode"), i + 1 < a.count { UserDefaults.standard.set(a[i + 1], forKey: AICoverEnhanceMode.defaultsKey) }
    }
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--settings") {
                NavigationStack { Form { AICoverSettingsSection() }.navigationTitle("设置") }
            } else { HeroFixture() }
        }
    }
}

struct HeroFixture: View {
    @StateObject private var model = AICoverEnhanceModel()
    @State private var viewer = false
    private let hq = ProcessInfo.processInfo.arguments.contains("--hq")
    private var cover: UIImage {
        let name = hq ? "neutral_422x600" : "neutral_378x538"
        let url = Bundle.main.url(forResource: name, withExtension: "png")!
        let image = UIImage(contentsOfFile: url.path)!
        guard hq else { return image }
        // HQ stand-in: a 1032×1468 "native" portrait (never enhanced).
        return UIGraphicsImageRenderer(size: CGSize(width: 1032, height: 1468), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: 1032, height: 1468))
        }
    }
    var body: some View {
        let image = cover
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        Image(uiImage: model.display(image)).resizable().scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height * 0.72, alignment: .top).clipped()
                            .contentShape(Rectangle()).onTapGesture { viewer = true }
                            .accessibilityIdentifier("detail-hero-artwork")
                        LinearGradient(colors: [.clear, Color(red: 0.2, green: 0.2, blue: 0.24)], startPoint: .center, endPoint: .bottom)
                            .frame(height: 260).allowsHitTesting(false)
                        VStack(spacing: 8) {
                            Text("NEUTRAL-285 示例标题").font(.title2.bold())
                            Text("NEUTRAL-285 · 2026-10-30 · 2 小时 0 分钟").font(.subheadline.weight(.semibold))
                        }.foregroundStyle(.white).padding(.bottom, 26)
                    }
                    Color(red: 0.2, green: 0.2, blue: 0.24).frame(height: 400)
                }
            }
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .top) {
                HStack {
                    circle("chevron.left")
                    Spacer()
                    AICoverHeroControl(model: model) { viewer = true }.padding(.trailing, 8)
                    circle("magnifyingglass")
                }.padding(.horizontal, 16).padding(.top, 6)
            }
        }
        .background(Color(red: 0.2, green: 0.2, blue: 0.24))
        .task {
            model.prepare(image: image, source: "https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/neutral00285/neutral00285pl.jpg",
                          nativeWidth: Int(image.size.width), nativeHeight: Int(image.size.height),
                          mode: .current, autoAllowed: true)
            if ProcessInfo.processInfo.arguments.contains("--hold-original") {
                while !model.isEnhanced { try? await Task.sleep(nanoseconds: 200_000_000) }
                model.showingOriginal = true
            }
            if ProcessInfo.processInfo.arguments.contains("--open-viewer") { viewer = true }
        }
        .fullScreenCover(isPresented: $viewer) { AICoverViewer(image: image, model: model) }
    }
    private func circle(_ icon: String) -> some View {
        Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 44, height: 44).background(.black.opacity(0.3), in: Circle())
    }
}
