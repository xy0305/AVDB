//
//  ReviewsSheetHost.swift
//  AVDB
//
//  评论面板用 UIKit 改高度：拖动只裁剪已排好的内容，不驱动 SwiftUI 回流。
//

import SwiftUI
import UIKit

struct ReviewsSheetHost: UIViewControllerRepresentable {
    let movieID: String
    let total: Int
    @ObservedObject var vm: ReviewsListViewModel

    func makeUIViewController(context: Context) -> ReviewsSheetController {
        let vc = ReviewsSheetController()
        vc.configure(movieID: movieID, total: total, vm: vm)
        return vc
    }

    func updateUIViewController(_ vc: ReviewsSheetController, context: Context) {
        vc.configure(movieID: movieID, total: total, vm: vm)
    }
}

final class ReviewsSheetController: UIViewController, UIGestureRecognizerDelegate {
    private let collapsedHeight: CGFloat = 76
    private let sheet = UIView()
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let hairline = UIView()
    private var host: UIHostingController<ReviewsPanelContent>!
    private var heightConstraint: NSLayoutConstraint!
    private var hostHeightConstraint: NSLayoutConstraint!
    private var dragStartHeight: CGFloat = 76
    private var expanded = false

    private var movieID = ""
    private var total = 0
    private weak var vm: ReviewsListViewModel?

    func configure(movieID: String, total: Int, vm: ReviewsListViewModel) {
        let movieChanged = self.movieID != movieID
        self.movieID = movieID
        self.total = total
        self.vm = vm
        if isViewLoaded {
            refreshRoot(force: movieChanged)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        sheet.translatesAutoresizingMaskIntoConstraints = false
        sheet.clipsToBounds = true
        sheet.layer.cornerRadius = 28
        sheet.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        sheet.layer.cornerCurve = .continuous
        view.addSubview(sheet)

        blur.translatesAutoresizingMaskIntoConstraints = false
        sheet.addSubview(blur)

        hairline.translatesAutoresizingMaskIntoConstraints = false
        hairline.backgroundColor = UIColor.white.withAlphaComponent(0.28)
        hairline.isUserInteractionEnabled = false
        sheet.addSubview(hairline)

        let content = ReviewsPanelContent(
            movieID: movieID,
            total: total,
            vm: vm ?? ReviewsListViewModel(),
            isExpanded: expanded
        )
        let hosted = UIHostingController(rootView: content)
        hosted.view.backgroundColor = .clear
        hosted.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(hosted)
        sheet.addSubview(hosted.view)
        hosted.didMove(toParent: self)
        host = hosted

        heightConstraint = sheet.heightAnchor.constraint(equalToConstant: collapsedHeight)
        hostHeightConstraint = host.view.heightAnchor.constraint(equalToConstant: 400)

        NSLayoutConstraint.activate([
            sheet.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sheet.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sheet.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            heightConstraint,

            blur.topAnchor.constraint(equalTo: sheet.topAnchor),
            blur.leadingAnchor.constraint(equalTo: sheet.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: sheet.trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: sheet.bottomAnchor),

            hairline.topAnchor.constraint(equalTo: sheet.topAnchor),
            hairline.leadingAnchor.constraint(equalTo: sheet.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: sheet.trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 0.6),

            host.view.topAnchor.constraint(equalTo: sheet.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: sheet.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: sheet.trailingAnchor),
            hostHeightConstraint
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.delegate = self
        sheet.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.delegate = self
        sheet.addGestureRecognizer(tap)
        tap.require(toFail: pan)

        refreshRoot(force: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let maxH = maximumHeight
        if abs(hostHeightConstraint.constant - maxH) > 0.5 {
            hostHeightConstraint.constant = maxH
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let local = sheet.convert(point, from: view)
        guard sheet.point(inside: local, with: event) else { return nil }
        return super.hitTest(point, with: event)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let loc = gestureRecognizer.location(in: sheet)
        guard loc.y <= collapsedHeight else { return false }
        if let pan = gestureRecognizer as? UIPanGestureRecognizer {
            let v = pan.velocity(in: sheet)
            return abs(v.y) > abs(v.x)
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    @objc private func handleTap() {
        snap(to: expanded ? collapsedHeight : mediumHeight, expand: !expanded)
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        let dy = pan.translation(in: view).y
        switch pan.state {
        case .began:
            dragStartHeight = heightConstraint.constant
        case .changed:
            let next = min(maximumHeight, max(collapsedHeight, dragStartHeight - dy))
            heightConstraint.constant = next
        case .ended, .cancelled:
            let velocity = pan.velocity(in: view).y
            let predicted = dragStartHeight - dy - velocity * 0.18
            snap(to: predicted, velocityY: velocity)
        default:
            break
        }
    }

    private var maximumHeight: CGFloat {
        max(300, view.bounds.height - 8)
    }

    private var mediumHeight: CGFloat {
        collapsedHeight + (maximumHeight - collapsedHeight) * 0.55
    }

    private func snap(to predicted: CGFloat, velocityY: CGFloat = 0, expand: Bool? = nil) {
        let span = max(1, maximumHeight - collapsedHeight)
        let nextExpanded: Bool
        let nextHeight: CGFloat
        if let expand {
            nextExpanded = expand
            nextHeight = expand ? mediumHeight : collapsedHeight
        } else if velocityY < -900 {
            nextExpanded = true
            nextHeight = maximumHeight
        } else if velocityY > 900 {
            nextExpanded = false
            nextHeight = collapsedHeight
        } else if predicted < collapsedHeight + span * 0.28 {
            nextExpanded = false
            nextHeight = collapsedHeight
        } else if predicted < collapsedHeight + span * 0.72 {
            nextExpanded = true
            nextHeight = mediumHeight
        } else {
            nextExpanded = true
            nextHeight = maximumHeight
        }
        expanded = nextExpanded
        heightConstraint.constant = nextHeight
        UIView.animate(
            withDuration: 0.32,
            delay: 0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: min(2.2, abs(velocityY) / 900),
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.view.layoutIfNeeded()
        }
        refreshRoot(force: false)
    }

    private func refreshRoot(force: Bool) {
        guard let vm else { return }
        host.rootView = ReviewsPanelContent(
            movieID: movieID,
            total: total,
            vm: vm,
            isExpanded: expanded
        )
        if force {
            host.view.setNeedsLayout()
        }
    }
}
