import Foundation

/// Build 285: pure (Foundation-only) policy for the on-device AI cover enhancer, shared by the
/// app, the Linux/macOS regression and the screenshot host.

/// 「AI 增强」 setting. 自动 = low-res covers are enhanced automatically (guarded by low-power /
/// battery only — never by thermal state, build 289); 仅手动 = only via the button; 关 = never (button hidden).
enum AICoverEnhanceMode: String, CaseIterable, Identifiable, Sendable {
    case auto, manual, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "自动"
        case .manual: return "仅手动"
        case .off: return "关"
        }
    }
    static let defaultsKey = "ai.cover.enhance.mode"
    static var current: AICoverEnhanceMode {
        get { AICoverEnhanceMode(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}

/// Which covers may be enhanced. Native HQ covers (DMM ps 1032×1468, Amazon, MILK 745×1081, DUGA
/// 474×674 is still low → eligible) are never touched once their NATIVE height reaches `hqHeight`.
/// Eligible: 800 px jacket crops (378×538), MGS pf_e 422×600, JavDB 376×538 fallbacks.
enum AICoverEnhancePolicy {
    static let hqHeight = 1000
    static let minHeight = 240
    static func eligible(nativeWidth w: Int, nativeHeight h: Int) -> Bool {
        guard w > 0, h > 0 else { return false }
        return h < hqHeight && h >= minHeight && w <= 1000 && w >= 120
    }
    static func eligible(source: String, nativeWidth w: Int, nativeHeight h: Int) -> Bool {
        guard !source.isEmpty, !source.hasPrefix("fixture://neutral") else { return false }
        return eligible(nativeWidth: w, nativeHeight: h)
    }
}

/// Battery guard (build 289: NO thermal gating — AI image enhancement is always allowed regardless of
/// thermal state, in both 自动 and 手动; thermal throttling applies only to live subtitles).
/// Automatic runs skip Low Power Mode and < 20 % battery (unless charging); a manual tap always runs.
enum AICoverEnhanceGuard {
    enum Verdict: Equatable { case ok, lowPower, lowBattery }
    /// battery < 0 = unknown.
    static func verdict(manual: Bool, lowPower: Bool, battery: Float, charging: Bool) -> Verdict {
        if manual { return .ok }
        if lowPower { return .lowPower }
        if battery >= 0, battery < 0.2, !charging { return .lowBattery }
        return .ok
    }
    static func message(_ v: Verdict) -> String? {
        switch v {
        case .ok: return nil
        case .lowPower: return "低电量模式下不自动增强"
        case .lowBattery: return "电量低于 20%，不自动增强"
        }
    }
}

/// Overlapping fixed-size tiles: the Core ML model has one static input shape (ANE friendly);
/// large covers are split, small ones edge-padded. Seams are hidden by linear feathering.
struct AICoverTilePlan: Equatable {
    let origins: [Int]
    static func make(length: Int, tile: Int, overlap: Int) -> AICoverTilePlan {
        guard length > tile else { return .init(origins: [0]) }
        let stride = max(1, tile - 2 * overlap)
        var values: [Int] = []
        var p = 0
        while p + tile < length { values.append(p); p += stride }
        values.append(length - tile)
        return .init(origins: values)
    }
}

/// Output size policy: native ×scale, but never taller than `maxOutputHeight` (display raster cap).
enum AICoverSRSize {
    static let maxOutputHeight = 2160
    static func output(width: Int, height: Int, scale: Int) -> (width: Int, height: Int) {
        let h = min(height * scale, maxOutputHeight)
        let w = Int((Double(width) * Double(h) / Double(height)).rounded())
        return (max(1, w), max(1, h))
    }
}
