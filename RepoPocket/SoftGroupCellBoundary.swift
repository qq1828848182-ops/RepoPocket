import SwiftUI
import UIKit

/// Keep the outer corner cutouts at the native row's fixed layout position.
/// Swipe controls are siblings of the moving cell; clipping that cell alone
/// cannot give the controls and the background the same outer boundary.
struct SoftGroupCellBoundary: UIViewRepresentable {
    let top: Bool
    let bottom: Bool
    func makeUIView(context: Context) -> BoundaryView { BoundaryView() }
    func updateUIView(_ view: BoundaryView, context: Context) { view.configure(top: top, bottom: bottom) }
    static func dismantleUIView(_ view: BoundaryView, coordinator: ()) { view.releaseCell() }

    final class BoundaryView: UIView {
        private let cover = CAShapeLayer()
        private var top = false
        private var bottom = false
        private var enabled = true
        override init(frame: CGRect) {
            super.init(frame: frame); isUserInteractionEnabled = false; backgroundColor = .clear
            cover.fillRule = .evenOdd; cover.zPosition = 10_000; cover.masksToBounds = true
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        func configure(top: Bool, bottom: Bool) {
            self.top = top; self.bottom = bottom; enabled = true
            attach()
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }
        override func didMoveToSuperview() { super.didMoveToSuperview(); attach() }
        override func didMoveToWindow() { super.didMoveToWindow(); attach() }
        override func layoutSubviews() { super.layoutSubviews(); attach() }
        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection); attach()
        }
        private func attach() {
            guard enabled else { return }
            guard top || bottom else { cover.removeFromSuperlayer(); return }
            var ancestor = superview
            var cell: UIView?
            while let candidate = ancestor {
                if candidate is UICollectionViewCell || candidate is UITableViewCell { cell = candidate }
                if let list = candidate as? UICollectionView, let cell = cell as? UICollectionViewCell,
                   let index = list.indexPath(for: cell), let layout = list.layoutAttributesForItem(at: index) {
                    paint(in: list, frame: layout.frame); return
                }
                if let list = candidate as? UITableView, let cell = cell as? UITableViewCell,
                   let index = list.indexPath(for: cell) {
                    paint(in: list, frame: list.rectForRow(at: index)); return
                }
                ancestor = candidate.superview
            }
            cover.removeFromSuperlayer()
        }
        private func paint(in list: UIScrollView, frame: CGRect) {
            guard frame.width > 0, frame.height > 0 else { return }
            let rect = CGRect(origin: .zero, size: frame.size)
            let radius: CGFloat = 22
            let extended = CGRect(x: 0, y: top ? 0 : -radius, width: rect.width,
                                  height: rect.height + (top ? 0 : radius) + (bottom ? 0 : radius))
            let cutouts = CGMutablePath()
            cutouts.addRect(extended)
            cutouts.addPath(SoftGroupShape(top: top, bottom: bottom).path(in: rect).cgPath)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            if cover.superlayer !== list.layer { cover.removeFromSuperlayer(); list.layer.addSublayer(cover) }
            cover.frame = frame; cover.path = cutouts
            cover.fillColor = UIColor.systemGroupedBackground.resolvedColor(with: traitCollection).cgColor
            CATransaction.commit()
        }
        func releaseCell() { enabled = false; cover.removeFromSuperlayer() }
    }
}
