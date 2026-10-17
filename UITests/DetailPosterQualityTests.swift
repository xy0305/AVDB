import XCTest
import UIKit
import ImageIO
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
        XCTAssertEqual(large.quality.score, 1800)
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
