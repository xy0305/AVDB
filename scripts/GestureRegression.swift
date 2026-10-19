import Foundation
import CoreGraphics

@main struct GestureRegression {
    static func main() {
        let size = CGSize(width: 844, height: 390)
        var pan = AVDBAdjustmentPan()
        pan.begin(origin: CGPoint(x: 80, y: 220), size: size)
        precondition(pan.side == .brightness)
        for y in 0...5 { precondition(!pan.lock(translation: CGPoint(x: 0, y: y), initial: 0.5)) }
        precondition(!pan.lock(translation: CGPoint(x: 12, y: -12), initial: 0.5))
        precondition(pan.lock(translation: CGPoint(x: 2, y: -20), initial: 0.5))
        precondition(pan.axis == .vertical && pan.value == 0.5)
        precondition(pan.update(translation: CGPoint(x: 2, y: -20), size: size) == 0.5)
        precondition(!pan.lock(translation: CGPoint(x: 100, y: 1), initial: 0))
        let first = pan.update(translation: CGPoint(x: 700, y: -51.2), size: size)!
        precondition(abs(first - 0.6) < 0.00001 && pan.side == .brightness)
        precondition(pan.update(translation: CGPoint(x: 700, y: -10000), size: size) == 1)
        let reverse = pan.update(translation: CGPoint(x: 700, y: -9968.8), size: size)!
        precondition(abs(reverse - 0.9) < 0.00001)
        precondition(pan.update(translation: CGPoint(x: 0, y: 10000), size: size) == 0)
        let minReverse = pan.update(translation: CGPoint(x: 0, y: 9968.8), size: size)!
        precondition(abs(minReverse - 0.1) < 0.00001)
        pan.end()
        precondition(!pan.active && pan.axis == nil)
        precondition(pan.update(translation: .zero, size: size) == nil)
        pan.begin(origin: CGPoint(x: 422, y: 100), size: size)
        precondition(pan.side == .volume)
        precondition(pan.lock(translation: CGPoint(x: 40, y: 5), initial: 0.8))
        precondition(pan.axis == .horizontal)
        precondition(pan.horizontal(translation: CGPoint(x: 40, y: 5), size: size) == 0)
        precondition(pan.horizontal(translation: CGPoint(x: 30, y: 300), size: size) == -10)
        precondition(pan.update(translation: CGPoint(x: 0, y: -200), size: size) == nil)
        pan.end() // cancelled/failed/ended share the same production reset
        pan.end() // repeated cancellation must be harmless
        pan.begin(origin: CGPoint(x: 700, y: 100), size: size)
        precondition(pan.lock(translation: CGPoint(x: 0, y: -10), initial: 0))
        precondition(pan.value == 0 && pan.side == .volume)
        precondition(pan.update(translation: CGPoint(x: 0, y: -100), size: CGSize(width: 390, height: 844)) == nil)
        precondition(!pan.active)
        var a = AVDBAdjustmentPan(), b = AVDBAdjustmentPan()
        a.begin(origin: .zero, size: size); _ = a.lock(translation: CGPoint(x: 0, y: -10), initial: 0.3)
        b.begin(origin: .zero, size: size); _ = b.lock(translation: CGPoint(x: 0, y: -10), initial: 0.3)
        let one = a.update(translation: CGPoint(x: 0, y: -100), size: size)!
        for y in stride(from: -20, through: -100, by: -10) { _ = b.update(translation: CGPoint(x: 0, y: y), size: size) }
        precondition(abs(one - b.value) < 0.00001)
        for x in [CGFloat(0), 421.9, 422, 843] {
            pan.begin(origin: CGPoint(x: x, y: 150), size: size)
            precondition(pan.side == (x < 422 ? .brightness : .volume))
        }
        pan.begin(origin: .zero, size: .zero)
        precondition(!pan.active && !pan.lock(translation: CGPoint(x: 10, y: 0), initial: 0))
        pan.begin(origin: .zero, size: size)
        precondition(pan.lock(translation: CGPoint(x: 6, y: 0), initial: 2))
        precondition(pan.value == 1)
        precondition(pan.horizontal(translation: .zero, size: .zero) == nil && !pan.active)
        // Execute the shipping policy with neutral effects: center must never seek.
        for width: CGFloat in [300, 390, 844, 1194] {
            let third = width / 3
            let cases: [(CGFloat, AVDBDoubleTapPolicy.Action)] = [
                (0, .backward), (third - 0.001, .backward), (third, .toggle),
                (width / 2, .toggle), (width * 2 / 3, .toggle),
                (width * 2 / 3 + 0.001, .forward), (width, .forward)]
            for (x, action) in cases {
                precondition(AVDBDoubleTapPolicy.action(x: x, width: width) == action)
                var toggles = 0, seeks: [Double] = []
                AVDBDoubleTapPolicy.perform(x: x, width: width,
                    toggle: { toggles += 1 }, seek: { seeks.append($0) })
                precondition(toggles == (action == .toggle ? 1 : 0))
                precondition(seeks == (action == .toggle ? [] : [action == .backward ? -10 : 10]))
            }
        }
        for (x, width): (CGFloat, CGFloat) in [(0, 0), (0, -1), (0, .nan), (0, .infinity), (-1, 300), (301, 300), (.nan, 300), (.infinity, 300)] {
            var effects = 0
            precondition(AVDBDoubleTapPolicy.action(x: x, width: width) == nil)
            AVDBDoubleTapPolicy.perform(x: x, width: width, toggle: { effects += 1 }, seek: { _ in effects += 1 })
            precondition(effects == 0)
        }
        precondition(AVDBPlaybackFileSize.text(bytes: 0) == "大小未知")
        precondition(AVDBPlaybackFileSize.text(bytes: -1) == "大小未知")
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB]
        for bytes: Int64 in [1, 999_999, 1_000_000, 12_345_678, 1_000_000_000, 12_345_678_901, Int64.max] {
            precondition(AVDBPlaybackFileSize.text(bytes: bytes) == formatter.string(fromByteCount: bytes))
        }
        print("PASS shipping double-tap policy: left/center/right, inclusive center boundaries, phone/pad widths, invalid inputs no effects, center toggle only; real byte file MB/GB and unknown size")
        print("PASS shipping AVDBAdjustmentPan: slow start/6pt/diagonal, half/axis lock, consumed lock travel, incremental event frequency, clamp/immediate reversal, zero route volume, horizontal preview, end/cancel/rebegin, rotation/invalid size")
    }
}
