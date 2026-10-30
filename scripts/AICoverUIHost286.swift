import SwiftUI
import UIKit

// Build 286 screenshot host. Production AICoverMetaChip / AICoverPressToCompare / AICoverViewer /
// AICoverSettingsSection + AICoverEnhanceModel + the bundled Core ML model, laid out like the production
// portrait hero (DetailPortraitGeometry numbers, top chrome = back + search only, metadata row, chip,
// play / action row) on the real IPX-706 800px jacket front crop (378×538). Simulator Core ML = CPU only.
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
    @State private var compareEvents = 0
    @State private var viewerOpens = 0
    private let args = ProcessInfo.processInfo.arguments
    private let cover: UIImage = {
        let url = Bundle.main.url(forResource: "ipx706_front_378x538", withExtension: "jpg")!
        return UIImage(contentsOfFile: url.path)!
    }()
    private let tint = Color(red: 0.52, green: 0.38, blue: 0.36)

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let imageHeight = min(width * 1.58, max(600, geo.size.height * 0.8))
            let titleTop = min(width * 1.06, max(390, geo.size.height * 0.56))
            let controlsTop = max(titleTop + 132, min(width * 1.42, geo.size.height * 0.64))
            ScrollView {
                ZStack(alignment: .top) {
                    Image(uiImage: model.display(cover)).resizable().scaledToFill()
                        .frame(width: width, height: imageHeight, alignment: .top).clipped()
                        .contentShape(Rectangle())
                        .onTapGesture { if model.viewerTapAllowed { viewerOpens += 1; viewer = true } }
                        .modifier(AICoverPressToCompare(model: model))
                        .accessibilityElement().accessibilityIdentifier("detail-hero-artwork")
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0.36), .init(color: tint.opacity(0.24), location: 0.57),
                        .init(color: tint.opacity(0.83), location: 0.86), .init(color: tint, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: imageHeight + 30).allowsHitTesting(false)
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            Text("IPX-706 · 2021-08-13 · 2 小时 30 分钟 · 中字")
                                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                                .padding(.horizontal, 18).padding(.top, 16)
                                .accessibilityIdentifier("portrait-hero-metadata")
                            if AICoverMetaChip.visible(model) {
                                AICoverMetaChip(model: model) { viewerOpens += 1; viewer = true }
                                    .padding(.horizontal, 18).padding(.top, 10).transition(.opacity)
                            }
                        }
                        .frame(minHeight: max(0, controlsTop - titleTop - 18), alignment: .bottom)
                        HStack(spacing: 12) {
                            Label("播放", systemImage: "play.fill").font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .overlay(Capsule().stroke(.white.opacity(0.72), lineWidth: 1.5))
                            HStack(spacing: 0) {
                                ForEach(["arrow.down.circle", "rectangle.stack.badge.plus", "heart", "checkmark.rectangle"], id: \.self) {
                                    Image(systemName: $0).font(.system(size: 22)).frame(width: 44, height: 44)
                                }
                            }
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .overlay(Capsule().stroke(.white.opacity(0.72), lineWidth: 1.5))
                        }
                        .padding(.horizontal, 18).padding(.top, 18)
                        Text("「IPX-706」").font(.system(size: 13)).frame(maxWidth: .infinity).padding(.top, 22)
                        HStack {
                            Text("播放资源:").font(.headline)
                            Text("115 原画").font(.subheadline).padding(.horizontal, 12).padding(.vertical, 6)
                                .overlay(Capsule().stroke(.white.opacity(0.5)))
                            Spacer()
                        }.padding(.horizontal, 18).padding(.top, 30)
                        Color.clear.frame(height: 400)
                        Text("\(compareEvents)").font(.system(size: 1)).opacity(0.01).accessibilityIdentifier("compare-events")
                        Text("\(viewerOpens)").font(.system(size: 1)).opacity(0.01).accessibilityIdentifier("viewer-opens")
                    }
                    .padding(.top, titleTop)
                }
                .foregroundStyle(.white)
                .frame(width: width)
            }
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .top) {
                // Production detailChrome after 286: back + search only.
                HStack { circle("chevron.left"); Spacer(minLength: 0); circle("magnifyingglass") }
                    .padding(.horizontal, 16).padding(.top, 6).accessibilityIdentifier("detail-chrome")
            }
        }
        .background(tint.ignoresSafeArea())
        .onChange(of: model.showingOriginal) { _, now in if now { compareEvents += 1 } }
        .task {
            let hq = args.contains("--hq")
            model.prepare(image: cover, source: "https://pics.dmm.co.jp/digital/video/ipx00706/ipx00706pl.jpg",
                          nativeWidth: hq ? 1032 : 378, nativeHeight: hq ? 1468 : 538, mode: .current, autoAllowed: true)
            if args.contains("--hold-original") {
                while !model.isEnhanced { try? await Task.sleep(nanoseconds: 200_000_000) }
                model.showingOriginal = true
            }
            if args.contains("--open-viewer") { viewer = true }
        }
        .fullScreenCover(isPresented: $viewer) { AICoverViewer(image: cover, model: model) }
    }
    private func circle(_ icon: String) -> some View {
        Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 44, height: 44).background(.black.opacity(0.3), in: Circle())
    }
}
