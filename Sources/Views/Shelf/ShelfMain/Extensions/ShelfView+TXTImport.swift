import SwiftUI
import SwiftData

/// Khối nhập truyện từ file TXT của `ShelfView`: đọc/giải mã file, tách chương, phân tích lại theo bảng mã hoặc
/// quy tắc TOC người dùng chọn, rồi ghi vào `ChapterStore` + `.bin`.
///
/// Tách khỏi `ShelfView.swift` để file gốc trở lại dưới baseline dòng — phần này độc lập với thân `body` và
/// chỉ đọc/ghi các `@State` của màn Kệ sách (vì vậy chúng phải là `internal`, không `private`).
extension ShelfView {
    nonisolated private func parseTxtBook(content: String, fileName: String, rules: [TOCRule]? = nil) -> ParsedBook {
        let lines = content.components(separatedBy: "\n")
        var chapters: [ParserChapter] = []
        var currentChapterTitle = "Mở đầu"
        var currentChapterLines: [String] = []

        let activeRules = rules ?? TranslateUtils.getActiveTOCRules()
        let compiledTOCRegexes = activeRules.compactMap { try? NSRegularExpression(pattern: $0.rule, options: [.caseInsensitive]) }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let isChapterTitle = TranslateUtils.isChapterHeaderLine(line, compiledTOCRegexes: compiledTOCRegexes)

            if isChapterTitle {
                if !currentChapterLines.isEmpty || currentChapterTitle != "Mở đầu" {
                    chapters.append(ParserChapter(
                        title: currentChapterTitle,
                        content: currentChapterLines.joined(separator: "\n")
                    ))
                }
                currentChapterTitle = trimmed
                currentChapterLines.removeAll()
            } else {
                currentChapterLines.append(trimmed)
            }
        }

        if !currentChapterLines.isEmpty || currentChapterTitle != "Mở đầu" {
            chapters.append(ParserChapter(
                title: currentChapterTitle,
                content: currentChapterLines.joined(separator: "\n")
            ))
        }

        var bookTitle = fileName.replacingOccurrences(of: ".txt", with: "", options: .caseInsensitive)
        if bookTitle.isEmpty {
            bookTitle = "Truyện nhập cục bộ"
        }

        return ParsedBook(title: bookTitle, chapters: chapters)
    }

    // importTxtBook: Đọc + giải mã + parse file TXT, sau đó hiện sheet xác nhận
    // trước khi thực sự nhập vào CSDL (tránh import nhầm/sai cấu trúc).
    internal func importTxtBook(from url: URL) {
        // startAccessingSecurityScopedResource: iOS yêu cầu cấp quyền tạm thời để truy cập các tệp tin ngoài sandbox của ứng dụng (ví dụ từ app Files)
        let accessing = url.startAccessingSecurityScopedResource()

        // Tạo một đường dẫn tệp tạm thời trong thư mục temp của ứng dụng
        let tempFileUrl = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
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

        // Hiện màn hình chờ từ lúc chọn file đến khi phân tích xong
        isParsingTXT = true

        // Chạy tiến trình nền để đọc và parse file TXT
        Task.detached(priority: .userInitiated) {
            do {
                let data = try Data(contentsOf: tempFileUrl)

                // Hỗ trợ giải mã với nhiều bảng mã (TextEncodingDecoder thử tuần tự UTF-8/BOM,
                // các mã đa byte CJK, mã đơn byte; tránh nuốt nhầm file tiếng Trung)
                let decodedContent = TextEncodingDecoder.decode(data)
                guard !decodedContent.isEmpty else {
                    throw NSError(domain: "ImportError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Định dạng file không hỗ trợ hoặc lỗi mã hóa ký tự."])
                }

                let fileName = url.lastPathComponent

                // Xác định bảng mã tự động được chọn (để đánh dấu active trong picker)
                let autoDecodeID = TextEncodingDecoder.detect(data)?.rawValue

                // Thực hiện phân tích nội dung thành các chương (Parser)
                let parsed = self.parseTxtBook(content: decodedContent, fileName: fileName)
                guard !parsed.chapters.isEmpty else {
                    throw NSError(domain: "ImportError", code: 2, userInfo: [NSLocalizedDescriptionKey: "File văn bản không chứa nội dung hoặc cấu trúc chương hợp lệ."])
                }

                // Các quy tắc TOC khớp với nội dung file (để đánh dấu active trong picker)
                let matchedRuleIDs = TranslateUtils.matchingRuleIDs(in: decodedContent, rules: TranslateUtils.getAllTOCRules())

                // Quay lại Main Thread để yêu cầu hiện sheet xác nhận. Giữ wait layer
                // cho đến khi sheet thực sự onAppear để không lộ khoảng trống chuyển tiếp.
                await MainActor.run {
                    self.pendingImport = PendingImport(
                        tempFileUrl: tempFileUrl,
                        fileName: fileName,
                        parsed: parsed,
                        autoDecodeID: autoDecodeID,
                        matchedRuleIDs: matchedRuleIDs
                    )
                }
            } catch {
                try? FileManager.default.removeItem(at: tempFileUrl)
                await MainActor.run {
                    self.isParsingTXT = false
                    AppLogger.shared.log("❌ Lỗi xử lý file TXT: \(error.localizedDescription)")
                    ToastManager.shared.show(message: "Lỗi import: \(error.localizedDescription)")
                }
            }
        }
    }

    // reanalyzeTxt: Đọc lại file tạm, giải mã theo bảng mã đã chọn và phân tích
    // chương theo các quy tắc TOC đã chọn. Trả về kết quả mới để sheet cập nhật.
    nonisolated internal func reanalyzeTxt(decodeID: String?, ruleIDs: Set<String>, tempFileUrl: URL, fileName: String) async -> TXTReanalysisResult? {
        guard let data = try? Data(contentsOf: tempFileUrl) else { return nil }

        // Giải mã: mã cụ thể nếu người dùng chọn, ngược lại tự động (thứ tự ưu tiên có sẵn)
        let decodedContent: String
        if let decodeID, let option = TextEncodingOption(rawValue: decodeID) {
            guard let text = TextEncodingDecoder.decode(data, using: option), !text.isEmpty else { return nil }
            decodedContent = text
        } else {
            decodedContent = TextEncodingDecoder.decode(data)
        }
        guard !decodedContent.isEmpty else { return nil }

        // Quy tắc TOC: tập hợp cụ thể nếu người dùng chọn, ngược lại dùng quy tắc đang bật
        let activeRules: [TOCRule]
        if ruleIDs.isEmpty {
            activeRules = TranslateUtils.getActiveTOCRules()
        } else {
            activeRules = TranslateUtils.getAllTOCRules().filter { ruleIDs.contains($0.id) }
        }

        let parsed = parseTxtBook(content: decodedContent, fileName: fileName, rules: activeRules)
        guard !parsed.chapters.isEmpty else { return nil }

        let autoDecodeID = TextEncodingDecoder.detect(data)?.rawValue
        let matchedRuleIDs = TranslateUtils.matchingRuleIDs(in: decodedContent, rules: TranslateUtils.getAllTOCRules())

        return TXTReanalysisResult(
            parsed: parsed,
            autoDecodeID: autoDecodeID,
            matchedRuleIDs: matchedRuleIDs
        )
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
            author: "Local",
            coverUrl: "",
            desc: "Truyện nhập cục bộ từ file \(fileName).",
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
                self.selectedTab = 1 // Chuyển sang Tab Kệ Sách để thấy truyện vừa nhập
            } catch {
                try? FileManager.default.removeItem(at: tempFileUrl)
                self.isImporting = false
                AppLogger.shared.log("❌ Lỗi khi lưu dữ liệu nhập TXT")
                ToastManager.shared.show(message: "Lỗi khi lưu dữ liệu TXT")
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
