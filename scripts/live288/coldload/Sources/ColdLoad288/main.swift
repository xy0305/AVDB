// Usage: ColdLoad288 <modelsRoot> <tier[,tier]|none> <sample.wav> <expected-ja> <out.json> [nllb]
import Foundation
setvbuf(stdout, nil, _IOLBF, 0)
let a = CommandLine.arguments
let tiers = a[2] == "none" ? [] : a[2].split(separator: ",").compactMap { LiveASRTier(rawValue: String($0)) }
let sem = DispatchSemaphore(value: 0)
Task {
    let r = await ColdLoad288.run(root: URL(fileURLWithPath: a[1]), tiers: tiers, sample: ColdLoad288.wav(URL(fileURLWithPath: a[3])),
                                  expected: a[4], nllb: a.count > 6 && a[6] == "nllb")
    let d = try! JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys])
    try! d.write(to: URL(fileURLWithPath: a[5]))
    print(String(decoding: d, as: UTF8.self))
    sem.signal()
}
sem.wait()
