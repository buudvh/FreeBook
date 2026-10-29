import SwiftUI
import SwiftData

/// Nhập truyện tranh (một file CBZ/ZIP = cả bộ) và phim (một/nhiều file MP4/MOV/M4V = một phim) từ bộ chọn file của
/// Kệ sách — tầng điều phối UI; việc nặng nằm ở `Sources/Services/Import/Media/`.
///
/// - `onPick` của bộ chọn file chỉ **ghi lại** các file (`queuedPickedFiles`); việc thật chạy khi sheet bộ chọn đã đóng
///   hẳn (`onDismiss`, dự phòng 1 giây nếu `onDismiss` không tới) — mở sheet xác nhận lúc sheet bộ chọn còn đang trượt
///   xuống thì sheet mới không hiện (cùng lý do với `queuedImportChoice`).
/// - Phân loại theo đuôi (`LocalMediaImportRoute`): sách chữ đi luồng cũ `importLocalBook`; chọn nhiều file lẫn loại ⇒
///   báo lỗi, không nhập gì.
/// - Sách được tạo **trước** (qua `BookTransactionCoordinator`, như truyện chữ) rồi mới chuyển ảnh/phim; lỗi giữa chừng
///   ⇒ xoá hẳn sách bằng `BookStorageManager` (dọn `comics/`/`videos/`, mục lục, bìa) để không còn sách dở.
@MainActor
extension ShelfView {
    // MARK: - Bộ chọn file

    internal func queuePickedFiles(_ urls: [URL]) {
        queuedPickedFiles = urls
        // Dự phòng: `onDismiss` của sheet bộ chọn không tới thì vẫn chạy (hàm tự bỏ qua khi hàng chờ đã rỗng).
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            runQueuedPickedFiles()
        }
    }

    internal func runQueuedPickedFiles() {
        let urls = queuedPickedFiles
        queuedPickedFiles = []
        guard let route = LocalMediaImportRoute.route(for: urls) else { return }
        switch route {
        case .text(let url):
            importLocalBook(from: url)
        case .comic(let url):
            prepareMediaImport(log: "truyện tranh") {
                let plan = try LocalComicImporter.prepare(pickedURL: url)
                await MainActor.run { self.pendingComicImport = plan }
            }
        case .video(let urls):
            prepareMediaImport(log: "phim") {
                let plan = try LocalVideoImporter.prepare(pickedURLs: urls)
                await MainActor.run { self.pendingVideoImport = plan }
            }
        case .rejected(let message):
            LocalMediaImportRoute.discardPickedCopies(urls)
            AppLogger.shared.log("⚠️ [MediaImport] Từ chối \(urls.count) file: \(message)")
            ToastManager.shared.show(message: message, type: .error)
        }
    }

    /// Chuẩn bị (giải nén / nhận file) ở tiến trình nền dưới overlay "Đang phân tích file..."; sheet xác nhận tắt overlay
    /// khi hiện.
    private func prepareMediaImport(log kind: String, _ work: @escaping @Sendable () async throws -> Void) {
        isParsingImport = true
        Task.detached(priority: .userInitiated) {
            do {
                try await work()
            } catch {
                await MainActor.run {
                    self.isParsingImport = false
                    AppLogger.shared.log("❌ [MediaImport] Lỗi chuẩn bị nhập \(kind): \(error.localizedDescription)")
                    ToastManager.shared.show(message: "Lỗi nhập \(kind): \(error.localizedDescription)", type: .error)
                }
            }
        }
    }

    // MARK: - Sheet xác nhận

    /// Hai sheet xác nhận, gắn trên một view rỗng trong `ZStack` của Kệ sách để `ShelfView.swift` chỉ thêm một dòng.
    internal var mediaImportSheetHost: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .sheet(item: $pendingComicImport) { plan in
                LocalComicImportSheet(
                    plan: plan,
                    onConfirm: { title in performComicImport(plan, title: title) },
                    onDiscard: { LocalMediaImportWorkspace.discard(plan.workDirectory) }
                )
                .onAppear { isParsingImport = false }
            }
            .sheet(item: $pendingVideoImport) { plan in
                LocalVideoImportSheet(
                    plan: plan,
                    onConfirm: { title in performVideoImport(plan, title: title) },
                    onDiscard: { LocalMediaImportWorkspace.discard(plan.workDirectory) }
                )
                .onAppear { isParsingImport = false }
            }
    }

    // MARK: - Nhập

    private func performComicImport(_ plan: LocalComicImportPlan, title: String) {
        pendingComicImport = nil
        let workDirectory = plan.workDirectory
        performMediaImport(
            title: title,
            packageId: LocalMediaPackage.comicPackageId,
            desc: "Truyện tranh nhập từ file \(plan.fileName).",
            unit: "chương",
            workDirectory: workDirectory
        ) { bookId, progress in
            try await LocalComicImporter.commit(plan, bookId: bookId, progress: progress)
        }
    }

    private func performVideoImport(_ plan: LocalVideoImportPlan, title: String) {
        pendingVideoImport = nil
        performMediaImport(
            title: title,
            packageId: LocalMediaPackage.videoPackageId,
            desc: "Phim nhập từ \(plan.episodes.count) file video trên máy.",
            unit: "tập",
            workDirectory: plan.workDirectory
        ) { bookId, progress in
            try await LocalVideoImporter.commit(plan, bookId: bookId, progress: progress)
        }
    }

    /// Tạo sách (`url` `local://` giữ `isLocalBook`, `host` nil để manifest khớp URL chương thô) rồi chạy `commit` ngoài
    /// main với tiến độ trên overlay nhập truyện (`BookImportProgressCenter`).
    private func performMediaImport(
        title: String,
        packageId: String,
        desc: String,
        unit: String,
        workDirectory: URL,
        commit: @escaping @Sendable (String, @escaping @Sendable (Int, Int) async -> Void) async throws -> Data?
    ) {
        let bookId = UUID().uuidString
        let progressCenter = BookImportProgressCenter.shared
        progressCenter.begin(title: title, message: "Đang tạo sách mới...")

        let command = AddBookToShelfCommand(
            bookId: bookId,
            title: title,
            author: "Local",
            coverUrl: "",
            desc: desc,
            detailUrl: "local://\(bookId)",
            sourceName: "Local",
            sourceUrl: "local://\(bookId)",
            extensionPackageId: packageId,
            currentChapterIndex: 0,
            currentChapterPage: 0,
            currentChapterTitle: "",
            isOnShelf: true,
            isHistory: false,
            host: nil
        )
        guard case .success = BookTransactionCoordinator.shared.addBookToShelf(command: command, in: modelContext) else {
            progressCenter.end()
            LocalMediaImportWorkspace.discard(workDirectory)
            AppLogger.shared.log("❌ [MediaImport] Không tạo được sách \(packageId) trong CSDL")
            ToastManager.shared.show(message: "Lỗi tạo sách trong CSDL", type: .error)
            return
        }

        let container = modelContext.container
        Task {
            do {
                let coverData = try await Task.detached(priority: .userInitiated) {
                    try await commit(bookId) { done, total in
                        await MainActor.run {
                            BookImportProgressCenter.shared.update(
                                message: "Đang nhập \(unit) \(done)/\(total)",
                                fraction: total > 0 ? Double(done) / Double(total) : nil
                            )
                        }
                    }
                }.value
                if let coverData {
                    _ = ImageCacheManager.shared.saveCover(data: coverData, for: bookId)
                }
                LocalMediaImportWorkspace.discard(workDirectory)
                progressCenter.end()
                AppLogger.shared.log("✅ [MediaImport] Đã nhập \(packageId): \(title)")
                ToastManager.shared.show(message: "Đã nhập thành công: \(title)", type: .success)
                self.selectedTab = .shelf
            } catch {
                LocalMediaImportWorkspace.discard(workDirectory)
                do {
                    try await BookStorageManager.shared.deleteBookAsync(bookId: bookId, container: container)
                } catch {
                    AppLogger.shared.log("❌ [MediaImport] Không xoá được sách nhập dở \(bookId): \(error.localizedDescription)")
                }
                progressCenter.end()
                AppLogger.shared.log("❌ [MediaImport] Lỗi nhập \(packageId): \(error.localizedDescription)")
                ToastManager.shared.show(message: "Lỗi nhập: \(error.localizedDescription)", type: .error)
            }
        }
    }
}
