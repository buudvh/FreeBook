import SwiftUI

/// Màn "Chọn chương…" của sheet quét tên riêng nhiều chương (1.3.602).
///
/// Chỉ liệt kê các chương **đã tải** (danh sách sheet đã nạp, không đọc lại mục lục). Tìm theo số chương (đánh từ 1,
/// khớp phần đầu: "12" ra ch.12, ch.120…) hoặc theo tên — tên hiển thị (đã dịch khi Reader bật dịch, 1.3.603) lẫn tên
/// gốc; dấu tích ở chương đang chọn, mở ra tự cuộn tới chương đó. Chạm một chương ⇒ báo `onSelect` (chỉ số 0-based)
/// rồi quay lại sheet.
struct ReaderAINameScanChapterPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let chapters: [AINameScanChapter]
    /// Chỉ số 0-based của chương đang chọn (dấu tích + cuộn tới khi mở); `nil` = chưa chọn.
    let selectedIndex: Int?
    let onSelect: (Int) -> Void

    @State private var query: String = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredChapters: [AINameScanChapter] {
        let text = trimmedQuery
        guard !text.isEmpty else { return chapters }
        let isNumber = Int(text) != nil
        return chapters.filter { chapter in
            if isNumber, String(chapter.number).hasPrefix(text) { return true }
            return chapter.title.localizedCaseInsensitiveContains(text)
                || chapter.rawTitle.localizedCaseInsensitiveContains(text)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List(filteredChapters) { chapter in
                row(for: chapter)
                    .id(chapter.index)
            }
            .listStyle(.plain)
            .overlay {
                if filteredChapters.isEmpty {
                    ContentUnavailableView.search(text: trimmedQuery)
                }
            }
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Số chương hoặc tên chương"
            )
            .navigationTitle("Chọn chương bắt đầu")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // `List` chưa dựng xong lúc `onAppear` ⇒ đẩy sang lượt sau mới cuộn được. Đang tìm thì không cuộn.
                guard let selectedIndex, trimmedQuery.isEmpty else { return }
                Task { @MainActor in
                    proxy.scrollTo(selectedIndex, anchor: .center)
                }
            }
        }
    }

    private func row(for chapter: AINameScanChapter) -> some View {
        let isSelected = chapter.index == selectedIndex
        return Button {
            onSelect(chapter.index)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ch.\(chapter.number)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if !chapter.title.isEmpty {
                        Text(chapter.title)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
