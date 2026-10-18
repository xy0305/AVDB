"""Replay captured readonly production responses through shipping SDK + Movie decoder.
Only HTTP transport and unrelated cover generation are substituted. No write endpoints.
"""
from pathlib import Path
import json, shutil, subprocess, tempfile
root = Path(__file__).resolve().parents[1]
read = lambda p: (root / p).read_text()
sdk = read('AVDB/Services/JavDBSDK.swift').split('    /// 分类搜索：按演员/系列/片商/导演/清单/番号 搜索。')[0] + '\n}\n'
core = read('AVDB/Services/JavRankingCore.swift')
source = read('AVDB/Services/JavRankingSource.swift')
assert 'JavDBSDK.shared.exactMovie(code: code, refresh: refresh)' in source
assert 'type: "code"' not in source
native = read('AVDB/Views/Search/SearchView.swift')
assert 'type: "movie"' in native and 'JavDBSDK.shared.search(' in native
fixtures = root / 'scripts/javranking-fixtures'
for code, mid in [('IPX580','68YVQ'),('IPX247','KmKGv')]:
    category = json.loads((fixtures / f'production-search-{code}-code.json').read_text())
    movies = json.loads((fixtures / f'production-search-{code}-movie.json').read_text())
    assert category['success'] == 1 and 'codes' in category['data'] and 'movies' not in category['data']
    assert any(m['id'] == mid and m['number'].replace('-','') == code for m in movies['data']['movies'])
print('PASS captured production differential: code -> data.codes; movie -> data.movies, IPX580=68YVQ IPX247=KmKGv')
response = read('AVDB/Networking/APIClient.swift').split('/// 统一响应包裹结构')[1].split('/// 空数据占位')[0]
errors = read('AVDB/Networking/APIClient.swift').split('/// API 错误')[1].split('/// JAVDB HTTP 客户端')[0]
swift = 'import Foundation\n' + core + read('AVDB/Services/ExternalLibraryClient.swift').split('final class ExternalLibraryClient')[0] + read('AVDB/Models/JSONFlex.swift') + read('AVDB/Models/Movie.swift') + response + errors + r'''
public enum CoverURLBuilder {
    public static func coverURLs(for number: String?) -> (poster: String?, backdrop: String?) { (nil, nil) }
}
@MainActor final class APIClient {
    static let shared = APIClient()
    var token: String? = "synthetic-initial"
    var payloads: [Data] = [] { didSet { token = UUID().uuidString } }
    var queries: [[String: String]] = []
    var failure: Error? { didSet { token = UUID().uuidString } }
    func get<T: Decodable>(_ path: String, query: [String: String]?) async throws -> T {
        precondition(path == "/api/v2/search")
        queries.append(query ?? [:])
        if let failure { throw failure }
        let page = Int(query?["page"] ?? "1")! - 1
        let bytes = page < payloads.count ? payloads[page] : Data(#"{"success":1,"data":{"movies":[]}}"#.utf8)
        return try JSONDecoder().decode(T.self, from: bytes)
    }
}
''' + sdk + r'''
func check(_ condition: Bool, _ name: String) {
    if !condition { fatalError("FAIL " + name) }
    print("PASS " + name)
}
func payload(_ movies: [[String: Any]]) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["success":1,"data":["movies":movies]])
}
Task { @MainActor in
    let client = APIClient.shared
    let sdk = JavDBSDK.shared
    do {
        for (code, id) in [("IPX580", "68YVQ"), ("IPX247", "KmKGv")] {
            let base = CommandLine.arguments[1] + "/production-search-" + code
            client.payloads = [try Data(contentsOf: URL(fileURLWithPath: base + "-code.json"))]
            let wrong = try await sdk.search(keyword: code, type: "code")
            check(wrong.isEmpty, code + " reproduces old false negative with real response")
            client.payloads = [try Data(contentsOf: URL(fileURLWithPath: base + "-movie.json"))]
            client.queries = []
            let resolved = try await sdk.exactMovie(code: code)
            check(resolved?.id == id, code + " production fixture exact ID")
            check(client.queries.count == 1, "page-one exact hit uses one request")
            let resolverQuery = client.queries.first!
            client.queries = []
            _ = try await sdk.exactMovie(code: code)
            check(client.queries.isEmpty, "known exact movie uses zero requests")
            _ = try await sdk.search(keyword: code, type: "movie")
            check(client.queries.first! == resolverQuery, "resolver first request equals native search including defaults")
            check(resolverQuery["movie_type"] == nil && resolverQuery["movie_filter_by"] == nil, "unfiltered native scope")
        }
        let cases: [(String, [[String:Any]], String?)] = [
            ("full width unicode dash", [["id":"a","number":"ＩＰＸ−５８０"]], "a"),
            ("title only", [["id":123,"title":"IPX580 测试影片"]], "123"),
            ("wrong prefix", [["id":"a","number":"IPX5800"]], nil),
            ("embedded title", [["id":"a","title":"合集 IPX580"]], nil),
            ("title prefix suffix", [["id":"a","title":"IPX580A title"]], nil),
            ("number authoritative", [["id":"a","number":"IPX247","title":"IPX580 title"]], nil),
            ("empty id", [["id":" ","number":"IPX580"]], nil),
            ("missing id", [["number":"IPX580"]], nil),
            ("same id dedup", [["id":"a","number":"IPX580"],["id":"a","number":"IPX-580"]], "a")
        ]
        for (name, movies, expected) in cases {
            client.payloads = [try payload(movies)]
            let result = try await sdk.exactMovie(code: "IPX580")
            check(result?.id == expected, name)
        }
        for requested in ["FC2-1234567", "FC2-PPV-1234567", "FC21234567", "FC2PPV1234567"] {
            client.payloads = [try payload([["id":"fc2-exact","number":"FC2-PPV-1234567"],
                ["id":"wrong-id","number":"FC2-PPV-1234568"],
                ["id":"non-fc2","number":"ABC-1234567"]])]
            check(try await sdk.exactMovie(code: requested)?.id == "fc2-exact", "FC2 variant resolves through production SDK: " + requested)
        }
        client.payloads = [try payload([["id":"short","number":"FC2-1234567"]])]
        check(try await sdk.exactMovie(code: "FC2-PPV-1234567")?.id == "short", "FC2 reverse variant exact")
        for invalid in ["1234567", "FC2-PPV-1234567X", "FC2-PPV-12345670", "ABC-1234567"] {
            client.payloads = [try payload([["id":"reject","number":"FC2-1234567"]])]
            check(try await sdk.exactMovie(code: invalid) == nil, "FC2 rejects nonidentity: " + invalid)
        }
        client.payloads = [try payload([["id":"a","number":"FC2-1234567"], ["id":"b","number":"FC2-PPV-1234567"]])]
        do { _ = try await sdk.exactMovie(code: "FC2-1234567"); fatalError("accepted FC2 ambiguity") }
        catch { check(error.localizedDescription.contains("多个"), "FC2 distinct IDs remain ambiguous") }
        let filler = Array(repeating: ["id":"fuzzy","number":"IPX247"], count:20)
        client.payloads = [try payload(Array(filler.prefix(19)) + [["id":"fast","number":"IPX580"]])]
        client.queries = []
        check(try await sdk.exactMovie(code:"IPX580")?.id == "fast", "full page unique exact hit")
        check(client.queries.count == 1, "full page hit does not fetch page two")
        client.payloads = [try payload(Array(filler.prefix(19)) + [["id":"first","number":"IPX580"]]), try payload([["id":"second","number":"IPX580"]])]
        client.queries = []
        do { _ = try await sdk.exactMovie(code:"IPX580", verifyAllPages:true); fatalError("accepted cross-page ambiguity") }
        catch { check(error.localizedDescription.contains("多个"), "MissAV strict mode rejects cross-page distinct exact IDs") }
        check(client.queries.count == 2, "strict mode inspects following page")
        client.payloads = [try payload(Array(filler.prefix(19)) + [["id":"first","number":"IPX580"]]), try payload([["id":"first","number":"IPX-580"]])]
        check(try await sdk.exactMovie(code:"IPX580", verifyAllPages:true)?.id == "first", "strict mode deduplicates same exact ID across pages")
        client.payloads = [try payload(filler), try payload([["id":"later","number":"IPX580"]])]
        check(try await sdk.exactMovie(code:"IPX580")?.id == "later", "exact beyond first page")
        client.payloads = [try payload([["id":"a","number":"IPX580"],["id":"b","number":"IPX580"]])]
        do { _ = try await sdk.exactMovie(code:"IPX580"); fatalError("accepted ambiguity") }
        catch { check(error.localizedDescription.contains("多个"), "distinct IDs ambiguous") }
        client.payloads = [try payload(filler), try payload(filler), try payload(filler)]
        client.queries = []
        check(try await sdk.exactMovie(code:"IPX580") == nil, "bounded no result")
        check(client.queries.count == 3, "three page bound")
        client.failure = JavDBError.httpError(401, "auth")
        do { _ = try await sdk.exactMovie(code:"IPX580"); fatalError("swallowed HTTP 401") }
        catch { check(error.localizedDescription.contains("401"), "HTTP error not no-result") }
        client.failure = URLError(.notConnectedToInternet)
        do { _ = try await sdk.exactMovie(code:"IPX580"); fatalError("swallowed network error") }
        catch { check(error is URLError, "network error not no-result") }
        print("PASS shipping SDK resolver and production Movie decoder")
        exit(0)
    } catch { fatalError("Unexpected error: \(error)") }
}
RunLoop.main.run()
'''
if shutil.which('swift'):
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / 'main.swift'
        p.write_text(swift)
        subprocess.run(['swift', str(p), str(fixtures)], check=True)
else:
    print('Swift unavailable on iSH; captured production contracts passed; actual Swift replay required on macOS CI')
