import Combine
import Foundation

/// Câu đang đọc + tiến độ chương cho sheet điều khiển nhanh TTS (`TTSQuickControlSheet`, 1.3.806). Tách khỏi sheet để chỉ
/// phần chữ này vẽ lại theo từng đoạn, không kéo theo cả sheet.
///
/// `currentParagraphIndex` là chỉ số trong mảng **chunk** `TTSManager.paragraphs` (không phải id dòng thưa `ChapterTextLine.id`).
/// `paragraphs` không `@Published` ⇒ đọc ở lượt sau (`receive(on:)`) của các tín hiệu có phát.
@MainActor
final class TTSQuickControlNowReading: ObservableObject {
    struct Snapshot: Equatable {
        var sentence = ""
        /// Số thứ tự đoạn đang đọc, đếm từ 1; 0 ⇒ chưa có.
        var position = 0
        var total = 0
        /// Model + tăng tốc của đoạn đang phát (VieNeu, 1.3.942) — `nil` khi không phải VieNeu / đoạn chưa tổng hợp xong.
        var engineLabel: VieNeuEngineBadgeStore.Label?

        var fraction: Double {
            guard total > 0, position > 0 else { return 0 }
            return Double(min(position, total)) / Double(total)
        }
    }

    @Published private(set) var snapshot = Snapshot()
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
        // Đoạn đầu: chỉ số đặt trước khi tổng hợp xong ⇒ tra lại nhãn lúc bắt đầu phát.
        manager.$isPlaying.map { _ in () }.receive(on: RunLoop.main).sink { [weak self, weak manager] in
            self?.refresh(from: manager)
        }.store(in: &cancellables)
    }

    private func refresh(from manager: TTSManager?) {
        guard let manager else { return }
        let paragraphs = manager.paragraphs
        let index = manager.currentParagraphIndex
        var next = Snapshot(total: paragraphs.count)
        if index >= 0, index < paragraphs.count {
            next.position = index + 1
            next.sentence = paragraphs[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Badge "model · tăng tốc": tra theo đúng chữ engine nhận (đã áp từ điển thay thế) — một lần mỗi đoạn.
            if manager.tool == "vieneu" {
                let spoken = TTSReplacementManager.shared.applyReplacements(
                    to: paragraphs[index].text, bookId: manager.playingBookId
                )
                next.engineLabel = VieNeuEngineBadgeStore.shared.label(for: spoken)
            }
        }
        guard next != snapshot else { return }
        snapshot = next
    }
}
