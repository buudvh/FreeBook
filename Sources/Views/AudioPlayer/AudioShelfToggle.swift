import Foundation
import SwiftData

/// Nút ♡ của màn nghe: bật / tắt "Trên kệ" cho album đang mở — ghi qua `BookTransactionCoordinator` (View không ghi
/// SwiftData). Bỏ kệ = `removeFromShelf` (album về Lịch sử như "Bỏ khỏi kệ" ở Kệ), **không** `setOnShelf(false)` (hạ cả
/// cờ Lịch sử ⇒ album biến khỏi cả hai tab) — như `VideoWatchModel.toggleShelf`. `Book` do trình nghe tạo khi nạp xong mục
/// lục; chưa có ⇒ `.notReady` (toast thuộc View).
@MainActor
enum AudioShelfToggle {
    enum Outcome: Equatable {
        case added
        case removed
        case notReady
        case failed(String)
    }

    /// Trạng thái kệ hiện tại: `nil` = album chưa có `Book`.
    static func shelfState(session: AudioPlaybackSession) -> Bool? {
        session.fetchBook().map(\.isOnShelf)
    }

    static func toggle(session: AudioPlaybackSession) -> Outcome {
        guard let book = session.fetchBook(), let context = session.modelContainer?.mainContext else {
            return .notReady
        }
        let bookId = book.bookId
        let wasOnShelf = book.isOnShelf
        let result = wasOnShelf
            ? BookTransactionCoordinator.shared.removeFromShelf(bookId: bookId, in: context)
            : BookTransactionCoordinator.shared.setOnShelf(bookId: bookId, isOnShelf: true, in: context)
        switch result {
        case .success:
            AppLogger.shared.log("🎵 [AudioPlayerUI] \(wasOnShelf ? "Bỏ album khỏi kệ" : "Thêm album vào kệ") (bookId=\(bookId))")
            return wasOnShelf ? .removed : .added
        case .failure(let error):
            AppLogger.shared.log("❌ [AudioPlayerUI] Không đổi được trạng thái kệ: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }
}
