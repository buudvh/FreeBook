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
        /// Đoạn đang phát do giọng dự phòng đọc (TTS online lỗi / mất mạng, 1.3.945) — engine dự phòng; `nil` ⇒ không.
        var fallbackEngine: TTSOnlineFallbackSettings.Engine?
        /// RTF của đoạn đang phát (VieNeu hoặc Piper, 1.3.954) — `nil` khi chưa tổng hợp xong.
        var rtf: Double?

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
        // Đoạn tổng hợp lúc cần (đọc song song / đọc lại bằng giọng dự phòng): dấu "dự phòng" + RTF chỉ có khi tiếng xong,
        // sau lúc đổi chỉ số ⇒ tra lại khi đoạn thật sự bắt đầu phát (snapshot thôi "đang chuẩn bị") (1.3.960).
        manager.$playbackSnapshot.map { $0.preparingParentParagraphIndex == nil }.removeDuplicates()
            .receive(on: RunLoop.main).sink { [weak self, weak manager] _ in
                self?.refresh(from: manager)
            }.store(in: &cancellables)
        // Sửa từ điển / rule lúc đang nghe ⇒ phần sau dòng đang đọc được nối bản dịch mới, số chunk đổi (`+RetranslationSplice`).
        TTSRetranslationCoordinator.shared.$layoutRevision.dropFirst().receive(on: RunLoop.main).sink { [weak self, weak manager] _ in
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
            next.fallbackEngine = manager.onlineFallbackEngine(forChunk: index)
            // Chữ đã nói (đã áp quy tắc thay thế) — khoá tra của cả badge engine lẫn RTF.
            let spoken = TTSReplacementManager.shared.applyReplacements(
                to: paragraphs[index].text, bookId: manager.playingBookId
            )
            // Badge "model · tăng tốc": tra theo đúng chữ engine nhận — một lần mỗi đoạn.
            if manager.tool == "vieneu" || next.fallbackEngine == .vieneu {
                next.engineLabel = VieNeuEngineBadgeStore.shared.label(for: spoken)
            }
            // RTF của đoạn đang phát (1.3.954) — VieNeu và Piper đều ghi vào cùng khoá. Chỉ khi tiếng đoạn này do engine
            // offline tạo: kho RTF khoá theo chữ, đoạn online cùng chữ không được mượn số của lượt dự phòng cũ (1.3.960).
            if TTSManager.isLocalEngine(manager.tool) || next.fallbackEngine != nil {
                next.rtf = TTSEngineRTFStore.shared.rtf(for: spoken)
            }
        }
        guard next != snapshot else { return }
        snapshot = next
    }
}
