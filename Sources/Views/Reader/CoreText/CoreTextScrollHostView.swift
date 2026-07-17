import SwiftUI
import UIKit

struct CoreTextScrollHostView: UIViewControllerRepresentable {
    
    let totalChapters: Int
    let initialChapter: Int
    let initialParagraph: Int
    
    let fontSize: CGFloat
    let textColor: Color
    let backgroundColor: Color
    let highlightColor: Color
    let lineSpacing: CGFloat
    let paragraphSpacing: CGFloat
    let isTranslationEnabled: Bool
    
    @ObservedObject var viewModel: ReaderViewModel
    @Binding var scrollTarget: ScrollTarget?
    
    var onTap: () -> Void
    var onProgressCommit: (Int, Int) -> Void
    
    func makeUIViewController(context: Context) -> CoreTextCollectionScrollViewController {
        let vc = CoreTextCollectionScrollViewController(
            totalChapters: totalChapters,
            initialChapter: initialChapter,
            initialParagraph: initialParagraph,
            horizontalInset: 20.0,
            verticalInset: 24.0,
            backgroundColor: UIColor(backgroundColor)
        )
        
        vc.onTap = onTap
        vc.onProgressCommit = onProgressCommit
        vc.onChapterContentRequired = { chapterIndex in
            // Yêu cầu ViewModel tải chương thông qua extension
            Task {
                try? await viewModel.loadChapterContentFromExtension(chapterIndex)
            }
        }
        
        return vc
    }
    
    func updateUIViewController(_ vc: CoreTextCollectionScrollViewController, context: Context) {
        // 1. Cập nhật Font và Theme màu sắc
        let uiFont = UIFont.systemFont(ofSize: fontSize)
        vc.updateTheme(
            font: uiFont,
            textColor: UIColor(textColor),
            backgroundColor: UIColor(backgroundColor),
            highlightColor: UIColor(highlightColor),
            lineSpacing: lineSpacing,
            paragraphSpacing: paragraphSpacing
        )
        
        // 2. Nhận tín hiệu nhảy chương/cuộn từ SwiftUI (Slider / TOC)
        if let target = scrollTarget {
            let paragraphIdx = target.paragraphIndex == -1 ? 0 : target.paragraphIndex
            vc.scrollToSavedPosition(chapter: target.chapterIndex, paragraph: paragraphIdx)
            
            // Đặt lại nil bất đồng bộ để tránh thay đổi state giữa chừng render SwiftUI
            DispatchQueue.main.async {
                self.scrollTarget = nil
            }
        }
        
        // 3. Đồng bộ dữ liệu chương từ Cache của ViewModel xuống Controller
        // FIX BUG 2: Truyền thẳng [ParagraphItem] — bỏ hoàn toàn HTML round-trip
        let visibleWindow = viewModel.computeWindowRange()
        
        for idx in visibleWindow {
            guard idx >= 0 && idx < totalChapters else { continue }
            
            if let cached = viewModel.cache.get(idx) {
                switch cached.state {
                case .loaded:
                    // Truyền mảng ParagraphItem trực tiếp xuống UIKit, không tạo HTML
                    vc.updateChapterData(
                        chapterIndex: idx,
                        state: .loaded,
                        paragraphs: cached.paragraphItems,
                        isTranslationEnabled: isTranslationEnabled
                    )
                case .loading, .prefetching:
                    vc.updateChapterData(chapterIndex: idx, state: .loading)
                case .failed(let msg):
                    vc.updateChapterData(chapterIndex: idx, state: .failed(msg))
                case .placeholder:
                    vc.updateChapterData(chapterIndex: idx, state: .notLoaded)
                }
            } else {
                vc.updateChapterData(chapterIndex: idx, state: .notLoaded)
            }
        }
    }
}

// MARK: - String HTML Escaping Extension (giữ lại cho trường hợp cần thiết khác)
private extension String {
    func htmlEscaped() -> String {
        return self.replacingOccurrences(of: "&", with: "&amp;")
                   .replacingOccurrences(of: "\"", with: "&quot;")
                   .replacingOccurrences(of: "'", with: "&#39;")
                   .replacingOccurrences(of: "<", with: "&lt;")
                   .replacingOccurrences(of: ">", with: "&gt;")
    }
}
