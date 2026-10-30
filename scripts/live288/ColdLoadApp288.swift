// Build 288 simulator cold-load host: fresh install → shipping loader on the bundled LiveModels (Core ML on the
// simulator runs on CPU) → per-model load time + first transcription, printed for the CI driver, then exits.
// A URLProtocol tripwire fails and records every URLSession.shared request (none are expected).
import SwiftUI

final class Tripwire288: URLProtocol {
    nonisolated(unsafe) static var hits: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { hits.append(request.url?.absoluteString ?? "?"); return true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}

@main
struct ColdLoadApp288: App {
    @State private var status = "cold load…"
    init() {
        URLProtocol.registerClass(Tripwire288.self)
        Task.detached {
            let root = Bundle.main.url(forResource: "LiveModels", withExtension: nil)!
            let sample = Bundle.main.url(forResource: "sample288", withExtension: "wav").flatMap(ColdLoad288.wav)
            var r = await ColdLoad288.run(root: root, tiers: [.small, .turbo], sample: sample,
                                          expected: "雨が降りそうだから、傘を持って行ってね。", nllb: true)
            r["tripwire_hits"] = Tripwire288.hits.filter { !$0.contains("huggingface.co/api/models/openai/whisper-small") }
            r["network_probe"] = "tripwire (simulator shares the host network)"
            let d = try! JSONSerialization.data(withJSONObject: r, options: [.sortedKeys])
            print("COLDLOAD288_JSON " + String(decoding: d, as: UTF8.self))
            fflush(stdout)
            exit(0)
        }
    }
    var body: some Scene { WindowGroup { Text(status) } }
}
