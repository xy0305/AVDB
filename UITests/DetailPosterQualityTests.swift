import XCTest
import UIKit
import ImageIO
import SwiftUI
@testable import AVDB

final class OnlineSubtitleModelTests: XCTestCase {
    @MainActor private func awaitModelState(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !predicate() && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(predicate(), "Expected model state within five seconds")
    }
    @MainActor func testNoAutomaticRequestAndVideoClearCancelsStaleResult() async throws {
        var calls = 0
        let body = Data(#"{"code":0,"data":[{"url":"https://subtitle.v.geilijiasu.com/AA/BB/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.srt","name":"self authored","ext":"srt","languages":[] }]}"#.utf8)
        let model = OnlineSubtitleModel(fetch: { _, _ in
            calls += 1
            try? await Task.sleep(nanoseconds: 80_000_000) // deliberately ignore cancellation to test generation guard
            return body
        })
        model.query = "公开查询"
        XCTAssertEqual(calls, 0); XCTAssertTrue(model.results.isEmpty)
        model.search()
        await Task.yield()
        model.clear()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(model.results.isEmpty); XCTAssertTrue(model.cues.isEmpty)
        XCTAssertNil(model.selected); XCTAssertEqual(model.query, "")
        model.query = "新视频"; model.search()
        try await awaitModelState { !model.busy && model.results.count == 1 }
        XCTAssertEqual(model.results.count, 1); XCTAssertNil(model.selected)
        XCTAssertTrue(model.cues.isEmpty) // never auto-select first result
    }
    @MainActor func testManualSelectionCloseAndOffsetReset() async throws {
        var downloads = 0
        let model = OnlineSubtitleModel(fetch: { _, search in
            XCTAssertFalse(search); downloads += 1
            return Data("1\n00:00:01,000 --> 00:00:02,000\n自创\n".utf8)
        })
        let row = OnlineSubtitleCandidate(id: "one", name: "自创", language: "未知", ext: "srt", url: URL(string: "https://subtitle.v.geilijiasu.com/AA/BB/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.srt")!)
        model.offset = 3; model.choose(row)
        try await awaitModelState { !model.busy && model.selected == row && model.cues.count == 1 }
        XCTAssertEqual(downloads, 1); XCTAssertEqual(model.cues.count, 1)
        XCTAssertEqual(model.offset, 0); XCTAssertEqual(model.selected, row)
        model.disable(); XCTAssertTrue(model.cues.isEmpty); XCTAssertNil(model.selected)
        XCTAssertEqual(model.offset, 0)
    }
    @MainActor func testDisableDuringDownloadRejectsLateCompletionAndCanReselect() async throws {
        let row = OnlineSubtitleCandidate(id: "late", name: "自创", language: "未知", ext: "srt", url: URL(string: "https://subtitle.v.geilijiasu.com/AA/BB/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.srt")!)
        let model = OnlineSubtitleModel(fetch: { _, _ in
            // Ignore Task cancellation on purpose: generation must still reject it.
            let data = Data("1\n00:00:00,000 --> 00:02:00,000\n外置字幕\n".utf8)
            return await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { continuation.resume(returning: data) }
            }
        })
        model.choose(row)
        await Task.yield()
        XCTAssertTrue(model.busy)
        model.disable()
        XCTAssertFalse(model.busy); XCTAssertTrue(model.cues.isEmpty); XCTAssertNil(model.selected)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(model.cues.isEmpty); XCTAssertNil(model.selected)
        XCTAssertEqual(model.status, "字幕已关闭")
        for time in [0.0, 1.0, 7.0, 45.0, 119.0] {
            XCTAssertEqual(OnlineSubtitleParser.display(model.cues, at: time, offset: model.offset), "")
        }
        model.choose(row)
        try await awaitModelState { !model.busy && model.selected == row && !model.cues.isEmpty }
        XCTAssertEqual(model.selected, row); XCTAssertFalse(model.cues.isEmpty)
        XCTAssertEqual(OnlineSubtitleParser.display(model.cues, at: 45, offset: 0), "外置字幕")
    }
}

final class DetailPosterQualityTests: XCTestCase {
    private func jpeg(_ width: Int, _ height: Int, orientation: Int = 1) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.gray.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image.cgImage!, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
    func testActualDecodedNativeFrontEXIFAndInvalidImages() {
        let wrap = DetailPosterResolver.decode(data: jpeg(800, 538), sourceURL: "https://tp.spfcas.com/covers/test.jpg", derive: true)!
        XCTAssertEqual(wrap.quality.width, 376); XCTAssertEqual(wrap.quality.height, 538)
        XCTAssertFalse(wrap.quality.originalPortrait)
        let full = DetailPosterResolver.decode(data: jpeg(1000, 700, orientation: 6), sourceURL: "official", derive: true)!
        XCTAssertEqual(full.quality.width, 700); XCTAssertEqual(full.quality.height, 1000)
        XCTAssertTrue(full.quality.originalPortrait)
        XCTAssertEqual(DetailPosterQuality.winner([wrap.quality, full.quality])?.source, "official")
        XCTAssertNil(DetailPosterResolver.decode(data: jpeg(147, 200), sourceURL: "thumbnail", derive: true))
        XCTAssertNil(DetailPosterResolver.decode(data: Data("<html>blocked</html>".utf8), sourceURL: "invalid", derive: true))
        XCTAssertNil(DetailPosterResolver.decode(data: jpeg(800, 538), sourceURL: "https://tp.spfcas.com/covers/test.jpg", derive: false))
        let large = DetailPosterResolver.decode(data: jpeg(1400, 2000), sourceURL: "large", derive: false)!
        XCTAssertEqual(large.quality.height, 2000)
        XCTAssertEqual(large.image.cgImage?.height, 1800)
        XCTAssertEqual(large.quality.score, 2000)
        let original = DetailPosterResolver.decode(data: jpeg(1778, 2530), sourceURL: "amazon-original", derive: false)!
        XCTAssertEqual(original.quality.width, 1778)
        XCTAssertEqual(original.quality.height, 2530)
        XCTAssertEqual(original.image.cgImage?.height, 1800)
        XCTAssertTrue(original.quality.originalPortrait)
        XCTAssertEqual(DetailPosterQuality.winner([large.quality, original.quality])?.source, "amazon-original")
    }
    func testTenhowOriginalIdentityAndOriginalCategoryExclusion() throws {
        func movie(_ type: String, _ number: String = "MEYD-575") throws -> Movie {
            let json: [String: Any] = ["id":"tenhow", "type":type, "number":number,
                "actors":[["id":"actor", "name":"蓮実クレア", "other_name":"蓮見クレア", "name_zht":"not an identity"]]]
            return try JSONDecoder().decode(Movie.self, from: JSONSerialization.data(withJSONObject:json))
        }
        let censored = try movie("0")
        XCTAssertEqual(DetailPosterResolver.tenhowPaths(censored), ["/hasumi_kurea.html"])
        for actor in [["id":"actor", "keyword":"蓮実クレア", "name_zht":"JULIA"],
                      ["id":"actor", "other_name":"蓮見クレア", "name_zht":"JULIA"]] {
            let data = try JSONSerialization.data(withJSONObject:["id":"raw", "type":"0", "number":"MEYD-575", "actors":[actor]])
            XCTAssertEqual(DetailPosterResolver.tenhowPaths(try JSONDecoder().decode(Movie.self, from:data)), ["/hasumi_kurea.html"])
        }
        let rawNames = try JSONSerialization.data(withJSONObject:["id":"raw", "type":"0", "number":"MEYD-575", "actor_names":["蓮実クレア"]])
        XCTAssertEqual(DetailPosterResolver.tenhowPaths(try JSONDecoder().decode(Movie.self, from:rawNames)), ["/hasumi_kurea.html"])
        for type in ["1", "2", "3", "uncensored", "western", "fc2"] {
            XCTAssertTrue(DetailPosterResolver.tenhowPaths(try movie(type)).isEmpty)
        }
        XCTAssertTrue(DetailPosterResolver.tenhowPaths(try movie("0", "FC2-PPV-1234567")).isEmpty)
        XCTAssertNotEqual(DetailPosterResolver.identity(movie:censored, account:"a"), DetailPosterResolver.identity(movie:censored, account:"b"))
        XCTAssertEqual(DetailPosterResolver.decode(data:jpeg(1055,1500),sourceURL:"https://www.tenhow.net/images/B084SXDZYQ.jpg",derive:true)?.quality.score,1500)
    }
    func testVerifiedDMMMetadataAndOriginalPolicy() throws {
        let cover = "https://pics.dmm.co.jp/mono/movie/adult/118abf295/118abf295pl.jpg?w=200#preview"
        func movie(_ type: String, _ number: String = "ABF-295") throws -> Movie {
            let json: [String: Any] = ["id":"dmm", "type":type, "number":number, "cover_url":cover]
            return try JSONDecoder().decode(Movie.self, from: JSONSerialization.data(withJSONObject:json))
        }
        let expected = "https://awsimgsrc.dmm.co.jp/pics_dig/mono/movie/118abf295/118abf295ps.jpg"
        XCTAssertTrue(DetailPosterResolver.validatedSources(try movie("0")).contains(expected))
        XCTAssertFalse(DetailPosterResolver.validatedSources(try movie("0", "ABF-296")).contains(expected))
        for type in ["1", "2", "3", "uncensored", "western", "fc2"] {
            XCTAssertFalse(DetailPosterResolver.validatedSources(try movie(type)).contains(expected))
        }
        // Real decoder failure checks, not a synthetic 'placeholder' hash.
        XCTAssertNil(DetailPosterResolver.decode(data: Data("<html>now_printing</html>".utf8), sourceURL:expected, derive:true))
        XCTAssertNil(DetailPosterResolver.decode(data: jpeg(147,200), sourceURL:expected, derive:true))
    }
    func testClickedSeedDoesNotRequireDetailMetadata() throws {
        let json: [String: Any] = ["id":"seed", "type":"0", "number":"MEYD-575",
            "cover_url":"https://tp.spfcas.com/covers/seed.jpg", "actor_names":["蓮実クレア"]]
        let seed = try JSONDecoder().decode(Movie.self, from: JSONSerialization.data(withJSONObject:json))
        XCTAssertNotNil(DetailPosterResolver.navigationSeed(seed, movieID:"seed"))
        XCTAssertNil(DetailPosterResolver.navigationSeed(seed, movieID:"another"))
        XCTAssertEqual(DetailPosterResolver.tenhowPaths(seed), ["/hasumi_kurea.html"])
        let incomplete = try JSONDecoder().decode(Movie.self, from: Data("{\"id\":\"seed\",\"type\":\"0\",\"number\":\"MEYD-575\"}".utf8))
        XCTAssertNil(DetailPosterResolver.navigationSeed(incomplete, movieID:"seed"))
    }
    func testResolutionPreferenceAndDeterministicTies() {
        let crop = DetailPosterQuality(source: "crop", width: 700, height: 1000, originalPortrait: false)
        let near = DetailPosterQuality(source: "original", width: 672, height: 960, originalPortrait: true)
        let low = DetailPosterQuality(source: "low", width: 376, height: 538, originalPortrait: true)
        XCTAssertEqual(DetailPosterQuality.winner([crop, near, low])?.source, "original")
        XCTAssertEqual(DetailPosterQuality.winner([low, crop])?.source, "crop")
        let a = DetailPosterQuality(source: "a", width: 700, height: 1000, originalPortrait: true)
        let z = DetailPosterQuality(source: "z", width: 700, height: 1000, originalPortrait: true)
        XCTAssertEqual(DetailPosterQuality.winner([z, a])?.source, "a")
        XCTAssertEqual(DetailPosterQuality.winner([a, z])?.source, "a")
    }
    func testLowFirstHighLaterSinglePublicationAndBudget() async {
        let low = DetailPosterResolver.decode(data: jpeg(376, 538), sourceURL: "low", derive: false)!
        let high = DetailPosterResolver.decode(data: jpeg(700, 1000), sourceURL: "high", derive: false)!
        let values: [DetailPosterResolver.DecodedPoster] = await DetailPosterSelection.collect(sources: ["low", "high", "invalid", "timeout"], budget: 0.15) { source, _ in
            do {
                try await Task.sleep(nanoseconds: source == "timeout" ? 2_000_000_000 : source == "high" ? 50_000_000 : 5_000_000)
            } catch { return nil }
            return source == "low" ? low : source == "high" ? high : nil
        }
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(DetailPosterQuality.winner(values.map(\.quality))?.source, "high")
        let generation = UUID()
        var presentation = DetailPosterPresentation<Int>(key: "new/account", generation: generation, layout: .resolving)
        presentation.complete(1, key: "old/account", generation: generation)
        XCTAssertNil(presentation.layout.artwork)
        presentation.complete(2, key: "new/account", generation: UUID())
        XCTAssertNil(presentation.layout.artwork)
        presentation.complete(7, key: "new/account", generation: generation)
        presentation.complete(9, key: "new/account", generation: generation)
        XCTAssertEqual(presentation.layout.artwork, 7)
        let task = Task { await DetailPosterSelection.collect(sources: ["late"], budget: 1) { _, _ -> Int? in
            try? await Task.sleep(nanoseconds: 500_000_000); return 99
        } }
        task.cancel()
        let cancelled = await task.value
        XCTAssertTrue(cancelled.isEmpty)
    }
}

/// Independent behavioral tests: no upstream implementation or fixtures copied.
final class Amane022RegressionTests: XCTestCase {
    func testAlphaPNGAtJPGURLProducesValidFrontAndInvalidCannotWin() {
        let flags = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(data: nil, width: 800, height: 538, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: flags)!
        context.clear(CGRect(x: 0, y: 0, width: 800, height: 538))
        context.setFillColor(UIColor.green.cgColor)
        context.fill(CGRect(x: 424, y: 0, width: 376, height: 538))
        let bytes = NSMutableData()
        let output = CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(output, context.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(output))
        let url = "https://tp.spfcas.com/covers/alpha.jpg"
        let result = DetailPosterResolver.decode(data: bytes as Data, sourceURL: url, derive: true)
        XCTAssertNotNil(result, "PNG alpha bytes must work even when the URL suffix says JPG")
        XCTAssertEqual(result?.image.cgImage?.width, 376)
        XCTAssertEqual(result?.image.cgImage?.height, 538)
        XCTAssertEqual(result?.quality.width, 376)
        XCTAssertFalse(result?.quality.originalPortrait ?? true)
        let invalid = DetailPosterResolver.decode(data: Data("<html>failure</html>".utf8), sourceURL: "invalid", derive: true)
        XCTAssertNil(invalid)
        XCTAssertEqual(DetailPosterQuality.winner([result, invalid].compactMap { $0?.quality })?.source, url)
        for (w, h) in [(800,538), (1350,1000), (1650,1000), (2,1)] {
            if let rect = FrontPosterPolicy.cropRect(width: w, height: h, source: url) {
                XCTAssertGreaterThan(rect.width, 0); XCTAssertGreaterThan(rect.height, 0)
                XCTAssertTrue(CGRect(x: 0, y: 0, width: w, height: h).contains(rect))
                XCTAssertEqual(rect.maxX, CGFloat(w))
            }
        }
        for (w, h) in [(0,538), (800,0), (-1,538), (100,200), (1920,1080)] {
            XCTAssertNil(FrontPosterPolicy.cropRect(width: w, height: h, source: url))
        }
    }

    @MainActor private final class Source: ObservableObject {
        @Published var url = "fixture://poster/wrap"
    }
    private struct ReusedImage: View {
        @ObservedObject var source: Source
        var body: some View {
            JavDBImage(url: source.url).frame(width: 200, height: 240)
                .animation(.easeInOut(duration: 1), value: source.url)
        }
    }
    @MainActor func testReusedImageRejectsPreviousArtworkWhenNewSourceFails() async throws {
        let source = Source()
        let host = UIHostingController(rootView: ReusedImage(source: source))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 240))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.frame = window.bounds
        func chromaticFraction() -> Double {
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let flags = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: flags)!
            context.draw(image.cgImage!, in: CGRect(x: 0, y: 0, width: 64, height: 64))
            let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
            var chromatic = 0
            for i in stride(from: 0, to: 64 * 64 * 4, by: 4) {
                let channels = [Int(pixels[i]), Int(pixels[i+1]), Int(pixels[i+2])]
                if channels.max()! - channels.min()! > 50 { chromatic += 1 }
            }
            return Double(chromatic) / 4096
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertGreaterThan(chromaticFraction(), 0.5, "The real JavDBImage must first render the neutral colorful artwork")
        let frame = host.view.frame
        source.url = "invalid://new-artwork"
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertLessThan(chromaticFraction(), 0.1, "Failed new identity must show a neutral placeholder, never the previous winner")
        XCTAssertEqual(host.view.frame, frame, "Image publication must not change its proposed layout")
        source.url = "fixture://poster/portrait"
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertGreaterThan(chromaticFraction(), 0.5)
        XCTAssertEqual(host.view.frame, frame)
    }
}

final class WesternCoverRegressionTests: XCTestCase {
    private func identity() -> WesternCoverPolicy.Identity {
        WesternCoverPolicy.identity(type: "2", number: "Blackedraw.2026.10.13", title: "Neutral Scene", date: "2026-10-13", minutes: 35)!
    }
    private func record() -> [String: Any] {
        ["id":"4d2c0748-71ea-4f1b-b486-94db042c7b34", "title":"Neutral Scene", "date":"2026-10-13", "duration":2091,
         "site":["short_name":"blackedraw", "name":"Blacked Raw"], "url":"https://www.blackedraw.com/videos/neutral-scene", "external_id":"blackedraw:neutral-scene"]
    }
    func testStrictIdentityAmbiguityDateSeriesAndCatalogIsolation() {
        let i = identity(), r = record()
        XCTAssertTrue(WesternCoverPolicy.recordMatches(r, identity: i))
        XCTAssertNotNil(WesternCoverPolicy.uniqueRecord([r], identity: i))
        XCTAssertNil(WesternCoverPolicy.uniqueRecord([r,r], identity: i))
        for change: [String: Any] in [["date":"2026-10-14"], ["title":"Neutral Scene 2"], ["duration":2600], ["external_id":"other:neutral-scene"], ["url":"https://attacker.test/videos/neutral-scene"], ["site":["short_name":"blacked", "name":"Blacked"]]] {
            XCTAssertFalse(WesternCoverPolicy.recordMatches(r.merging(change) { _, new in new }, identity: i))
        }
        for type in ["0", "1", "3", "western", ""] {
            XCTAssertNil(WesternCoverPolicy.identity(type: type, number: "Blackedraw.2026.10.13", title: "Neutral Scene", date: "2026-10-13", minutes: 35))
        }
        XCTAssertNil(WesternCoverPolicy.identity(type: "2", number: "FC2-PPV-1234567", title: "Neutral Scene", date: "2026-10-13", minutes: 35))
        XCTAssertNil(WesternCoverPolicy.identity(type: "2", number: "Blackedraw.2026.10.13", title: "Blackedraw.2026.10.13", date: "2026-10-13", minutes: 35))
        XCTAssertNil(WesternCoverPolicy.identity(type: "2", number: "Blackedraw.2026.10.13", title: "Neutral Scene", date: "2026-10-14", minutes: 35))
        let urlIdentity = WesternCoverPolicy.Identity(title: i.title, date: i.date, minutes: i.minutes, officialURL: "https://www.blackedraw.com/videos/another-scene")
        XCTAssertFalse(WesternCoverPolicy.recordMatches(r, identity: urlIdentity))
    }
    func testDerivativeSSRFAndCredentialDestinationsFailClosed() async {
        for bad in ["https://thumb.theporndb.net/800x1200/smart/filters:upscale()/x.jpg", "https://cdn.theporndb.net/scene/x/background/c/large.jpg", "https://cdn.blackedraw.com.evil.test/scene/videoimages/x/mainLandscape/x.jpg", "https://127.0.0.1/scene/x/background/a.jpg", "http://cdn.theporndb.net/scene/x/background/a.jpg", "https://cdn.theporndb.net/scene/x/background/a.jpg?token=x", "https://user@cdn.theporndb.net/scene/x/background/a.jpg"] {
            XCTAssertFalse(WesternCoverPolicy.imageAllowed(URL(string: bad)!))
        }
        let cdn = URL(string: "https://cdn.theporndb.net/scene/x/background/a.jpg")!
        XCTAssertTrue(WesternCoverPolicy.imageAllowed(cdn))
        XCTAssertFalse(WesternCoverPolicy.apiAllowed(cdn))
        let rejected = await WesternCoverService.request(cdn, token: "neutral-not-a-real-token", deadline: ProcessInfo.processInfo.systemUptime + 1)
        XCTAssertNil(rejected)
        let guarder = WesternRedirectGuard()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let original = URL(string: "https://api.theporndb.net/scenes")!
        let task = session.dataTask(with: original)
        for target in [cdn, original, URL(string:"https://api.theporndb.net.evil.test/scenes")!] {
            let response = HTTPURLResponse(url: original, statusCode: 302, httpVersion: nil, headerFields: nil)!
            var called = false
            guarder.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: target)) { redirect in called = true; XCTAssertNil(redirect) }
            XCTAssertTrue(called)
        }
    }
    private func jpeg(_ width: Int, _ height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { c in
            UIColor.gray.setFill(); c.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }.jpegData(compressionQuality: 0.8)!
    }
    func testActualNativeDimensionsWidePreservedAndLateHigherWinnerPublishedOnce() async throws {
        let low = try XCTUnwrap(DetailPosterResolver.decode(data: jpeg(640,360), sourceURL: "low", derive: false, native: true))
        let high = try XCTUnwrap(DetailPosterResolver.decode(data: jpeg(1920,1080), sourceURL: "high", derive: false, native: true))
        XCTAssertEqual(high.quality.width, 1920); XCTAssertEqual(high.quality.height, 1080)
        XCTAssertEqual(high.image.size.width / high.image.size.height, 16.0 / 9.0, accuracy: 0.001)
        let results = await DetailPosterSelection.collect(sources: ["low","high","low"], budget: 0.7) { s, _ in
            if s == "high" { try? await Task.sleep(nanoseconds: 150_000_000) }
            return s == "high" ? high.quality : low.quality
        }
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(WesternCoverPolicy.winner(results)?.source, "high")
        let generation = UUID()
        var presentation = DetailPosterPresentation<DetailPosterQuality>(key: "movie-A", generation: generation, layout: .resolving)
        presentation.complete(WesternCoverPolicy.winner(results), key: "movie-A", generation: generation)
        presentation.complete(low.quality, key: "movie-A", generation: generation)
        XCTAssertEqual(presentation.layout.artwork?.source, "high")
        XCTAssertNil(DetailPosterResolver.decode(data: Data([1,2,3]), sourceURL: "corrupt", derive: false, native: true))
        let movie = Movie(id: "one", type: "2", number: "Blackedraw.2026.10.13", thumbURL: "https://tp.spfcas.com/small_covers/one.jpg", coverURL: "https://tp.spfcas.com/covers/one.jpg")
        XCTAssertEqual(DetailPosterResolver.validatedSources(movie).count, 2)
        XCTAssertTrue(WesternCoverPolicy.eligible(width: 1000, height: 562))
    }
    func testBudgetTimeoutAndInvalidationDoNotPublishLateResults() async throws {
        let result = await DetailPosterSelection.collect(sources: ["a","b","c","d","e","f","g"], budget: 0.08) { _, _ in
            do { try await Task.sleep(nanoseconds: 250_000_000); return 1 } catch { return nil }
        }
        XCTAssertTrue(result.isEmpty)
        let cache = DetailPosterCache<Int>()
        let flight = Task { await cache.value(key: "old-account-generation") {
            try? await Task.sleep(nanoseconds: 150_000_000); return 8
        } }
        try await Task.sleep(nanoseconds: 20_000_000)
        cache.invalidate()
        _ = await flight.value
        if case .resolving = cache.snapshot(key: "old-account-generation") {} else { XCTFail("Old token completion entered new cache") }
        XCTAssertEqual(DetailPosterSelection.maxAttempts, 6); XCTAssertEqual(DetailPosterSelection.concurrency, 2); XCTAssertEqual(DetailPosterSelection.totalBudget, 12)
    }
    final class Store: ExternalTokenStore {
        var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    @MainActor func testTokenSaveClearNamespaceAndNoDefaultsSecret() throws {
        let suite = "western-neutral-" + UUID().uuidString
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        let store = Store(), s = WesternCoverSettings(store: Store(), defaults: d)
        XCTAssertFalse(s.enabled); XCTAssertFalse(s.hasToken)
        let settings = WesternCoverSettings(store: store, defaults: d), old = settings.namespace
        try settings.save(enabled: true, replacement: "neutral-only")
        XCTAssertTrue(settings.hasToken); XCTAssertNotEqual(old, settings.namespace)
        XCTAssertFalse(d.dictionaryRepresentation().values.contains { ($0 as? String) == "neutral-only" })
        let saved = settings.namespace
        try settings.clear(); XCTAssertFalse(settings.hasToken); XCTAssertNotEqual(saved, settings.namespace)
        XCTAssertNil(store.value)
        XCTAssertThrowsError(try settings.save(enabled: true, replacement: "bad\nvalue"))
        XCTAssertFalse(settings.hasToken)
    }
    func testData18MovieSceneDateDurationAndActualPrimaryURLs() {
        let html = #"<title>Neutral Scene Porn Scene | DATA18</title><h1><a href="https://www.data18.com/scenes/123-neutral-scene">Neutral Scene</a></h1><a href="https://www.data18.com/studios/blacked-raw">Blacked Raw</a><a href="https://www.data18.com/scenes#date20261013">October 13, 2026</a> | Duration: <b>34:51</b><img id="playpriimage" src="https://cdn.dt18.com/media/scenes/1/2/a.jpg"><a href="https://www.data18.com/g/scenes/123/3117?c=1">Official</a>"#
        XCTAssertNotNil(WesternCoverPolicy.dataMatch(html, identity: identity()))
        for bad in [html.replacingOccurrences(of: "Porn Scene", with: "Porn Movie"), html.replacingOccurrences(of: "date20261013", with: "date20261014"), html.replacingOccurrences(of: "34:51", with: "59:51"), html.replacingOccurrences(of: "studios/blacked-raw", with: "studios/blacked")] {
            XCTAssertNil(WesternCoverPolicy.dataMatch(bad, identity: identity()))
        }
        let search = #"<a href="https://www.data18.com/scenes/123-neutral-scene" title="Neutral Scene"><p>Neutral Scene</p></a>"#
        XCTAssertEqual(WesternCoverPolicy.dataLinks(search, title: "Neutral Scene"), ["https://www.data18.com/scenes/123-neutral-scene"])
        XCTAssertEqual(WesternCoverPolicy.primaryImage(#"<img src="https://bdn.dt18.com/1/2/3/0.jpg">"#), "https://bdn.dt18.com/1/2/3/0.jpg")
        XCTAssertNil(WesternCoverPolicy.primaryImage(#"<img src="https://bdn.dt18.com/1/2/3/1.jpg">"#))
        XCTAssertNil(WesternCoverPolicy.primaryImage(#"<img src="https://bdn.dt18.com/1/2/3/0.jpg"><img src="https://bdn.dt18.com/4/5/6/0.jpg">"#))
    }
    func testDiscoveryReservationKeepsVerifiedWesternImagesAheadOfBaseline() async {
        let low = DetailPosterQuality(source: "javdb", width: 640, height: 360, originalPortrait: true)
        let high = DetailPosterQuality(source: "official", width: 1920, height: 1080, originalPortrait: true)
        let sources = (1...6).map { "legacy-\($0)" }
        let collected = await DetailPosterSelection.collect(sources: sources, budget: 0.4, discover: { _ in ["official"] }, reservedDiscoveries: 2) { source, _ in
            source == "official" ? high : low
        }
        XCTAssertEqual(collected.count, 6)
        XCTAssertTrue(collected.contains { $0.source == "official" })
        XCTAssertEqual(WesternCoverPolicy.winner(collected)?.source, "official")
        let japanese = await DetailPosterSelection.collect(sources: sources, budget: 0.4, discover: { _ in ["tenhow", "amazon"] }) { source, _ in source }
        XCTAssertEqual(Array(japanese.prefix(2)), ["legacy-1", "legacy-2"])
        XCTAssertTrue(japanese.contains("tenhow") && japanese.contains("amazon"))
        XCTAssertEqual(japanese.count, 6)
        XCTAssertThrowsError(try WesternCoverSettings(store: Store(), defaults: .standard).save(enabled: true, replacement: "contains space"))
    }
}
