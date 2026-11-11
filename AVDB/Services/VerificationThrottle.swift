import Foundation

// Build 337: one shared throttle for every AUTOMATIC JavDB verification —
// the external ranking sources (JAV Ranking, DMM, MissAV, JAVLibrary,
// 中指通） matching their rows against JavDB in the background. Automatic
// verifications run one at a time, start at most 20 per rolling minute,
// and pause a random 1.5–3.5 s after each one finishes, so a cold scroll
// through a board advances at a human pace instead of a machine burst.
// Checks the user initiates personally (a row's 核对 button, the MissAV
// verification sheet, an interactive retry) never pass through here.
@MainActor
enum VerificationThrottle {
    static let perMinute = 20
    private static var active = false
    private static var window: [Date] = []
    private static var notBefore = Date.distantPast

    /// Waits until an automatic verification may start. Returns false when
    /// the task is cancelled or the optional deadline passes first.
    static func acquire(deadline: Date? = nil) async -> Bool {
        while true {
            if Task.isCancelled { return false }
            let now = Date()
            window = window.filter { now.timeIntervalSince($0) < 60 }
            if !active, window.count < perMinute, now >= notBefore {
                active = true
                window.append(now)
                return true
            }
            if let deadline, now > deadline { return false }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    static func release() {
        active = false
        notBefore = Date().addingTimeInterval(Double.random(in: 1.5...3.5))
    }
}
