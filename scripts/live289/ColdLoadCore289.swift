// Build 289 simulator cold-load probe: shipping LiveRecognizerFactory (SenseVoice via the iOS SherpaOnnxC
// framework, Whisper small via WhisperKit) on the bundled LiveModels; per-model load + per-chunk latency.
import Foundation

enum ColdLoad289 {
    static func wav(_ url: URL) -> [Float]? {
        guard let d = try? Data(contentsOf: url), d.count > 44 else { return nil }
        var i = 12
        while i + 8 <= d.count {
            let tag = String(decoding: d[i ..< i + 4], as: UTF8.self)
            let n = Int(d[i + 4]) | Int(d[i + 5]) << 8 | Int(d[i + 6]) << 16 | Int(d[i + 7]) << 24
            if tag == "data" {
                return d[(i + 8) ..< min(d.count, i + 8 + n)].withUnsafeBytes { raw in raw.bindMemory(to: Int16.self).map { Float($0) / 32768 } }
            }
            i += 8 + n + (n & 1)
        }
        return nil
    }

    static func run(root: URL, tiers: [LiveASRTier], samples: [(String, [Float])]) async -> [String: Any] {
        setenv("AVDB_LIVE_MODELS", root.path, 1)
        var out: [String: Any] = ["root": root.path, "os": ProcessInfo.processInfo.operatingSystemVersionString,
                                  "sherpa_onnx": SenseVoiceRecognizer.version]
        var rows: [[String: Any]] = []
        for tier in tiers {
            var row: [String: Any] = ["tier": tier.rawValue]
            let t0 = Date()
            do {
                let r = try await LiveRecognizerFactory.load(tier, installApple: false, log: { print("[\(tier.rawValue)] \($0)") })
                row["load_s"] = Date().timeIntervalSince(t0)
                var chunks: [[String: Any]] = []
                for (ref, s) in samples {
                    let t1 = Date()
                    let text = try await r.transcribe(s, prompt: nil)
                    let ms = Date().timeIntervalSince(t1) * 1000
                    chunks.append(["ref": ref, "hyp": text, "ms": ms, "audio_s": Double(s.count) / 16000])
                }
                row["chunks"] = chunks
                row["ok"] = chunks.contains { !(($0["hyp"] as? String) ?? "").isEmpty }
            } catch { row["error"] = "\(error)"; row["ok"] = false; row["load_s"] = Date().timeIntervalSince(t0) }
            print("[\(tier.rawValue)] \(row)")
            rows.append(row)
        }
        out["recognizers"] = rows
        return out
    }
}
