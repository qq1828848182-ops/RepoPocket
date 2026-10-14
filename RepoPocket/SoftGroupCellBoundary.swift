import SwiftUI
import UIKit

/// Clip the native cell, including its swipe container, to the same outer corners
/// as its SwiftUI background. Uses public UIKit types and restores reused cells.
struct SoftGroupCellBoundary: UIViewRepresentable {
    let top: Bool
    let bottom: Bool
    func makeUIView(context: Context) -> BoundaryView { BoundaryView() }
    func updateUIView(_ view: BoundaryView, context: Context) { view.configure(top: top, bottom: bottom) }
    static func dismantleUIView(_ view: BoundaryView, coordinator: ()) { view.releaseCell() }

    final class BoundaryView: UIView {
        private static let owners = NSMapTable<UIView, BoundaryView>.weakToWeakObjects()
        private weak var cell: UIView?
        private var previous: (CGFloat, CACornerMask, CALayerCornerCurve, Bool)?
        private var top = false
        private var bottom = false
        private var enabled = true
        override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false; backgroundColor = .clear }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        func configure(top: Bool, bottom: Bool) {
            self.top = top; self.bottom = bottom; enabled = true
            attach()
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }
        override func didMoveToSuperview() { super.didMoveToSuperview(); attach() }
        override func didMoveToWindow() { super.didMoveToWindow(); attach() }
        override func layoutSubviews() { super.layoutSubviews(); attach() }
        private func attach() {
            guard enabled else { return }
            var ancestor = superview
            while let candidate = ancestor {
                if candidate is UICollectionViewCell || candidate is UITableViewCell {
                    if cell !== candidate {
                        restore()
                        cell = candidate
                        let layer = candidate.layer
                        previous = (layer.cornerRadius, layer.maskedCorners, layer.cornerCurve, layer.masksToBounds)
                    }
                    Self.owners.setObject(self, forKey: candidate)
                    var corners: CACornerMask = []
                    if top { corners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner]) }
                    if bottom { corners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]) }
                    let layer = candidate.layer
                    let radius: CGFloat = top || bottom ? 22 : 0
                    if layer.cornerRadius != radius { layer.cornerRadius = radius }
                    if layer.maskedCorners != corners { layer.maskedCorners = corners }
                    if layer.cornerCurve != .continuous { layer.cornerCurve = .continuous }
                    if !layer.masksToBounds { layer.masksToBounds = true }
                    return
                }
                ancestor = candidate.superview
            }
        }
        private func restore() {
            if let cell, Self.owners.object(forKey: cell) === self, let previous {
                cell.layer.cornerRadius = previous.0
                cell.layer.maskedCorners = previous.1
                cell.layer.cornerCurve = previous.2
                cell.layer.masksToBounds = previous.3
                Self.owners.removeObject(forKey: cell)
            }
            cell = nil; previous = nil
        }
        func releaseCell() { enabled = false; restore() }
    }
}
