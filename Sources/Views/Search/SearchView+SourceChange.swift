import SwiftUI
import SwiftData

extension SearchView {
    /// Lượt đổi nguồn đã xác nhận ở alert. Việc nặng (mục lục, chép chương theo lô, dọn truyện cũ, khôi phục khi app chết)
    /// nằm ở `BookSourceChangeCoordinator` (1.3.689); ở đây chỉ chụp giá trị truyện cũ, hiện tiến trình, toast và điều hướng.
    func executeSourceChange(to result: ExtensionItemResult, ext: Extension) async {
        guard let oldBook = changeSourceTargetBook else { return }

        // Chụp **giá trị** ngay: instance `Book` cũ sẽ bị xoá ở cuối lượt, không đọc lại nó sau khi bắt đầu.
        let oldBookId = oldBook.bookId
        let oldPackageId = oldBook.extensionPackageId
        let isPlayingTTS = (TTSManager.shared.isPlaying || TTSManager.shared.showFloatingWidget) && TTSManager.shared.playingBookId == oldBookId
        let request = BookSourceChangeCoordinator.Request(
            oldBookId: oldBookId,
            oldTitle: oldBook.title,
            oldChapterIndex: oldBook.currentChapterIndex,
            oldIsOnShelf: oldBook.isOnShelf,
            oldIsHistory: oldBook.isHistory,
            oldLastReadDate: oldBook.lastReadDate,
            keepsOldBook: isPlayingTTS,
            result: result,
            ext: ext
        )
        let container = modelContext.container
        defer { sourceChangeStatus = "" }

        do {
            try BookSourceMigrator.ensureSameContentKind(oldPackageId: oldPackageId, newPackageId: ext.packageId)
        } catch {
            // Lỗi "khác loại nội dung" không phải lỗi tải trang ⇒ không gắn "Mở link lỗi".
            AppLogger.shared.log("❌ Lỗi đổi nguồn truyện: \(error.localizedDescription)")
            searchStatusMessage = "Lỗi đổi nguồn: \(error.localizedDescription)"
            statusErrorLink = nil
            return
        }

        // Lượt tìm mọi nguồn còn chạy giành luồng JS và vẽ lại danh sách kết quả suốt lúc chép chương.
        searchTask?.cancel()
        resetSearchPaging()

        // Phim của truyện cũ đang phát (màn xem, hub, PiP) ⇒ dừng hẳn trước: lượt đổi nguồn xoá truyện cũ mà phiên phát
        // còn giữ id của nó (lưu tiến độ, bản tải, server đã nhớ).
        if VideoPlaybackSession.shared.launch?.bookId == oldBookId {
            AppLogger.shared.log("🎬 [VideoPlayer] Đổi nguồn phim đang phát ⇒ dừng phim trước")
            VideoPlaybackSession.shared.stop()
        }

        do {
            let outcome = try await BookSourceChangeCoordinator.shared.run(request, container: container) { status in
                sourceChangeStatus = status
            }
            AIRuntimeCoordinator.shared.migrateLastSession(from: oldBookId, to: outcome.newBookId)
            showSourceChangeToast(outcome, extName: ext.name)

            // Gửi `ShelfTab.rawValue` chứ không phải số trần — xem `ShelfTab`.
            let targetShelfTab = (outcome.isOnShelf ? ShelfTab.shelf : ShelfTab.history).rawValue
            NotificationCenter.default.post(
                name: NSNotification.Name("sourceChangedNavigateToShelf"),
                object: nil,
                userInfo: ["shelfTab": targetShelfTab]
            )
            // Đóng các màn đang giữ `Book` cũ — coordinator chờ `finishDelayNanoseconds` rồi mới xoá truyện cũ.
            onSourceChanged?()
        } catch {
            AppLogger.shared.log("❌ Lỗi đổi nguồn truyện: \(error.localizedDescription)")
            searchStatusMessage = "Lỗi đổi nguồn: \(error.localizedDescription)"
            guard !(error is BookSourceChangeCoordinator.Failure) else {
                statusErrorLink = nil
                return
            }
            let bookHost = ExtensionHostResolver.nonEmpty(result.host) ?? ext.sourceUrl
            attachStatusErrorLink(error, fallbacks: [result.link, ext.sourceUrl], host: bookHost,
                                  retry: .sourceChange(result: result, ext: ext), packageId: ext.packageId)
        }
    }

    private func showSourceChangeToast(_ outcome: BookSourceChangeCoordinator.Outcome, extName: String) {
        let report = outcome.copyReport
        if report.failed > 0 {
            ToastManager.shared.show(
                message: "Chép lỗi \(report.failed)/\(report.total) chương đã tải sang '\(extName)', đã giữ lại truyện cũ",
                type: .error
            )
        } else if outcome.keptOldBook {
            ToastManager.shared.show(message: "Đã thêm nguồn mới '\(extName)' vào kệ sách!", type: .success)
        } else {
            let copiedNote = report.copied > 0 ? ", chép \(report.copied) chương đã tải" : ""
            let target = outcome.reusedExistingBook ? "truyện có sẵn ở nguồn" : "nguồn"
            ToastManager.shared.show(message: "Đã đổi sang \(target) '\(extName)'\(copiedNote)", type: .success)
        }
    }
}
