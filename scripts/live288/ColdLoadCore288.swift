// Build 288 cold-load probe — shared by the macOS CLI (run under sandbox-exec with all network denied) and the
// iOS-simulator host app. Uses the *shipping* LiveWhisperRecognizer.load / LiveBundledTokenizer / NLLB loader
// against the bundled LiveModels folder only, one tier resident at a time, and times every stage.
import CoreML
import Foundation

enum ColdLoad288 {
    static func networkProbe() async -> String {
        var req = URLRequest(url: URL(string: "https://huggingface.co/api/models/openai/whisper-small")!)
        req.timeoutInterval = 8
        do {
            let (_, r) = try await URLSession.shared.data(for: req)
            return "reachable HTTP \((r as? HTTPURLResponse)?.statusCode ?? 0)"
        } catch { return "blocked (\((error as NSError).code)) \(error.localizedDescription)" }
    }

    /// 16 kHz mono s16 WAV → Float samples (data chunk located by tag; afconvert may add FLLR/other chunks).
    static func wav(_ url: URL) -> [Float]? {
        guard let d = try? Data(contentsOf: url), d.count > 44 else { return nil }
        var i = 12
        while i + 8 <= d.count {
            let tag = String(decoding: d[i ..< i + 4], as: UTF8.self)
            let n = Int(d[i + 4]) | Int(d[i + 5]) << 8 | Int(d[i + 6]) << 16 | Int(d[i + 7]) << 24
            if tag == "data" {
                let body = d[(i + 8) ..< min(d.count, i + 8 + n)]
                return body.withUnsafeBytes { raw in raw.bindMemory(to: Int16.self).map { Float($0) / 32768 } }
            }
            i += 8 + n + (n & 1)
        }
        return nil
    }

    static func run(root: URL, tiers: [LiveASRTier], sample: [Float]?, expected: String, nllb: Bool) async -> [String: Any] {
        setenv("AVDB_LIVE_MODELS", root.path, 1)
        var out: [String: Any] = ["root": root.path, "network_probe": await networkProbe(),
                                  "machine": LiveDiagnostics.machine, "os": ProcessInfo.processInfo.operatingSystemVersionString,
                                  "ram_mb": ProcessInfo.processInfo.physicalMemory / 1_048_576]
        var rows: [[String: Any]] = []
        for tier in tiers {
            var row: [String: Any] = ["tier": tier.rawValue, "folder": tier.folder]
            let t0 = Date()
            do {
                var stages: [String] = []
                let lock = NSLock()
                let r = try await LiveWhisperRecognizer.load(tier, root: root, log: { s in
                    print("[\(tier.rawValue)] \(s)"); lock.lock(); stages.append(s); lock.unlock()
                })
                row["load_s"] = Date().timeIntervalSince(t0)
                row["stages"] = stages
                row["tokenizer"] = r.tokenizerKind
                if let sample {
                    let t1 = Date()
                    let text = try await r.transcribe(sample, prompt: nil)
                    row["first_transcribe_ms"] = Date().timeIntervalSince(t1) * 1000
                    let t2 = Date()
                    let text2 = try await r.transcribe(sample, prompt: nil)
                    row["second_transcribe_ms"] = Date().timeIntervalSince(t2) * 1000
                    row["text"] = text; row["text2"] = text2; row["expected"] = expected
                    row["ok"] = !text.trimmingCharacters(in: .whitespaces).isEmpty
                } else { row["ok"] = true }
            } catch {
                row["load_s"] = Date().timeIntervalSince(t0); row["error"] = "\(error)"; row["ok"] = false
            }
            print("[\(tier.rawValue)] \(row)")
            rows.append(row)
        }
        out["whisper"] = rows
        if nllb {
            let t0 = Date()
            do {
                let m = try NLLBCoreMLTranslator(root: root)
                let load = Date().timeIntervalSince(t0)
                let t1 = Date()
                let zh = try m.translateSync(expected)
                out["nllb"] = ["load_s": load, "translate_ms": Date().timeIntervalSince(t1) * 1000, "zh": zh, "ok": !zh.isEmpty]
            } catch { out["nllb"] = ["error": "\(error)", "ok": false] }
        }
        let hub = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("huggingface")
        out["hub_cache_created"] = FileManager.default.fileExists(atPath: hub.path)
        return out
    }
}
