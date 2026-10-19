import Foundation
import CoreGraphics

/// Value-only production logic. UIKit owns one instance per active player.
struct AVDBAdjustmentPan {
    enum Axis { case horizontal, vertical }
    enum Side { case brightness, volume }
    private(set) var axis: Axis?
    private(set) var side: Side = .brightness
    private(set) var active = false
    private(set) var size = CGSize.zero
    private var last = CGPoint.zero
    private var lockPoint = CGPoint.zero
    private(set) var value: CGFloat = 0

    mutating func begin(origin: CGPoint, size: CGSize) {
        self = AVDBAdjustmentPan()
        active = size.width > 0 && size.height > 0
        self.size = size
        side = origin.x < size.width / 2 ? .brightness : .volume
    }

    /// Wait inside the state machine, never reject slow starts in shouldBegin.
    mutating func lock(translation: CGPoint, initial: CGFloat) -> Bool {
        guard active, axis == nil else { return false }
        let x = abs(translation.x), y = abs(translation.y)
        guard max(x, y) >= 6, max(x, y) >= min(x, y) * 1.15 else { return false }
        axis = x > y ? .horizontal : .vertical
        value = min(1, max(0, initial))
        last = translation
        lockPoint = translation // consume all pre-lock travel, including diagonal hesitation
        return true
    }

    mutating func update(translation: CGPoint, size: CGSize) -> CGFloat? {
        guard active, self.size == size else { end(); return nil }
        guard axis == .vertical else { return nil }
        value = min(1, max(0, value - (translation.y - last.y) / max(180, self.size.height * 0.8)))
        last = translation
        return value
    }

    mutating func horizontal(translation: CGPoint, size: CGSize) -> CGFloat? {
        guard active, self.size == size else { end(); return nil }
        guard axis == .horizontal else { return nil }
        return translation.x - lockPoint.x
    }

    mutating func end() { active = false; axis = nil; last = .zero; lockPoint = .zero }
}

/// Shared by the UIKit receiver on iPhone/iPad, including 115 playback.
enum AVDBDoubleTapPolicy {
    enum Action: Equatable { case backward, toggle, forward }
    static func action(x: CGFloat, width: CGFloat) -> Action? {
        guard width.isFinite, width > 0, x.isFinite, x >= 0, x <= width else { return nil }
        if x < width / 3 { return .backward }
        if x <= width * 2 / 3 { return .toggle }
        return .forward
    }
    static func perform(x: CGFloat, width: CGFloat, toggle: () -> Void, seek: (Double) -> Void) {
        switch action(x: x, width: width) {
        case .backward: seek(-10)
        case .toggle: toggle()
        case .forward: seek(10)
        case nil: break
        }
    }
}

/// Real stored bytes only, never inferred from duration, resolution or bitrate.
enum AVDBPlaybackFileSize {
    static func text(bytes: Int64) -> String {
        guard bytes > 0 else { return "大小未知" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.includesUnit = true
        return formatter.string(fromByteCount: bytes)
    }
}
