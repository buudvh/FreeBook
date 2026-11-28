import SwiftUI

extension DictionaryListView {
    /// bookId dùng cho hướng Chung → Riêng.
    ///
    /// Ở danh sách Riêng thì chính là `bookId` của danh sách; ở danh sách Chung
    /// (`bookId == nil`) thì lấy `contextBookId` — truyện của màn Từ điển đang mở,
    /// truyền xuống từ `DictionaryHubView`. Không bao giờ lấy truyện đang phát TTS,
    /// truyện mở gần nhất hay bất kỳ nguồn "current book" toàn cục nào khác.
    var transferContextBookId: String? { bookId ?? contextBookId }

    /// Tên truyện trong toast chia sẻ / nhập: ba cấp của popup dịch + phồn → giản của truyện đó.
    static func displayTitle(of book: Book) -> String {
        BookDisplayTranslation.text(book.title, BookDisplayTranslation.options(for: book))
    }

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

    /// Đuôi toast sau khi nhập: "thêm X, cập nhật Y" (thay toàn bộ ⇒ số mục mới).
    static func importSummary(_ counts: TranslationDictionaryWriter.ImportCounts, mode: DataImportMode) -> String {
        mode == .replaceAll ? "thay bằng \(counts.added) từ" : "thêm \(counts.added), cập nhật \(counts.updated)"
    }

    func shareToBook(targetBook: Book, mode: DataImportMode) {
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

                let counts = try await TranslationDictionaryWriter.shared.importEntries(
                    from: sourceURL,
                    isName: type == .names,
                    bookId: targetBook.bookId,
                    mode: mode
                )

                let targetTitle = Self.displayTitle(of: targetBook)
                ToastManager.shared.show(
                    message: "Đã chia sẻ \(type.displayName) sang truyện \(targetTitle): \(Self.importSummary(counts, mode: mode))",
                    type: .success
                )
            } catch {
                ToastManager.shared.show(message: "Lỗi chia sẻ: \(error.localizedDescription)", type: .error)
            }
        }
    }

    func importFromBook(sourceBook: Book, mode: DataImportMode) {
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

                let counts = try await TranslationDictionaryWriter.shared.importEntries(
                    from: sourceURL,
                    isName: type == .names,
                    bookId: targetBid,
                    mode: mode
                )

                await loadData()
                let sourceTitle = Self.displayTitle(of: sourceBook)
                ToastManager.shared.show(
                    message: "Đã nhập \(type.displayName) từ truyện \(sourceTitle): \(Self.importSummary(counts, mode: mode))",
                    type: .success
                )
            } catch {
                ToastManager.shared.show(message: "Lỗi nhập từ điển: \(error.localizedDescription)", type: .error)
            }
        }
    }

    /// Nhập file: ngăn kéo "…" mở bộ chọn file trước, chọn xong popup hỏi cách nhập kèm tên file (`dataImportFilePicker`).
    func importFile(from url: URL, mode: DataImportMode) {
        Task {
            do {
                let counts: TranslationDictionaryWriter.ImportCounts
                if let bid = bookId {
                    counts = try await TranslationDictionaryWriter.shared.importEntries(
                        from: url,
                        isName: type == .names,
                        bookId: bid,
                        mode: mode
                    )
                    await loadData()
                } else {
                    counts = try await DictionaryCache.shared.importEntries(from: url, type: type, mode: mode)
                }
                ToastManager.shared.show(message: "Đã nhập \(type.displayName): \(Self.importSummary(counts, mode: mode))", type: .success)
            } catch {
                ToastManager.shared.show(message: "Lỗi import: \(error.localizedDescription)", type: .error)
            }
        }
    }
}