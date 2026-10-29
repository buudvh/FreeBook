import SwiftUI
import SwiftData

/// Sheet tuỳ chọn của tác vụ tải / xuất truyện — mở từ Kệ, Lịch sử, Chi tiết, tab Tải, danh sách chương Reader/comic và
/// trình phát video.
///
/// 1.3.624:
/// - Mở toàn màn (1.3.625 bỏ nửa màn của 1.3.624 theo yêu cầu người dùng).
/// - Đoạn giải thích chuyển vào nút "?" ở tiêu đề từng mục (`TaskOptionsSheet+Help`).
/// - Chọn chương bắt đầu từ mục lục đã dịch, nạp ngầm (`TaskOptionsSheet+StartChapter`).
/// - Nghỉ giữa các lần tải và số luồng, nhớ theo nguồn (`TaskOptionsSheet+Speed`).
struct TaskOptionsSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let book: Book
    let taskType: TaskType

    @State internal var startChoice: StartChoice = .current
    /// `index` của chương tự chọn ở "Chọn chương…" — chỉ có nghĩa khi `startChoice == .custom`.
    @State internal var customStartIndex: Int? = nil
    @State private var limitOption: ChapterLimitOption = .all
    /// Số chương của mốc "Tuỳ chọn" — chỉ có nghĩa khi `limitOption == .custom`.
    @State private var customLimit: Int = 100
    @State private var translateContent = false
    @State internal var onlyExportCached = false
    @State private var displayInShelf = true
    /// Định dạng bản xuất. `taskType` chỉ quyết định đây là tác vụ tải hay xuất; định dạng do người dùng
    /// chọn ở sheet này và được ghi bền qua `BookExportFormat.taskType`.
    @State internal var exportFormat: BookExportFormat = .txt
    /// Số chương đã có cache / tổng số chương — để người dùng biết trước bản xuất offline sẽ thiếu bao nhiêu.
    @State internal var cachedChapterCount: Int? = nil
    @State internal var totalChapterCount: Int? = nil
    /// Mục lục đã nạp (`nil` = đang nạp). `.task` của màn gốc chạy lại mỗi lần quay về từ "Chọn chương…".
    @State internal var tocChapters: [StoredChapterSnapshot]? = nil
    /// Danh sách cho màn chọn chương, tên đã dịch (`nil` = đang nạp/dịch).
    @State internal var pickerChapters: [AINameScanChapter]? = nil
    /// Nghỉ giữa các lần tải + số luồng của nguồn; ghi lại khi bấm "Bắt đầu".
    @State internal var speed: DownloadSpeedSettings
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false
    /// Chất lượng tải video — lựa chọn chung, tác vụ đọc lúc chạy (`VideoDownloadQuality`).
    @AppStorage(VideoDownloadQuality.defaultsKey) private var videoQuality: VideoDownloadQuality = VideoDownloadQuality.defaultValue
    /// Tải phim (`DownloadManager+Video`): tiêu đề "Tải video", dòng Chất lượng, giải thích riêng. Nhãn "tập" và sidecar
    /// tập bắt đầu theo **loại sách** (`contentKind == .video`) để xuất video cũng dùng.
    internal let isVideo: Bool
    /// Loại nội dung của nguồn: truyện tranh/video bỏ dòng tiêu đề nhóm ở mục lục, dấu "đã tải" đọc từ manifest.
    internal let contentKind: ExtensionContentKind
    /// Chỉ truyện chữ của tiện ích JS được chọn số luồng (Legado luôn 1 luồng — `DownloadManager+ChapterLanes`).
    internal let supportsLanes: Bool

    init(book: Book, taskType: TaskType, defaultOnlyExportCached: Bool = false) {
        self.book = book
        self.taskType = taskType
        let kind = ExtensionContentKind.resolve(packageId: book.extensionPackageId)
        self.isVideo = !taskType.isExport && kind == .video
        self.contentKind = kind
        let isLegado = ExtensionLibraryRepository.snapshot(packageId: book.extensionPackageId)
            .map { SourceRuntime.shared.isLegado(localPath: $0.localPath) } ?? false
        self.supportsLanes = !kind.isMedia && !isLegado
        // Xuất truyện tranh / video chỉ lấy chương/tập đã tải (không có mạng) ⇒ luôn "chỉ chương đã tải", ẩn mục tốc độ.
        let isMediaExport = taskType.isExport && kind.isMedia
        self._onlyExportCached = State(initialValue: defaultOnlyExportCached || isMediaExport)
        // 5 lối mở xuất đều truyền `.exportTxt` ⇒ đổi sang định dạng đầu tiên hợp với loại sách (truyện tranh: CBZ).
        let formats = BookExportFormat.formats(for: kind)
        let requested = taskType.exportFormat ?? .txt
        self._exportFormat = State(initialValue: formats.contains(requested) ? requested : (formats.first ?? requested))
        self._speed = State(initialValue: DownloadSpeedSettings.load(packageId: book.extensionPackageId))
    }

    internal var unitNoun: String { contentKind == .video ? "tập" : "chương" }

    private var sheetTitle: String { isVideo ? "Tải video" : effectiveTaskType.rawValue }

    /// Tác vụ này có tạo file hay chỉ tải cache.
    internal var isExport: Bool { taskType.isExport }

    /// Xuất truyện tranh ra CBZ/PDF: không dịch, không tải thêm — chỉ chương đã có ảnh offline.
    internal var isComicExport: Bool { isExport && contentKind == .comic }

    /// Xuất video (`DownloadManager+VideoExport`): chỉ tập đã tải về máy, không dịch, không tải thêm.
    internal var isVideoExport: Bool { isExport && contentKind == .video }

    /// Loại tác vụ thật sự được đưa vào hàng đợi — với tác vụ xuất, nó theo định dạng đang chọn.
    private var effectiveTaskType: TaskType {
        return isExport ? exportFormat.taskType : taskType
    }

    var body: some View {
        NavigationStack {
            Form {
                bookInfoSection

                if isExport {
                    Section {
                        Picker("Định dạng", selection: $exportFormat) {
                            ForEach(BookExportFormat.formats(for: contentKind), id: \.self) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                        .pickerStyle(.menu)
                    } header: {
                        helpHeader("Định dạng bản xuất", paragraphs: [LocalizedStringKey(exportFormat.summary)])
                    }
                }

                startChapterSection

                taskOptionsSection

                if showsSpeedSection {
                    speedSection
                }
            }
            .pageTitle(sheetTitle)
            .task {
                await loadChapterCatalog()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bắt đầu") {
                        startTask()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        // Toàn màn (1.3.625): người dùng bỏ nửa màn của 1.3.624 — đừng thêm lại `.medium`.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var bookInfoSection: some View {
        Section {
            HStack(spacing: 16) {
                BookCoverView(bookId: book.bookId, coverUrl: book.coverUrl, width: 60, height: 84, host: book.host, extensionPackageId: book.extensionPackageId)
                    .cornerRadius(6)
                    .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text(displayedBookTitle)
                        .font(.headline)
                        .lineLimit(2)

                    if !displayedAuthor.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "person.fill")
                                .font(.caption)
                            Text(displayedAuthor)
                                .lineLimit(1)
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }

                    Text("\(book.sourceName)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(4)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(contentKind == .video ? "Thông tin phim" : "Thông tin truyện")
        }
    }

    private var taskOptionsSection: some View {
        Section {
            ChapterLimitPicker.optionPicker(option: $limitOption, noun: unitNoun)

            if limitOption == ChapterLimitOption.custom {
                ChapterLimitPicker.customRow(customLimit: $customLimit, noun: unitNoun)
            }

            if isVideo {
                Picker("Chất lượng", selection: $videoQuality) {
                    ForEach(VideoDownloadQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
                .pickerStyle(.menu)
            }

            if isExport {
                if !isComicExport && !isVideoExport {
                    Toggle("Chỉ xuất chương đã tải", isOn: $onlyExportCached)
                        .toggleStyle(SwitchToggleStyle(tint: Color(white: 0.35)))

                    Toggle("Dịch nội dung", isOn: $translateContent)
                        .toggleStyle(SwitchToggleStyle(tint: Color(white: 0.35)))
                }

                if let cachedPreview {
                    Text(cachedPreview)
                        .font(.caption)
                        .foregroundColor(onlyExportCached && (totalChapterCount ?? 0) > (cachedChapterCount ?? 0) ? .orange : .secondary)
                }
            }

            Toggle("Hiển thị trong Kệ sách", isOn: $displayInShelf)
                .toggleStyle(SwitchToggleStyle(tint: Color(white: 0.35)))
        } header: {
            helpHeader("Tùy chọn tác vụ", paragraphs: taskOptionsHelpParagraphs)
        }
    }

    private var displayedBookTitle: String {
        let title = isTranslationEnabled && TranslateUtils.containsChinese(book.title)
            ? TranslateUtils.translateMeta(book.title, bookId: book.bookId)
            : book.title
        return DisplayTextFormatter.titleCase(title)
    }

    private var displayedAuthor: String {
        let author = isTranslationEnabled ? TranslateUtils.translateAuthorHanViet(book.author) : book.author
        return DisplayTextFormatter.titleCase(author)
    }

    /// Dòng xem trước "đã tải X/Y chương" (video: "tập"), `nil` khi chưa đọc được mục lục.
    private var cachedPreview: String? {
        guard let cached = cachedChapterCount, let total = totalChapterCount, total > 0 else { return nil }
        if cached >= total {
            return "Đã tải đủ \(total) \(unitNoun) — bản xuất sẽ không thiếu \(unitNoun) nào."
        }
        return "Đã tải \(cached)/\(total) \(unitNoun) — thiếu \(total - cached) \(unitNoun)."
    }

    /// Giới hạn thật đưa vào hàng đợi: mốc "Tuỳ chọn" được quy đổi thành số chương đang kéo.
    private var effectiveLimit: ChapterLimitOption {
        limitOption == ChapterLimitOption.custom
            ? ChapterLimitOption(rawValue: ChapterLimitOption.clampCustom(customLimit))
            : limitOption
    }

    private func startTask() {
        let placementResult = displayInShelf
            ? BookTransactionCoordinator.shared.setOnShelf(bookId: book.bookId, isOnShelf: true, in: modelContext)
            : BookTransactionCoordinator.shared.removeFromShelf(bookId: book.bookId, in: modelContext)
        if case .failure(let err) = placementResult {
            AppLogger.shared.log("❌ [TaskOptionsSheet] Lỗi cập nhật vị trí hiển thị truyện: \(err.localizedDescription)")
        }

        // Sidecar chương bắt đầu ghi **trước** `enqueueTask`: tác vụ có thể chạy ngay khi vào hàng đợi.
        let taskId = UUID()
        if startChoice == .custom, let index = customStartIndex {
            // Tải và xuất video cùng đọc tập bắt đầu ở `VideoDownloadRequestStore` (`videoEpisodesToDownload`).
            if contentKind == .video {
                VideoDownloadRequestStore.setStartEpisode(index, taskId: taskId)
            } else {
                DownloadStartChapterStore.setStartChapter(index, taskId: taskId)
            }
        }
        if showsSpeedSection {
            DownloadSpeedSettings.save(speed, packageId: book.extensionPackageId)
        }

        DownloadManager.shared.enqueueTask(
            book: book,
            taskType: effectiveTaskType,
            startFromCurrent: startChoice == .current,
            limit: effectiveLimit,
            translate: translateContent,
            onlyExportCached: onlyExportCached,
            container: modelContext.container,
            taskId: taskId
        )

        ToastManager.shared.show(message: "Đã thêm tác vụ '\(sheetTitle)' vào hàng đợi.")
    }
}
