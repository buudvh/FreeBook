import SwiftUI

/// Màn **chọn từng mục cần thay** khi áp kết quả "Phiên âm lại" theo kiểu **Trộn**.
///
/// So file kết quả (`phien-am-lai-*.plist`) với từ điển **đang dùng** và chỉ hỏi những mục **trùng khoá
/// nhưng khác nghĩa**; khoá mới được **thêm tự động**, khoá chỉ có trên máy **giữ nguyên**.
///
/// ## Skeleton hiện NGAY, việc nặng chạy ngầm
/// Màn mở **trước** khi biết file có gì: `.task` đọc từ điển + parse file + so khớp trong `Task.detached`,
/// còn `body` chỉ vẽ skeleton tám dòng. Với từ điển NghiTTS (~30k mục) mà parse trên main sẽ đơ UI đúng lúc
/// người dùng vừa bấm.
///
/// ## Tự đọc từ điển, **không** nhận ảnh chụp từ caller
/// `currentProvider` được gọi **bên trong** `Task.detached` ngay lúc màn mở. Nếu nhận một bảng chụp sẵn từ
/// caller cờ "cũ" có thể đã lỗi thời ở thời điểm người dùng bấm Áp dụng — và lúc đó mục bị bỏ chọn sẽ bị
/// ghi **đè** bằng giá trị cũ của một bản chụp cũ.
///
/// ## Huỷ = KHÔNG ghi gì
/// View **không** tự ghi vào từ điển. Nó trả bảng cuối qua `onApply`, và caller ghi **sau khi** view đã
/// `dismiss()` — nhờ vậy thoát màn giữa chừng không bao giờ để lại dữ liệu ghi dở.
struct DictionaryImportConflictView: View {
    enum Phase {
        case loading
        case ready(DictionaryImportDiff.Summary)
        case failed(String)
    }

    @Environment(\.dismiss) var dismiss

    let fileURL: URL
    let title: String
    /// Phải `@Sendable` vì nó được capture trong `Task.detached` ở `loadDiff()`.
    let normalizedKey: @Sendable (String) -> String
    /// Đọc từ điển **đang dùng** — chạy ngầm, xem doc ở đầu type.
    let currentProvider: @Sendable () async -> [String: String]
    let onApply: ([String: String]) -> Void

    @State private var phase: Phase = .loading
    @State private var current: [String: String] = [:]
    @State private var imported: [String: String] = [:]
    @State private var selection: Set<String> = []
    @State private var searchText = ""

    /// Màu nhấn **riêng của màn này**: không dùng `Color.accentColor` vì app đặt `.tint(.white)` toàn cục
    /// (`MainTabView.swift:38`) ⇒ accent có thể là trắng và mất hẳn chữ trên nền sáng (1.3.447).
    private let accent = Color(red: 0.204, green: 0.780, blue: 0.349)

    /// Khai `init` **tường minh**: các `@State` ở trên là `private`, nên `init` memberwise do compiler sinh
    /// sẽ mang mức truy cập `private` và **không** gọi được từ file khác.
    init(
        fileURL: URL,
        title: String,
        normalizedKey: @escaping @Sendable (String) -> String,
        currentProvider: @escaping @Sendable () async -> [String: String],
        onApply: @escaping ([String: String]) -> Void
    ) {
        self.fileURL = fileURL
        self.title = title
        self.normalizedKey = normalizedKey
        self.currentProvider = currentProvider
        self.onApply = onApply
    }

    /// Mục đang hiển thị sau khi lọc theo ô tìm kiếm — "Chọn hết" tác động lên **danh sách đang nhìn thấy**,
    /// không phải toàn bộ, để lọc rồi chọn nhanh một nhóm.
    private var visibleConflicts: [DictionaryImportDiff.Conflict] {
        guard case .ready(let summary) = phase else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return summary.conflicts }
        return summary.conflicts.filter { $0.key.contains(query) }
    }

    private var allVisibleSelected: Bool {
        !visibleConflicts.isEmpty && visibleConflicts.allSatisfy { selection.contains($0.key) }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .task { await loadDiff() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            skeleton
        case .failed(let message):
            failure(message)
        case .ready(let summary):
            list(summary)
        }
    }

    // MARK: - Skeleton

    /// Khung xám trong lúc đọc file. Vẽ bằng khối hình thay vì `redacted` để không phải bịa chữ giả.
    private var skeleton: some View {
        List {
            ForEach(0..<8, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).frame(width: 120, height: 14)
                    RoundedRectangle(cornerRadius: 4).frame(width: 190, height: 11)
                }
                .foregroundStyle(Color.secondary.opacity(0.35))
                .padding(.vertical, 2)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Color.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Danh sách

    private func list(_ summary: DictionaryImportDiff.Summary) -> some View {
        List {
            Section {
                chips(summary)
                filterRow
            }

            Section {
                if visibleConflicts.isEmpty {
                    Text(summary.conflicts.isEmpty
                         ? "Không có mục nào trùng khoá mà khác nghĩa."
                         : "Không mục nào khớp \"\(searchText)\".")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleConflicts) { conflict in
                        row(conflict)
                    }
                }
            } header: {
                Text("Trùng khoá — bấm một dòng để chọn")
            } footer: {
                Text("Chạm cả dòng để chọn/bỏ. Mục **bỏ chọn** giữ nguyên cách đọc đang có. Khoá mới được thêm tự động.")
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Tìm từ")
    }

    /// Hàng chip tóm tắt — thay cho câu chữ dài ở `header`: đọc số liệu nhanh hơn và không chiếm hai dòng.
    private func chips(_ summary: DictionaryImportDiff.Summary) -> some View {
        HStack(spacing: 6) {
            chip("\(summary.conflicts.count) trùng", color: Color.orange)
            chip("\(summary.newKeys.count) thêm mới", color: accent)
            chip("\(summary.keptCount) giữ nguyên", color: Color.secondary)
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.vertical, 2)
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(Capsule().stroke(color.opacity(0.45), lineWidth: 0.5))
    }

    /// Hàng lọc: nút chọn/bỏ chọn tác động lên **danh sách đang nhìn thấy** (ô tìm kiếm nằm ở nav).
    private var filterRow: some View {
        HStack(spacing: 8) {
            Text(selection.count == 0 ? "Chưa chọn mục nào" : "Đã chọn \(selection.count) mục")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button(allVisibleSelected ? "Bỏ chọn hết" : "Chọn hết") { toggleVisibleSelection() }
                .font(.caption)
                .buttonStyle(.bordered)
                .disabled(visibleConflicts.isEmpty)
        }
    }

    /// Một dòng: khoá ở tầng trên, rồi `cách đọc hiện tại → cách đọc mới` trên **cùng một dòng** để so
    /// được trực tiếp (bản cũ xếp hai dòng riêng nên scroll nhiều mà vẫn khó so).
    private func row(_ conflict: DictionaryImportDiff.Conflict) -> some View {
        let isSelected = selection.contains(conflict.key)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17))
                .foregroundStyle(isSelected ? accent : Color.secondary.opacity(0.55))

            VStack(alignment: .leading, spacing: 2) {
                Text(conflict.key)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Text(conflict.currentValue)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(conflict.importedValue)
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
        // Bỏ `Toggle`: chạm **cả dòng** để chọn/bỏ — diện tích bấm lớn hơn hẳn cái công tắc nhỏ ở đầu dòng.
        .contentShape(Rectangle())
        .onTapGesture { toggle(conflict.key) }
        // Nền `nil` (mặc định) không viết được trong toán tử ba ngôi ⇒ dùng đúng màu nền của `.insetGrouped`.
        .listRowBackground(isSelected ? accent.opacity(0.12) : Color(.systemGroupedBackground))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Huỷ") { dismiss() }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if case .ready = phase {
                Button("Áp dụng (\(selection.count))") { apply() }
                    .fontWeight(.semibold)
                    .disabled(selection.isEmpty)
            }
        }
    }

    private func toggle(_ key: String) {
        if selection.contains(key) {
            selection.remove(key)
        } else {
            selection.insert(key)
        }
    }

    private func toggleVisibleSelection() {
        if allVisibleSelected {
            for conflict in visibleConflicts { selection.remove(conflict.key) }
        } else {
            for conflict in visibleConflicts { selection.insert(conflict.key) }
        }
    }

    // MARK: - Nạp & áp

    /// Đọc từ điển đang dùng + parse file kết quả + so khớp, tất cả **ngoài main thread**.
    private func loadDiff() async {
        guard case .loading = phase else { return }
        let url = fileURL
        let keyNormalizer = normalizedKey
        let provider = currentProvider

        let outcome = await Task.detached(priority: .userInitiated) {
            () -> (words: [String: String]?, current: [String: String]?, summary: DictionaryImportDiff.Summary?, message: String?) in
            do {
                let snapshot = await provider()
                let words = try DictionaryImportParser.parse(url: url)
                let summary = DictionaryImportDiff.diff(
                    imported: words,
                    current: snapshot,
                    normalizedKey: keyNormalizer
                )
                return (words, snapshot, summary, nil)
            } catch {
                return (nil, nil, nil, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }.value

        if let words = outcome.words, let snapshot = outcome.current, let summary = outcome.summary {
            current = snapshot
            imported = words
            selection = Set(summary.conflicts.map(\.key))
            phase = .ready(summary)
        } else {
            phase = .failed(outcome.message ?? "Không đọc được file kết quả phiên âm lại.")
        }
    }

    private func apply() {
        let merged = DictionaryImportDiff.merged(
            current: current,
            imported: imported,
            selection: selection,
            normalizedKey: normalizedKey
        )
        onApply(merged)
        dismiss()
    }
}
