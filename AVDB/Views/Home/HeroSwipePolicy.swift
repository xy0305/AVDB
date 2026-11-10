import SwiftUI
import UIKit

/// Build 328 vertical+horizontal hero swipe arbitrator.
/// Pure policy: lock mode at touch-down, lock axis at 14 pt, at most one
/// title change per gesture, passthrough to the parent ScrollView (and the
/// system refreshable) on the first-item-down / last-item-up edges.
/// The UIKit recognizer uses this so the pager and the ScrollView never move together.
enum HeroSwipePolicy {
    static let axisLockDistance: CGFloat = 14
    static let axisRatio: CGFloat = 1.5
    static let verticalPageTranslation: CGFloat = 56
    static let verticalFlickTranslation: CGFloat = 24
    static let verticalFlickVelocity: CGFloat = 500
    /// Existing horizontal thresholds (kept unless the axis lock requires alignment).
    static let horizontalPageTranslation: CGFloat = 60
    static let horizontalPredictedTranslation: CGFloat = 140
    static let horizontalRubber: CGFloat = 0.85
    static let pageSpringResponse: Double = 0.38
    static let pageSpringDamping: Double = 0.88

    enum Mode: Equatable {
        /// scroll.offset > 1 pt at touch-down: the entire gesture belongs to the ScrollView.
        case scrollView
        /// offset ≤ 1 pt at touch-down: hero arbitration.
        case hero
    }

    enum Axis: Equatable {
        case undecided
        case horizontal
        case vertical
    }

    enum Outcome: Equatable {
        case none
        case trackHorizontal(CGFloat)
        case pageHorizontal(delta: Int)
        case springHorizontal
        case trackVertical(CGFloat)
        case pageVertical(delta: Int)
        case springVertical
        /// Fail the hero recognizer so the parent ScrollView / refreshable can run.
        case passthrough
        /// After a page change, ignore the rest of this gesture.
        case locked
    }

    struct Session: Equatable {
        var mode: Mode
        var axis: Axis = .undecided
        var consumedPageChange = false
        var index: Int
        var count: Int

        static func begin(scrollOffset: CGFloat, index: Int, count: Int) -> Session {
            Session(mode: scrollOffset > 1 ? .scrollView : .hero, index: index, count: count)
        }

        mutating func lockAxis(dx: CGFloat, dy: CGFloat) {
            guard axis == .undecided else { return }
            guard hypot(dx, dy) >= HeroSwipePolicy.axisLockDistance else { return }
            if abs(dy) >= HeroSwipePolicy.axisRatio * abs(dx) {
                axis = .vertical
            } else if abs(dx) >= HeroSwipePolicy.axisRatio * abs(dy) {
                axis = .horizontal
            }
        }

        /// Vertical-up on the last item, or vertical-down on the first item, must
        /// not be captured by the hero (scroll / system refreshable instead).
        func isVerticalPassthrough(dy: CGFloat) -> Bool {
            guard axis == .vertical, count >= 1 else { return false }
            if dy < 0, index >= count - 1 { return true }
            if dy > 0, index <= 0 { return true }
            return false
        }

        mutating func changed(dx: CGFloat, dy: CGFloat) -> Outcome {
            if mode == .scrollView { return .passthrough }
            if consumedPageChange { return .locked }
            lockAxis(dx: dx, dy: dy)
            switch axis {
            case .undecided:
                return .none
            case .horizontal:
                return .trackHorizontal(dx * HeroSwipePolicy.horizontalRubber)
            case .vertical:
                if isVerticalPassthrough(dy: dy) { return .passthrough }
                return .trackVertical(dy)
            }
        }

        mutating func ended(dx: CGFloat, dy: CGFloat, velocityX: CGFloat, velocityY: CGFloat,
                            predictedX: CGFloat) -> Outcome {
            if mode == .scrollView { return .passthrough }
            if consumedPageChange { return .locked }
            lockAxis(dx: dx, dy: dy)
            switch axis {
            case .undecided:
                return .none
            case .horizontal:
                if abs(dx) > HeroSwipePolicy.horizontalPageTranslation
                    || abs(predictedX) > HeroSwipePolicy.horizontalPredictedTranslation {
                    consumedPageChange = true
                    return .pageHorizontal(delta: dx < 0 ? 1 : -1)
                }
                return .springHorizontal
            case .vertical:
                if isVerticalPassthrough(dy: dy) { return .passthrough }
                let translation = abs(dy)
                let flick = translation >= HeroSwipePolicy.verticalFlickTranslation
                    && abs(velocityY) >= HeroSwipePolicy.verticalFlickVelocity
                if translation >= HeroSwipePolicy.verticalPageTranslation || flick {
                    consumedPageChange = true
                    return .pageVertical(delta: dy < 0 ? 1 : -1)
                }
                return .springVertical
            }
        }
    }
}

/// UIKit pan on the hero. The parent UIScrollView's pan is required to wait
/// for this recognizer to fail (passthrough / scroll-lock / first-down / last-up).
/// When this recognizer begins, the ScrollView must not run.
struct HeroSwipeOverlay: UIViewRepresentable {
    var scrollOffset: () -> CGFloat
    var index: () -> Int
    var count: () -> Int
    var onTrackHorizontal: (CGFloat) -> Void
    var onTrackVertical: (CGFloat) -> Void
    var onPageHorizontal: (Int) -> Void
    var onPageVertical: (Int) -> Void
    var onSpringHorizontal: () -> Void
    var onSpringVertical: () -> Void
    var onTouch: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isOpaque = false
        let recognizer = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handle(_:)))
        recognizer.delegate = context.coordinator
        recognizer.cancelsTouchesInView = false
        recognizer.maximumNumberOfTouches = 1
        view.addGestureRecognizer(recognizer)
        context.coordinator.recognizer = recognizer
        context.coordinator.parent = self
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: HeroSwipeOverlay?
        weak var recognizer: UIPanGestureRecognizer?
        var session: HeroSwipePolicy.Session?

        @objc func handle(_ sender: UIPanGestureRecognizer) {
            guard let parent, let view = sender.view else { return }
            let translation = sender.translation(in: view)
            let velocity = sender.velocity(in: view)
            switch sender.state {
            case .began:
                parent.onTouch(true)
                var started = HeroSwipePolicy.Session.begin(
                    scrollOffset: parent.scrollOffset(),
                    index: parent.index(),
                    count: max(parent.count(), 0)
                )
                if started.mode == .scrollView {
                    session = started
                    sender.state = .failed
                    parent.onTouch(false)
                    return
                }
                let outcome = started.changed(dx: translation.x, dy: translation.y)
                session = started
                if outcome == .passthrough {
                    sender.state = .failed
                    parent.onTouch(false)
                    return
                }
                apply(outcome)
            case .changed:
                guard var session else { return }
                let outcome = session.changed(dx: translation.x, dy: translation.y)
                self.session = session
                if outcome == .passthrough {
                    sender.state = .failed
                    parent.onTouch(false)
                    return
                }
                apply(outcome)
            case .ended:
                guard var session else {
                    parent.onTouch(false)
                    return
                }
                let predictedX = translation.x + velocity.x * 0.25
                let outcome = session.ended(dx: translation.x, dy: translation.y,
                                            velocityX: velocity.x, velocityY: velocity.y,
                                            predictedX: predictedX)
                self.session = session
                apply(outcome)
                self.session = nil
                parent.onTouch(false)
            case .cancelled, .failed:
                if let session, !session.consumedPageChange {
                    if session.axis == .horizontal { parent.onSpringHorizontal() }
                    if session.axis == .vertical { parent.onSpringVertical() }
                }
                self.session = nil
                parent.onTouch(false)
            default:
                break
            }
        }

        private func apply(_ outcome: HeroSwipePolicy.Outcome) {
            guard let parent else { return }
            switch outcome {
            case .none, .passthrough, .locked:
                break
            case .trackHorizontal(let x):
                parent.onTrackHorizontal(x)
            case .trackVertical(let y):
                parent.onTrackVertical(y)
            case .pageHorizontal(let delta):
                parent.onPageHorizontal(delta)
            case .pageVertical(let delta):
                parent.onPageVertical(delta)
            case .springHorizontal:
                parent.onSpringHorizontal()
            case .springVertical:
                parent.onSpringVertical()
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // Never let the hero pager and the page ScrollView move at once.
            false
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            // The parent ScrollView may begin only after the hero recognizer fails.
            other is UIPanGestureRecognizer && other.view is UIScrollView
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
            false
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var current: UIView? = touch.view
            while let view = current {
                if view is UIControl { return false }
                current = view.superview
            }
            return true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // If the finger landed while the page was already scrolled, never begin.
            // (touches may not have run .began against our session yet on some paths.)
            guard let parent else { return true }
            if parent.scrollOffset() > 1 { return false }
            return parent.count() > 1
        }
    }
}
