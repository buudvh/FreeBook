import Combine
import Foundation

/// Câu đang đọc + tiến độ chương cho sheet điều khiển nhanh TTS (`TTSQuickControlSheet`, 1.3.806). Tách khỏi sheet để chỉ
/// phần chữ này vẽ lại theo từng đoạn, không kéo theo cả sheet.
///
/// `currentParagraphIndex` là chỉ số trong mảng **chunk** `TTSManager.paragraphs` (không phải id dòng thưa `ChapterTextLine.id`).
/// `paragraphs` không `@Published` ⇒ đọc ở lượt sau (`receive(on:)`) của các tín hiệu có phát.
///
/// Tiến độ "N/M" đếm theo **đoạn** = dòng cha (2026-11-19, anh Bửu: vạch tiến độ kéo để tua theo đoạn): M = số
/// `paragraphIndex` ≥ 0 khác nhau, N = thứ tự dòng đang đọc (tiêu đề ⇒ 0). Trước đó đếm chunk (tính cả chunk tiêu đề và
/// chunk con của NghiTTS / VieNeu). `outline` (đầu từng đoạn) dựng lại chỉ khi phiên / chương / số chunk / lượt nối đổi, để
/// kéo vạch không phải đọc `TTSManager` mỗi nhịp.
@MainActor
final class TTSQuickControlNowReading: ObservableObject {
    struct Snapshot: Equatable {
        var sentence = ""
        /// Thứ tự **đoạn** (dòng cha) đang đọc, đếm từ 1; 0 ⇒ chưa có / đang đọc tên chương.
        var position = 0
        /// Số đoạn của chương (không tính tên chương).
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

    /// Đầu một đoạn: id dòng (`TTSParagraph.paragraphIndex`) + câu của chunk đầu (bong bóng khi kéo vạch).
    struct OutlineEntry: Equatable {
        let lineId: Int
        let sentence: String
    }

    private struct OutlineKey: Equatable {
        let sessionID: UUID
        let bookId: String
        let chapterIndex: Int
        let chunkCount: Int
        let layoutRevision: Int
    }

    @Published private(set) var snapshot = Snapshot()
    private(set) var outline: [OutlineEntry] = []
    private var ordinalByLineId: [Int: Int] = [:]
    private var outlineKey: OutlineKey?
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
        rebuildOutlineIfNeeded(manager: manager, paragraphs: paragraphs)
        var next = Snapshot(total: outline.count)
        if index >= 0, index < paragraphs.count {
            next.position = ordinalByLineId[paragraphs[index].paragraphIndex] ?? 0
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

    private func rebuildOutlineIfNeeded(manager: TTSManager, paragraphs: [TTSParagraph]) {
        let key = OutlineKey(
            sessionID: manager.sessionID,
            bookId: manager.playingBookId,
            chapterIndex: manager.playingChapterIndex,
            chunkCount: paragraphs.count,
            layoutRevision: TTSRetranslationCoordinator.shared.layoutRevision
        )
        guard key != outlineKey else { return }
        outlineKey = key
        var entries: [OutlineEntry] = []
        var ordinals: [Int: Int] = [:]
        for paragraph in paragraphs where paragraph.paragraphIndex >= 0 && ordinals[paragraph.paragraphIndex] == nil {
            entries.append(OutlineEntry(
                lineId: paragraph.paragraphIndex,
                sentence: paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
            ordinals[paragraph.paragraphIndex] = entries.count
        }
        outline = entries
        ordinalByLineId = ordinals
    }

    // MARK: - Kéo vạch tiến độ

    /// Thứ tự đoạn (1…M) ứng với vị trí kéo `0…1` — cùng thang với `Snapshot.fraction` (đoạn k ở `k / M`).
    func ordinal(forFraction fraction: Double) -> Int? {
        guard !outline.isEmpty, fraction.isFinite else { return nil }
        let raw = Int((min(max(fraction, 0), 1) * Double(outline.count)).rounded())
        return min(max(raw, 1), outline.count)
    }

    func entry(atOrdinal ordinal: Int) -> OutlineEntry? {
        outline.indices.contains(ordinal - 1) ? outline[ordinal - 1] : nil
    }

    /// Thả tay: nhảy tới đầu đoạn thứ `ordinal`. Trùng đoạn đang đọc ⇒ không làm gì (kéo rồi thả lại chỗ cũ).
    func seek(toOrdinal ordinal: Int) {
        guard ordinal != snapshot.position, let entry = entry(atOrdinal: ordinal) else { return }
        TTSManager.shared.seekToParagraph(lineId: entry.lineId)
    }
}
