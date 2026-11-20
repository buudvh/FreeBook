import SwiftUI
import UIKit

/// **Tạm thời** (1.3.1026) — đầu dò UIKit của trang mẫu trong màn tự thử nhịp dọc header. ~1 s sau khi trang vào cửa sổ
/// chụp toạ độ cửa sổ (pt): đáy thanh điều hướng, ô tìm, mũi back hệ thống, ô / tiêu đề nhóm đầu tiên của List, và (một
/// lần) cây view con của thanh — để biết iOS 26 dựng ô nút toolbar bằng lớp gì (đầu dò 1.3.1025 không bắt được).
struct HeaderSpacingLabProbe: UIViewRepresentable {
    struct Snapshot {
        var windowWidth: CGFloat = 0
        var barBottom: CGFloat?
        var fieldBottom: CGFloat?
        var systemBack: CGRect?
        var firstCellTop: CGFloat?
        var firstHeaderTop: CGFloat?
        var firstHeaderHeight: CGFloat?
        var barDump: [String] = []
    }

    let dumpsBar: Bool
    let onSnapshot: (Snapshot) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.dumpsBar = dumpsBar
        view.onSnapshot = onSnapshot
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.dumpsBar = dumpsBar
        uiView.onSnapshot = onSnapshot
    }

    final class ProbeView: UIView {
        var dumpsBar = false
        var onSnapshot: ((Snapshot) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                MainActor.assumeIsolated { self?.capture() }
            }
        }

        private func capture() {
            guard let window, let controller = Self.owningViewController(of: self) else { return }
            var snap = Snapshot(windowWidth: window.bounds.width)
            if let bar = controller.navigationController?.navigationBar, !bar.isHidden {
                snap.barBottom = bar.convert(bar.bounds, to: window).maxY
                walk(bar, window: window, depth: 0, snap: &snap)
            }
            if let scroll = Self.primaryScrollView(in: controller.view) {
                if let collection = scroll as? UICollectionView {
                    snap.firstCellTop = collection.visibleCells.map { $0.convert($0.bounds, to: window).minY }.min()
                    let headers = collection.visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionHeader)
                        .map { $0.convert($0.bounds, to: window) }
                        .filter { $0.height > 0.5 }
                    if let first = headers.min(by: { $0.minY < $1.minY }) {
                        snap.firstHeaderTop = first.minY
                        snap.firstHeaderHeight = first.height
                    }
                } else if let table = scroll as? UITableView {
                    snap.firstCellTop = table.visibleCells.map { $0.convert($0.bounds, to: window).minY }.min()
                }
            }
            onSnapshot?(snap)
        }

        /// Mũi back hệ thống (ảnh nhỏ sát trái), ô tìm, và — nếu `dumpsBar` — mọi view con của thanh (lớp + khung).
        private func walk(_ view: UIView, window: UIWindow, depth: Int, snap: inout Snapshot) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            let frame = view.convert(view.bounds, to: window)
            if let imageView = view as? UIImageView, imageView.image != nil,
               frame.minX < 60, (10...34).contains(frame.height), frame.width < 34,
               snap.systemBack == nil || frame.minX < snap.systemBack!.minX {
                snap.systemBack = frame
            }
            if let searchBar = view as? UISearchBar {
                snap.fieldBottom = searchBar.searchTextField.convert(searchBar.searchTextField.bounds, to: window).maxY
            }
            if dumpsBar, depth > 0, frame.width > 2, snap.barDump.count < 60 {
                let name = String(String(describing: type(of: view)).prefix(44))
                snap.barDump.append("\(depth):\(name) x\(Int(frame.minX))–\(Int(frame.maxX)) y\(Int(frame.minY)) h\(Int(frame.height))")
            }
            guard depth < 10 else { return }
            for sub in view.subviews { walk(sub, window: window, depth: depth + 1, snap: &snap) }
        }

        private static func owningViewController(of view: UIView) -> UIViewController? {
            var responder: UIResponder? = view.next
            while let current = responder {
                if let controller = current as? UIViewController { return controller }
                responder = current.next
            }
            return nil
        }

        private static func primaryScrollView(in root: UIView?) -> UIScrollView? {
            guard let root else { return nil }
            var best: UIScrollView?
            var bestArea: CGFloat = 0
            var queue: [UIView] = [root]
            while !queue.isEmpty {
                let view = queue.removeFirst()
                if let scrollView = view as? UIScrollView, !(view is UITextView) {
                    let area = scrollView.bounds.width * scrollView.bounds.height
                    if area > bestArea {
                        best = scrollView
                        bestArea = area
                    }
                    continue
                }
                queue.append(contentsOf: view.subviews)
            }
            return best
        }
    }
}
