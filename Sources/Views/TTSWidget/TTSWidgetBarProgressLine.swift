import Combine
import SwiftUI

/// Vạch tiến độ chương của kiểu Thanh nghe nhạc (1.3.796): đoạn đang đọc / tổng đoạn của chương. Là view **riêng** tự
/// observe tiến độ (`Reader` lồng bên trong) để thân thanh không vẽ lại theo từng đoạn.
struct TTSWidgetBarProgressLine: View {
    @StateObject private var reader = Reader()

    var body: some View {
        MiniPlayerProgressLine(fraction: reader.fraction)
    }

    /// `currentParagraphIndex` là chỉ số trong mảng chunk `paragraphs` (không phải `currentParentParagraphIndex` — id dòng
    /// thưa). `paragraphs` không `@Published` ⇒ đọc số lượng ở lượt sau (`receive(on:)`). Làm tròn 1/500 để khỏi phát
    /// lặp cùng một vạch.
    @MainActor
    final class Reader: ObservableObject {
        @Published private(set) var fraction: Double = 0
        private var cancellables = Set<AnyCancellable>()

        init(manager: TTSManager? = nil) {
            let manager = manager ?? TTSManager.shared
            refresh(from: manager)
            manager.$currentParagraphIndex.map { _ in () }.receive(on: RunLoop.main).sink { [weak self, weak manager] in
                self?.refresh(from: manager)
            }.store(in: &cancellables)
            manager.$playingChapterIndex.map { _ in () }.receive(on: RunLoop.main).sink { [weak self, weak manager] in
                self?.refresh(from: manager)
            }.store(in: &cancellables)
        }

        private func refresh(from manager: TTSManager?) {
            guard let manager else { return }
            let count = manager.paragraphs.count
            let index = manager.currentParagraphIndex
            let raw = (count > 0 && index >= 0) ? Double(min(index + 1, count)) / Double(count) : 0
            let rounded = (raw * 500).rounded() / 500
            guard rounded != fraction else { return }
            fraction = rounded
        }
    }
}
