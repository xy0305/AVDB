import Foundation

/// Verified read-only ranking queries against https://api.video.dmm.co.jp/graphql
/// (probed 2026-10-27). Introspection is disabled server-side; only independently
/// confirmed ContentRankingPage / ActressRankingPage field shapes are used.
/// Prefer WKWebView-hydrated official HTML when available; GraphQL is secondary.
enum DMMRankingGraphQL {
    static let endpoint = URL(string: "https://api.video.dmm.co.jp/graphql")!

    private static let contentQuery = """
    query AVDBContentRanking($limit: Int!, $offset: Int!, $filter: PPVContentRankingFilterInput) {
      ppvContentRanking(limit: $limit, offset: $offset, filter: $filter) {
        __typename
        items {
          id
          rank
          content {
            id
            title
          }
        }
      }
    }
    """

    private static let actressQuery = """
    query AVDBActressRanking($limit: Int!, $offset: Int, $filter: PPVActressRankingFilterInput!) {
      ppvActressRanking(limit: $limit, offset: $offset, filter: $filter) {
        __typename
        items {
          id
          rank
          actress {
            id
            name
          }
        }
      }
    }
    """

    /// Official OneOf filters observed in video.dmm.co.jp ranking JS.
    static func filter(for kind: DMMRankingKind) -> [String: Any] {
        switch kind {
        case .daily: return ["daily": ["floor": "AV"]]
        case .weekly: return ["weekly": ["floor": "AV"]]
        case .monthly: return ["monthly": ["floor": "AV"]]
        case .actress: return ["monthly": ["floor": "AV"]]
        }
    }

    static func payload(for kind: DMMRankingKind) throws -> Data {
        let body: [String: Any]
        if kind.isActress {
            body = [
                "query": actressQuery,
                "operationName": "AVDBActressRanking",
                "variables": [
                    "limit": kind.expectedCount,
                    "offset": 0,
                    "filter": filter(for: kind)
                ]
            ]
        } else {
            body = [
                "query": contentQuery,
                "operationName": "AVDBContentRanking",
                "variables": [
                    "limit": kind.expectedCount,
                    "offset": 0,
                    "filter": filter(for: kind)
                ]
            ]
        }
        return try JSONSerialization.data(withJSONObject: body)
    }

    static func board(data: Data, kind: DMMRankingKind, observedAt: Date) throws -> DMMRankingBoard {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DMMRankingError.malformed
        }
        if let errors = root["errors"] as? [Any], !errors.isEmpty {
            throw DMMRankingError.accessGate
        }
        guard let dataObj = root["data"] as? [String: Any] else { throw DMMRankingError.accessGate }
        if kind.isActress {
            return try actressBoard(dataObj: dataObj, kind: kind, observedAt: observedAt)
        }
        return try contentBoard(dataObj: dataObj, kind: kind, observedAt: observedAt)
    }

    private static func contentBoard(dataObj: [String: Any], kind: DMMRankingKind, observedAt: Date) throws -> DMMRankingBoard {
        guard let ranking = dataObj["ppvContentRanking"] as? [String: Any],
              let items = ranking["items"] as? [[String: Any]], !items.isEmpty else {
            throw DMMRankingError.accessGate
        }
        var rows: [DMMContentRow] = []
        for item in items {
            guard let rank = item["rank"] as? Int,
                  let content = item["content"] as? [String: Any],
                  let cid = (content["id"] as? String) ?? (item["id"] as? String),
                  cid.range(of: "^[a-z0-9_]+$", options: .regularExpression) != nil, cid.count <= 100,
                  let title = content["title"] as? String, !title.isEmpty else {
                throw DMMRankingError.malformed
            }
            let url = URL(string: "https://video.dmm.co.jp/av/content/?id=\(cid)")!
            rows.append(DMMContentRow(rank: rank, cid: cid, sourceTitle: title, sourceURL: url, kind: kind))
        }
        rows.sort { $0.rank < $1.rank }
        guard rows.map(\.rank) == Array(1...kind.expectedCount) else { throw DMMRankingError.incomplete }
        return DMMRankingBoard(kind: kind, sourceURL: kind.sourceURL, observedAt: observedAt, contentRows: rows, actressRows: [])
    }

    private static func stringID(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let n = value as? Int { return String(n) }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private static func actressBoard(dataObj: [String: Any], kind: DMMRankingKind, observedAt: Date) throws -> DMMRankingBoard {
        guard let ranking = dataObj["ppvActressRanking"] as? [String: Any],
              let items = ranking["items"] as? [[String: Any]], !items.isEmpty else {
            throw DMMRankingError.accessGate
        }
        var rows: [DMMActressRow] = []
        var seen = Set<String>()
        for item in items {
            guard let rank = item["rank"] as? Int,
                  let actress = item["actress"] as? [String: Any],
                  let actressID = stringID(actress["id"]) ?? stringID(item["id"]),
                  actressID.range(of: "^[0-9]+$", options: .regularExpression) != nil, actressID.count <= 20,
                  let name = actress["name"] as? String, !name.isEmpty else {
                throw DMMRankingError.malformed
            }
            if !seen.insert(actressID).inserted { throw DMMRankingError.conflictingIdentity }
            let url = URL(string: "https://video.dmm.co.jp/av/list/?actress=\(actressID)")!
            rows.append(DMMActressRow(rank: rank, actressID: actressID, name: name, sourceURL: url))
        }
        rows.sort { $0.rank < $1.rank }
        guard rows.map(\.rank) == Array(1...kind.expectedCount) else { throw DMMRankingError.incomplete }
        return DMMRankingBoard(kind: kind, sourceURL: kind.sourceURL, observedAt: observedAt, contentRows: [], actressRows: rows)
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    /// Cookie-free ephemeral POST. Host is fixed to the verified GraphQL endpoint.
    static func fetch(_ kind: DMMRankingKind) async throws -> DMMRankingBoard {
        let body = try payload(for: kind)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 25
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://video.dmm.co.jp", forHTTPHeaderField: "Origin")
        request.setValue(kind.sourceURL.absoluteString, forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url == endpoint, data.count <= 8_000_000 else {
            throw DMMRankingError.accessGate
        }
        return try board(data: data, kind: kind, observedAt: Date())
    }

    /// Ranking summary type lacks makerContentId; full ppvContent exposes official メーカー品番.
    static func makerCodes(cids: [String]) async throws -> [String: String] {
        var out: [String: String] = [:]
        let unique = cids.filter { $0.range(of: "^[a-z0-9_]+$", options: .regularExpression) != nil && $0.count <= 100 }
        var index = 0
        while index < unique.count {
            let end = min(index + 10, unique.count)
            let chunk = Array(unique[index..<end])
            index = end
            let body = try makerCodePayload(cids: chunk)
            let data = try await post(body: body, referer: URL(string: "https://video.dmm.co.jp/av/ranking/?term=weekly")!)
            let part = try makerCodes(data: data, expectedCIDs: chunk)
            for (cid, code) in part { out[cid] = code }
        }
        return out
    }

    static func makerCodePayload(cids: [String]) throws -> Data {
        var selections: [String] = []
        var variables: [String: Any] = [:]
        var defs: [String] = []
        for (i, cid) in cids.enumerated() {
            defs.append("$id\(i): ID!")
            selections.append("c\(i): ppvContent(id: $id\(i)) { id makerContentId }")
            variables["id\(i)"] = cid
        }
        let query = "query AVDBMakerCodes(\(defs.joined(separator: ", "))) { \(selections.joined(separator: " ")) }"
        return try JSONSerialization.data(withJSONObject: [
            "query": query,
            "operationName": "AVDBMakerCodes",
            "variables": variables
        ])
    }

    static func makerCodes(data: Data, expectedCIDs: [String]) throws -> [String: String] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DMMRankingError.malformed }
        if let errors = root["errors"] as? [Any], !errors.isEmpty { throw DMMRankingError.accessGate }
        guard let dataObj = root["data"] as? [String: Any] else { throw DMMRankingError.accessGate }
        var out: [String: String] = [:]
        for (i, cid) in expectedCIDs.enumerated() {
            guard let record = dataObj["c\(i)"] as? [String: Any],
                  let id = record["id"] as? String, id == cid,
                  let raw = record["makerContentId"] as? String,
                  let code = DMMRankingCore.manufacturerCode(raw) else { continue }
            out[cid] = code
        }
        return out
    }

    private static func post(body: Data, referer: URL) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 25
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://video.dmm.co.jp", forHTTPHeaderField: "Origin")
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url == endpoint, data.count <= 8_000_000 else {
            throw DMMRankingError.accessGate
        }
        return data
    }
}
