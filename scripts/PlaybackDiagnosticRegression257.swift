import Foundation

@MainActor enum PlaybackDiagnosticRegression257 {
    static func run() async throws {
        typealias D = PlaybackDiagnostic
        var count = 0
        func check(_ value: Bool, _ name: String) { count += 1; precondition(value, name) }
        let signed = URL(string: "https://cdn.example.test/private/SECRET_PATH/index.m3u8?token=SECRET_QUERY#SECRET_FRAGMENT")!
        let raw = NSError(domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed,
            userInfo: [NSLocalizedDescriptionKey: signed.absoluteString, NSURLErrorFailingURLErrorKey: signed])
        let safe = D.system(raw, stage: .manifest, url: signed)
        check(safe.category == .tls && safe.stage == .manifest, "typed stage and TLS")
        check(safe.host == "cdn.example.test" && safe.systemCode == -1200, "host and system code")
        for secret in ["SECRET", "token", "index.m3u8", "https:", "private/"] {
            check(!safe.display.contains(secret), "signed URL must not leak")
            check(!String(describing: safe).contains(secret), "stored data must not leak")
        }
        for text in ["https://u:p@cdn.example.test/path?token=SECRET", "file:///private/SECRET", "https://cdn.example.test@evil.example.test/SECRET"] {
            check(D.resourceHost(URL(string: text)) == nil, "userinfo/unsupported resource hidden")
        }
        for host in ["u:p@cdn.example.test", "cdn.example.test/path", "cdn.example.test?token=x", "cdn.example.test\nSECRET", "https://cdn.example.test"] {
            check(D(stage: .document, category: .unknown, host: host).host == nil, "invalid host hidden")
        }
        for stage in [D.Stage.discovery, .document, .embed, .manifest, .segment, .decode] {
            let incomplete = OnlineFailure.incomplete.presentation(at: stage)
            check(incomplete.category == .unsupported && incomplete.stage == stage, "incomplete preserves caller stage")
            check(!incomplete.display.contains("DNS"), "incomplete never fabricates DNS cause")
        }
        let http = OnlineFailure.http(403).presentation(at: .manifest)
        check(http.httpCode == 403 && http.category == .http && http.display.contains("403"), "typed HTTP code")
        check(D(stage: .manifest, category: .http, httpCode: 999).httpCode == nil, "invalid HTTP status hidden")
        let hostile = OnlineFailure.diagnostic(stage: signed.absoluteString, host: signed.absoluteString, reason: signed.absoluteString).presentation(at: .document)
        check(hostile.stage == .document && hostile.host == nil && !hostile.display.contains("SECRET"), "untrusted legacy free text removed")
        for (code, category) in [(NSURLErrorCannotConnectToHost, D.Category.connection), (NSURLErrorCannotFindHost, .dns), (NSURLErrorTimedOut, .timeout), (NSURLErrorCancelled, .cancelled)] {
            let error = NSError(domain: NSURLErrorDomain, code: code, userInfo: [NSLocalizedDescriptionKey:signed.absoluteString])
            check(D.system(error, stage: .decode).category == category, "URL domain mapping")
            check(D.system(NSError(domain: "NeutralOtherDomain", code: code), stage: .decode).category == .unknown, "integer collision not URL error")
        }
        check(OnlineFailure.classify(NSError(domain: "NeutralOtherDomain", code: -1200)).presentation(at: .decode).category == .unknown, "legacy classifier domain checked")
        check(OnlineFailure.classify(NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)).presentation(at: .decode).category == .connection, "connection is not DNS")
        check(D.system(CancellationError(), stage: .discovery).category == .cancelled, "Swift cancellation mapped")
        let label = OnlinePlaybackModel.State.failed(.incomplete).label
        check(label.contains("查询") && label.contains("暂不支持"), "production query label")
        let line = OnlineLine(source: .jable, recordID: "neutral", code: "DEMO-123", version: "neutral", lineKey: "0")
        let resolution = OnlinePlaybackModel.Resolution(line: line, status: .failed(.incomplete))
        check(resolution.label.contains("详情") && resolution.label.contains("暂不支持"), "production resolution label")
        // Real production parser, synthetic bytes only; no Python parser replacement.
        let manifest = Data("#EXTM3U\n#EXTINF:4,\nneutral.ts\n#EXT-X-ENDLIST\n".utf8)
        do {
            _ = try OnlineManifest.parse(manifest, at: signed, root: signed)
            preconditionFailure("reserved test TLD escaped existing production policy")
        } catch { check(OnlineFailure.classify(error) == .unsafe, "existing reserved-domain restriction preserved") }
        let memoryOnly = URL(string: "https://cdn.example.net/neutral/index.m3u8")!
        _ = try OnlineManifest.parse(manifest, at: memoryOnly, root: memoryOnly)
        check(true, "production HLS parser with synthetic in-memory bytes; no fetch")
        // Child ignores task cancellation while waiting for a genuine async callback.
        // Old structured task group waited 300ms before delivering its 20ms timeout.
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let _: Int = try await OnlinePlaybackModel.bounded(nanoseconds: 20_000_000) {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { continuation.resume(returning: 7) }
                }
            }
            preconditionFailure("late success escaped deadline")
        } catch { check(OnlineFailure.classify(error) == .timeout, "timeout terminal marker") }
        check(DispatchTime.now().uptimeNanoseconds - start < 250_000_000, "timeout returns before uncooperative worker")
        let task = Task { try await OnlinePlaybackModel.bounded { () async throws -> Int in
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { continuation.resume(returning: 9) }
            }
        } }
        await Task.yield(); let cancelStart = DispatchTime.now().uptimeNanoseconds; task.cancel()
        do { _ = try await task.value; preconditionFailure("cancel result escaped") }
        catch { check(OnlineFailure.classify(error) == .cancelled, "cancel terminal marker") }
        check(DispatchTime.now().uptimeNanoseconds - cancelStart < 250_000_000, "cancel returns before uncooperative worker")
        try await Task.sleep(nanoseconds: 350_000_000)
        do { _ = try await task.value; preconditionFailure("late result overwrote cancellation") }
        catch { check(OnlineFailure.classify(error) == .cancelled, "late result cannot overwrite terminal marker") }
        for _ in 0..<30 {
            let race = Task { try await PlaybackDeadline<Int>.run(nanoseconds: 500_000) { await Task.yield(); return 1 } }
            await Task.yield(); race.cancel()
            do { check(try await race.value == 1, "completed terminal preserved") }
            catch { let e = OnlineFailure.classify(error); check(e == .cancelled || e == .timeout, "one race terminal") }
        }
        // Existing model must bind the new context BEFORE checking old busy flags.
        let suite = "neutral257." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let transport = OnlineTransport(loader: { request in
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { continuation.resume() }
            }
            return try OnlineRegression254.response(request)
        })
        let model = OnlinePlaybackModel(provider: OnlineProvider(transport: transport), preferences: preferences)
        model.query(.jable, number: "DEMO-123", versions: false)
        model.query(.jable, number: "DEMO-124", versions: false)
        try await OnlineRegression254.settle(model)
        check(model.states[.jable] == .failed(.noMatch), "new query context replaces busy old generation")
        check(model.plan == nil, "late query never launches player")
        model.choose(line, number: "DEMO-123", versions: false)
        var replacement = line; replacement.routeDigest = "neutral-replacement"
        model.choose(replacement, number: "DEMO-124", versions: false)
        check(model.resolutions[.jable]?.line == replacement, "new selection context replaces old busy resolution")
        model.cancelPending()
        try await Task.sleep(nanoseconds: 350_000_000)
        check(model.plan == nil && model.resolving == nil, "late cancelled resolution cannot publish plan")
        print("PASS257", count, "typed diagnostic/privacy/system-domain/stage/production-label/timeout/cancel/late-result/context/race assertions; neutral injected data only")
    }
}

@main struct NeutralPlayback257 {
    @MainActor static func main() async throws {
        precondition(ProcessInfo.processInfo.environment["ONLINE254_LIVE"] != "1")
        try await OnlineRegression254.main()
        try await OnlineCompatibilityRegression256.run()
        try await PlaybackDiagnosticRegression257.run()
        print("NEUTRAL257 COMPLETE; no real-source requests; real playback not verified")
    }
}
