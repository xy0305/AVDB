import AVFoundation
import Foundation

/// Engine-reported video dimensions, never a viewport or a filename-derived guess.
struct PlaybackVideoMetrics: Equatable {
    enum Evidence: String { case presentation, track }
    let width: Int
    let height: Int
    let evidence: Evidence

    init?(width: Double, height: Double, evidence: Evidence) {
        guard width.isFinite, height.isFinite, width >= 1, height >= 1,
              width < 100_000, height < 100_000 else { return nil }
        self.width = Int(width.rounded())
        self.height = Int(height.rounded())
        self.evidence = evidence
    }
    var grade: String {
        let long = max(width, height), short = min(width, height)
        // Non-standard/cropped heights retain their measured p value, not a lower bucket.
        if short == 4320 && long >= 7680 { return "8K" }
        if short == 2160 && long >= 3840 { return "4K" }
        if short == 1440 && long >= 2560 { return "1440p" }
        if short == 1080 && long >= 1920 { return "1080p" }
        if short == 720 && long >= 1280 { return "720p" }
        return "\(short)p"
    }
    var detail: String {
        "\(evidence == .presentation ? "当前视频分辨率" : "轨道分辨率")：\(width)×\(height) · \(grade)"
    }
}

/// A single source lifetime. URL and generation jointly reject delayed callbacks,
/// including a retry that reuses the exact same signed URL.
struct PlaybackMetricsState {
    private(set) var generation = 0
    private(set) var sourceURL: URL?
    private(set) var metrics: PlaybackVideoMetrics?
    private(set) var settled = false
    mutating func reset(url: URL?) {
        generation += 1
        sourceURL = url
        metrics = nil
        settled = false
    }
    @discardableResult
    mutating func receive(_ value: PlaybackVideoMetrics?, settled: Bool, url: URL, generation: Int) -> Bool {
        guard generation == self.generation, url == sourceURL else { return false }
        guard metrics != value || self.settled != settled else { return false }
        metrics = value
        self.settled = settled
        return true
    }
    var detail: String { metrics?.detail ?? (settled ? "当前视频分辨率：未知" : "当前视频分辨率：检测中") }
    func label(original: Bool) -> String {
        let source = original ? "原画" : "HLS"
        guard let metrics else { return source + "·" + (settled ? "未知" : "检测中") }
        return source + "·" + metrics.grade + (metrics.evidence == .track ? "(轨道)" : "")
    }
    static func isCurrent(name: String, original: Bool, activeName: String?, activeOriginal: Bool?) -> Bool {
        name == activeName && original == activeOriginal
    }
}

/// Displayed selection is the session hint, not a promise that adaptation never drops.
/// This file stays independently compilable for the 115 metrics regression.
enum OnlinePlaybackQualityStatus {
    static func display(mode: String, label: String, cap: CGSize?, observed: CGSize) -> String {
        let selected = mode == "specific" ? "手动·" + label : (mode == "automatic" ? "自动" : label)
        var text = "画质 " + selected
        if observed.width > 1, observed.height > 1 {
            let grade = PlaybackVideoMetrics(width: observed.width, height: observed.height, evidence: .presentation)?.grade ?? "\(Int(min(observed.width, observed.height)))p"
            text += " · 当前 " + grade
            if (mode == "highest" || mode == "specific"), let cap, cap.height > 1,
               min(observed.width, observed.height) + 8 < min(cap.width, cap.height) {
                text += "（网络降档）"
            }
        }
        return text
    }
}

/// Applies a finite session hint to one AVPlayerItem. Zero peak/size clears the hint.
enum OnlineQualitySession {
    struct Applied: Equatable {
        var generation: Int
        var peakBitRate: Double
        var maximumResolution: CGSize
        var label: String
    }
    static func apply(peakBitRate: Double?, maximumResolution: CGSize?, label: String, generation: Int, to item: AVPlayerItem) -> Applied {
        let peak = peakBitRate ?? 0
        let size = maximumResolution ?? .zero
        precondition(peak.isFinite && peak >= 0 && peak < 1_000_000_000)
        precondition(size.width.isFinite && size.height.isFinite && size.width >= 0 && size.height >= 0)
        if item.preferredPeakBitRate != peak { item.preferredPeakBitRate = peak }
        if item.preferredMaximumResolution != size { item.preferredMaximumResolution = size }
        return Applied(generation: generation, peakBitRate: item.preferredPeakBitRate, maximumResolution: item.preferredMaximumResolution, label: label)
    }
}
