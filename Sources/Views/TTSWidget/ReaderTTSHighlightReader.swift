import Combine
import Foundation

/// Phần **mịn** của trạng thái TTS cho một Reader: đoạn đang đọc, vệt highlight, vệt chuẩn bị — đổi theo từng câu.
///
/// **Vì sao tách khỏi `ReaderTTSStateReader` (1.3.513).** Trước đây một `@Published snapshot` gộp cả trạng thái thô
/// (đang phát, truyện/chương) lẫn `highlightRange`; ReaderView `@StateObject` nó nên **mỗi nhịp highlight** làm cả
/// thân ReaderView (~2050 dòng) tính lại, kéo theo overlay, danh sách chương và nội dung mọi màn đang trình bày từ
/// Reader. Hệ quả đã gặp thật: sheet đăng nhập Gemini Web bị dựng lại 10 lần/30 s (1.3.512), danh sách chương phải
/// bọc `.equatable()` (1.3.510). Telemetry máy thật: `updateRPM=105.7` khi nghe TTS.
///
/// **Hợp đồng sử dụng**: ReaderView giữ instance bằng `@State` — **không** `@StateObject`/`@ObservedObject`, vì như
/// thế ReaderView sẽ quan sát và lại vẽ lại theo highlight. Chỉ các view con nhỏ quan sát nó:
/// `ReaderTTSHighlightBinder` (mỗi hàng đoạn văn) và `ReaderTTSParagraphChangeObserver` (tự cuộn). Code hành động
/// đọc giá trị tức thời qua `currentParentParagraphIndex` (không subscribe).
///
/// Đoạn đang đọc và các vệt của **truyện khác** gộp thành trống (`scope(to:)`); `playingBookId`/`playingChapterIndex`
/// vẫn là giá trị thật nên truyện khác đổi chương thì các hàng tính lại một lần (rẻ).
@MainActor
final class ReaderTTSHighlightReader: ObservableObject {
    struct Snapshot: Equatable {
        var playingBookId = ""
        var playingChapterIndex = -1
        var currentParentParagraphIndex = -1
        var highlightRange: NSRange?
        var preparingParentParagraphIndex: Int?
        var preparingHighlightRange: NSRange?
    }

    @Published private(set) var snapshot = Snapshot()
    private var scopedBookId: String?
    private var cancellables = Set<AnyCancellable>()
    private let manager: TTSManager

    /// Không đăng ký gì ở đây: `@State(wrappedValue:)` khởi tạo lại instance mỗi lần struct ReaderView được dựng rồi
    /// bỏ đi; đăng ký trong `scope(to:)` (gọi từ `onAppear`, chỉ trên instance thật) để instance thừa hoàn toàn trơ.
    init(manager: TTSManager? = nil) {
        self.manager = manager ?? TTSManager.shared
    }

    /// Đoạn đang đọc của truyện đã scope (-1 nếu TTS không phát truyện này). Đọc tức thời, không subscribe.
    var currentParentParagraphIndex: Int { snapshot.currentParentParagraphIndex }

    func scope(to bookId: String) {
        if cancellables.isEmpty {
            manager.$playbackSnapshot.receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }
                .store(in: &cancellables)
        }
        guard scopedBookId != bookId else { return }
        scopedBookId = bookId
        refresh()
    }

    private func refresh() {
        let ps = manager.playbackSnapshot
        let ownsBook = scopedBookId != nil && scopedBookId == ps.playingBookId
        let next = Snapshot(
            playingBookId: ps.playingBookId,
            playingChapterIndex: ps.playingChapterIndex,
            currentParentParagraphIndex: ownsBook ? ps.currentParentParagraphIndex : -1,
            highlightRange: ownsBook ? ps.highlightRange : nil,
            preparingParentParagraphIndex: ownsBook ? ps.preparingParentParagraphIndex : nil,
            preparingHighlightRange: ownsBook ? ps.preparingHighlightRange : nil
        )
        guard next != snapshot else { return }
        snapshot = next
    }
}
