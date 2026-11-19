import Combine
import Foundation

/// Trạng thái của **dịch lại khi đang nghe** (sửa rule / VP / Name lúc truyện đang nghe). Anh Bửu chốt 2026-11-20:
/// "Hiển thị phải thay đổi cho đúng … Việc để nguyên đoạn trước khi nghe chỉ nên làm với nghe chứ không phải làm với đọc"
/// + chọn "Tô cả đoạn".
///
/// - Reader luôn hiện bản dịch mới cho **mọi** đoạn (dựng lại như trước khi có tính năng này).
/// - TTS (`TTSManager+Retranslation` / `+RetranslationSplice`) nối bản mới từ dòng sau dòng đang đọc, tiếng không cắt;
///   chunk của dòng ≤ mốc vẫn **đọc chữ cũ** (`staleLineIds`). Reader tô **cả đoạn** khi chữ dòng TTS đang đọc khác chữ
///   đang hiện (`ReaderTTSHighlightReader` lấy chữ dòng qua `TTSManager.spokenLineText`, `ReaderTTSHighlightBinder` so).
/// - Lùi / tua về dòng còn chữ cũ ⇒ TTS thay cả chương bằng bản mới (`fullRetranslation`, `+RetranslationRewind`).
/// - TTS dựng lại chữ chương (đọc lại, chuyển chương, thay cả chương khi lùi) ⇒ hết dòng chữ cũ (`noteTTSChapterTextChanged`).
///
/// Thêm: chủ của mảng chunk (`ttsChunkOwner`) + `layoutRevision` cho tua đoạn / sheet nghe mini. Chỉ chạm trên main.
/// Không import SwiftUI (luật `SERVICE_SWIFTUI_IMPORT`).
@MainActor
final class TTSRetranslationCoordinator: ObservableObject {
    /// Mảng chunk `TTSManager.paragraphs` hiện tại thuộc phiên / truyện / chương nào (ghi lúc gán mảng). Lệch phiên / chương
    /// đang phát ⇒ một lượt dựng chương đang chạy, chunk cũ chưa bị thay.
    struct ChunkOwner: Equatable {
        let sessionID: UUID
        let bookId: String
        let chapterIndex: Int
    }

    /// Bản dịch mới **đầy đủ** của chương lúc nối — lùi / tua về dòng còn chữ cũ thì thay cả chương bằng bản này.
    struct FullRetranslation {
        let token: Int
        let inputs: TTSManager.RetranslationInputs
        /// `ProcessedChapterDTO.paragraphs` (chưa `expand`), `normalizedContent`, `chapterTitle`.
        let baseParagraphs: [TTSParagraph]
        let content: String
        let title: String
    }

    static let shared = TTSRetranslationCoordinator()

    /// Dòng của chương TTS đang đọc mà chunk còn **chữ cũ** khác bản dịch mới — chỉ các dòng ≤ mốc nối (dòng đang đọc lúc
    /// nối, dòng đã nghe qua, chunk đã xếp sẵn hàng đợi Nghi / VieNeu, tên chương = -1).
    private(set) var staleLineIds: Set<Int> = []
    /// Tăng mỗi lần `TTSManager.paragraphs` được gán (dựng chương, nối bản dịch, đổi cài đặt) — sheet nghe mini dựng lại
    /// danh sách đầu đoạn + "N/M".
    @Published private(set) var layoutRevision = 0
    private(set) var ttsChunkOwner: ChunkOwner?
    private(set) var fullRetranslation: FullRetranslation?
    /// Lượt dịch lại TTS đang chạy (gộp sự kiện → tải → dịch → nối). Lượt mới huỷ lượt cũ.
    var retranslationTask: Task<Void, Never>?

    private init() {}

    /// `didSet` của `TTSManager.paragraphs`.
    func noteTTSParagraphsChanged(owner: ChunkOwner) {
        ttsChunkOwner = owner
        layoutRevision &+= 1
    }

    /// `didSet` của `TTSManager.chapterContent`: chữ chương TTS vừa được dựng / thay ⇒ hết dòng chữ cũ (lượt nối gán chữ
    /// trộn rồi mới công bố tập mới).
    func noteTTSChapterTextChanged() {
        fullRetranslation = nil
        staleLineIds = []
    }

    /// Lượt nối xong: dòng còn chữ cũ (rỗng ⇒ không có) + bản mới đầy đủ cho lượt lùi / tua.
    func recordStaleLines(_ lineIds: Set<Int>, full: FullRetranslation) {
        staleLineIds = lineIds
        fullRetranslation = lineIds.isEmpty ? nil : full
    }

    /// Đọc tiếp từ dòng `line` sẽ gặp dòng chunk chữ cũ (dòng `line` hoặc sau nó) ⇒ lượt lùi / tua phải thay cả chương.
    func needsFullRetranslation(from line: Int) -> Bool {
        staleLineIds.contains { $0 >= line }
    }
}
