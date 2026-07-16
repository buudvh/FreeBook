import SwiftUI
import UIKit

public enum ChapterBoundaryDirection {
    case forward
    case backward
}

/// ViewController đại diện cho một trang đọc truyện đơn
class ReaderPageViewController: UIHostingController<AnyView> {
    let pageIndex: Int
    let chapterIndex: Int
    
    init(pageIndex: Int, chapterIndex: Int, rootView: AnyView) {
        self.pageIndex = pageIndex
        self.chapterIndex = chapterIndex
        super.init(rootView: rootView)
        self.view.backgroundColor = .clear
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// SwiftUI Wrapper cho UIPageViewController của UIKit để thực hiện lật trang chuyên nghiệp
struct ReaderPagedView: UIViewControllerRepresentable {
    let pages: [ReaderPage]
    let chapterIndex: Int
    let isTranslationEnabled: Bool
    let fontSize: Double
    let lineSpacing: Double
    let theme: ReaderTheme
    let highlightRange: NSRange? // Range highlight của paragraph đang đọc (tương đối trong trang)
    let activeParagraphId: Int? // ID của paragraph đang đọc (để xác định trang cần highlight)
    let showChapterTitle: Bool // Ẩn/hiện tiêu đề chương
    let scrollParagraphIndex: Int // Đoạn văn tiến độ hiện hành để đồng bộ chính xác trang
    
    @Binding var currentPageIndex: Int
    
    let onSelectionChange: (String, String, Int, Int, ParagraphItem) -> Void
    let onSpeakFromHere: (Int, ParagraphItem) -> Void
    let onChapterBoundaryReached: (ChapterBoundaryDirection) -> Void
    let onPageChanged: (Int) -> Void // Callback khi transition lật trang settled
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(
            transitionStyle: .scroll, // Trượt ngang mượt mà
            navigationOrientation: .horizontal,
            options: nil
        )
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        
        context.coordinator.pageViewController = pvc
        
        // Thiết lập trang hiển thị ban đầu
        if let initialVC = context.coordinator.viewController(at: currentPageIndex) {
            pvc.setViewControllers([initialVC], direction: .forward, animated: false, completion: nil)
        }
        
        // Thêm TapGestureRecognizer để nhận diện tap biên lật trang (20%) và tap giữa hiện HUD (20%-80%)
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.cancelsTouchesInView = false
        pvc.view.addGestureRecognizer(tap)
        
        return pvc
    }
    
    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.pageViewController = uiViewController
        
        // 1. Đồng bộ trang hiển thị hiện tại nếu Binding currentPageIndex thay đổi từ bên ngoài (ví dụ nạp bookmark, TTS nhảy trang)
        if let currentVC = uiViewController.viewControllers?.first as? ReaderPageViewController {
            if currentVC.pageIndex != currentPageIndex && currentPageIndex >= 0 && currentPageIndex < pages.count {
                // Đảm bảo không bị giật ngược trang khi vuốt tay:
                // Nếu trang hiện tại của UIPageViewController đã chứa đoạn văn tiến độ hiện tại, ta không gọi setViewControllers
                let activeId = scrollParagraphIndex
                
                let currentPageContainsParagraph: Bool
                if currentVC.pageIndex >= 0 && currentVC.pageIndex < pages.count {
                    currentPageContainsParagraph = pages[currentVC.pageIndex].paragraphItems.contains(where: { $0.id == activeId })
                } else {
                    currentPageContainsParagraph = false
                }
                
                if currentPageContainsParagraph {
                    return
                }
                
                if let targetVC = context.coordinator.viewController(at: currentPageIndex) {
                    let direction: UIPageViewController.NavigationDirection = currentPageIndex > currentVC.pageIndex ? .forward : .reverse
                    uiViewController.setViewControllers([targetVC], direction: direction, animated: true, completion: nil)
                }
            } else {
                // 2. Nếu trang không đổi nhưng các cấu hình khác đổi (theme, font, highlight), ta chỉ cập nhật rootView của VC hiện tại để tránh giật hình
                let updatedView = context.coordinator.makePageView(at: currentVC.pageIndex)
                currentVC.rootView = AnyView(updatedView)
            }
        } else if !pages.isEmpty {
            // Trường hợp chưa có VC nào hiển thị
            if let initialVC = context.coordinator.viewController(at: currentPageIndex) {
                uiViewController.setViewControllers([initialVC], direction: .forward, animated: false, completion: nil)
            }
        }
    }
    
    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: ReaderPagedView
        weak var pageViewController: UIPageViewController?
        
        init(_ parent: ReaderPagedView) {
            self.parent = parent
        }
        
        /// Nhận diện Tap và phân vùng hành động: biên trái <20% (lật về), biên phải >80% (lật đi), giữa (hiện HUD)
        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let view = recognizer.view,
                  let pvc = self.pageViewController
            else { return }
            
            // Nếu người dùng đang thực hiện cử chỉ bôi đen chọn chữ, chặn toggle HUD và chặn lật trang
            if let currentVC = pvc.viewControllers?.first as? ReaderPageViewController {
                if let textView = findTextView(in: currentVC.view), textView.selectedRange.length > 0 {
                    return
                }
            }
            
            let point = recognizer.location(in: view)
            let xFraction = point.x / max(view.bounds.width, 1.0)
            
            if xFraction < 0.2 {
                // Tap biên trái -> Lật về trước
                turnPage(direction: .reverse)
            } else if xFraction > 0.8 {
                // Tap biên phải -> Lật sang sau
                turnPage(direction: .forward)
            } else {
                // Tap vùng giữa -> Hiện HUD Controls
                NotificationCenter.default.post(name: NSNotification.Name("toggleReaderControls"), object: nil)
            }
        }
        
        /// Lật trang bằng code lập trình khi người dùng tap biên
        private func turnPage(direction: UIPageViewController.NavigationDirection) {
            guard let pvc = self.pageViewController else { return }
            let currentIndex = parent.currentPageIndex
            let targetIndex = direction == .forward ? currentIndex + 1 : currentIndex - 1
            
            if targetIndex >= 0 && targetIndex < parent.pages.count {
                if let targetVC = viewController(at: targetIndex) {
                    pvc.setViewControllers([targetVC], direction: direction, animated: true) { [weak self] completed in
                        if completed {
                            DispatchQueue.main.async {
                                self?.parent.currentPageIndex = targetIndex
                                self?.parent.onPageChanged(targetIndex)
                            }
                        }
                    }
                }
            } else if targetIndex == parent.pages.count {
                parent.onChapterBoundaryReached(.forward)
            } else if targetIndex == -1 {
                parent.onChapterBoundaryReached(.backward)
            }
        }
        
        /// Tìm UITextView đệ quy trong view hierarchy
        private func findTextView(in view: UIView) -> UITextView? {
            if let textView = view as? UITextView {
                return textView
            }
            for subview in view.subviews {
                if let found = findTextView(in: subview) {
                    return found
                }
            }
            return nil
        }
        
        /// Tạo giao diện trang SwiftUI bọc trong AnyView
        func makePageView(at index: Int) -> some View {
            // Trang ảo chuyển chương sau
            if index == parent.pages.count {
                return AnyView(
                    VStack {
                        Spacer()
                        ProgressView()
                            .padding(.bottom, 8)
                        Text("Đang tải chương tiếp theo...")
                            .font(.system(size: 16))
                            .foregroundColor(Color(uiColor: UIColor(parent.theme.textColor)).opacity(0.6))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: UIColor(parent.theme.backgroundColor)))
                )
            }
            
            // Trang ảo chuyển chương trước
            if index == -1 {
                return AnyView(
                    VStack {
                        Spacer()
                        ProgressView()
                            .padding(.bottom, 8)
                        Text("Đang tải chương trước...")
                            .font(.system(size: 16))
                            .foregroundColor(Color(uiColor: UIColor(parent.theme.textColor)).opacity(0.6))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: UIColor(parent.theme.backgroundColor)))
                )
            }
            
            guard index >= 0 && index < parent.pages.count else {
                return AnyView(EmptyView())
            }
            
            let page = parent.pages[index]
            
            // Tính toán highlight range tương đối cho trang này
            var pageHighlightRange: NSRange? = nil
            if let activeId = parent.activeParagraphId {
                if parent.isTranslationEnabled {
                    pageHighlightRange = page.translatedParagraphRanges[activeId]
                } else {
                    pageHighlightRange = page.originalParagraphRanges[activeId]
                }
            }
            
            // Tìm range của tiêu đề (paragraph ID -1) trong trang này để render to/đậm (chỉ hiện khi showChapterTitle là true và ở trang đầu)
            let pageTitleRange: NSRange? = (parent.showChapterTitle && page.id == 0)
                ? (parent.isTranslationEnabled ? page.translatedParagraphRanges[-1] : page.originalParagraphRanges[-1])
                : nil
            
            let safeAreaTop = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.windows.first?.safeAreaInsets.top ?? 47
            let safeAreaBottom = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.windows.first?.safeAreaInsets.bottom ?? 34
            
            let topPadding = max(16, safeAreaTop)
            let renderHeight = UIScreen.main.bounds.height - safeAreaTop - safeAreaBottom
            
            return AnyView(
                VStack(spacing: 0) {
                    ReaderTextView(
                        text: parent.isTranslationEnabled ? page.combinedTranslated : page.combinedOriginal,
                        fontSize: parent.fontSize,
                        lineSpacing: parent.lineSpacing,
                        theme: parent.theme,
                        highlightRange: pageHighlightRange,
                        titleRange: pageTitleRange,
                        isBold: false,
                        isCentered: false,
                        triggerGetVisibleIndex: .constant(nil),
                        onGetVisibleIndex: { _ in },
                        onSelectionChange: { [weak self] selectedText, sentence, offset, absoluteOffset in
                            // Ánh xạ ngược tọa độ từ Trang về ParagraphItem gốc để dịch
                            if let self = self, let mapped = self.findParagraphItem(for: absoluteOffset, in: page) {
                                // QUAN TRỌNG: Phải truyền mapped.relativeOffset thay vì absoluteOffset của trang
                                self.parent.onSelectionChange(selectedText, sentence, offset, mapped.relativeOffset, mapped.item)
                            }
                        },
                        onSpeakFromHere: { [weak self] absoluteOffset in
                            if let self = self, let mapped = self.findParagraphItem(for: absoluteOffset, in: page) {
                                self.parent.onSpeakFromHere(mapped.relativeOffset, mapped.item)
                            }
                        }
                    )
                    .padding(.horizontal, 16) // Lề trang sách trái phải
                    .padding(.top, topPadding) // Lề trang sách trên tránh tai thỏ
                    // Tự động căn lề dưới động theo Grid Alignment để chữ luôn nguyên vẹn dòng
                    .padding(.bottom, ReaderPageHelper.gridAlignedBottomInset(
                        renderSize: CGSize(width: UIScreen.main.bounds.width, height: renderHeight),
                        fontSize: CGFloat(parent.fontSize),
                        lineSpacing: CGFloat(parent.lineSpacing),
                        contentInsets: UIEdgeInsets(top: topPadding, left: 16, bottom: 16, right: 16)
                    ))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(uiColor: UIColor(parent.theme.backgroundColor)))
            )
        }
        
        /// Khởi tạo ViewController chứa trang tại index chỉ định
        func viewController(at index: Int) -> ReaderPageViewController? {
            guard index >= -1 && index <= parent.pages.count else { return nil }
            let view = makePageView(at: index)
            return ReaderPageViewController(pageIndex: index, chapterIndex: parent.chapterIndex, rootView: AnyView(view))
        }
        
        /// Ánh xạ ngược tọa độ offset tuyệt đối trong trang về ParagraphItem gốc và offset tương đối của nó
        private func findParagraphItem(for absoluteOffset: Int, in page: ReaderPage) -> (item: ParagraphItem, relativeOffset: Int)? {
            let ranges = parent.isTranslationEnabled ? page.translatedParagraphRanges : page.originalParagraphRanges
            
            // 1. Thử so khớp chính xác trước
            for (pId, range) in ranges {
                if absoluteOffset >= range.location && absoluteOffset < range.location + range.length {
                    if let item = page.paragraphItems.first(where: { $0.id == pId }) {
                        let relativeOffset = absoluteOffset - range.location
                        return (item, relativeOffset)
                    }
                }
            }
            
            // 2. Nếu trượt (rơi vào ranh giới \n hoặc khoảng trắng), tìm đoạn văn có khoảng cách gần nhất
            var nearestPId: Int? = nil
            var minDistance = Int.max
            var nearestRange = NSRange(location: 0, length: 0)
            
            for (pId, range) in ranges {
                let distance: Int
                if absoluteOffset < range.location {
                    distance = range.location - absoluteOffset
                } else {
                    distance = absoluteOffset - (range.location + range.length)
                }
                
                if distance < minDistance {
                    minDistance = distance
                    nearestPId = pId
                    nearestRange = range
                }
            }
            
            if let pId = nearestPId, let item = page.paragraphItems.first(where: { $0.id == pId }) {
                let relativeOffset = max(0, min(absoluteOffset - nearestRange.location, nearestRange.length - 1))
                return (item, relativeOffset)
            }
            
            return nil
        }
        
        // MARK: - UIPageViewControllerDataSource
        
        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let pvc = viewController as? ReaderPageViewController else { return nil }
            let prevIndex = pvc.pageIndex - 1
            return self.viewController(at: prevIndex)
        }
        
        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let pvc = viewController as? ReaderPageViewController else { return nil }
            let nextIndex = pvc.pageIndex + 1
            return self.viewController(at: nextIndex)
        }
        
        // MARK: - UIPageViewControllerDelegate
        
        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            // QUAN TRỌNG: Chỉ thông báo cập nhật tiến độ khi transition lật trang kết thúc và settled thực sự
            guard completed && finished,
                  let currentVC = pageViewController.viewControllers?.first as? ReaderPageViewController
            else { return }
            
            if currentVC.pageIndex == parent.pages.count {
                parent.onChapterBoundaryReached(.forward)
            } else if currentVC.pageIndex == -1 {
                parent.onChapterBoundaryReached(.backward)
            } else {
                if currentVC.pageIndex >= 0 && currentVC.pageIndex < parent.pages.count {
                    parent.currentPageIndex = currentVC.pageIndex
                    parent.onPageChanged(currentVC.pageIndex) // Chỉ trigger update progress khi settled
                }
            }
        }
    }
}
