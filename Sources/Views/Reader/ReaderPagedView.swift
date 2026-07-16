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
    
    @Binding var currentPageIndex: Int
    
    let onSelectionChange: (String, String, Int, Int, ParagraphItem) -> Void
    let onSpeakFromHere: (Int, ParagraphItem) -> Void
    let onChapterBoundaryReached: (ChapterBoundaryDirection) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(
            transitionStyle: .scroll, // Trượt ngang mượt mà (có thể đổi thành .pageCurl nếu muốn lật 3D)
            navigationOrientation: .horizontal,
            options: nil
        )
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        
        // Thiết lập trang hiển thị ban đầu
        if let initialVC = context.coordinator.viewController(at: currentPageIndex) {
            pvc.setViewControllers([initialVC], direction: .forward, animated: false, completion: nil)
        }
        
        return pvc
    }
    
    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        
        // 1. Đồng bộ trang hiển thị hiện tại nếu Binding currentPageIndex thay đổi từ bên ngoài (ví dụ nạp bookmark, TTS nhảy trang)
        if let currentVC = uiViewController.viewControllers?.first as? ReaderPageViewController {
            if currentVC.pageIndex != currentPageIndex && currentPageIndex >= 0 && currentPageIndex < pages.count {
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
        
        init(_ parent: ReaderPagedView) {
            self.parent = parent
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
                            .foregroundColor(UIColor(parent.theme.textColor).toColor().opacity(0.6))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(UIColor(parent.theme.backgroundColor).toColor())
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
                            .foregroundColor(UIColor(parent.theme.textColor).toColor().opacity(0.6))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(UIColor(parent.theme.backgroundColor).toColor())
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
            
            return AnyView(
                VStack(spacing: 0) {
                    ReaderTextView(
                        text: parent.isTranslationEnabled ? page.combinedTranslated : page.combinedOriginal,
                        fontSize: parent.fontSize,
                        lineSpacing: parent.lineSpacing,
                        theme: parent.theme,
                        highlightRange: pageHighlightRange,
                        isBold: false,
                        isCentered: false,
                        triggerGetVisibleIndex: .constant(nil),
                        onGetVisibleIndex: { _ in },
                        onSelectionChange: { selectedText, sentence, offset, absoluteOffset in
                            // Ánh xạ ngược tọa độ từ Trang về ParagraphItem gốc để dịch
                            if let mapped = self.findParagraphItem(for: absoluteOffset, in: page) {
                                self.parent.onSelectionChange(selectedText, sentence, offset, absoluteOffset, mapped.item)
                            }
                        },
                        onSpeakFromHere: { absoluteOffset in
                            if let mapped = self.findParagraphItem(for: absoluteOffset, in: page) {
                                self.parent.onSpeakFromHere(mapped.relativeOffset, mapped.item)
                            }
                        }
                    )
                    .padding(.horizontal, 16) // Lề trang sách trái phải
                    .padding(.top, 16)        // Lề trang sách trên
                    // Tự động căn lề dưới động theo Grid Alignment để chữ luôn nguyên vẹn dòng
                    .padding(.bottom, ReaderPageHelper.gridAlignedBottomInset(
                        renderSize: CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height),
                        fontSize: CGFloat(parent.fontSize),
                        lineSpacing: CGFloat(parent.lineSpacing),
                        contentInsets: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
                    ))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(UIColor(parent.theme.backgroundColor).toColor())
            )
        }
        
        /// Khởi tạo ViewController chứa trang tại index chỉ định
        func viewController(at index: Int) -> ReaderPageViewController? {
            // Cho phép index từ -1 đến pages.count (bao gồm cả 2 trang ảo ở biên để vuốt chuyển chương)
            guard index >= -1 && index <= parent.pages.count else { return nil }
            let view = makePageView(at: index)
            return ReaderPageViewController(pageIndex: index, chapterIndex: parent.chapterIndex, rootView: AnyView(view))
        }
        
        /// Ánh xạ ngược tọa độ offset tuyệt đối trong trang về ParagraphItem gốc và offset tương đối của nó
        private func findParagraphItem(for absoluteOffset: Int, in page: ReaderPage) -> (item: ParagraphItem, relativeOffset: Int)? {
            let ranges = parent.isTranslationEnabled ? page.translatedParagraphRanges : page.originalParagraphRanges
            
            for (pId, range) in ranges {
                if absoluteOffset >= range.location && absoluteOffset < range.location + range.length {
                    if let item = page.paragraphItems.first(where: { $0.id == pId }) {
                        let relativeOffset = absoluteOffset - range.location
                        return (item, relativeOffset)
                    }
                }
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
            guard completed,
                  let currentVC = pageViewController.viewControllers?.first as? ReaderPageViewController
            else { return }
            
            // Xử lý khi vuốt trúng trang ảo ở biên chuyển chương
            if currentVC.pageIndex == parent.pages.count {
                // Sang chương sau
                parent.onChapterBoundaryReached(.forward)
            } else if currentVC.pageIndex == -1 {
                // Về chương trước
                parent.onChapterBoundaryReached(.backward)
            } else {
                // Trang bình thường: Cập nhật chỉ số trang hiện tại
                parent.currentPageIndex = currentVC.pageIndex
            }
        }
    }
}

// Helper chuyển đổi UIColor sang SwiftUI Color
extension UIColor {
    func toColor() -> Color {
        return Color(self)
    }
}
