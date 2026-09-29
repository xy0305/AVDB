import Foundation

struct ExternalLink: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String?
    let downloadURL: String
    let sizeMB: Double?
    let seeders: Int?
    let chinese: Bool?
    let uncensored: Bool?
    let uhd: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title
        case downloadURL = "download_url"
        case sizeMB = "size_mb"
        case seeders, chinese
        case uncensored = "uc"
        case uhd
    }

    var isED2K: Bool { downloadURL.lowercased().hasPrefix("ed2k:") }
    var isMagnet: Bool { downloadURL.lowercased().hasPrefix("magnet:") }
}

final class ExternalLibraryClient {
    static let shared = ExternalLibraryClient()
    static let baseURL = "http://163.47.40.207:18000"
    static let apiKey = "4F7mEx2o3o81RllBzruk1YjglYWZ7NjO"

    func links(for number: String) async -> [ExternalLink] {
        let keyword = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, let url = url(keyword) else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(Self.apiKey, forHTTPHeaderField: "X-API-Key")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let envelope = try JSONDecoder().decode(ExternalLinkEnvelope.self, from: data)
            return envelope.data ?? []
        } catch {
            return []
        }
    }

    private func url(_ keyword: String) -> URL? {
        var parts = URLComponents(string: Self.baseURL + "/api/v1/articles/torrents")
        parts?.queryItems = [URLQueryItem(name: "keyword", value: keyword)]
        return parts?.url
    }
}

private struct ExternalLinkEnvelope: Decodable {
    let data: [ExternalLink]?
}
