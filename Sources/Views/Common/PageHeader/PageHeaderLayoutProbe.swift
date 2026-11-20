import SwiftUI
import UIKit

/// **Tạm thời** (1.3.1025; sửa cho iOS 26 ở 1.3.1026) — đầu dò đo bố cục header thật trên máy để chỉnh khoảng cách dọc
/// dưới tiêu đề (anh Bửu: "hàng 1 với hàng 2 nhiều lúc cách khoảng rỗng, nhiều lúc khoảng hẹp" → "Làm tiếp" phần đo, chọn
/// mốc B "đáy thanh +16"). Gỡ cả file khi đã chốt số.
///
/// Gắn ở mọi trang dùng `PageTitleModifier`. Chỉ làm việc khi công tắc Ghi log đang bật: ~0,8 s sau khi trang hiện, ghi
/// **một** dòng `📐 [HeaderLayout]` toạ độ cửa sổ (pt) của thanh điều hướng, mũi back hệ thống, các mảnh nhìn thấy ở hàng
/// nút (trái / phải), ô tìm, scroll view chính và nội dung đầu tiên. Không đổi gì trên màn.
///
/// 1.3.1026: iOS 26 không còn lớp tên chứa "HostingView" trong thanh ⇒ đo **view lá** (không có view con) ở hàng nút
/// thay vì ô SwiftUI; trang có tab vuốt (scroll view chính phân trang) ⇒ đo scroll view dọc bên trong trang đang hiện;
/// `note=` đánh dấu dòng nhiễu (trang đã cuộn sẵn, trang nằm ngoài màn).
struct PageHeaderLayoutProbe: UIViewRepresentable {
    let title: String
    let style: String

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.title = title
        view.style = style
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.title = title
        uiView.style = style
    }

    final class ProbeView: UIView {
        var title = ""
        var style = ""
        private var scheduled = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, !scheduled, AppLogger.shared.isLoggingEnabled else { return }
            scheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                MainActor.assumeIsolated {
                    self?.scheduled = false
                    self?.logLayout()
                }
            }
        }

        private func logLayout() {
            guard let window, let controller = Self.owningViewController(of: self) else { return }
            var notes: [String] = []
            var parts: [String] = ["\"\(title)\"", "style=\(style)", "pres=\(Self.presentation(of: controller))"]
            parts.append("w=\(Self.f(window.bounds.width)) safeTop=\(Self.f(window.safeAreaInsets.top))")
            if let bar = controller.navigationController?.navigationBar, !bar.isHidden {
                let barFrame = bar.convert(bar.bounds, to: window)
                parts.append("bar=y\(Self.f(barFrame.minY)) h\(Self.f(barFrame.height)) margin\(Self.f(bar.layoutMargins.left))")
                parts.append(contentsOf: Self.barItems(in: bar, barFrame: barFrame, window: window))
            } else {
                parts.append("bar=-")
                notes.append("nobar")
            }
            parts.append(Self.content(in: controller.view, window: window, notes: &notes))
            if !notes.isEmpty { parts.append("note=" + notes.joined(separator: ",")) }
            AppLogger.shared.log("📐 [HeaderLayout] " + parts.joined(separator: " "))
        }

        // MARK: - Thanh điều hướng

        /// Mũi back hệ thống (ảnh nhỏ sát trái), các **view lá** nhìn thấy ở hàng nút (chữ tiêu đề, icon) chia trái / phải,
        /// ô tìm.
        private static func barItems(in bar: UINavigationBar, barFrame: CGRect, window: UIWindow) -> [String] {
            var back: CGRect?
            var leaves: [CGRect] = []
            var search: CGRect?
            let rowBottom = barFrame.minY + 56
            var queue: [UIView] = [bar]
            while !queue.isEmpty {
                let view = queue.removeFirst()
                guard !view.isHidden, view.alpha > 0.01 else { continue }
                let frame = view.convert(view.bounds, to: window)
                if let searchBar = view as? UISearchBar {
                    search = searchBar.searchTextField.convert(searchBar.searchTextField.bounds, to: window)
                    continue // ô tìm: không đi sâu, không tính là mảnh hàng nút
                }
                if let imageView = view as? UIImageView, imageView.image != nil,
                   frame.minX < 60, (10...34).contains(frame.height), frame.width < 34,
                   back == nil || frame.minX < back!.minX {
                    back = frame
                }
                let isLeaf = view.subviews.isEmpty || view is UIImageView || view is UILabel
                if isLeaf, frame.width > 2, frame.width < 220, frame.height > 2, frame.height <= 50,
                   frame.minY >= barFrame.minY - 1, frame.maxY <= rowBottom {
                    leaves.append(frame)
                    continue
                }
                queue.append(contentsOf: view.subviews)
            }
            let midX = window.bounds.width / 2
            let others = leaves.filter { frame in back.map { !$0.equalTo(frame) } ?? true }
            let left = others.filter { $0.midX < midX }
            let right = others.filter { $0.midX >= midX }
            var parts: [String] = []
            parts.append(back.map { "back=x\(f($0.minX)) w\(f($0.width)) h\(f($0.height)) midY\(f($0.midY))" } ?? "back=-")
            parts.append("left=" + group(left))
            parts.append("right=" + group(right))
            parts.append(search.map { "search=x\(f($0.minX))–\(f($0.maxX)) y\(f($0.minY))–\(f($0.maxY))" } ?? "search=-")
            return parts
        }

        /// Một nhóm mảnh: số mảnh, mép trái nhất – mép phải nhất, khoảng y.
        private static func group(_ frames: [CGRect]) -> String {
            guard let minX = frames.map(\.minX).min(), let maxX = frames.map(\.maxX).max(),
                  let minY = frames.map(\.minY).min(), let maxY = frames.map(\.maxY).max() else { return "-" }
            return "n\(frames.count) x\(f(minX))–\(f(maxX)) y\(f(minY))–\(f(maxY))"
        }

        // MARK: - Nội dung

        /// Scroll view lớn nhất của trang (trang có tab vuốt ⇒ scroll view dọc trong trang đang hiện) + phần tử đầu tiên.
        private static func content(in root: UIView?, window: UIWindow, notes: inout [String]) -> String {
            guard var scrollView = primaryScrollView(in: root, window: window) else { return "scroll=-" }
            var paged = false
            if scrollView.isPagingEnabled, let collection = scrollView as? UICollectionView,
               let page = collection.visibleCells.first(where: { cell in
                   let frame = cell.convert(cell.bounds, to: window)
                   return frame.minX > -1 && frame.minX < 1
               }),
               let inner = primaryScrollView(in: page.contentView, window: window) {
                scrollView = inner
                paged = true
            }
            let frame = scrollView.convert(scrollView.bounds, to: window)
            let origin = frame.minY - scrollView.contentOffset.y
            var text = "scroll=\(String(describing: type(of: scrollView)).prefix(24))\(paged ? "(paged)" : "")"
            text += " y\(f(frame.minY)) inset\(f(scrollView.adjustedContentInset.top)) off\(f(scrollView.contentOffset.y))"
            text += " origin\(f(origin))"
            if abs(scrollView.contentOffset.y + scrollView.adjustedContentInset.top) > 0.6 { notes.append("scrolled") }
            var firsts: [CGRect] = []
            if let collection = scrollView as? UICollectionView {
                firsts += collection.visibleCells.map { $0.convert($0.bounds, to: window) }
                firsts += collection.visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionHeader)
                    .map { $0.convert($0.bounds, to: window) }
            } else if let table = scrollView as? UITableView {
                firsts += table.visibleCells.map { $0.convert($0.bounds, to: window) }
            }
            if let first = firsts.filter({ $0.height > 1 }).min(by: { $0.minY < $1.minY }) {
                text += " first=y\(f(first.minY)) x\(f(first.minX))–\(f(first.maxX)) h\(f(first.height))"
                if first.minX < -1 || first.minX >= window.bounds.width { notes.append("offscreen") }
            } else {
                text += " first=-"
            }
            return text
        }

        // MARK: - Đọc cây UIKit

        private static func presentation(of controller: UIViewController) -> String {
            var root = controller
            while let parent = root.parent { root = parent }
            if root.presentingViewController != nil {
                return [.fullScreen, .overFullScreen].contains(root.modalPresentationStyle) ? "cover" : "sheet"
            }
            return (controller.navigationController?.viewControllers.count ?? 0) > 1 ? "push" : "root"
        }

        private static func owningViewController(of view: UIView) -> UIViewController? {
            var responder: UIResponder? = view.next
            while let current = responder {
                if let controller = current as? UIViewController { return controller }
                responder = current.next
            }
            return nil
        }

        /// Scroll view có diện tích **nằm trong cửa sổ** lớn nhất (bỏ scroll view ngang nhỏ như dải chip, trang tab khuất).
        private static func primaryScrollView(in root: UIView?, window: UIWindow) -> UIScrollView? {
            guard let root else { return nil }
            var best: UIScrollView?
            var bestArea: CGFloat = 0
            var queue: [UIView] = root is UIScrollView ? root.subviews : [root]
            while !queue.isEmpty {
                let view = queue.removeFirst()
                if let scrollView = view as? UIScrollView, !(view is UITextView) {
                    let visible = scrollView.convert(scrollView.bounds, to: window).intersection(window.bounds)
                    let area = visible.isNull ? 0 : visible.width * visible.height
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

        private static func f(_ value: CGFloat) -> String {
            String(format: "%.1f", Double(value))
        }
    }
}
