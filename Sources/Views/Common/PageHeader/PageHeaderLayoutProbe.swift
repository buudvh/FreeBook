import SwiftUI
import UIKit

/// **Tạm thời** (1.3.1025) — đầu dò đo bố cục header thật trên máy để chỉnh khoảng cách dọc dưới tiêu đề (anh Bửu: "hàng 1
/// với hàng 2 nhiều lúc cách khoảng rỗng, nhiều lúc khoảng hẹp" → "Làm tiếp" phần đo). Gỡ cả file khi đã chốt số.
///
/// Gắn ở mọi trang dùng `PageTitleModifier`. Chỉ làm việc khi công tắc Ghi log đang bật: ~0,8 s sau khi trang hiện, ghi
/// **một** dòng `📐 [HeaderLayout]` toạ độ cửa sổ (pt) của thanh điều hướng, mũi back hệ thống, ô nút trái / phải, ô tìm,
/// scroll view chính và nội dung đầu tiên. Không đổi gì trên màn.
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
            var parts: [String] = ["\"\(title)\"", "style=\(style)", "pres=\(Self.presentation(of: controller))"]
            parts.append("w=\(Self.f(window.bounds.width)) safeTop=\(Self.f(window.safeAreaInsets.top))")
            if let bar = controller.navigationController?.navigationBar, !bar.isHidden {
                let barFrame = bar.convert(bar.bounds, to: window)
                parts.append("bar=y\(Self.f(barFrame.minY)) h\(Self.f(barFrame.height)) margin\(Self.f(bar.layoutMargins.left))")
                parts.append(contentsOf: Self.barItems(in: bar, window: window))
            } else {
                parts.append("bar=-")
            }
            parts.append(Self.content(in: controller.view, window: window))
            AppLogger.shared.log("📐 [HeaderLayout] " + parts.joined(separator: " "))
        }

        // MARK: - Thanh điều hướng

        /// Mũi back hệ thống (ảnh nhỏ sát trái), ô SwiftUI của các mục toolbar (trái / phải), ô tìm.
        private static func barItems(in bar: UINavigationBar, window: UIWindow) -> [String] {
            var back: CGRect?
            var hosts: [CGRect] = []
            var search: CGRect?
            var queue: [UIView] = [bar]
            while !queue.isEmpty {
                let view = queue.removeFirst()
                guard !view.isHidden, view.alpha > 0.01 else { continue }
                let frame = view.convert(view.bounds, to: window)
                if let imageView = view as? UIImageView, imageView.image != nil,
                   frame.minX < 60, (10...34).contains(frame.height), frame.width < 34 {
                    if back == nil || frame.minX < back!.minX { back = frame }
                }
                if let searchBar = view as? UISearchBar {
                    search = searchBar.searchTextField.convert(searchBar.searchTextField.bounds, to: window)
                }
                let typeName = String(describing: type(of: view))
                if typeName.contains("HostingView"), frame.width > 4, frame.width < window.bounds.width * 0.9, frame.height <= 60 {
                    hosts.append(frame)
                    continue // ô SwiftUI: không đi sâu hơn
                }
                queue.append(contentsOf: view.subviews)
            }
            var parts: [String] = []
            parts.append(back.map { "back=x\(f($0.minX)) w\(f($0.width)) h\(f($0.height)) midY\(f($0.midY))" } ?? "back=-")
            let midX = window.bounds.width / 2
            let left = hosts.filter { $0.minX < midX }.sorted { $0.minX < $1.minX }
            let right = hosts.filter { $0.minX >= midX }.sorted { $0.minX < $1.minX }
            parts.append("left=" + (left.isEmpty ? "-" : left.map(span).joined(separator: ",")))
            parts.append("right=" + (right.isEmpty ? "-" : right.map(span).joined(separator: ",")))
            parts.append(search.map { "search=x\(f($0.minX))–\(f($0.maxX)) y\(f($0.minY))–\(f($0.maxY))" } ?? "search=-")
            return parts
        }

        private static func span(_ frame: CGRect) -> String {
            "x\(f(frame.minX))–\(f(frame.maxX))/y\(f(frame.minY))h\(f(frame.height))"
        }

        // MARK: - Nội dung

        /// Scroll view lớn nhất của trang + vị trí phần tử đầu tiên (ô / tiêu đề nhóm của List; với ScrollView SwiftUI chỉ
        /// biết gốc nội dung).
        private static func content(in root: UIView?, window: UIWindow) -> String {
            guard let scrollView = primaryScrollView(in: root) else { return "scroll=-" }
            let frame = scrollView.convert(scrollView.bounds, to: window)
            // Gốc nội dung (y = 0 của content) trên cửa sổ.
            let origin = frame.minY - scrollView.contentOffset.y
            var text = "scroll=\(String(describing: type(of: scrollView)).prefix(24)) y\(f(frame.minY)) inset\(f(scrollView.adjustedContentInset.top))"
            text += " off\(f(scrollView.contentOffset.y)) origin\(f(origin))"
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

        /// Scroll view có diện tích lớn nhất trong trang (bỏ scroll view ngang nhỏ như dải chip).
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

        private static func f(_ value: CGFloat) -> String {
            String(format: "%.1f", Double(value))
        }
    }
}
