import Foundation

/// So sánh mục lục đang lưu với mục lục vừa lấy về để `ChapterStoreDatabase` biết **có cần ghi gì không**.
///
/// Trước đây `replaceFullTOC` luôn mở transaction và `REPLACE` đủ N hàng dù người dùng chỉ kéo-để-tải-lại,
/// nên truyện 2000 chương phải chạy 2000 statement + một pass xoá stale cho một lần refresh không có chương mới.
/// Hàm `plan` ở đây là hàm thuần (không I/O) và **không cấp phát chuỗi nội suy** — so từng field — nên rẻ hơn
/// nhiều so với việc dựng 2×N chuỗi identity như tầng caller từng làm.
///
/// Nguyên tắc an toàn: mọi trường hợp không chắc chắn đều rơi về `.full` (làm đúng như trước khi tối ưu).
internal enum ChapterTOCDiff {
    internal enum Plan: Equatable {
        /// Mục lục mới trùng khít mục lục cũ ⇒ không mở transaction.
        case unchanged
        /// Toàn bộ tiền tố khớp, chỉ có chương mới ở đuôi: chỉ ghi `incoming[tailStart...]`,
        /// và **không** có hàng nào stale để xoá.
        case appendOnly(tailStart: Int)
        /// Có chương bị xoá / đổi vị trí / đổi tiêu đề ⇒ đi đường đối chiếu đầy đủ như cũ.
        case full
    }

    internal static func plan(
        existing: [StoredChapterSnapshot],
        incoming: [ChapterMetadataSnapshot],
        protectedTTS: ProtectedTTSChapter?,
        bookId: String
    ) -> Plan {
        // Chương TTS đang phát chỉ được giữ lại bởi pass xoá stale của nhánh `.full`.
        // Nếu mục lục mới không còn chứa nó thì bắt buộc đi `.full` để pass đó chạy.
        if let prot = protectedTTS, prot.bookId == bookId {
            let stillPresent = incoming.contains { item in
                item.index == prot.index && (prot.url.isEmpty || item.url == prot.url)
            }
            if !stillPresent { return .full }
        }

        // Ít chương hơn trước ⇒ có hàng phải xoá ⇒ `.full`.
        guard incoming.count >= existing.count else { return .full }

        // `existing` đã `ORDER BY chapter_index ASC`, `incoming` đánh index tăng dần từ 0,
        // nên so theo vị trí là so đúng cặp chương.
        for (position, old) in existing.enumerated() {
            let new = incoming[position]
            if old.index != new.index { return .full }
            if old.url != new.url { return .full }
            if old.title != new.title { return .full }
            if (old.host ?? "") != (new.host ?? "") { return .full }
            // `titleTrans` rỗng ở bản mới nghĩa là "giữ giá trị cũ" (xem `replaceFullTOC`), không phải xoá.
            if let newTrans = new.titleTrans, !newTrans.isEmpty, newTrans != old.titleTrans { return .full }
        }

        if incoming.count == existing.count { return .unchanged }
        return .appendOnly(tailStart: existing.count)
    }
}
