import Foundation
import AVFoundation

@MainActor enum OnlineQualityRegression259 {
    static func run() async throws {
        var count = 0
        func check(_ value: Bool, _ name: String) { count += 1; precondition(value, name) }
        let root = URL(string: "https://cdn.example.net/neutral/index.m3u8")!
        func master(_ body: String) throws -> OnlineManifest {
            try OnlineManifest.parse(Data(("#EXTM3U\n" + body).utf8), at: root, root: root)
        }
        let ranked = try master("""
        #EXT-X-STREAM-INF:BANDWIDTH=800000,AVERAGE-BANDWIDTH=750000,RESOLUTION=1280x720,CODECS="avc1.4d401f,mp4a.40.2"
        low.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2"
        mid.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=4500000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2"
        high.m3u8
        """)
        check(ranked.variants.count == 3 && ranked.ladder.count == 3, "master ladder keeps variant URLs")
        check(ranked.ladder[2].width == 1920 && ranked.ladder[2].bandwidth == 4_500_000, "resolution and bandwidth metadata")
        check(ranked.ladder[0].averageBandwidth == 750_000 && ranked.ladder[0].codecs?.contains("avc1") == true, "average bandwidth and codecs")
        let highest = OnlineQualitySelector.select(ranked.ladder, preferHighest: true)
        check(highest.mode == .highest && highest.variant?.url?.absoluteString.hasSuffix("high.m3u8") == true, "highest resolution then bandwidth")
        check(highest.peakBitRate == 4_500_000 && highest.maximumResolution == CGSize(width: 1920, height: 1080), "finite session cap, not unbounded peak")
        check(highest.peakBitRate != Double.greatestFiniteMagnitude, "never uses infinite peak as highest")
        let tied = try master("""
        #EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1920x1080,CODECS="avc1.640028"
        first.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1920x1080,CODECS="avc1.640028"
        second.m3u8
        """)
        let tie = OnlineQualitySelector.select(tied.ladder, preferHighest: true)
        check(tie.variant?.order == 0 && tie.variant?.url?.absoluteString.hasSuffix("first.m3u8") == true, "equal resolution and bandwidth keep stable order")
        let bandwidthOnly = try master("""
        #EXT-X-STREAM-INF:BANDWIDTH=900000,CODECS="avc1.4d401f"
        a.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=4200000,CODECS="avc1.640028"
        b.m3u8
        """)
        let byBandwidth = OnlineQualitySelector.select(bandwidthOnly.ladder, preferHighest: true)
        check(byBandwidth.variant?.url?.absoluteString.hasSuffix("b.m3u8") == true && byBandwidth.maximumResolution == nil, "no resolution uses bandwidth")
        let mixed = try master("""
        #EXT-X-STREAM-INF:BANDWIDTH=9000000,CODECS="avc1.640028"
        bandwidth-only.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=1200000,RESOLUTION=1280x720,CODECS="avc1.4d401f"
        sized.m3u8
        """)
        check(OnlineQualitySelector.select(mixed.ladder, preferHighest: true).variant?.url?.absoluteString.hasSuffix("sized.m3u8") == true, "legal resolution outranks bandwidth-only")
        let unsupported = try master("""
        #EXT-X-STREAM-INF:BANDWIDTH=8000000,RESOLUTION=3840x2160,CODECS="vp09.00.41.08"
        vp9.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720,CODECS="avc1.4d401f"
        avc.m3u8
        """)
        let skipped = OnlineQualitySelector.select(unsupported.ladder, preferHighest: true)
        check(skipped.variant?.url?.absoluteString.hasSuffix("avc.m3u8") == true, "unsupported codec skipped")
        let none = try master("""
        #EXT-X-STREAM-INF:BANDWIDTH=8000000,RESOLUTION=3840x2160,CODECS="av01.0.08M.08"
        av1.m3u8
        """)
        let fallback = OnlineQualitySelector.select(none.ladder, preferHighest: true)
        check(fallback.mode == .unavailable && fallback.peakBitRate == nil && fallback.maximumResolution == nil, "all unsupported falls back without a cap")
        let single = try master("#EXT-X-STREAM-INF:BANDWIDTH=1800000,RESOLUTION=1280x720,CODECS=\"avc1.4d401f\"\nonly.m3u8\n")
        check(OnlineQualitySelector.select(single.ladder, preferHighest: true).variant?.height == 720, "single variant selected")
        let leaf = Data("#EXTM3U\n#EXTINF:4,\nneutral.ts\n#EXT-X-ENDLIST\n".utf8)
        let leafManifest = try OnlineManifest.parse(leaf, at: root, root: root)
        check(leafManifest.ladder.isEmpty && leafManifest.variants.isEmpty, "leaf has no ladder and existing URL remains")
        check(OnlineQualitySelector.select(leafManifest.ladder, preferHighest: true).mode == .automatic, "no variants keep existing automatic URL")
        do {
            _ = try master("#EXT-X-STREAM-INF:BANDWIDTH=nope,RESOLUTION=1920x1080\nbad.m3u8\n")
            preconditionFailure("malformed bandwidth accepted")
        } catch { check(OnlineFailure.classify(error) == .parse, "malformed bandwidth rejected") }
        do {
            _ = try master("#EXT-X-STREAM-INF:BANDWIDTH=1000,RESOLUTION=1920x\nbad.m3u8\n")
            preconditionFailure("malformed resolution accepted")
        } catch { check(OnlineFailure.classify(error) == .parse, "malformed resolution rejected") }
        let off = OnlineQualitySelector.select(ranked.ladder, preferHighest: false)
        check(off.mode == .automatic && off.peakBitRate == nil && off.maximumResolution == nil, "disabled preference keeps automatic")
        let manual = ranked.ladder[0]
        let picked = OnlineQualitySelector.select(ranked.ladder, preferHighest: true, manual: manual)
        check(picked.mode == .specific && picked.variant?.height == 720, "manual override retained")

        let suite = "neutral259." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        check(OnlineQualityPreference(preferences: preferences).preferHighest, "online default is highest")
        OnlineQualityPreference(preferHighest: false).save(preferences)
        check(!OnlineQualityPreference(preferences: preferences).preferHighest, "disable persists locally")
        let model = OnlinePlaybackModel(provider: OnlineProvider(transport: OnlineTransport(loader: { _ in Data() })), preferences: preferences)
        check(!model.preferHighestQuality, "model loads saved disable without a request")
        model.setPreferHighestQuality(true)
        check(preferences.bool(forKey: OnlineQualityPreference.storageKey), "toggle persists without querying")
        check(model.qualityStatus.contains("已开启"), "advanced status")

        let item = AVPlayerItem(url: URL(string: "https://cdn.example.net/neutral/high.m3u8")!)
        let applied = OnlineQualitySession.apply(highest, generation: 7, to: item)
        check(applied.generation == 7 && item.preferredPeakBitRate == 4_500_000, "player item peak applied")
        check(item.preferredMaximumResolution == CGSize(width: 1920, height: 1080), "player item resolution applied")
        let cleared = OnlineQualitySession.apply(.automatic, generation: 8, to: item)
        check(cleared.generation == 8 && item.preferredPeakBitRate == 0 && item.preferredMaximumResolution == .zero, "automatic clears hint")
        let plain = AVPlayerItem(url: URL(string: "https://cdn.example.net/neutral/plain.mp4")!)
        check(plain.preferredPeakBitRate == 0 && plain.preferredMaximumResolution == .zero, "115/plain session starts unconstrained")
        let dropped = OnlinePlaybackQualityStatus.display(choice: highest, observed: CGSize(width: 1280, height: 720))
        check(dropped.contains("最高") && dropped.contains("720p") && dropped.contains("网络降档"), "downshift is not labeled as still highest")
        let steady = OnlinePlaybackQualityStatus.display(choice: highest, observed: CGSize(width: 1920, height: 1080))
        check(steady.contains("最高") && steady.contains("1080p") && !steady.contains("网络降档"), "matching rendition is not a false downshift")

        // Late selection cannot publish after cancel, and preference toggle does not query.
        let slow = OnlineTransport(loader: { request in
            try await Task.sleep(nanoseconds: 200_000_000)
            return try OnlineRegression254.response(request)
        })
        let live = OnlinePlaybackModel(provider: OnlineProvider(transport: slow), preferences: preferences)
        let line = OnlineLine(source: .jable, recordID: "neutral", code: "DEMO-123", version: "neutral", lineKey: "0")
        live.choose(line, number: "DEMO-123", versions: false)
        live.cancelSelection()
        live.setPreferHighestQuality(false)
        try await Task.sleep(nanoseconds: 350_000_000)
        check(live.plan == nil, "cancelled/late resolution does not publish a plan or query")
        check(!live.preferHighestQuality, "preference change is local")
        print("PASS259", count, "synthetic ladder/selection/persistence/player-item/isolation assertions; no adult source or media")
    }
}
