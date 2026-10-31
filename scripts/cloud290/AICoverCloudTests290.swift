// Build 290 unit + integration tests for AVDB/Services/AICoverCloud.swift (compiled together with it).
//   t                       → unit tests with a scripted mock transport (hit / miss / 401 / offline / 5xx fallback /
//                             timeout / upload ok / 507 / 413 / retry+backoff / Wi‑Fi-only / LRU + migration)
//   t --server <base>       → same client over real URLSession against scripts/cloud290/mock_worker.py
//   t --real <base>         → CI e2e against the deployed Worker under the `ci/` prefix (key from env AVDB_COVERS_KEY;
//                             skips with exit 0 when the key is missing). The key is never printed.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

var failures = 0
func check(_ c: Bool, _ m: String) { if c { print("ok  ", m) } else { failures += 1; print("FAIL", m) } }

final class MockTransport: AICoverCloudTransport, @unchecked Sendable {
    typealias Handler = (URLRequest) async throws -> (Int, Data, [String: String])
    let lock = NSLock()
    var handler: Handler
    private(set) var requests: [URLRequest] = []
    init(_ h: @escaping Handler) { handler = h }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock(); requests.append(request); let h = handler; lock.unlock()
        let (code, data, headers) = try await h(request)
        return (data, HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!)
    }
    var count: Int { lock.lock(); defer { lock.unlock() }; return requests.count }
    var hosts: [String] { lock.lock(); defer { lock.unlock() }; return requests.map { $0.url!.host ?? "" } }
}
let A = URL(string: "https://primary.test")!, B = URL(string: "https://fallback.test")!
func freshSettings(_ name: String) -> AICoverCloudSettings {
    let d = UserDefaults(suiteName: "avdb.test.\(name).\(UUID().uuidString)")!
    return AICoverCloudSettings(defaults: d)
}
let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: UInt8(7), count: 2000) + [0xFF, 0xD9])

func unitTests() async {
    // Names
    check(AICoverCloudName.make(number: "ipx-706", width: 378, height: 538, fallbackHash: "ab") == "IPX-706_378x538", "name from 番号 + native size")
    check(AICoverCloudName.make(number: "FC2 PPV/12 34", width: 1, height: 2, fallbackHash: "x") == "FC2-PPV-12-34_1x2", "name sanitized to [A-Za-z0-9._-]")
    check(AICoverCloudName.make(number: nil, width: 3, height: 4, fallbackHash: "DEADbeef00") == "hdeadbeef00_3x4", "hash fallback without 番号")
    check(AICoverCloudName.valid(AICoverCloudName.make(number: String(repeating: "A", count: 200), width: 1000, height: 1000, fallbackHash: "")), "long names stay ≤ 80 chars")
    check(AICoverCloudName.path("IPX-706_378x538", ext: "jpg") == "/v1/cover/nomos1/IPX-706_378x538.jpg", "path uses model prefix nomos1")

    // fetch: hit
    let hit = MockTransport { r in
        precondition(r.value(forHTTPHeaderField: "X-AVDB-Key") == "k" && (r.httpMethod == "GET" || r.httpMethod == "HEAD"))
        return (200, r.httpMethod == "HEAD" ? Data() : jpeg, ["Content-Type": "image/jpeg"])
    }
    let c1 = AICoverCloudClient(bases: [A, B], key: "k", transport: hit)
    check(await c1.fetch(name: "IPX-706_378x538") == .hit(jpeg, contentType: "image/jpeg"), "HEAD 200 → GET → hit (key header sent)")
    check(hit.count == 2 && hit.hosts == ["primary.test", "primary.test"] && hit.requests.map { $0.httpMethod ?? "" } == ["HEAD", "GET"], "hit = HEAD + GET on the primary")
    // miss
    let miss = MockTransport { _ in (404, Data("{}".utf8), [:]) }
    check(await AICoverCloudClient(bases: [A, B], key: "k", transport: miss).fetch(name: "X_1x1") == .miss, "404 → miss")
    check(miss.count == 1 && miss.requests[0].httpMethod == "HEAD", "404 on HEAD → no GET, no fallback")
    // 401
    let unauth = MockTransport { _ in (401, Data(), [:]) }
    if case .unavailable(let w) = await AICoverCloudClient(bases: [A, B], key: "bad", transport: unauth).fetch(name: "X_1x1") { check(w == "HTTP 401" && unauth.count == 1, "401 → unavailable (silent local fallback)") } else { check(false, "401") }
    // offline primary → fallback
    let flaky = MockTransport { r in
        if r.url!.host == "primary.test" { throw URLError(.notConnectedToInternet) }
        return (200, r.httpMethod == "HEAD" ? Data() : jpeg, ["Content-Type": "image/heic"])
    }
    check(await AICoverCloudClient(bases: [A, B], key: "k", transport: flaky).fetch(name: "X_1x1") == .hit(jpeg, contentType: "image/heic"), "primary offline → fallback base hit")
    // fully offline
    let offline = MockTransport { _ in throw URLError(.notConnectedToInternet) }
    if case .unavailable = await AICoverCloudClient(bases: [A, B], key: "k", transport: offline).fetch(name: "X_1x1") { check(offline.count == 2, "offline → unavailable after both bases") } else { check(false, "offline") }
    // 5xx → fallback
    let five = MockTransport { r in r.url!.host == "primary.test" ? (502, Data(), [:]) : (404, Data(), [:]) }
    check(await AICoverCloudClient(bases: [A, B], key: "k", transport: five).fetch(name: "X_1x1") == .miss, "502 on primary → fallback answers 404 → miss")
    // timeout (never blocks the cover): a server that hangs 10 s is cut at fetchTimeout
    let slow = MockTransport { _ in try await Task.sleep(nanoseconds: 10_000_000_000); return (200, jpeg, [:]) }
    let t0 = Date()
    let r = await AICoverCloudClient(bases: [A, B], key: "k", transport: slow, fetchTimeout: 0.4).fetch(name: "X_1x1")
    let dt = Date().timeIntervalSince(t0)
    check(r == .unavailable("timeout") && dt < 1.5, String(format: "hung server → timeout in %.2fs (budget 0.4 s total, both bases)", dt))
    check(AICoverCloudConfig.fetchTimeout == 2.5, "production HEAD budget 2.5 s")
    // slow body after a quick HEAD: still a hit (body budget is separate)
    let slowBody = MockTransport { r in
        if r.httpMethod == "GET" { try await Task.sleep(nanoseconds: 900_000_000) }
        return (200, r.httpMethod == "HEAD" ? Data() : jpeg, ["Content-Type": "image/jpeg"])
    }
    check(await AICoverCloudClient(bases: [A], key: "k", transport: slowBody, fetchTimeout: 0.4).fetch(name: "X_1x1") == .hit(jpeg, contentType: "image/jpeg"),
          "HEAD in time + body slower than the HEAD budget → still a hit")
    // no key
    check(await AICoverCloudClient(bases: [A], key: nil, transport: hit).fetch(name: "X") == .unavailable("未配置云端密钥"), "no build key → local only")

    // upload
    let put = MockTransport { r in
        precondition(r.httpMethod == "PUT" && r.value(forHTTPHeaderField: "Content-Type") == "image/jpeg" && r.httpBody == jpeg)
        return (201, Data(#"{"ok":true}"#.utf8), [:])
    }
    check(await AICoverCloudClient(bases: [A, B], key: "k", transport: put).upload(name: "N_1x1", data: jpeg, contentType: "image/jpeg") == .ok, "PUT 201 → ok")
    let full = MockTransport { _ in (507, Data(), [:]) }
    check(await AICoverCloudClient(bases: [A, B], key: "k", transport: full).upload(name: "N", data: jpeg, contentType: "image/jpeg") == .quotaFull, "PUT 507 → quotaFull")
    check(await AICoverCloudClient(bases: [A], key: "k", transport: put).upload(name: "N", data: Data(count: 3 * 1024 * 1024 + 1), contentType: "image/jpeg") == .rejected(413), "> 3 MiB never sent")
    check(put.count == 1, "oversize body not uploaded")

    // queue: 507 stops uploading and is remembered (settings note)
    let s1 = freshSettings("q507")
    let full2 = MockTransport { _ in (507, Data(), [:]) }
    let q1 = AICoverUploadQueue(client: AICoverCloudClient(bases: [A], key: "k", transport: full2), settings: s1, isExpensiveNetwork: { false }, sleep: { _ in })
    await q1.enqueue(.init(name: "A_1x1", contentType: "image/jpeg", fileURL: nil, data: jpeg))
    await q1.enqueue(.init(name: "B_1x1", contentType: "image/jpeg", fileURL: nil, data: jpeg))
    await q1.drain()
    check(s1.quotaFull() && full2.count == 1, "507 → stop after the first PUT, quota flag set (settings note)")
    await q1.enqueue(.init(name: "C_1x1", contentType: "image/jpeg", fileURL: nil, data: jpeg)); await q1.drain()
    check(full2.count == 1, "no more PUTs while the 507 pause is active")

    // queue: retry with backoff then success
    var attempts = 0
    let retry = MockTransport { _ in attempts += 1; return attempts < 3 ? (503, Data(), [:]) : (201, Data(), [:]) }
    let slept = NSMutableArray()
    let s2 = freshSettings("retry")
    let q2 = AICoverUploadQueue(client: AICoverCloudClient(bases: [A], key: "k", transport: retry), settings: s2, isExpensiveNetwork: { false },
                                sleep: { s in slept.add(s) })
    await q2.enqueue(.init(name: "R_1x1", contentType: "image/jpeg", fileURL: nil, data: jpeg)); await q2.drain()
    check(s2.uploads == 1 && s2.isInCloud("R_1x1") && (slept as! [Double]) == [2, 8], "503,503,201 → uploaded after backoff 2 s, 8 s")
    check(AICoverUploadQueue.backoff(5) == 300, "backoff capped at 300 s")
    await q2.enqueue(.init(name: "R_1x1", contentType: "image/jpeg", fileURL: nil, data: jpeg)); await q2.drain()
    check(retry.count == 3, "already-in-cloud names are not uploaded again")

    // queue: Wi‑Fi only on cellular → skipped; off → uploads
    let s3 = freshSettings("wifi"); s3.wifiOnly = true
    let q3 = AICoverUploadQueue(client: AICoverCloudClient(bases: [A], key: "k", transport: put), settings: s3, isExpensiveNetwork: { true }, sleep: { _ in })
    await q3.enqueue(.init(name: "W_1x1", contentType: "image/jpeg", fileURL: nil, data: jpeg)); await q3.drain()
    check(put.count == 1 && s3.uploads == 0, "仅 Wi‑Fi 上传 on + cellular → no PUT")
    s3.wifiOnly = false
    await q3.enqueue(.init(name: "W_1x1", contentType: "image/jpeg", fileURL: nil, data: jpeg)); await q3.drain()
    check(put.count == 2 && s3.uploads == 1, "default (off) → uploads on cellular too")
    // cloud off
    let s4 = freshSettings("off"); s4.enabled = false
    let q4 = AICoverUploadQueue(client: AICoverCloudClient(bases: [A], key: "k", transport: put), settings: s4, isExpensiveNetwork: { false }, sleep: { _ in })
    await q4.enqueue(.init(name: "O_1x1", contentType: "image/jpeg", fileURL: nil, data: jpeg)); await q4.drain()
    check(put.count == 2, "云端增强图 off → nothing uploaded")
    check(freshSettings("defaults").enabled && freshSettings("d2").capMB == 200 && !freshSettings("d3").wifiOnly, "defaults: cloud on, cap 200 MB, Wi‑Fi-only off")

    // LRU + migration grace
    let now = Date()
    let files: [(id: String, bytes: Int, lastUse: Date)] = [("old1", 100, now.addingTimeInterval(-500)), ("old2", 100, now.addingTimeInterval(-400)),
                                                            ("new1", 100, now.addingTimeInterval(-10)), ("new2", 100, now.addingTimeInterval(-5)), ("new3", 100, now)]
    check(AICoverLRU.evictions(files, cap: 250) == ["old1", "old2", "new1"], "LRU evicts least recently used down to the cap")
    check(AICoverLRU.evictions(files, cap: 250, protectBefore: now.addingTimeInterval(-100)) == ["new1"], "pre-290 files are protected (not counted) during migration grace")
    let d = UserDefaults(suiteName: "avdb.test.mig.\(UUID().uuidString)")!
    AICoverMigration.begin(d, now: now)
    check(AICoverMigration.protectBefore(d, now: now.addingTimeInterval(86400)) == now, "grace open on day 1")
    check(AICoverMigration.protectBefore(d, now: now.addingTimeInterval(31 * 86400)) == nil, "grace closed after 30 days → trimmed to cap")
}

func serverTests(_ base: URL) async {
    let client = AICoverCloudClient(bases: [base], key: "test-key", transport: AICoverURLSessionTransport(), prefix: "ci")
    let name = "MOCK-001_378x538"
    // 291: cold URLSession + freshly started Python server can exceed the 2.5 s HEAD budget on a loaded runner
    // (flaked once in CI run 41162861939); one retry keeps the assertion about the 404 → miss mapping.
    var first = await client.fetch(name: name)
    if case .unavailable = first { first = await client.fetch(name: name) }
    check(first == .miss, "mock server: GET before upload → 404 miss")
    check(await client.upload(name: name, data: jpeg, contentType: "image/jpeg") == .ok, "mock server: PUT → 201")
    check(await client.fetch(name: name) == .hit(jpeg, contentType: "image/jpeg"), "mock server: GET after upload → identical bytes")
    let bad = AICoverCloudClient(bases: [base], key: "wrong", transport: AICoverURLSessionTransport(), prefix: "ci")
    check(await bad.fetch(name: name) == .unavailable("HTTP 401"), "mock server: wrong key → 401 → unavailable")
    let fullClient = AICoverCloudClient(bases: [base], key: "test-key", transport: AICoverURLSessionTransport(), prefix: "full")
    check(await fullClient.upload(name: name, data: jpeg, contentType: "image/jpeg") == .quotaFull, "mock server: quota → 507")
    let dead = AICoverCloudClient(bases: [URL(string: "http://127.0.0.1:9")!, base], key: "test-key", transport: AICoverURLSessionTransport(), prefix: "ci")
    check(await dead.fetch(name: name) == .hit(jpeg, contentType: "image/jpeg"), "mock server: dead primary → fallback hit")
    let offline = AICoverCloudClient(bases: [URL(string: "http://127.0.0.1:9")!], key: "test-key", transport: AICoverURLSessionTransport(), prefix: "ci")
    if case .unavailable = await offline.fetch(name: name) { check(true, "offline (connection refused) → unavailable") } else { check(false, "offline") }
}

func realTests(_ base: URL) async -> Bool {
    guard let key = ProcessInfo.processInfo.environment["AVDB_COVERS_KEY"], key.count >= 32 else {
        print("SKIP real Worker e2e: AVDB_COVERS_KEY not set"); return false
    }
    let client = AICoverCloudClient(bases: [base], key: key, transport: AICoverURLSessionTransport(), fetchTimeout: 10, prefix: "ci")
    let run = ProcessInfo.processInfo.environment["GITHUB_RUN_ID"] ?? "local"
    let name = "e2e-\(run)-\(base.host?.split(separator: ".").first ?? "b")-\(Int(Date().timeIntervalSince1970))"   // 291: unique per base (both bases share one bucket; same-second runs collided)
    let body = (try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))) ?? jpeg
    check(await client.fetch(name: name) == .miss, "real Worker: fresh ci/ name → 404 miss")
    let t0 = Date()
    let up = await client.upload(name: name, data: body, contentType: "image/jpeg")
    check(up == .ok, "real Worker: PUT \(body.count) B → 201 (\(String(format: "%.2f", Date().timeIntervalSince(t0))) s)")
    let t1 = Date()
    let got = await client.fetch(name: name)
    check(got == .hit(body, contentType: "image/jpeg"), "real Worker: GET → identical bytes (\(String(format: "%.2f", Date().timeIntervalSince(t1))) s)")
    let wrong = AICoverCloudClient(bases: [base], key: "wrong-key", transport: AICoverURLSessionTransport(), fetchTimeout: 10, prefix: "ci")
    check(await wrong.fetch(name: name) == .unavailable("HTTP 401"), "real Worker: wrong key → 401")
    return true
}

let args = CommandLine.arguments
if args.count >= 3, args[1] == "--server" { await serverTests(URL(string: args[2])!) }
else if args.count >= 4, args[1] == "--real" { _ = await realTests(URL(string: args[2])!) }
else { await unitTests() }
if failures > 0 { print("\(failures) FAILED"); exit(1) }
print("PASS cloud290 \(args.count > 1 ? args[1] : "unit")")
