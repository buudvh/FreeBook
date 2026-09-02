import SwiftUI

/// Danh sách một từ điển tham chiếu, có tìm kiếm và tải thêm theo trang.
///
/// Cùng khuôn với `DictionaryListView`: `searchable`, đếm hiển thị/tổng, và nạp thêm 100 mục khi cuộn
/// tới cuối — để hai màn hình cảm giác giống nhau. Khác một điểm: **không** có thêm/sửa/xoá, vì ba bộ
/// này không đi qua đường CRUD một-từ (`TranslationManager` không ghi vào `.dat` và
/// `ChinesePhienAmWords.txt`), nên một nút Lưu ở đây sẽ không có tác dụng thật.
struct ReferenceDictionaryListView: View {
    let kind: ReferenceDictionaryReader.Kind

    @State private var entries: [DictEntry] = []
    @State private var hasTextFile = true
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var visibleCount = 100

    private static let pageSize = 100

    private var matched: [DictEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.key.lowercased().contains(query) || $0.value.lowercased().contains(query)
        }
    }

    private var visible: [DictEntry] {
        Array(matched.prefix(visibleCount))
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Đang đọc \(kind.title)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard isLoading else { return }
            let outcome = ReferenceDictionaryReader.load(kind)
            entries = outcome.entries
            hasTextFile = outcome.hasTextFile
            isLoading = false
        }
    }

    private var content: some View {
        List {
            Section {
                Text(countText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if entries.isEmpty {
                Section {
                    Text(emptyReason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(visible) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.key)
                            .font(.headline)
                        Text(entry.value)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = "\(entry.key)=\(entry.value)"
                        } label: {
                            Label("Sao chép dòng", systemImage: "doc.on.doc")
                        }
                    }
                    .onAppear {
                        if entry.id == visible.last?.id, visibleCount < matched.count {
                            visibleCount += Self.pageSize
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Tìm khoá hoặc nghĩa…")
        .onChange(of: searchText) { _, _ in
            visibleCount = Self.pageSize
        }
    }

    private var countText: String {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return visible.count < entries.count
                ? "Hiển thị \(visible.count)/\(entries.count) mục. Cuộn xuống để tải thêm."
                : "Đã hiển thị toàn bộ \(entries.count) mục."
        }
        return visible.count < matched.count
            ? "Hiển thị \(visible.count)/\(matched.count) kết quả. Cuộn xuống để tải thêm."
            : "\(matched.count) kết quả."
    }

    private var emptyReason: String {
        if !hasTextFile && kind.loadedCount > 0 {
            return "Bộ này đang dùng bản nhị phân (.dat) nên không liệt kê được từng mục — \(kind.loadedCount) mục vẫn đang hoạt động khi dịch. Muốn xem danh sách thì đặt file \(kind.textFileName) vào thư mục dịch."
        }
        if kind.loadedCount == 0 {
            return "Chưa nạp bộ này. Tải từ điển mặc định hoặc nhập file \(kind.textFileName)."
        }
        return "Không đọc được \(kind.textFileName)."
    }
}
