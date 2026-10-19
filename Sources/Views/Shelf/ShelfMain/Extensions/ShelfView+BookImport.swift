import SwiftUI
import SwiftData

/// Khối nhập truyện từ file của `ShelfView` (TXT / HTML / EPUB / MOBI–AZW3 / PRC / DOCX / FB2 / PDF):
/// copy file vào thư mục tạm, gọi `BookImportService` bóc tách, phân tích lại theo lựa chọn của người
/// dùng, rồi ghi vào `ChapterStore` + `.bin`.
///
/// Tách khỏi `ShelfView.swift` để file gốc trở lại dưới baseline dòng — phần này độc lập với thân
/// `body` và chỉ đọc/ghi các `@State` của màn Kệ sách (vì vậy chúng phải là `internal`, không
/// `private`). Mọi logic bóc tách nằm ở `Sources/Services/Import/`, đây chỉ là tầng điều phối UI.
extension ShelfView {
    // importLocalBook: Copy file người dùng chọn vào thư mục tạm, bóc tách ở tiến trình nền,
    // sau đó hiện sheet xác nhận trước khi thực sự nhập vào CSDL.
    internal func importLocalBook(from url: URL) {
        // startAccessingSecurityScopedResource: iOS yêu cầu cấp quyền tạm thời để truy cập các tệp tin ngoài sandbox của ứng dụng (ví dụ từ app Files)
        let accessing = url.startAccessingSecurityScopedResource()

        // Giữ đúng đuôi file gốc: `BookImportFormat.detect` ưu tiên đuôi trước khi dò magic bytes.
        let fileExtension = url.pathExtension.isEmpty ? "txt" : url.pathExtension.lowercased()
        let tempFileUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
        do {
            if FileManager.default.fileExists(atPath: tempFileUrl.path) {
                try FileManager.default.removeItem(at: tempFileUrl)
            }
            // Sao chép tệp gốc vào thư mục tạm thời của ứng dụng để xử lý an toàn
            try FileManager.default.copyItem(at: url, to: tempFileUrl)
            // Ngừng yêu cầu quyền truy cập bảo mật sau khi sao chép xong
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        } catch {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
            AppLogger.shared.log("❌ Lỗi sao chép file tạm: \(error.localizedDescription)")
            ToastManager.shared.show(message: "Lỗi sao chép file: \(error.localizedDescription)")
            return
        }

        startImportParse(tempFileUrl: tempFileUrl, fileName: url.lastPathComponent, password: nil)
    }

    // startImportParse: Bóc tách file tạm ở tiến trình nền rồi mở sheet xác nhận. Dùng cho cả lần
    // chọn file đầu tiên và lần thử lại sau khi người dùng nhập mật khẩu, nên file tạm chỉ bị xoá
    // khi lỗi **không** phải chuyện thiếu mật khẩu.
    internal func startImportParse(tempFileUrl: URL, fileName: String, password: String?) {
        // Hiện màn hình chờ từ lúc chọn file đến khi phân tích xong
        isParsingImport = true

        // Chạy tiến trình nền để đọc và bóc tách file
        Task.detached(priority: .userInitiated) {
            do {
                let result = try await BookImportService.parse(
                    BookImportService.Request(
                        tempFileUrl: tempFileUrl,
                        fileName: fileName,
                        password: password
                    )
                )

                // Quay lại Main Thread để yêu cầu hiện sheet xác nhận. Giữ wait layer
                // cho đến khi sheet thực sự onAppear để không lộ khoảng trống chuyển tiếp.
                await MainActor.run {
                    self.pendingImport = PendingImport(
                        tempFileUrl: tempFileUrl,
                        fileName: fileName,
                        format: result.format,
                        parsed: result.parsed,
                        autoDecodeID: result.autoDecodeID,
                        matchedRuleIDs: result.matchedRuleIDs,
                        password: password
                    )
                }
            } catch BookImportService.ImportError.passwordRequired {
                await MainActor.run {
                    self.askImportPassword(tempFileUrl: tempFileUrl, fileName: fileName, message: nil)
                }
            } catch BookImportService.ImportError.wrongPassword {
                await MainActor.run {
                    self.askImportPassword(
                        tempFileUrl: tempFileUrl,
                        fileName: fileName,
                        message: "Mật khẩu không đúng, thử lại."
                    )
                }
            } catch {
                try? FileManager.default.removeItem(at: tempFileUrl)
                await MainActor.run {
                    self.isParsingImport = false
                    AppLogger.shared.log("❌ Lỗi xử lý file nhập: \(error.localizedDescription)")
                    ToastManager.shared.show(message: "Lỗi import: \(error.localizedDescription)")
                }
            }
        }
    }

    // askImportPassword: Mở hộp thoại nhập mật khẩu cho tài liệu khoá. Không log mật khẩu.
    internal func askImportPassword(tempFileUrl: URL, fileName: String, message: String?) {
        isParsingImport = false
        importPassword = ""
        pendingPasswordFile = PendingPasswordFile(tempFileUrl: tempFileUrl, fileName: fileName)
        showingPasswordPrompt = true
        if let message {
            ToastManager.shared.show(message: message)
        }
    }

    // submitImportPassword: Thử lại việc bóc tách với mật khẩu người dùng vừa nhập.
    internal func submitImportPassword() {
        guard let pending = pendingPasswordFile else { return }
        let password = importPassword
        pendingPasswordFile = nil
        importPassword = ""
        guard !password.isEmpty else {
            try? FileManager.default.removeItem(at: pending.tempFileUrl)
            return
        }
        startImportParse(tempFileUrl: pending.tempFileUrl, fileName: pending.fileName, password: password)
    }

    // cancelPasswordPrompt: Người dùng bỏ qua tài liệu khoá — xoá file tạm để không rác thư mục tạm.
    internal func cancelPasswordPrompt() {
        if let pending = pendingPasswordFile {
            try? FileManager.default.removeItem(at: pending.tempFileUrl)
        }
        pendingPasswordFile = nil
        importPassword = ""
    }

    // reanalyzeImport: Bóc tách lại file tạm theo bảng mã / quy tắc TOC / cách tách chương
    // người dùng chọn trên sheet. Trả về kết quả mới để sheet cập nhật, `nil` khi thất bại.
    nonisolated internal func reanalyzeImport(
        decodeID: String?,
        ruleIDs: Set<String>,
        structure: BookImportService.StructureMode,
        tempFileUrl: URL,
        fileName: String,
        password: String? = nil
    ) async -> BookImportService.Result? {
        let request = BookImportService.Request(
            tempFileUrl: tempFileUrl,
            fileName: fileName,
            encodingOverride: decodeID.flatMap { TextEncodingOption(rawValue: $0) },
            ruleIDs: ruleIDs,
            structure: structure,
            password: password
        )
        return try? await BookImportService.parse(request)
    }

    // performImport: Thực hiện nhập dữ liệu đã xác nhận vào CSDL dưới dạng một cuốn sách.
    internal func performImport(parsed: ParsedBook, fileName: String, tempFileUrl: URL) {
        self.pendingImport = nil

        // Hiện overlay tiến trình và Toast ban đầu trên Main Thread
        self.isImporting = true
        self.importIsIndeterminate = true
        self.importProgress = 0.0
        self.importStatusText = "Đang chuẩn bị file..."

        let newBookId = UUID().uuidString
        let totalChapters = parsed.chapters.count
        let importChapters = parsed.chapters

        // Quay lại Main Thread để chèn dữ liệu trực tiếp bằng modelContext chính, giúp UI đồng bộ lập tức và cập nhật progress bar mượt mà
        self.importStatusText = "Đang tạo cuốn sách mới..."

        let cmd = AddBookToShelfCommand(
            bookId: newBookId,
            title: parsed.title,
            author: parsed.author ?? "Local",
            coverUrl: parsed.remoteCoverUrl ?? "",
            desc: parsed.desc ?? "Truyện nhập cục bộ từ file \(fileName).",
            detailUrl: "local://\(newBookId)",
            sourceName: "Local",
            sourceUrl: "local://\(newBookId)",
            extensionPackageId: "local",
            currentChapterIndex: 0,
            currentChapterPage: 0,
            currentChapterTitle: "",
            isOnShelf: true,
            isHistory: false,
            host: "local://"
        )
        let createRes = BookTransactionCoordinator.shared.addBookToShelf(command: cmd, in: self.modelContext)
        guard case .success(let newBook) = createRes else {
            self.isImporting = false
            try? FileManager.default.removeItem(at: tempFileUrl)
            ToastManager.shared.show(message: "Lỗi tạo sách local trong CSDL", type: .error)
            return
        }

        // Bìa nhúng trong file: ghi thẳng vào cache bìa local như `BookInfoEditView` đang làm và để
        // `coverUrl` rỗng — `BookCoverView` ưu tiên file bìa local trước `AsyncImage(coverUrl)`.
        if let coverData = parsed.coverData {
            _ = ImageCacheManager.shared.saveCover(data: coverData, for: newBookId)
        }

        // Thực hiện chèn từng chương vào database / ChapterStore
        Task {
            do {
                self.importStatusText = "Đang dịch tên chương..."
                let snapshots = await Task.detached(priority: .userInitiated) {
                    importChapters.enumerated().map { index, chapter in
                        ChapterMetadataSnapshot(
                            title: chapter.title,
                            url: "local://\(newBookId)/chapter/\(index)",
                            index: index,
                            titleTrans: TranslateUtils.translateChapterTitle(
                                chapter.title,
                                bookId: newBookId
                            )
                        )
                    }
                }.value
                _ = try await ChapterStore.shared.replaceFullTOC(bookId: newBookId, chapters: snapshots, protectedTTS: nil)

                self.importIsIndeterminate = false
                for (idx, chapData) in importChapters.enumerated() {
                    let meta = snapshots[idx]
                    let (offset, length) = try await BookBinManager.shared.writeChapterContent(bookId: newBookId, content: chapData.content)

                    try await ChapterStore.shared.upsertCachedChapter(
                        bookId: newBookId,
                        metadata: meta,
                        isCached: true,
                        offset: offset,
                        length: length
                    )

                    if ChapterStoreConfiguration.enableSwiftDataTOCWrite {
                        let res = BookTransactionCoordinator.shared.insertChapterDTO(bookId: newBook.bookId, title: chapData.title, url: meta.url, index: idx, isCached: true, offset: offset, length: length, titleTrans: meta.titleTrans, in: self.modelContext)
                        if case .failure(let err) = res {
                            AppLogger.shared.log("⚠️ [ShelfImport] Failed to insert chapter \(idx): \(err.localizedDescription)")
                        }
                    }

                    // Cập nhật tiến độ sau mỗi 50 chương và nhường thread (sleep 1ms) để tránh treo/khựng UI
                    if idx % 50 == 0 || idx == totalChapters - 1 {
                        let progress = Double(idx + 1) / Double(totalChapters)
                        self.importProgress = progress
                        self.importStatusText = "Đang nhập chương \(idx + 1)/\(totalChapters) (\(Int(progress * 100))%)"
                        try? await Task.sleep(nanoseconds: 1_000_000) // Sleep 1ms
                    }
                }

                self.importStatusText = "Đang ghi dữ liệu xuống bộ nhớ..."
                self.importIsIndeterminate = true

                AppLogger.shared.log("✅ Đã nhập thành công truyện: \(parsed.title) (\(totalChapters) chương)")
                ToastManager.shared.show(message: "Đã nhập thành công: \(TranslateUtils.translateBookTitleIfNeeded(parsed.title, bookId: newBookId))")

                try? FileManager.default.removeItem(at: tempFileUrl)
                self.isImporting = false
                self.selectedTab = .shelf // Chuyển sang Tab Kệ Sách để thấy truyện vừa nhập
            } catch {
                try? FileManager.default.removeItem(at: tempFileUrl)
                self.isImporting = false
                AppLogger.shared.log("❌ Lỗi khi lưu dữ liệu nhập từ file")
                ToastManager.shared.show(message: "Lỗi khi lưu dữ liệu truyện nhập")
            }
        }
    }

    // cancelImport: Hủy bỏ việc nhập, xóa file tạm và đóng sheet xác nhận.
    internal func cancelImport() {
        if let pending = pendingImport {
            try? FileManager.default.removeItem(at: pending.tempFileUrl)
        }
        self.pendingImport = nil
    }
}
