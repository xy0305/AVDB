// Build 289 simulator host: fresh install → SenseVoice + Whisper small cold load on bundled models → JSON → exit.
import SwiftUI

@main
struct ColdLoadApp289: App {
    init() {
        Task.detached {
            let root = Bundle.main.url(forResource: "LiveModels", withExtension: nil)!
            var samples: [(String, [Float])] = []
            if let list = Bundle.main.url(forResource: "samples289", withExtension: "json"),
               let d = try? Data(contentsOf: list), let refs = try? JSONSerialization.jsonObject(with: d) as? [[String: String]] {
                for r in refs {
                    if let f = r["file"], let ref = r["ja"],
                       let u = Bundle.main.url(forResource: (f as NSString).deletingPathExtension, withExtension: "wav"),
                       let s = ColdLoad289.wav(u) { samples.append((ref, s)) }
                }
            }
            let r = await ColdLoad289.run(root: root, tiers: [.senseVoice, .small], samples: samples)
            let d = try! JSONSerialization.data(withJSONObject: r, options: [.sortedKeys])
            print("COLDLOAD289_JSON " + String(decoding: d, as: UTF8.self))
            fflush(stdout)
            exit(0)
        }
    }
    var body: some Scene { WindowGroup { Text("cold load 289…") } }
}
