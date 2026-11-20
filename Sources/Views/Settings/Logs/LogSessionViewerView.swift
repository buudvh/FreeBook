import SwiftUI

/// Màn **Xem log** của một phiên (1.3.1015, anh Bửu: "nhấn giữ một phiên sẽ hiển thị các option xem log, xoá log, xuất
/// log" — duyệt mockup). Mở từ menu nhấn giữ phiên ở `LogSettingsView`.
///
/// - Thẻ đầu = khối đầu phiên như file xuất (`AppLogger.loadSessionHeader`).
/// - Chip "Tất cả / Chỉ lỗi (N)" + chip đảo thứ tự "Mới nhất trước / Cũ nhất trước"; ô lọc chữ luôn hiện (lọc sau 300 ms,
///   lọc ở SQLite — `AppLogDatabase.lines(sessionId:cursor:…)`).
/// - Mỗi dòng: giờ `HH:mm:ss.SSS` + nội dung, chữ đơn cách 11pt; dòng ❌ chữ đỏ, nền đỏ mờ. Nhấn giữ dòng ⇒ "Sao chép dòng".
/// - Nạp `AppLogger.browsePageSize` dòng mỗi lượt, tới chân danh sách thì nạp tiếp (`LoadMoreFooter`, id cố định).
/// - Nút chia sẻ góc phải = xuất cả phiên ra `.txt` (cùng đường với màn danh sách phiên).
struct LogSessionViewerView: View {
    let session: AppLogger.SessionSummary

    private struct ExportFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    @State private var headerLines: [String] = []
    @State private var lines: [AppLogger.LogLineItem] = []
    @State private var hasMore = true
    @State private var isLoading = false
    /// Tăng mỗi lần đổi bộ lọc / thứ tự ⇒ trang của lượt cũ về muộn bị bỏ.
    @State private var generation = 0
    @State private var onlyErrors = false
    @State private var newestFirst = true
    @State private var searchText = ""
    @State private var appliedQuery = ""
    @State private var isExporting = false
    @State private var exportFile: ExportFile?

    var body: some View {
        List {
            Section {
                headerCard
                filterChips
            }
            Section {
                ForEach(lines) { line in
                    lineRow(line)
                }
                LoadMoreFooter(
                    phase: hasMore ? .loading : .finished(lines.isEmpty ? "Không có dòng nào" : "Hết · \(lines.count.formatted()) dòng"),
                    token: lines.count,
                    onAppear: loadMore
                )
                .id("log-viewer-footer")
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Lọc dòng chứa…")
        .task(id: searchText) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed != appliedQuery else { return }
            appliedQuery = trimmed
            reload()
        }
        .backPageTitle("Log \(Self.dayTime(session.startedAt))")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: export) {
                    if isExporting {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .frame(width: 36, height: 38)
                .disabled(isExporting)
                .accessibilityLabel("Xuất log (.txt)")
            }
        }
        .sheet(item: $exportFile) { file in
            ShareSheet(activityItems: [file.url])
        }
        .onAppear {
            if headerLines.isEmpty {
                AppLogger.shared.loadSessionHeader(sessionId: session.id) { headerLines = $0 }
            }
            if lines.isEmpty, !isLoading { reload() }
        }
    }

    // MARK: - Phần đầu

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            if headerLines.isEmpty {
                Text("Đang đọc…")
            } else {
                ForEach(Array(headerLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private var filterChips: some View {
        HStack(spacing: 6) {
            chip("Tất cả", isSelected: !onlyErrors) { setOnlyErrors(false) }
            chip("Chỉ lỗi (\(session.errorCount.formatted()))", isSelected: onlyErrors) { setOnlyErrors(true) }
            Spacer(minLength: 0)
            chip(newestFirst ? "Mới nhất trước" : "Cũ nhất trước", isSelected: true) {
                newestFirst.toggle()
                reload()
            }
        }
    }

    /// Chip kiểu `ExtensionKindFilterBar`: đang chọn = chữ màu nhấn, nền nhấn mờ 18%, viền 60%. `.borderless` vì nhiều nút
    /// chung một hàng `List`.
    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.08), in: Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Dòng

    private func lineRow(_ line: AppLogger.LogLineItem) -> some View {
        let time = Self.timeFormatter.string(from: line.ts)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(time)
                .foregroundStyle(.secondary)
            Text(line.text)
                .foregroundStyle(line.isError ? Color.red : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, design: .monospaced))
        .listRowBackground(line.isError ? Color.red.opacity(0.12) : nil)
        .contextMenu {
            Button {
                ClipboardCopier.copy("[\(time)] \(line.text)", message: "Đã sao chép dòng log")
            } label: {
                Label("Sao chép dòng", image: AppGlyph.copy.assetName)
            }
        }
    }

    // MARK: - Nạp

    private func setOnlyErrors(_ value: Bool) {
        guard onlyErrors != value else { return }
        onlyErrors = value
        reload()
    }

    private func reload() {
        generation &+= 1
        lines = []
        hasMore = true
        isLoading = false
        loadMore()
    }

    private func loadMore() {
        guard hasMore, !isLoading else { return }
        isLoading = true
        let token = generation
        AppLogger.shared.loadLines(
            sessionId: session.id,
            cursor: lines.last?.id,
            newestFirst: newestFirst,
            onlyErrors: onlyErrors,
            contains: appliedQuery
        ) { page in
            guard token == generation else { return }
            lines.append(contentsOf: page)
            hasMore = page.count == AppLogger.browsePageSize
            isLoading = false
        }
    }

    private func export() {
        guard !isExporting else { return }
        isExporting = true
        AppLogger.shared.exportSessions([session.id]) { url in
            isExporting = false
            guard let url else {
                ToastManager.shared.show(message: "Không xuất được log", type: .error)
                return
            }
            exportFile = ExportFile(url: url)
        }
    }

    // MARK: - Định dạng

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm dd/MM"
        return formatter
    }()

    static func dayTime(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }
}
