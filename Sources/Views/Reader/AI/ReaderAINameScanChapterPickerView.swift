import SwiftUI

/// Màn "Chọn chương…" của sheet quét tên riêng nhiều chương (1.3.602), dùng lại ở mục "Bắt đầu từ" của sheet tải/xuất
/// (`TaskOptionsSheet`, 1.3.624).
///
/// Liệt kê đúng danh sách caller đã nạp, không đọc lại mục lục: sheet quét tên đưa chương **đã tải**, sheet tải/xuất
/// đưa **cả mục lục**. `noun` = "tập" với video (tiêu đề, ô tìm, nhãn số). Tìm theo số chương (đánh từ 1,
/// khớp phần đầu: "12" ra ch.12, ch.120…) hoặc theo tên — tên hiển thị (đã dịch khi Reader bật dịch, 1.3.603) lẫn tên
/// gốc; dấu tích ở chương đang chọn, mở ra tự cuộn tới chương đó. Chạm một chương ⇒ báo `onSelect` (chỉ số 0-based)
/// rồi quay lại sheet.
struct ReaderAINameScanChapterPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let chapters: [AINameScanChapter]
    /// "chương" hoặc "tập".
    var noun: String = "chương"
    /// Chỉ số 0-based của chương đang chọn (dấu tích + cuộn tới khi mở); `nil` = chưa chọn.
    let selectedIndex: Int?
    let onSelect: (Int) -> Void

    @State private var query: String = ""

    /// Nhãn số đứng trước tên: "ch.12" (chương) hoặc "tập 12".
    private var numberPrefix: String {
        noun == "chương" ? "ch." : "\(noun) "
    }

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
                prompt: "Số \(noun) hoặc tên \(noun)"
            )
            .backPageTitle("Chọn \(noun) bắt đầu")
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
                    Text("\(numberPrefix)\(chapter.number)")
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
                // Cùng kiểu icon "đã tải" của danh sách chương Reader / Chi tiết truyện / mục lục comic (1.3.627).
                if chapter.isCached {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                        .accessibilityLabel("Đã tải")
                }
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
