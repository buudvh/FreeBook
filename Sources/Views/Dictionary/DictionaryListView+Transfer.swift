import SwiftUI

extension DictionaryListView {
    /// bookId dùng cho hướng Chung → Riêng.
    ///
    /// Ở danh sách Riêng thì chính là `bookId` của danh sách; ở danh sách Chung
    /// (`bookId == nil`) thì lấy `contextBookId` — truyện của màn Từ điển đang mở,
    /// truyền xuống từ `DictionaryHubView`. Không bao giờ lấy truyện đang phát TTS,
    /// truyện mở gần nhất hay bất kỳ nguồn "current book" toàn cục nào khác.
    var transferContextBookId: String? { bookId ?? contextBookId }

    /// COPY một entry sang phạm vi/loại khác. Nguồn không bị xoá hay sửa;
    /// key trùng ở đích bị ghi đè hoàn toàn (xem `DictionaryEntryTransferAction`).
    func copyEntry(_ entry: DictEntry, to destinationType: DictType, target: DictionaryTransferTarget) {
        Task { @MainActor in
            do {
                try await DictionaryEntryTransferAction.copy(
                    key: entry.key,
                    value: entry.value,
                    destinationType: destinationType,
                    target: target
                )
                let label = DictionaryEntryTransferAction.destinationLabel(
                    destinationType: destinationType,
                    target: target
                )
                ToastManager.shared.show(message: "Đã copy \(entry.key) → \(label)", type: .success)
            } catch {
                ToastManager.shared.show(message: "Lỗi copy: \(error.localizedDescription)", type: .error)
            }
        }
    }

    /// Chạm icon chuyển ở danh sách Chung khi không biết truyện hiện tại: không copy.
    func reportMissingTransferContext() {
        ToastManager.shared.show(
            message: "Không xác định được truyện hiện tại, không thể chuyển qua từ điển riêng",
            type: .error
        )
    }

    func shareToBook(targetBook: Book, isMerge: Bool) {
        guard let sourceBid = bookId, targetBook.bookId != sourceBid else { return }

        Task {
            do {
                let translateDir = TranslationManager.shared.translateDirectory
                let sourceURL = translateDir
                    .appendingPathComponent("books").appendingPathComponent(sourceBid)
                    .appendingPathComponent("\(type.fileName).txt")
                let sourceRecords = (try? DictionaryTextFileStore.parseRecords(from: sourceURL)) ?? []
                guard !sourceRecords.isEmpty else {
                    ToastManager.shared.show(message: "Từ điển này chưa có dữ liệu để chia sẻ.", type: .info)
                    return
                }

                try await TranslationDictionaryWriter.shared.importEntries(
                    from: sourceURL,
                    isName: type == .names,
                    bookId: targetBook.bookId,
                    isMerge: isMerge
                )

                let targetTitle = TranslateUtils.translateBookTitleIfNeeded(targetBook.title, bookId: targetBook.bookId)
                ToastManager.shared.show(
                    message: "Đã chia sẻ \(type.displayName) sang truyện \(targetTitle)",
                    type: .success
                )
            } catch {
                ToastManager.shared.show(message: "Lỗi chia sẻ: \(error.localizedDescription)", type: .error)
            }
        }
    }

    func importFromBook(sourceBook: Book, isMerge: Bool) {
        guard let targetBid = bookId, sourceBook.bookId != targetBid else { return }

        Task {
            do {
                let translateDir = TranslationManager.shared.translateDirectory
                let sourceURL = translateDir
                    .appendingPathComponent("books").appendingPathComponent(sourceBook.bookId)
                    .appendingPathComponent("\(type.fileName).txt")
                let sourceRecords = (try? DictionaryTextFileStore.parseRecords(from: sourceURL)) ?? []
                guard !sourceRecords.isEmpty else {
                    ToastManager.shared.show(message: "Truyện nguồn chưa có dữ liệu từ điển để nhập.", type: .info)
                    return
                }

                try await TranslationDictionaryWriter.shared.importEntries(
                    from: sourceURL,
                    isName: type == .names,
                    bookId: targetBid,
                    isMerge: isMerge
                )

                await loadData()
                let sourceTitle = TranslateUtils.translateBookTitleIfNeeded(sourceBook.title, bookId: sourceBook.bookId)
                ToastManager.shared.show(
                    message: "Đã nhập \(type.displayName) từ truyện \(sourceTitle)",
                    type: .success
                )
            } catch {
                ToastManager.shared.show(message: "Lỗi nhập từ điển: \(error.localizedDescription)", type: .error)
            }
        }
    }
    func importFile(from url: URL, isMerge: Bool) {
        Task {
            do {
                if isGlobal {
                    try await cache.importEntries(from: url, type: type, isMerge: isMerge)
                } else {
                    guard let bid = bookId else { return }
                    try await TranslationDictionaryWriter.shared.importEntries(from: url, isName: type == .names, bookId: bid, isMerge: isMerge)
                    await loadData()
                }
                ToastManager.shared.show(message: "Import thành công!", type: .success)
            } catch {
                ToastManager.shared.show(message: "Lỗi import: \(error.localizedDescription)", type: .error)
            }
        }
    }
}