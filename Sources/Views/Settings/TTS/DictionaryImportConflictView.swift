import SwiftUI

/// Màn **danh sách mục trùng khoá nhưng khác nghĩa** khi nhập từ điển theo kiểu **Trộn**.
///
/// ## Skeleton hiện NGAY, việc nặng chạy ngầm
/// Màn mở **trước** khi biết file có gì: `.task` đọc file + parse + so khớp trong `Task.detached`, còn
/// `body` chỉ vẽ skeleton ~8 dòng. Với từ điển NghiTTS (~30k mục) parse trên main sẽ chặn UI đúng lúc người
/// dùng vừa bấm — đó là thứ màn này tránh.
///
/// ## Huỷ = KHÔNG ghi gì
/// View **không** tự ghi vào từ điển. Nó chỉ trả bảng cuối qua `onApply`, và caller ghi **sau khi** view đã
/// `dismiss()`. Nhờ vậy thoát màn giữa chừng không bao giờ để lại dữ liệu ghi dở.
struct DictionaryImportConflictView: View {
    enum Phase {
        case loading
        case ready(DictionaryImportDiff.Summary)
        case failed(String)
    }

    @Environment(\.dismiss) var dismiss

    let fileURL: URL
    let title: String
    /// Phải là `@Sendable` vì nó được capture trong `Task.detached` ở `loadDiff()`.
    let normalizedKey: @Sendable (String) -> String
    let current: [String: String]
    let onApply: ([String: String]) -> Void

    @State private var phase: Phase = .loading
    @State private var imported: [String: String] = [:]
    @State private var selection: Set<String> = []
    @State private var searchText = ""

    /// Khai `init` **tường minh**: các `@State` ở trên là `private`, nên `init` memberwise do compiler sinh
    /// sẽ mang mức truy cập `private` và **không** gọi được từ `DictionaryImportFlowModifier.swift`.
    init(
        fileURL: URL,
        title: String,
        normalizedKey: @escaping @Sendable (String) -> String,
        current: [String: String],
        onApply: @escaping ([String: String]) -> Void
    ) {
        self.fileURL = fileURL
        self.title = title
        self.normalizedKey = normalizedKey
        self.current = current
        self.onApply = onApply
    }

    /// Mục đang hiển thị sau khi lọc theo ô tìm kiếm — thao tác "Chọn hết" tác động lên **danh sách đang
    /// nhìn thấy**, không phải toàn bộ, để lọc rồi chọn nhanh một nhóm.
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
                    RoundedRectangle(cornerRadius: 4).frame(width: 160, height: 11)
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
                .foregroundColor(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Danh sách

    private func list(_ summary: DictionaryImportDiff.Summary) -> some View {
        List {
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
                Text("\(summary.conflicts.count) mục trùng · \(summary.newKeys.count) mục thêm mới · \(summary.keptCount) mục giữ nguyên")
            } footer: {
                Text("Mục **bỏ chọn** giữ nguyên cách đọc đang có trên máy. Mục **thêm mới** và mục trùng mà nghĩa giống hệt luôn được áp.")
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Tìm từ")
    }

    private func row(_ conflict: DictionaryImportDiff.Conflict) -> some View {
        Toggle(isOn: Binding(
            get: { selection.contains(conflict.key) },
            set: { isOn in
                if isOn { selection.insert(conflict.key) } else { selection.remove(conflict.key) }
            }
        )) {
            VStack(alignment: .leading, spacing: 3) {
                Text(conflict.key)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text("cũ: \(conflict.currentValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("mới: \(conflict.importedValue)")
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Huỷ") { dismiss() }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if case .ready = phase {
                Button(allVisibleSelected ? "Bỏ chọn hết" : "Chọn hết") { toggleVisibleSelection() }
                    .disabled(visibleConflicts.isEmpty)

                Button("Áp dụng (\(selection.count))") { apply() }
                    .disabled(selection.isEmpty)
            }
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

    /// Đọc file + parse + so khớp **ngoài main thread**.
    ///
    /// Giữ quyền truy cập security-scoped tới khi parse xong rồi mới nhả — `DocumentPicker` dùng
    /// `asCopy: true` nên thực tế là file trong sandbox, nhưng nhả sớm vẫn là bẫy đã trả giá.
    private func loadDiff() async {
        guard case .loading = phase else { return }
        let url = fileURL
        let keyNormalizer = normalizedKey
        let snapshot = current

        let outcome = await Task.detached(priority: .userInitiated) {
            () -> (words: [String: String]?, summary: DictionaryImportDiff.Summary?, message: String?) in
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let words = try DictionaryImportParser.parse(url: url)
                let summary = DictionaryImportDiff.diff(imported: words, current: snapshot, normalizedKey: keyNormalizer)
                return (words, summary, nil)
            } catch {
                return (nil, nil, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }.value

        if let words = outcome.words, let summary = outcome.summary {
            imported = words
            selection = Set(summary.conflicts.map(\.key))
            phase = .ready(summary)
        } else {
            phase = .failed(outcome.message ?? "Không đọc được file từ điển.")
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
