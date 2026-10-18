import XCTest
import UIKit
@testable import AVDB

final class WesternCoverTests: XCTestCase {
    func identity(_ brand: String = "Blackedraw", title: String = "Neutral Original Title", url: String? = nil) -> WesternCoverPolicy.Identity {
        WesternCoverPolicy.identity(type: "2", number: brand + ".2026.10.13", title: title, date: "2026-10-13", minutes: 35, officialURL: url)!
    }
    func record(_ brand: String = "blackedraw", name: String = "Blacked Raw") -> [String: Any] {
        ["id":"4d2c0748-71ea-4f1b-b486-94db042c7b34", "title":"Neutral Original Title", "date":"2026-10-13", "duration":2091,
         "site":["name":name,"short_name":brand], "url":"https://www." + brand + ".com/videos/neutral-original-title",
         "image":"https://cdn." + brand + ".com/scene/videoimages/12/mainLandscape/34/neutral_1920x1080.jpeg"]
    }
    func testFourBrandsAndUnknownFailClosed() {
        for site in WesternCoverPolicy.sites {
            let i = identity(site.key)
            XCTAssertTrue(WesternCoverPolicy.recordMatches(record(site.key, name: site.name), identity: i))
        }
        XCTAssertNil(WesternCoverPolicy.identity(type:"2", number:"Unknown.2026.10.13", title:"Neutral Original Title", date:nil, minutes:35))
        XCTAssertNil(WesternCoverPolicy.identity(type:"0", number:"Blackedraw.2026.10.13", title:"Neutral Original Title", date:nil, minutes:35))
        XCTAssertNil(WesternCoverPolicy.identity(type:"2", number:"Vixen.2026.02.30", title:"Neutral Original Title", date:nil, minutes:35))
    }
    func testCompoundConflictsAmbiguityAndExactURLDatePrecedence() {
        var r = record(); let i = identity()
        XCTAssertTrue(WesternCoverPolicy.recordMatches(r, identity:i))
        XCTAssertNil(WesternCoverPolicy.uniqueRecord([r,r], identity:i))
        r["title"] = "Another Original Title"; XCTAssertFalse(WesternCoverPolicy.recordMatches(r, identity:i))
        r = record(); r["duration"] = 4000; XCTAssertFalse(WesternCoverPolicy.recordMatches(r, identity:i))
        r = record(); r["date"] = "2026-10-14"; XCTAssertFalse(WesternCoverPolicy.recordMatches(r, identity:i))
        let exact = identity(url:"https://www.blackedraw.com/videos/neutral-original-title")
        XCTAssertTrue(WesternCoverPolicy.recordMatches(r, identity:exact))
        r["url"] = "https://www.blackedraw.com/videos/another-title"; XCTAssertFalse(WesternCoverPolicy.recordMatches(r, identity:exact))
    }
    func testAPIOriginAndDerivedImagesRejected() {
        for raw in ["http://api.theporndb.net/scenes", "https://api.theporndb.net.evil.test/scenes", "https://x:pass@api.theporndb.net/scenes", "https://cdn.theporndb.net/scenes", "https://api.theporndb.net:444/scenes"] {
            XCTAssertFalse(WesternCoverPolicy.apiAllowed(URL(string:raw)!))
        }
        XCTAssertTrue(WesternCoverPolicy.apiAllowed(URL(string:"https://api.theporndb.net/scenes?site=Vixen")!))
        XCTAssertFalse(WesternCoverPolicy.imageAllowed(URL(string:"https://cdn.theporndb.net/scene/800x1200/smart/filters:upscale()/background/neutral.jpg")!))
        XCTAssertFalse(WesternCoverPolicy.imageAllowed(URL(string:"https://cdn.vixen.com/scene/videoimages/1/mainLandscape/2/neutral.jpg?token=x")!))
    }
    func testNativePixelsLandscapeNoCropAndLateLargerWinner() async {
        let renderer = UIGraphicsImageRenderer(size:CGSize(width:1920,height:1080), format: { let f=UIGraphicsImageRendererFormat();f.scale=1;return f }())
        let png = renderer.image { c in UIColor.systemTeal.setFill();c.fill(CGRect(x:0,y:0,width:1920,height:1080)) }.pngData()!
        let decoded = DetailPosterResolver.decode(data:png, sourceURL:"https://cdn.vixen.com/scene/videoimages/1/mainLandscape/2/neutral.jpg", derive:false, western:true)!
        XCTAssertEqual(decoded.quality.width,1920);XCTAssertEqual(decoded.quality.height,1080)
        let q = await DetailPosterSelection.collect(sources:["fast","late"], budget:1) { source,_ -> DetailPosterQuality? in
            if source == "late" { try? await Task.sleep(nanoseconds:120_000_000) }
            return DetailPosterQuality(source:source,width:source == "late" ? 1920:640,height:source == "late" ? 1080:360,originalPortrait:true)
        }
        XCTAssertEqual(WesternCoverPolicy.winner(q)?.source,"late")
    }
    func testSourceHostSpoofingAndSafeCopy() {
        XCTAssertEqual(CoverSourceDisplay.name(host:"cdn.vixen.com"),"片商")
        XCTAssertEqual(CoverSourceDisplay.name(host:"image.mgstage.com"),"MGStage")
        XCTAssertEqual(CoverSourceDisplay.name(host:"fakejavdb.example"),"fakejavdb.example")
        XCTAssertEqual(CoverSourceDisplay.safeURL("https://user:password@example.test/image.jpg?token=secret#fragment"),"https://example.test/image.jpg")
    }
    final class Store: ExternalTokenStore {
        var token: String?
        func read() throws -> String? { token }
        func write(_ token: String) throws { self.token = token }
        func clear() throws { token=nil }
    }
    @MainActor func testSavedSwitchTokenClearNamespaceAndCancelledCache() async throws {
        let store=Store();let defaults=UserDefaults(suiteName:"neutral-western-tests")!;defaults.removePersistentDomain(forName:"neutral-western-tests")
        let s=WesternCoverSettings(store:store,defaults:defaults)
        XCTAssertFalse(s.enabled);XCTAssertFalse(s.hasToken);let first=s.namespace
        try s.save(enabled:true,replacement:"neutral-fixture-token");XCTAssertTrue(s.enabled);XCTAssertTrue(s.hasToken);XCTAssertNotEqual(first,s.namespace)
        let second=s.namespace;try s.clear();XCTAssertFalse(s.hasToken);XCTAssertNotEqual(second,s.namespace)
        let cache=DetailPosterCache<String>();let started=expectation(description:"cache flight started")
        let t=Task { await cache.value(key:"account-A") { started.fulfill();try? await Task.sleep(nanoseconds:80_000_000);return "stale" } }
        await fulfillment(of:[started],timeout:2);cache.invalidate();_ = await t.value
        XCTAssertNil(cache.snapshot(key:"account-A").artwork);XCTAssertNil(cache.snapshot(key:"account-B").artwork)
    }
    func testData18AgeMovieAndSyntheticGalleryFailClosed() {
        XCTAssertTrue(WesternCoverPolicy.restricted("<h1>Age Verification</h1>"))
        XCTAssertNil(WesternCoverPolicy.dataMatch("<title>Neutral Porn Movie | DATA18</title>",identity:identity()))
        XCTAssertNil(WesternCoverPolicy.primaryImage("scene=1398670 gallery0Primary"))
        XCTAssertEqual(WesternCoverPolicy.primaryImage("<a href='https://bdn.dt18.com/338/3117/398670/0.jpg'>Primary</a>"),"https://bdn.dt18.com/338/3117/398670/0.jpg")
    }
}
