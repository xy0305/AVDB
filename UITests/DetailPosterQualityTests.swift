import XCTest
import UIKit
import ImageIO
import SwiftUI
@testable import AVDB

final class Playback235URLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> Data)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class Playback235Tests: XCTestCase {
    @MainActor func testProductionAuthenticatedPostDeleteReadbackAndRejection() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Playback235URLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); Playback235URLProtocol.handler = nil }
        let sdk = JavDBSDK(client: APIClient(session: session, token: "neutral-fixture-noncredential"))
        var stored: String?
        var requests: [String] = []
        var reject = false
        var stale = false
        Playback235URLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer neutral-fixture-noncredential")
            let method = request.httpMethod!
            let path = request.url!.path
            requests.append(method + " " + path)
            if method == "POST" {
                if reject { return Data(#"{"success":0,"message":"controlled failure"}"#.utf8) }
                var parts = URLComponents(); parts.percentEncodedQuery = String(data: request.httpBody ?? Data(), encoding: .utf8)
                let desired = parts.queryItems?.first { $0.name == "status" }?.value
                if !stale { stored = desired }
                return Data(#"{"success":1,"data":{"review":null}}"#.utf8) // must not force ON from null
            }
            if method == "DELETE" {
                XCTAssertEqual(path, "/api/v1/movies/neutral/reviews/123456789")
                stored = nil
                return Data(#"{"success":1,"data":null}"#.utf8)
            }
            XCTAssertEqual(method, "GET"); XCTAssertEqual(path, "/api/v4/movies/neutral")
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            var movie: [String: Any] = ["id":"neutral", "number":"TEST-235"]
            if let stored { movie["review"] = ["id":123456789, "status":stored] }
            return try JSONSerialization.data(withJSONObject: ["success":1, "data":["movie":movie]])
        }
        let want = try await sdk.updateMovieReview("neutral", status: "want_watch")
        XCTAssertEqual(want, "want_watch")
        let off = try await sdk.updateMovieReview("neutral", status: nil); XCTAssertNil(off)
        let watched = try await sdk.updateMovieReview("neutral", status: "watched"); XCTAssertEqual(watched, "watched")
        let offAgain = try await sdk.updateMovieReview("neutral", status: nil); XCTAssertNil(offAgain)
        XCTAssertEqual(requests.filter { $0.hasPrefix("POST") }.count, 2)
        XCTAssertEqual(requests.filter { $0.hasPrefix("DELETE") }.count, 2)
        reject = true
        do { _ = try await sdk.updateMovieReview("neutral", status: "watched"); XCTFail("Rejected POST must not succeed") } catch {}
        reject = false; stale = true
        do { _ = try await sdk.updateMovieReview("neutral", status: "want_watch"); XCTFail("Unconfirmed write must not force ON") } catch {}
    }
    @MainActor func testHistoryGatePersistenceDedupDeleteAndAccountIsolation() throws {
        let suite = "avdb.235.test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let store = PlaybackHistoryStore(defaults: defaults, directory: directory)
        store.activate(accountID: 235)
        let scope = store.scope
        let a = Movie(id: "neutral-a", number: "TEST-001", title: "自创中性封面", coverURL: "https://example.test/cover.jpg")
        let b = Movie(id: "neutral-b", number: "TEST-002", title: "另一个测试作品", coverURL: "https://example.test/cover.jpg?token=DO-NOT-SAVE")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 90)).image { c in
            UIColor.systemTeal.setFill(); c.fill(CGRect(x: 0, y: 0, width: 60, height: 90))
        }
        var gate = PlaybackHistoryStartGate()
        XCTAssertTrue(store.items.isEmpty) // merely holding movie/detail metadata is not a play
        XCTAssertFalse(gate.sample(time: 0, playing: false, seeking: false, failed: false))
        XCTAssertFalse(gate.sample(time: 0, playing: true, seeking: false, failed: false))
        XCTAssertFalse(gate.sample(time: 0, playing: true, seeking: false, failed: false))
        XCTAssertFalse(gate.sample(time: 30, playing: true, seeking: true, failed: false))
        XCTAssertFalse(gate.sample(time: 30, playing: true, seeking: false, failed: true))
        XCTAssertFalse(gate.sample(time: 0.5, playing: true, seeking: false, failed: false))
        XCTAssertTrue(gate.sample(time: 1, playing: true, seeking: false, failed: false))
        store.record(a, artwork: image, scope: scope, at: Date(timeIntervalSince1970: 1))
        XCTAssertFalse(gate.sample(time: 1.5, playing: true, seeking: false, failed: false))
        store.record(b, artwork: nil, scope: scope, at: Date(timeIntervalSince1970: 2))
        store.record(a, artwork: image, scope: scope, at: Date(timeIntervalSince1970: 3))
        XCTAssertEqual(store.items.map(\.id), [a.id, b.id]); XCTAssertNil(store.items.last?.coverURL)
        XCTAssertNotNil(store.artwork(for: a.id))
        let restored = PlaybackHistoryStore(defaults: defaults, directory: directory)
        restored.activate(accountID: 235)
        XCTAssertEqual(restored.items, store.items); XCTAssertNotNil(restored.artwork(for: a.id))
        let encoded = String(data: defaults.data(forKey: "avdb.play.history.v1.user-235")!, encoding: .utf8)!
        XCTAssertFalse(encoded.contains("token")); XCTAssertFalse(encoded.contains("DO-NOT-SAVE"))
        restored.activate(accountID: nil); XCTAssertTrue(restored.items.isEmpty)
        restored.record(a, artwork: nil, scope: scope); XCTAssertTrue(restored.items.isEmpty)
        restored.activate(accountID: 999); XCTAssertTrue(restored.items.isEmpty)
        restored.record(a, artwork: nil, scope: scope); XCTAssertTrue(restored.items.isEmpty)
        restored.activate(accountID: 235); XCTAssertEqual(restored.items.count, 2)
        restored.remove(a.id); XCTAssertEqual(restored.items.map(\.id), [b.id]); XCTAssertNil(restored.artwork(for: a.id))
        restored.clear(); XCTAssertTrue(restored.items.isEmpty)
        let empty = PlaybackHistoryStore(defaults: defaults, directory: directory); empty.activate(accountID: 235)
        XCTAssertTrue(empty.items.isEmpty)
        for bad in ["https://115.com/private.jpg", "https://example.test/a.mp4", "https://user:pass@example.test/a.jpg", "https://example.test/a.jpg?sign=x"] {
            XCTAssertNil(PlaybackHistoryStore.safeCoverURL(bad))
        }
    }

    @MainActor func testMarkTrueFalsePendingLateResponseAndFailureRollback() async throws {
        var calls = 0
        let model = MovieDetailViewModel(movieID: "neutral") { _, status in
            calls += 1
            try await Task.sleep(nanoseconds: 100_000_000)
            return status
        }
        let first = Task { await model.setReviewStatus("want_watch") }
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(model.reviewPending)
        await model.setReviewStatus("watched") // explicit pending policy, not concurrent writers
        XCTAssertEqual(calls, 1)
        await first.value
        XCTAssertEqual(model.reviewStatus, "want_watch"); XCTAssertFalse(model.reviewPending)
        await model.setReviewStatus("want_watch"); XCTAssertNil(model.reviewStatus)
        await model.setReviewStatus("watched"); XCTAssertEqual(model.reviewStatus, "watched")
        await model.setReviewStatus("watched"); XCTAssertNil(model.reviewStatus)
        var fail = false
        let failing = MovieDetailViewModel(movieID: "neutral") { _, status in
            if fail { throw URLError(.notConnectedToInternet) }; return status
        }
        await failing.setReviewStatus("watched"); fail = true
        await failing.setReviewStatus("watched")
        XCTAssertEqual(failing.reviewStatus, "watched"); XCTAssertNotNil(failing.errorMessage)
        XCTAssertFalse(failing.reviewPending)
        let inconsistent = MovieDetailViewModel(movieID: "neutral") { _, _ in nil }
        await inconsistent.setReviewStatus("want_watch")
        XCTAssertNil(inconsistent.reviewStatus); XCTAssertNotNil(inconsistent.errorMessage)
    }

    @MainActor func testActualNeutralKSPlayerStartsHistoryNotDetailOrFailure() async throws {
        let store = PlaybackHistoryStore.shared
        store.activate(accountID: 23500001); store.clear()
        defer { store.clear(); store.activate(accountID: nil) }
        let movie = Movie(id: "neutral-real-play", number: "TEST-235", title: "自创纯色测试短片")
        XCTAssertTrue(store.items.isEmpty)
        let url = try XCTUnwrap(Bundle.main.url(forResource: "neutral-subtitle", withExtension: "mp4"))
        let host = UIHostingController(rootView: KSChromePlayer(url: url, managesOrientation: false, historyMovie: movie))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 700))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let deadline = Date().addingTimeInterval(12)
        while store.items.isEmpty && Date() < deadline { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertEqual(store.items.map(\.id), [movie.id], "Real bundled neutral media must advance the actual engine clock")
    }
}

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
        let model = OnlineSubtitleModel(fetch: { _, kind in
            if kind == .catSearch { return Data("<table class='sub-table'></table>".utf8) }
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
        let model = OnlineSubtitleModel(fetch: { _, kind in
            XCTAssertEqual(kind, .download); downloads += 1
            return Data("1\n00:00:01,000 --> 00:00:02,000\n自创\n".utf8)
        })
        let row = OnlineSubtitleCandidate(id: "one", name: "自创", language: "未知", ext: "srt", url: URL(string: "https://subtitle.v.geilijiasu.com/AA/BB/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.srt")!)
        model.results = [row]; model.offset = 3; model.choose(row)
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
        model.results = [row]
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

// Build233: exercises production model with deliberately late/cancellation-ignoring replies.
actor Subtitle233Transport {
    var downloads: [String: Int] = [:]
    func count(_ id: String) -> Int { downloads[id, default: 0] }
    func fetch(_ url: URL, _ kind: OnlineSubtitleRequestKind) async throws -> Data {
        let key = url.lastPathComponent
        if kind == .download { downloads[key, default: 0] += 1 }
        let attempt = downloads[key, default: 0]
        let delay: Double = kind == .catSearch ? 0.35 : (key.hasPrefix("A") ? 0.7 : 0.07)
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { continuation.resume() }
        }
        switch kind {
        case .xunleiSearch:
            let rows = ["A", "B", "C"].map { letter in ["name": letter, "ext": "srt", "url": "https://subtitle.v.geilijiasu.com/AA/BB/" + String(repeating: letter, count: 40) + ".srt"] }
            return try JSONSerialization.data(withJSONObject: ["code": 0, "data": rows])
        case .catSearch:
            return Data("<table class='sub-table'><tr><td><a href='/subs/1/neutral.html'>Neutral</a></td></tr></table>".utf8)
        case .catDetail:
            return Data("<div class='sub-single'><a id='download_zh-CN' href='/subs/2/neutral-zh-CN.srt'>Download</a></div>".utf8)
        case .download:
            if key.hasPrefix("B"), attempt == 1 { return Data("invalid subtitle".utf8) }
            return Data("1\n00:00:00,000 --> 00:01:00,000\nSelf authored \(key)\n".utf8)
        }
    }
}
extension OnlineSubtitleModelTests {
    @MainActor func test234FlattenedRowsPreserveIdentityAcrossFeedbackAndExpansion() {
        let model = OnlineSubtitleModel(fetch: { _, _ in Data() })
        let parents = (0..<180).map { index in
            OnlineSubtitleCandidate(id: "parent-\(index)", name: "Neutral \(index)", language: "待选语言", ext: "html", url: URL(string: "https://www.subtitlecat.com/subs/234/neutral-\(index).html")!, source: .subtitleCat)
        }
        model.results = parents
        XCTAssertEqual(model.displayRows.count, 360)
        let firstID = model.displayRows[0].id
        let variants = (0..<48).map { index in
            OnlineSubtitleCandidate(id: "language-\(index)", name: "Neutral", language: "qx-\(index + 10)", ext: "srt", url: URL(string: "https://www.subtitlecat.com/subs/234/neutral-\(index).srt")!, source: .subtitleCat, parentID: parents[0].id)
        }
        model.languages[parents[0].id] = variants
        XCTAssertEqual(model.displayRows.count, 408)
        XCTAssertEqual(model.displayRows[0].id, firstID)
        XCTAssertEqual(model.displayRows[1].candidate.id, variants[0].id)
        XCTAssertEqual(Set(model.displayRows.map(\.id)).count, 408)
        let ids = model.displayRows.map(\.id)
        model.rowStates[variants[0].id] = "下载中…（旧字幕保留）"
        model.selected = variants[1]
        model.offset = 0.5
        XCTAssertEqual(model.displayRows.map(\.id), ids, "Non-structural state cannot invalidate row topology")
        model.clear()
        XCTAssertTrue(model.displayRows.isEmpty)
    }
    @MainActor func test233PartialSearchDedupeLastChoiceAndLateBytes() async throws {
        let transport = Subtitle233Transport()
        let model = OnlineSubtitleModel(fetch: { url, kind in try await transport.fetch(url, kind) })
        model.query = "neutral"; model.search()
        try await awaitModelState { model.results.count == 3 }
        let a = model.results[0], c = model.results[2]
        model.choose(a); model.choose(a)
        XCTAssertEqual(model.pendingID, a.id); XCTAssertNil(model.selected)
        try await awaitModelState { model.results.count == 4 }
        XCTAssertTrue(model.status.contains("下载"), "Late search must not overwrite download")
        let count = await transport.count(a.url.lastPathComponent)
        XCTAssertEqual(count, 1, "Same pending selection must be deduplicated")
        model.choose(c)
        try await awaitModelState { model.selected?.id == c.id }
        let old = model.cues
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertEqual(model.selected?.id, c.id); XCTAssertEqual(model.cues, old)
        XCTAssertTrue(model.status.contains("已加载"))
    }
    @MainActor func test233FailedParsingRetryPreservesOldAndLateSearchStatus() async throws {
        let transport = Subtitle233Transport()
        let model = OnlineSubtitleModel(fetch: { url, kind in try await transport.fetch(url, kind) })
        model.query = "neutral"; model.search()
        try await awaitModelState { model.results.count == 3 }
        let b = model.results[1], c = model.results[2]
        model.choose(c); try await awaitModelState { model.selected?.id == c.id }
        let old = model.cues
        model.choose(b); try await awaitModelState { model.pendingID == nil }
        XCTAssertEqual(model.selected?.id, c.id); XCTAssertEqual(model.cues, old)
        XCTAssertTrue(model.rowStates[b.id]?.contains("点按重试") == true)
        try await awaitModelState { model.results.count == 4 }
        XCTAssertTrue(model.status.contains("加载失败"), "Late search must preserve selection failure")
        model.choose(b); try await awaitModelState { model.selected?.id == b.id }
        XCTAssertNil(model.rowStates[b.id]); XCTAssertFalse(model.cues.isEmpty)
        let count = await transport.count(b.url.lastPathComponent); XCTAssertEqual(count, 2)
    }
    @MainActor func test233ExpansionDoesNotCancelSelectionAndCompletionCancelsPending() async throws {
        let transport = Subtitle233Transport()
        let model = OnlineSubtitleModel(fetch: { url, kind in try await transport.fetch(url, kind) })
        model.query = "neutral"; model.search()
        try await awaitModelState { model.results.count == 4 }
        let parent = model.results.first { $0.ext == "html" }!
        let a = model.results.first { $0.name == "A" }!
        model.choose(a); model.choose(parent); model.choose(parent)
        try await awaitModelState { model.languages[parent.id] != nil }
        model.choose(parent)
        XCTAssertEqual(model.pendingID, a.id)
        try await awaitModelState { model.selected?.id == a.id }
        let variant = model.languages[parent.id]![0]
        model.choose(variant); model.choose(parent)
        try await awaitModelState { model.selected?.id == variant.id }
        let old = model.cues
        model.choose(a); model.cancelPending()
        XCTAssertNil(model.pendingID); XCTAssertTrue(model.rowStates[a.id]?.contains("已取消") == true)
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertEqual(model.selected?.id, variant.id); XCTAssertEqual(model.cues, old)
        model.choose(a); model.disable()
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertNil(model.selected); XCTAssertTrue(model.cues.isEmpty); XCTAssertEqual(model.status, "字幕已关闭")
    }
}

final class DetailAuth327Tests: XCTestCase {
    // Keep in sync with scripts/fixtures/detail-auth-jwt-error.json
    // Production shape: HTTP 200 + success:0 + action:JWTVerificationError + message:請登錄帳號
    private static let jwtFailurePayload = Data(#"{"success":0,"action":"JWTVerificationError","message":"請登錄帳號"}"#.utf8)

    private func session() -> (URLSession, () -> Void) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Playback235URLProtocol.self]
        let session = URLSession(configuration: configuration)
        return (session, { session.invalidateAndCancel(); Playback235URLProtocol.handler = nil })
    }

    @MainActor func test327MovieDetailAuthorizationAndCachePolicy() async throws {
        let (session, cleanup) = session()
        defer { cleanup() }
        var recorded: [URLRequest] = []
        Playback235URLProtocol.handler = { request in
            recorded.append(request)
            return Data(#"{"success":1,"data":{"movie":{"id":"m327","type":"1","number":"TEST-327","title":"Neutral fixture"}}}"#.utf8)
        }

        let anonymous = JavDBSDK(client: APIClient(session: session, token: nil))
        _ = try await anonymous.movieDetail("m327")
        _ = try await anonymous.movieDetailFull("m327")
        XCTAssertEqual(recorded.count, 2)
        for request in recorded {
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(request.cachePolicy, .useProtocolCachePolicy)
            XCTAssertTrue(request.url?.path.hasPrefix("/api/v4/movies/m327") == true)
        }

        recorded.removeAll()
        let token = "neutral-fixture-327"
        let signedIn = JavDBSDK(client: APIClient(session: session, token: token))
        _ = try await signedIn.movieDetail("m327")
        _ = try await signedIn.movieDetailFull("m327")
        XCTAssertEqual(recorded.count, 2)
        for request in recorded {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertTrue(request.url?.path.hasPrefix("/api/v4/movies/m327") == true)
        }
    }

    func test327ProductionJWTPayloadIsAuthAndNotSuccess() throws {
        let data = Self.jwtFailurePayload
        let decoded = try JSONDecoder().decode(JavDBResponse<MovieDetailData>.self, from: data)
        XCTAssertEqual(decoded.success, 0)
        XCTAssertFalse(decoded.isSuccess)
        XCTAssertEqual(decoded.action, "JWTVerificationError")
        XCTAssertEqual(decoded.message, "請登錄帳號")
        let error = JavDBError.apiError(action: decoded.action, message: decoded.message)
        XCTAssertTrue(JavDBError.isAuthenticationFailure(error), "HTTP 200 business failure must be classified as auth")
        XCTAssertFalse(JavDBError.isAuthenticationFailure(JavDBError.httpError(500, "服务器错误")))
        XCTAssertFalse(JavDBError.isAuthenticationFailure(JavDBError.decodeError("truncated")))
        XCTAssertTrue(JavDBError.isAuthenticationFailure(JavDBError.httpError(401, "鉴权失败或无访问权限，请检查登录状态")))
        XCTAssertTrue(JavDBError.isAuthenticationFailure(JavDBError.apiError(action: nil, message: "请登录帐号")))
    }

    @MainActor func test327MovieDetailHTTP200JWTIsAuthError() async throws {
        let (session, cleanup) = session()
        defer { cleanup() }
        Playback235URLProtocol.handler = { _ in Self.jwtFailurePayload }
        let sdk = JavDBSDK(client: APIClient(session: session, token: nil))
        do {
            _ = try await sdk.movieDetail("m327")
            XCTFail("HTTP 200 + success:0 must not be treated as success")
        } catch {
            XCTAssertTrue(JavDBError.isAuthenticationFailure(error), "must be auth, not a generic error")
            guard case JavDBError.apiError(let action, let message) = error else {
                return XCTFail("expected apiError, got \(error)")
            }
            XCTAssertEqual(action, "JWTVerificationError")
            XCTAssertEqual(message, "請登錄帳號")
        }
        do {
            _ = try await sdk.movieDetailFull("m327")
            XCTFail("HTTP 200 + success:0 must not be treated as success")
        } catch {
            XCTAssertTrue(JavDBError.isAuthenticationFailure(error))
        }
    }

    @MainActor func test327ViewModelLoadsMovieWhenTokenPresent() async throws {
        let (session, cleanup) = session()
        defer { cleanup() }
        let token = "neutral-fixture-327"
        Playback235URLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
            return Data(#"{"success":1,"data":{"movie":{"id":"m327","type":"1","number":"TEST-327","title":"Neutral fixture"}}}"#.utf8)
        }
        let sdk = JavDBSDK(client: APIClient(session: session, token: token))
        let vm = MovieDetailViewModel(movieID: "m327", sdk: sdk)
        await vm.load()
        XCTAssertEqual(vm.movie?.id, "m327")
        XCTAssertEqual(vm.movie?.number, "TEST-327")
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isAuthError)
    }
}

final class HomeHot328Tests: XCTestCase {
    /// Kai's seven-row arbitration table, as a pure function (no SwiftUI gestures).
    func test328ArbitratorAcceptanceTable() {
        // 1. Pinned, slow upward drag ≥ 56 pt, not last item: exactly one page change.
        var session = HeroSwipePolicy.Session.begin(scrollOffset: 0, index: 0, count: 5)
        XCTAssertEqual(session.mode, .hero)
        _ = session.changed(dx: 0, dy: -14)
        XCTAssertEqual(session.axis, .vertical)
        XCTAssertEqual(session.changed(dx: 0, dy: -56), .trackVertical(-56))
        let first = session.ended(dx: 0, dy: -56, velocityX: 0, velocityY: -10, predictedX: 0)
        XCTAssertEqual(first, .pageVertical(delta: 1))
        XCTAssertTrue(session.consumedPageChange)
        // The rest of the same gesture is ignored (no multi-page chain).
        XCTAssertEqual(session.changed(dx: 0, dy: -120), .locked)
        XCTAssertEqual(session.ended(dx: 0, dy: -120, velocityX: 0, velocityY: -800, predictedX: 0), .locked)

        // 2. Pinned, last item upward: passthrough (page scrolls, no item change).
        session = HeroSwipePolicy.Session.begin(scrollOffset: 0, index: 4, count: 5)
        _ = session.changed(dx: 0, dy: -20)
        XCTAssertEqual(session.changed(dx: 0, dy: -80), .passthrough)
        XCTAssertEqual(session.ended(dx: 0, dy: -80, velocityX: 0, velocityY: -600, predictedX: 0), .passthrough)
        XCTAssertFalse(session.consumedPageChange)

        // 3. Pinned, first item downward: passthrough so system pull-to-refresh can run.
        session = HeroSwipePolicy.Session.begin(scrollOffset: 0, index: 0, count: 5)
        _ = session.changed(dx: 0, dy: 20)
        XCTAssertEqual(session.changed(dx: 0, dy: 80), .passthrough)
        XCTAssertEqual(session.ended(dx: 0, dy: 80, velocityX: 0, velocityY: 400, predictedX: 0), .passthrough)
        XCTAssertFalse(session.consumedPageChange)

        // 4. Gesture started at ~300 pt scroll, dragged back to top: only scrolls.
        session = HeroSwipePolicy.Session.begin(scrollOffset: 300, index: 2, count: 5)
        XCTAssertEqual(session.mode, .scrollView)
        XCTAssertEqual(session.changed(dx: 0, dy: 300), .passthrough)
        XCTAssertEqual(session.ended(dx: 0, dy: 300, velocityX: 0, velocityY: 400, predictedX: 0), .passthrough)
        XCTAssertFalse(session.consumedPageChange)

        // 5. 30° diagonal: dominant axis wins (30° from horizontal is horizontal).
        session = HeroSwipePolicy.Session.begin(scrollOffset: 0, index: 1, count: 5)
        let dx: CGFloat = 80
        let dy = dx * 0.57735026919 // tan(30°)
        XCTAssertEqual(session.changed(dx: dx, dy: dy), .trackHorizontal(dx * HeroSwipePolicy.horizontalRubber))
        XCTAssertEqual(session.axis, .horizontal)
        // Vertical 30° from the vertical axis (i.e. 60° from horizontal) is vertical.
        session = HeroSwipePolicy.Session.begin(scrollOffset: 0, index: 1, count: 5)
        let vdy: CGFloat = -80
        let vdx = abs(vdy) * 0.57735026919 // tan(30°)
        XCTAssertEqual(session.changed(dx: vdx, dy: vdy), .trackVertical(vdy))
        XCTAssertEqual(session.axis, .vertical)

        // 6. Rapid vertical flick: translation ≥ 24 and velocity ≥ 500, at most one change.
        session = HeroSwipePolicy.Session.begin(scrollOffset: 0, index: 2, count: 5)
        _ = session.changed(dx: 0, dy: -24)
        XCTAssertEqual(session.ended(dx: 0, dy: -24, velocityX: 0, velocityY: -500, predictedX: 0), .pageVertical(delta: 1))
        XCTAssertTrue(session.consumedPageChange)
        XCTAssertEqual(session.ended(dx: 0, dy: -80, velocityX: 0, velocityY: -900, predictedX: 0), .locked)

        // Below the line: spring back, no page change.
        session = HeroSwipePolicy.Session.begin(scrollOffset: 0, index: 2, count: 5)
        _ = session.changed(dx: 0, dy: -30)
        XCTAssertEqual(session.ended(dx: 0, dy: -30, velocityX: 0, velocityY: -100, predictedX: 0), .springVertical)

        // Vertical down + not first item → previous.
        session = HeroSwipePolicy.Session.begin(scrollOffset: 0, index: 2, count: 5)
        _ = session.changed(dx: 0, dy: 56)
        XCTAssertEqual(session.ended(dx: 0, dy: 56, velocityX: 0, velocityY: 10, predictedX: 0), .pageVertical(delta: -1))
    }

    /// MIDE-991 stand-in: a hanging CDN URL plus a usable DTO thumb must not sit
    /// on brand-brown #2A2019. The per-item deadline forces a terminal state
    /// (blur / floor), and the thumb is not promoted to a finalized A/B sharp.
    @MainActor
    func test328StuckSourceDeadlinePaintsFloorNotBrown() async throws {
        HeroCoverPolicy.overallBudgetOverride = 0.3
        defer { HeroCoverPolicy.overallBudgetOverride = nil }
        HeroCoverStore.shared.resetForTests()
        let movie = Movie(
            id: "stuck-328",
            number: "STUCK-328",
            title: "Stuck CDN stand-in",
            thumbURL: "fixture://poster/portrait-floor",
            coverURL: "fixture://hang/cdn"
        )
        HeroCoverStore.shared.start(movies: [movie], currentIndex: 0)
        let deadline = Date().addingTimeInterval(2.5)
        var presentation = HeroCoverStore.shared.presentation(for: "stuck-328")
        while Date() < deadline, !presentation.settled {
            try await Task.sleep(nanoseconds: 50_000_000)
            presentation = HeroCoverStore.shared.presentation(for: "stuck-328")
        }
        XCTAssertTrue(presentation.settled, "6s (overridden) deadline provisionally settles — 已定案（可升级）")
        XCTAssertTrue(presentation.hasQuick, "DTO thumb must paint as the floor/blur, not an empty field")
        XCTAssertNotEqual(presentation.phase, .empty)
        XCTAssertFalse(presentation.isAB, "sub-tier / thumb floor must not become a finalized A/B hero")
        XCTAssertNotEqual(presentation.phase, .finalized, "or if finalized, it would be from a ≥C sharp, which a hanging CDN must not provide")
        // The visible empty floor token is no longer #2A2019.
        XCTAssertNotEqual(HomeTheme.heroLoadingFloor, HomeTheme.fallbackBase)
    }
}


final class HomeHot329Tests: XCTestCase {
    override func tearDown() async throws {
        await MainActor.run { HeroCoverStore.shared.resetForTests() }
        HeroCoverPolicy.overallBudgetOverride = nil
        await ImageLoader.shared.resetCachesForTests()
        ImageLoader.resetTestTransport()
        try await super.tearDown()
    }

    func test329RailFloorAccepts147ThumbAnd360IsPreferenceOnly() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: 147, height: 200), format: format).image { ctx in
            UIColor.gray.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 147, height: 200))
        }
        let jacket = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 538), format: format).image { ctx in
            UIColor.darkGray.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 538))
        }
        let dmmThumb = "https://pics.dmm.co.jp/digital/video/ipx00706/ipx00706ps.jpg"
        // VisibleHQ may still reject a sub-360 upgrade, but the *floor* never discards.
        XCTAssertTrue(RailCoverFloor.rejects(source: dmmThumb, image: thumb))
        XCTAssertFalse(RailCoverFloor.prefers(thumb, source: dmmThumb, to: jacket, currentSource: "https://example/jacket.jpg"))
        XCTAssertTrue(RailCoverFloor.prefers(jacket, source: "https://example/jacket.jpg", to: thumb, currentSource: dmmThumb))
        // A lonely 147×200 is paintable as the floor: prefers is only among candidates.
        XCTAssertEqual(RailPosterPlaceholder.kind(hasURL: true, failed: false), .loading)
        XCTAssertEqual(RailPosterPlaceholder.kind(hasURL: true, failed: true), .retry)
        XCTAssertEqual(RailPosterPlaceholder.kind(hasURL: false, failed: false), .filmIcon)
        XCTAssertEqual(RailPosterPlaceholder.kind(hasURL: false, failed: true), .filmIcon)
    }

    /// (i) CDN delayed 15s → sharp unblurred floor at t0, auto-upgrade at 15s.
    @MainActor
    func test329DelayedCDNPaintsSharpFloorThenUpgrades() async throws {
        HeroCoverStore.shared.resetForTests()
        let movie = Movie(
            id: "delay-329",
            number: "DELAY-329",
            title: "Delayed CDN stand-in",
            thumbURL: "fixture://poster/thumb147-floor",
            coverURL: "fixture://delay/15/poster/portrait-hero-a"
        )
        let t0 = Date()
        HeroCoverStore.shared.start(movies: [movie], currentIndex: 0)
        var presentation = HeroCoverStore.shared.presentation(for: "delay-329")
        let floorDeadline = Date().addingTimeInterval(2.0)
        while Date() < floorDeadline, presentation.blurImage == nil && presentation.sharpImage == nil {
            try await Task.sleep(nanoseconds: 50_000_000)
            presentation = HeroCoverStore.shared.presentation(for: "delay-329")
        }
        XCTAssertLessThan(Date().timeIntervalSince(t0), 3, "floor must paint well before the delayed HQ")
        XCTAssertNotNil(presentation.blurImage, "DTO 147×200 thumb must be the unblurred floor at t0")
        XCTAssertFalse(presentation.isAB, "15s HQ must not already be the sharp hero")
        XCTAssertNotEqual(presentation.tier, .a)

        let upgradeDeadline = Date().addingTimeInterval(18)
        while Date() < upgradeDeadline, presentation.isAB == false {
            try await Task.sleep(nanoseconds: 200_000_000)
            presentation = HeroCoverStore.shared.presentation(for: "delay-329")
        }
        XCTAssertTrue(presentation.isAB, "late A/B must upgrade after the 6s settle, at ~15s")
        XCTAssertEqual(presentation.tier, .a)
        XCTAssertNotNil(presentation.sharpImage)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(t0), 14.5)
    }

    /// (ii) Preheat DTO thumbs for 我的關注 so a fast scroll does not film-flash.
    func test329PreheatFollowingDTOThumbs() async throws {
        await ImageLoader.shared.resetCachesForTests()
        let following = (1...9).map {
            Movie(id: "follow-\($0)", number: "TEST-F\($0)", title: "Follow \($0)",
                  coverURL: "fixture://poster/thumb147-\($0)")
        }
        let recommended = (1...3).map {
            Movie(id: "past-\($0)", number: "TEST-P\($0)", title: "Past \($0)",
                  coverURL: "fixture://poster/\($0)")
        }
        let loaded = await HomeRailThumbPreheat.preheat(sections: [recommended, [], [], following])
        XCTAssertGreaterThanOrEqual(loaded, 9)
        let t0 = Date()
        let again = await ImageLoader.shared.load(following[0].coverURL, maxPixelSize: 900, timeout: 2)
        XCTAssertNotNil(again)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 0.25, "second load must be a memory-cache hit, not a film flash")
        XCTAssertEqual(RailPosterPlaceholder.kind(hasURL: following[0].coverURL != nil, failed: false), .loading)
    }

    /// (iii) Offline cold start → sharp floor from disk, not a smear.
    @MainActor
    func test329OfflineColdStartRestoresSharpFloor() async throws {
        HeroCoverStore.shared.resetForTests()
        let image = ImageLoader.fixturePoster("fixture://poster/portrait-hero-a")
        HeroCoverDisk.storeAccepted(image, number: "OFF-329", source: "hero-disk")
        let movie = Movie(
            id: "off-329",
            number: "OFF-329",
            title: "Offline sharp",
            coverURL: "fixture://hang/offline"
        )
        HeroCoverStore.shared.start(movies: [movie], currentIndex: 0)
        var presentation = HeroCoverStore.shared.presentation(for: "off-329")
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, presentation.sharpImage == nil {
            try await Task.sleep(nanoseconds: 40_000_000)
            presentation = HeroCoverStore.shared.presentation(for: "off-329")
        }
        XCTAssertNotNil(presentation.sharpImage, "HeroCoverDisk / HQPosterDiskCache must restore a sharp unblurred floor offline")
        XCTAssertTrue(presentation.tier.isAB || presentation.tier == .c)
        XCTAssertNotEqual(HomeTheme.heroLoadingFloor, HomeTheme.fallbackBase)
    }

    func test329HeroCIDMapReadsDTOAndCache() {
        let url = "https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/ipx00706/ipx00706ps.jpg"
        let movie = Movie(id: "cid-329", number: "IPX-706", title: "CID", coverURL: url)
        XCTAssertEqual(HeroCIDMap.cid(from: movie), "ipx00706")
        XCTAssertTrue(HeroCIDMap.learn(from: movie))
        let bare = Movie(id: "cid-329b", number: "IPX-706", title: "CID cached")
        XCTAssertEqual(HeroCIDMap.cid(from: bare), "ipx00706")
    }
}


final class HomeChrome330Tests: XCTestCase {
    override func tearDown() async throws {
        await MainActor.run { HeroCoverStore.shared.resetForTests() }
        HeroCoverPolicy.overallBudgetOverride = nil
        await ImageLoader.shared.resetCachesForTests()
        ImageLoader.resetTestTransport()
        try await super.tearDown()
    }

    /// (a) A clean tap opens detail; a swipe / page-commit does not.
    func test330CleanTapOpensDetailAndPageCommitDoesNot() {
        let origin = Date()
        XCTAssertTrue(HeroTapPolicy.shouldOpen(translation: 0, duration: 0.12,
                                               consumedPageChange: false,
                                               lastPageCommitAt: .distantPast, now: origin))
        XCTAssertTrue(HeroTapPolicy.shouldOpen(translation: 9.5, duration: 0.29,
                                               consumedPageChange: false,
                                               lastPageCommitAt: .distantPast, now: origin))
        XCTAssertFalse(HeroTapPolicy.shouldOpen(translation: 10, duration: 0.12,
                                                consumedPageChange: false,
                                                lastPageCommitAt: .distantPast, now: origin))
        XCTAssertFalse(HeroTapPolicy.shouldOpen(translation: 2, duration: 0.3,
                                                consumedPageChange: false,
                                                lastPageCommitAt: .distantPast, now: origin))
        XCTAssertFalse(HeroTapPolicy.shouldOpen(translation: 2, duration: 0.12,
                                                consumedPageChange: true,
                                                lastPageCommitAt: .distantPast, now: origin))
        // lastDragAt is set only on page-commit and suppresses a trailing touch for 0.35s.
        XCTAssertFalse(HeroTapPolicy.shouldOpen(translation: 0, duration: 0.08,
                                                consumedPageChange: false,
                                                lastPageCommitAt: origin,
                                                now: origin.addingTimeInterval(0.34)))
        XCTAssertTrue(HeroTapPolicy.shouldOpen(translation: 0, duration: 0.08,
                                               consumedPageChange: false,
                                               lastPageCommitAt: origin,
                                               now: origin.addingTimeInterval(0.36)))
    }

    /// (b) DTO floor paints immediately even if the resolver is delayed 15s, then upgrades to the winner.
    @MainActor
    func test330DTOFloorPaintsThenUpgradesToResolverWinner() async throws {
        HeroCoverStore.shared.resetForTests()
        let winner = ImageLoader.fixturePoster("fixture://poster/portrait-hero-a")
        HeroCoverStore.testResolverProvider = { movie in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            return DetailPosterArtwork(image: winner, backdrop: winner, tint: .black,
                                       provenance: PosterProvenance(source: "official-ps"),
                                       sourceURL: "https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/ipx00706/ipx00706ps.jpg",
                                       nativeWidth: 1200, nativeHeight: 1800, rawImage: winner)
        }
        let movie = Movie(
            id: "delay-330",
            number: "DELAY-330",
            title: "Resolver delayed 15s",
            thumbURL: "fixture://poster/thumb147-floor"
        )
        let t0 = Date()
        HeroCoverStore.shared.start(movies: [movie], currentIndex: 0)
        var presentation = HeroCoverStore.shared.presentation(for: "delay-330")
        let floorDeadline = Date().addingTimeInterval(2.0)
        while Date() < floorDeadline, presentation.blurImage == nil && presentation.sharpImage == nil {
            try await Task.sleep(nanoseconds: 50_000_000)
            presentation = HeroCoverStore.shared.presentation(for: "delay-330")
        }
        XCTAssertLessThan(Date().timeIntervalSince(t0), 3, "DTO floor must paint well before the delayed resolver")
        XCTAssertNotNil(presentation.blurImage, "ranking DTO thumb must be the unblurred floor at t0")
        XCTAssertNil(presentation.sharpImage)
        XCTAssertFalse(presentation.isAB)

        let upgradeDeadline = Date().addingTimeInterval(18)
        while Date() < upgradeDeadline, presentation.isAB == false {
            try await Task.sleep(nanoseconds: 200_000_000)
            presentation = HeroCoverStore.shared.presentation(for: "delay-330")
        }
        XCTAssertTrue(presentation.isAB, "late official resolver winner must upgrade after the 6s rhythm point, at ~15s")
        XCTAssertEqual(presentation.tier, .a)
        XCTAssertNotNil(presentation.sharpImage)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(t0), 14.5)
        XCTAssertEqual(HeroCoverPolicy.pixelWidth(presentation.sharpImage!), HeroCoverPolicy.pixelWidth(winner))
    }

    /// (c) A HeroCoverDisk / resolver-cache hit is used immediately as the sharp layer.
    @MainActor
    func test330CacheHitUsedImmediately() async throws {
        HeroCoverStore.shared.resetForTests()
        let image = ImageLoader.fixturePoster("fixture://poster/portrait-hero-a")
        HeroCoverDisk.storeAccepted(image, number: "CACHE-330", source: "hero-disk")
        HeroCoverStore.testResolverProvider = { _ in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            return nil
        }
        let movie = Movie(
            id: "cache-330",
            number: "CACHE-330",
            title: "Cached official portrait",
            coverURL: "https://c0.jdbstatic.com/covers/cache-330.jpg"
        )
        let t0 = Date()
        HeroCoverStore.shared.start(movies: [movie], currentIndex: 0)
        var presentation = HeroCoverStore.shared.presentation(for: "cache-330")
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, presentation.sharpImage == nil {
            try await Task.sleep(nanoseconds: 40_000_000)
            presentation = HeroCoverStore.shared.presentation(for: "cache-330")
        }
        XCTAssertNotNil(presentation.sharpImage, "HeroCoverDisk / resolver cache must be the sharp layer immediately")
        XCTAssertLessThan(Date().timeIntervalSince(t0), 1.0)
        XCTAssertTrue(presentation.tier.isAB || presentation.tier == .c)
    }

    /// (d) Build 331 two-level semantics: there is no separate middle step any
    /// more. The enrich-merged detail cover_url re-evaluates the *floor* (level 1)
    /// and replaces the DTO thumb when it is sharper; the official resolver
    /// winner (level 2) is still absent while the resolver is delayed.
    @MainActor
    func test330EnrichMergedDetailCoverIsMiddleStep() async throws {
        HeroCoverStore.shared.resetForTests()
        HeroCoverStore.testDetailProvider = { movie in
            Movie(id: movie.id, number: movie.number, title: movie.title,
                  coverURL: "fixture://poster/portrait-mid-cover")
        }
        HeroCoverStore.testResolverProvider = { _ in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            return nil
        }
        let movie = Movie(
            id: "enrich-330",
            number: "ENRICH-330",
            title: "Needs detail cover",
            thumbURL: "fixture://poster/thumb147-floor"
        )
        HeroCoverStore.shared.start(movies: [movie], currentIndex: 0)
        var presentation = HeroCoverStore.shared.presentation(for: "enrich-330")
        let floorDeadline = Date().addingTimeInterval(2)
        while Date() < floorDeadline, presentation.blurImage == nil {
            try await Task.sleep(nanoseconds: 40_000_000)
            presentation = HeroCoverStore.shared.presentation(for: "enrich-330")
        }
        XCTAssertNotNil(presentation.blurImage, "DTO thumb floor must paint first")
        let midDeadline = Date().addingTimeInterval(3)
        while Date() < midDeadline, presentation.floorPixelWidth <= 147 {
            try await Task.sleep(nanoseconds: 40_000_000)
            presentation = HeroCoverStore.shared.presentation(for: "enrich-330")
        }
        XCTAssertEqual(presentation.floorPixelWidth, 700, "enrich-merged cover_url must re-evaluate and upgrade the floor itself")
        XCTAssertNotEqual(HeroCoverPolicy.pixelWidth(presentation.blurImage!), 147)
        XCTAssertEqual(presentation.floorSource, "fixture://poster/portrait-mid-cover")
        XCTAssertNil(presentation.sharpImage, "delayed resolver must not have won yet")
        XCTAssertFalse(presentation.isSharp, "a floor never poses as the final winner")
    }

    /// (e) backdrop / pl is not chosen as the primary sharp over the official portrait winner.
    @MainActor
    func test330BackdropPLIsNotPrimaryOverOfficialPortrait() async throws {
        let ps = "https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/ipx00706/ipx00706ps.jpg"
        let pl = "https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/ipx00706/ipx00706pl.jpg"
        XCTAssertFalse(HeroResolverSharp.isBackdropOrJacket(ps))
        XCTAssertTrue(HeroResolverSharp.isBackdropOrJacket(pl))
        XCTAssertTrue(HeroResolverSharp.isBackdropOrJacket("https://example/hdBackdrop.jpg"))

        let official = DetailPosterQuality(source: ps, width: 745, height: 1081, originalPortrait: true)
        let jacket = DetailPosterQuality(source: pl, width: 800, height: 1080, originalPortrait: false)
        let winner = DetailPosterQuality.winner([jacket, official])
        XCTAssertEqual(winner?.source, ps, "official typography / front-crop portrait must beat the pl jacket")

        let portrait = ImageLoader.fixturePoster("fixture://poster/portrait-hero-a")
        let backdrop = ImageLoader.fixturePoster("fixture://poster/jacket-pl")
        XCTAssertNotEqual(HeroCoverPolicy.pixelWidth(portrait), HeroCoverPolicy.pixelWidth(backdrop))
        let art = DetailPosterArtwork(image: portrait, backdrop: backdrop, tint: .black,
                                      provenance: PosterProvenance(source: ps),
                                      sourceURL: ps, nativeWidth: 1200, nativeHeight: 1800, rawImage: portrait)
        let primary = HeroResolverSharp.primaryImage(from: art)
        XCTAssertEqual(HeroCoverPolicy.pixelWidth(primary), HeroCoverPolicy.pixelWidth(portrait))
        XCTAssertNotEqual(HeroCoverPolicy.pixelWidth(primary), HeroCoverPolicy.pixelWidth(backdrop))

        HeroCoverStore.shared.resetForTests()
        HeroCoverStore.testResolverProvider = { _ in art }
        let movie = Movie(id: "pl-330", number: "PL-330", title: "Portrait vs jacket",
                          thumbURL: "fixture://poster/thumb147-floor")
        HeroCoverStore.shared.start(movies: [movie], currentIndex: 0)
        var presentation = HeroCoverStore.shared.presentation(for: "pl-330")
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, presentation.sharpImage == nil {
            try await Task.sleep(nanoseconds: 40_000_000)
            presentation = HeroCoverStore.shared.presentation(for: "pl-330")
        }
        XCTAssertNotNil(presentation.sharpImage)
        XCTAssertEqual(HeroCoverPolicy.pixelWidth(presentation.sharpImage!), HeroCoverPolicy.pixelWidth(portrait),
                       "home hero sharp must be the official portrait, not the backdrop / pl jacket")
    }
}

/// Build 331: the home hero never shows the wide DVD jacket "collage".
/// Neutral rendered fixtures only (no network, no adult imagery): the jacket's
/// back half is red, its front (the right 0.70·h) is blue; the thumb is blue.
final class HomeHero331Tests: XCTestCase {
    override func tearDown() async throws {
        await MainActor.run { HeroCoverStore.shared.resetForTests() }
        HeroCoverPolicy.overallBudgetOverride = nil
        await ImageLoader.shared.resetCachesForTests()
        ImageLoader.resetTestTransport()
        Self.offline.set(false)
        try await super.tearDown()
    }

    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set(_ v: Bool) { lock.lock(); value = v; lock.unlock() }
        func get() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
    }
    static let offline = Flag()

    static func render(_ width: Int, _ height: Int, frontFrom: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: frontFrom, height: height))
            UIColor.blue.setFill(); ctx.fill(CGRect(x: frontFrom, y: 0, width: width - frontFrom, height: height))
        }
    }

    /// 840×568 JavDB jacket: back cover left, front = right 398 px (0.70·568).
    static let jacket = render(840, 568, frontFrom: 840 - 398)
    /// 166×236 portrait small_cover: the front at low resolution.
    static let thumb = render(166, 236, frontFrom: 0)

    static func installJacketTransport(thumbDelay: Double = 0, coverDelay: Double = 0) {
        ImageLoader.testTransport = { url, _ in
            if HomeHero331Tests.offline.get() { return nil }
            if url.contains("/small_covers/") {
                if thumbDelay > 0 { try? await Task.sleep(nanoseconds: UInt64(thumbDelay * 1_000_000_000)) }
                return HomeHero331Tests.thumb
            }
            if url.contains("/covers/") {
                if coverDelay > 0 { try? await Task.sleep(nanoseconds: UInt64(coverDelay * 1_000_000_000)) }
                return HomeHero331Tests.jacket
            }
            return nil
        }
    }

    static func abfLike(_ id: String, number: String, slug: String) -> Movie {
        Movie(id: id, number: number, title: "ABF-398-like \(id)",
              thumbURL: "https://tp.spfcas.com/rhe951l4q/small_covers/mb/\(slug).jpg",
              coverURL: "https://tp.spfcas.com/rhe951l4q/covers/mb/\(slug).jpg")
    }

    static func winnerArt(_ tag: String, width: Int = 760, height: Int = 1081) -> DetailPosterArtwork {
        let image = render(width, height, frontFrom: 0)
        let url = "https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/\(tag)/\(tag)ps.jpg"
        return DetailPosterArtwork(image: image, backdrop: image, tint: .black,
                                   provenance: PosterProvenance(source: url), sourceURL: url,
                                   nativeWidth: width, nativeHeight: height, rawImage: image)
    }

    /// Average colour of the bitmap: true when it is the blue front, not the red back / collage.
    static func isFront(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        var px = [UInt8](repeating: 0, count: 4)
        let ok: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        return ok && Int(px[2]) > Int(px[0]) + 100
    }

    static func isPortrait(_ image: UIImage?) -> Bool {
        guard let image else { return true }
        return HeroCoverPolicy.pixelHeight(image) >= HeroCoverPolicy.pixelWidth(image)
    }

    @MainActor
    func poll(_ seconds: Double, _ id: String, until done: (HeroCoverPresentation) -> Bool) async throws -> HeroCoverPresentation {
        var p = HeroCoverStore.shared.presentation(for: id)
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline, !done(p) {
            try await Task.sleep(nanoseconds: 20_000_000)
            p = HeroCoverStore.shared.presentation(for: id)
        }
        return p
    }

    /// (1) Cold start, ABF-398-like DTO: the first painted frame is the single
    /// front portrait (thumb or front crop), never the jacket collage; the
    /// floor then settles on the 398×568 right-half front crop.
    @MainActor
    func test331ColdStartFirstFrameIsFrontPortrait() async throws {
        HeroCoverStore.shared.resetForTests()
        await ImageLoader.shared.resetCachesForTests()
        Self.installJacketTransport()
        HeroCoverStore.testDetailProvider = { _ in nil }
        HeroCoverStore.testResolverProvider = { _ in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            return nil
        }
        let movie = Self.abfLike("abf-331a", number: "ABF-9311", slug: "Mb331a")
        HeroCoverStore.shared.start(movies: [movie], currentIndex: 0)
        let first = try await poll(2, movie.id) { $0.blurImage != nil }
        let frame = try XCTUnwrap(first.blurImage, "a floor must paint at cold start")
        XCTAssertTrue(Self.isPortrait(frame), "first frame must be a portrait, not the 840×568 jacket")
        XCTAssertTrue(Self.isFront(frame), "first frame must be the front, not the back / spine collage")
        let settled = try await poll(3, movie.id) { $0.floorPixelWidth == 398 }
        let floor = try XCTUnwrap(settled.blurImage)
        XCTAssertEqual(HeroCoverPolicy.pixelWidth(floor), 398, "floor = right 0.70·h front crop of cover_url")
        XCTAssertEqual(HeroCoverPolicy.pixelHeight(floor), 568)
        XCTAssertTrue(Self.isFront(floor))
        XCTAssertNil(settled.sharpImage)
        XCTAssertFalse(settled.isSharp)
    }

    /// (2) Swipe to item 4 and back: neither reverts to the jacket, and neither
    /// sits on a low-res floor posing as final — the official winner is restored.
    @MainActor
    func test331SwipeToFourthAndBackKeepsSharpWinner() async throws {
        HeroCoverStore.shared.resetForTests()
        await ImageLoader.shared.resetCachesForTests()
        Self.installJacketTransport()
        HeroCoverStore.testDetailProvider = { _ in nil }
        let movies = (0..<5).map { Self.abfLike("swipe-331-\($0)", number: "ABF-93\(20 + $0)", slug: "Sw331\($0)") }
        HeroCoverStore.testResolverProvider = { movie in
            Self.winnerArt("abf0\(movie.id.suffix(1))331")
        }
        HeroCoverStore.shared.start(movies: movies, currentIndex: 0)
        for movie in movies {
            let p = try await poll(6, movie.id) { $0.isSharp }
            XCTAssertTrue(p.isSharp, "\(movie.id) must hold a retrievable official winner")
            XCTAssertEqual(p.tier, .b)
        }
        // Item 4 (index 3) was resolved while not adjacent: on disk, not in memory.
        XCTAssertNil(HeroCoverStore.shared.presentation(for: movies[3].id).sharpImage)
        XCTAssertTrue(HeroCoverStore.shared.presentation(for: movies[3].id).sharpOnDisk)

        HeroCoverStore.shared.setCurrentIndex(3, movies: movies)
        let fourth = try await poll(1.5, movies[3].id) { $0.sharpImage != nil }
        let fourthSharp = try XCTUnwrap(fourth.sharpImage, "item 4 must show its winner, not the floor")
        XCTAssertEqual(HeroCoverPolicy.pixelWidth(fourthSharp), 760)
        XCTAssertTrue(Self.isPortrait(fourthSharp) && Self.isPortrait(fourth.blurImage))
        XCTAssertNil(HeroCoverStore.shared.presentation(for: movies[0].id).sharpImage, "item 1 evicted outside ±1")

        HeroCoverStore.shared.setCurrentIndex(0, movies: movies)
        let back = try await poll(1.5, movies[0].id) { $0.sharpImage != nil }
        let backSharp = try XCTUnwrap(back.sharpImage, "swipe back must restore the winner, not the floor")
        XCTAssertEqual(HeroCoverPolicy.pixelWidth(backSharp), 760)
        XCTAssertTrue(back.isSharp && back.phase == .finalized)
        XCTAssertTrue(Self.isPortrait(back.blurImage), "floor underneath is still the cropped front")
        XCTAssertNotEqual(back.floorPixelWidth, 840)
    }

    /// (3) Offline cold start with a cached detail-page winner: shown directly.
    @MainActor
    func test331OfflineColdStartShowsDetailWinner() async throws {
        HeroCoverStore.shared.resetForTests()
        await ImageLoader.shared.resetCachesForTests()
        Self.offline.set(true)
        Self.installJacketTransport()
        HeroCoverStore.testDetailProvider = { _ in nil }
        HeroCoverStore.testResolverProvider = { _ in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            return nil
        }
        let art = Self.winnerArt("off00331")
        // Exactly what DetailPosterResolver.resolve writes for the detail page.
        XCTAssertTrue(HeroCoverDisk.storeAccepted(art.image, number: "OFF-9331", source: art.sourceURL))
        let movie = Self.abfLike("off-331", number: "OFF-9331", slug: "Off331")
        let t0 = Date()
        HeroCoverStore.shared.start(movies: [movie], currentIndex: 0)
        let p = try await poll(1.5, movie.id) { $0.sharpImage != nil }
        XCTAssertNotNil(p.sharpImage, "cached detail winner must paint offline")
        XCTAssertLessThan(Date().timeIntervalSince(t0), 1.5)
        XCTAssertEqual(HeroCoverPolicy.pixelWidth(p.sharpImage!), 760)
        XCTAssertTrue(p.isAB)
        XCTAssertTrue(Self.isFront(p.sharpImage!))
    }

    /// (4) Landscape fixture 840×568 cover + 166×236 thumb: no layer ever shows
    /// an uncropped bitmap, and the floor uses the cropped version.
    @MainActor
    func test331LandscapeFixtureNeverShowsUncroppedLayer() async throws {
        HeroCoverStore.shared.resetForTests()
        await ImageLoader.shared.resetCachesForTests()
        Self.installJacketTransport(thumbDelay: 0.05, coverDelay: 0.25)
        let movie = Self.abfLike("land-331", number: "ABF-9341", slug: "Land331")
        HeroCoverStore.testDetailProvider = { dto in
            Movie(id: dto.id, type: "0", number: dto.number, title: dto.title,
                  thumbURL: dto.thumbURL, coverURL: dto.coverURL)
        }
        HeroCoverStore.testResolverProvider = { _ in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            return nil
        }
        HeroCoverStore.shared.start(movies: [movie], currentIndex: 0)
        let deadline = Date().addingTimeInterval(2.5)
        var samples = 0
        while Date() < deadline {
            let p = HeroCoverStore.shared.presentation(for: movie.id)
            XCTAssertTrue(Self.isPortrait(p.blurImage), "floor layer drew an uncropped landscape bitmap")
            XCTAssertTrue(Self.isPortrait(p.sharpImage), "sharp layer drew an uncropped landscape bitmap")
            if let floor = p.blurImage { XCTAssertTrue(Self.isFront(floor)); samples += 1 }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertGreaterThan(samples, 0)
        let p = HeroCoverStore.shared.presentation(for: movie.id)
        XCTAssertEqual(p.floorPixelWidth, 398, "floor must use the front-cropped cover, not the 166 px thumb")
        XCTAssertEqual(p.floorSource, movie.coverURL)
        // Ambient wash is sampled from the displayed (cropped) bitmap.
        XCTAssertEqual(p.ambient, HomeAmbientColor.base(from: p.blurImage!))
        // The shared crop chain itself.
        let cropped = await ImageLoader.shared.loadPoster(movie.coverURL!, maxPixelSize: 1024)
        XCTAssertEqual(cropped.map(HeroCoverPolicy.pixelWidth), 398)
        // Safety net: a residual landscape raster is right-anchored, portraits center.
        XCTAssertEqual(HeroFillAnchor.x(imageWidth: 840, imageHeight: 568, drawnWidth: 668, containerWidth: 393), 393 - 668)
        XCTAssertEqual(HeroFillAnchor.x(imageWidth: 398, imageHeight: 568, drawnWidth: 393, containerWidth: 393), 0)
    }

    /// (5) Network off and the resolver never completes: stays on the sharp front floor.
    @MainActor
    func test331ResolverNeverCompletesStaysOnSharpFrontFloor() async throws {
        HeroPolicyOverride.short()
        HeroCoverStore.shared.resetForTests()
        await ImageLoader.shared.resetCachesForTests()
        Self.installJacketTransport()
        HeroCoverStore.testDetailProvider = { _ in nil }
        HeroCoverStore.testResolverProvider = { _ in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            return nil
        }
        let movies = (0..<3).map { Self.abfLike("off-floor-331-\($0)", number: "ABF-935\($0)", slug: "Nf331\($0)") }
        HeroCoverStore.shared.start(movies: movies, currentIndex: 0)
        _ = try await poll(3, movies[0].id) { $0.floorPixelWidth == 398 }
        _ = try await poll(3, movies[1].id) { $0.floorPixelWidth == 398 }
        Self.offline.set(true)
        _ = try await poll(2, movies[0].id) { $0.settled }
        HeroCoverStore.shared.setCurrentIndex(1, movies: movies)
        HeroCoverStore.shared.setCurrentIndex(0, movies: movies)
        HeroCoverStore.shared.noteNetworkRecovered()
        try await Task.sleep(nanoseconds: 500_000_000)
        let p = HeroCoverStore.shared.presentation(for: movies[0].id)
        XCTAssertTrue(p.settled)
        XCTAssertEqual(p.floorPixelWidth, 398, "stays on the sharp front-cropped floor")
        XCTAssertTrue(Self.isFront(p.blurImage!) && Self.isPortrait(p.blurImage))
        XCTAssertNil(p.sharpImage)
        XCTAssertFalse(p.isSharp)
        XCTAssertFalse(p.isAB)
        XCTAssertNotEqual(p.phase, .finalized, "a floor never poses as final")
    }

    /// (6) Evict, then swipe back: restored from HeroCoverDisk by winner URL
    /// with zero network requests and no resolver rerun.
    @MainActor
    func test331EvictedWinnerRestoresWithZeroNetwork() async throws {
        HeroCoverStore.shared.resetForTests()
        await ImageLoader.shared.resetCachesForTests()
        Self.installJacketTransport()
        HeroCoverStore.testDetailProvider = { _ in nil }
        HeroCoverStore.testResolverProvider = { movie in
            Self.winnerArt("evc0\(movie.id.suffix(1))331")
        }
        let movies = (0..<4).map { Self.abfLike("evict-331-\($0)", number: "ABF-936\($0)", slug: "Ev331\($0)") }
        HeroCoverStore.shared.start(movies: movies, currentIndex: 0)
        for movie in movies {
            _ = try await poll(6, movie.id) { $0.isSharp && $0.floorPixelWidth == 398 }
        }
        HeroCoverStore.shared.setCurrentIndex(2, movies: movies)
        let evicted = HeroCoverStore.shared.presentation(for: movies[0].id)
        XCTAssertNil(evicted.sharpImage, "item 1 bitmap evicted outside current ±1")
        XCTAssertTrue(evicted.sharpOnDisk && evicted.isAB, "evicted winner stays retrievable from HeroCoverDisk")
        try await Task.sleep(nanoseconds: 300_000_000)
        ImageLoader.testTransportLock.lock()
        let callsBefore = ImageLoader.testTransportCalls
        ImageLoader.testTransportLock.unlock()
        let runsBefore = HeroCoverStore.resolverRunCount

        HeroCoverStore.shared.setCurrentIndex(0, movies: movies)
        let back = try await poll(1.5, movies[0].id) { $0.sharpImage != nil }
        XCTAssertNotNil(back.sharpImage, "swipe back restores the winner")
        XCTAssertEqual(back.sharpImage.map(HeroCoverPolicy.pixelWidth), 760)
        try await Task.sleep(nanoseconds: 300_000_000)
        ImageLoader.testTransportLock.lock()
        let callsAfter = ImageLoader.testTransportCalls
        ImageLoader.testTransportLock.unlock()
        XCTAssertEqual(callsAfter, callsBefore, "restore must make zero network requests")
        XCTAssertEqual(HeroCoverStore.resolverRunCount, runsBefore, "restore must not rerun the resolver")
    }

    /// (7) setCurrentIndex with raw ranking DTOs never drops enriched cover / type;
    /// rank-level fields (title) follow the latest ranking; the resolver gets the merged record.
    @MainActor
    func test331SetCurrentIndexKeepsMergedFields() async throws {
        HeroCoverStore.shared.resetForTests()
        await ImageLoader.shared.resetCachesForTests()
        Self.installJacketTransport()
        let cover = "https://tp.spfcas.com/rhe951l4q/covers/mm/Merge331.jpg"
        HeroCoverStore.testDetailProvider = { dto in
            Movie(id: dto.id, type: "0", number: dto.number, title: dto.title, coverURL: cover)
        }
        final class Seen: @unchecked Sendable { var movies: [Movie] = [] }
        let seen = Seen()
        HeroCoverStore.testResolverProvider = { movie in
            await MainActor.run { seen.movies.append(movie) }
            return nil
        }
        let dto = Movie(id: "merge-331", number: "ABF-9371", title: "Old title",
                        thumbURL: "https://tp.spfcas.com/rhe951l4q/small_covers/mm/Merge331.jpg")
        HeroCoverStore.shared.start(movies: [dto], currentIndex: 0)
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, seen.movies.isEmpty { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(seen.movies.first?.type, "0", "resolver must receive the enrich-merged record")
        XCTAssertEqual(seen.movies.first?.coverURL, cover)

        let refreshed = Movie(id: "merge-331", number: "ABF-9371", title: "New title",
                              thumbURL: "https://tp.spfcas.com/rhe951l4q/small_covers/mm/Merge331.jpg")
        HeroCoverStore.shared.setCurrentIndex(0, movies: [refreshed])
        HeroCoverStore.shared.clearNegativesAndRetry()
        let again = Date().addingTimeInterval(3)
        while Date() < again, seen.movies.count < 2 { try await Task.sleep(nanoseconds: 20_000_000) }
        let latest = try XCTUnwrap(seen.movies.last)
        XCTAssertEqual(latest.type, "0", "enriched type is never overwritten by the raw DTO")
        XCTAssertEqual(latest.coverURL, cover, "enriched cover is never overwritten by the raw DTO")
        XCTAssertEqual(latest.title, "New title", "rank / title follow the latest ranking")
        let merged = refreshed.preservingHeroEnrichment(from: Movie(id: "merge-331", type: "0", number: "ABF-9371", coverURL: cover))
        XCTAssertEqual(merged.coverURL, cover)
        XCTAssertEqual(merged.type, "0")
        XCTAssertEqual(merged.title, "New title")
    }

    /// (8) Winner sharing by movie id between the detail page and home, both ways.
    @MainActor
    func test331DetailWinnerSharedByMovieID() async throws {
        HeroCoverStore.shared.resetForTests()
        await ImageLoader.shared.resetCachesForTests()
        Self.installJacketTransport()
        HeroCoverStore.testDetailProvider = { _ in nil }
        HeroCoverStore.testResolverProvider = { _ in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            return nil
        }
        let account = APIClient.shared.token
        let dto = Self.abfLike("share-331", number: "ABF-9381", slug: "Share331")
        HeroCoverStore.shared.start(movies: [dto], currentIndex: 0)
        _ = try await poll(3, dto.id) { $0.floorPixelWidth == 398 }
        XCTAssertNil(HeroCoverStore.shared.presentation(for: dto.id).sharpImage)

        // Detail page resolves with its *full* record (type / different fields):
        // returning home upgrades the hero immediately.
        let art = Self.winnerArt("abf09381")
        DetailPosterWinners.store(art, movieID: dto.id, account: account)
        let upgraded = try await poll(1.5, dto.id) { $0.sharpImage != nil }
        XCTAssertEqual(upgraded.sharpImage.map(HeroCoverPolicy.pixelWidth), 760, "detail winner overrides the floor on arrival")
        XCTAssertEqual(upgraded.winnerURL, art.sourceURL)

        // Home → detail: the detail page's full-record identity finds the same winner by id.
        let full = Movie(id: dto.id, type: "0", number: dto.number, title: "Full detail record",
                         thumbURL: dto.thumbURL, coverURL: "https://tp.spfcas.com/rhe951l4q/covers/mb/Share331-full.jpg")
        let layout = DetailPosterResolver.initialLayout(movie: full, account: account)
        XCTAssertEqual(layout.artwork?.sourceURL, art.sourceURL)
        XCTAssertNil(DetailPosterWinners.winner(movieID: "other-331", account: account))
    }
}

/// Short 6s rhythm point for the never-completing resolver test.
enum HeroPolicyOverride {
    static func short() { HeroCoverPolicy.overallBudgetOverride = 0.3 }
}
