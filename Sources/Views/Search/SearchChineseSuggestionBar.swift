import SwiftUI

/// Hàng chip **"Chữ Hán:"** ngay dưới ô tìm của `SearchView` (tìm một nguồn và mọi nguồn): gõ âm Hán Việt
/// (`đấu phá thương khung`) ⇒ tối đa 6 cách viết chữ Hán (`ChineseQuerySuggester`), cuộn ngang. Không tự đổi gì —
/// bấm Tìm vẫn tìm đúng chữ đã gõ; chạm chip ⇒ `onPick(chữ Hán)` (ô tìm thành chữ đó và tìm ngay).
///
/// Tính ngoài main sau khi ngừng gõ 300 ms; gõ tiếp ⇒ `.task(id:)` huỷ lượt cũ và kết quả muộn bị bỏ. Truy vấn chắc
/// chắn không có gợi ý (rỗng, đã có chữ Hán, một âm tiết…) ⇒ ẩn ngay, không chờ debounce, để không còn chip cũ bấm
/// được cho truy vấn mới.
struct SearchChineseSuggestionBar: View {
    let query: String
    let onPick: (String) -> Void

    @State private var suggestions: [String] = []

    private static let suggestionLimit = 6
    private static let debounceNanoseconds: UInt64 = 300_000_000

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        content
            .task(id: trimmedQuery) { await refresh(for: trimmedQuery) }
    }

    /// Luôn có một view (kể cả khi không có chip) để `.task(id:)` chạy được.
    @ViewBuilder
    private var content: some View {
        if suggestions.isEmpty {
            Color.clear.frame(height: 0)
        } else {
            HStack(spacing: 8) {
                Text("Chữ Hán:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { chip($0) }
                    }
                    .padding(.trailing, 16)
                    .padding(.vertical, 2)
                }
            }
            .padding(.leading, 16)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
        }
    }

    private func chip(_ text: String) -> some View {
        Button {
            hideKeyboard()
            onPick(text)
        } label: {
            Text(text)
                .font(.subheadline)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .foregroundColor(.accentColor)
                .background(Color.accentColor.opacity(0.18))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.accentColor.opacity(0.6), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tìm bằng chữ Hán \(text)")
    }

    @MainActor
    private func refresh(for query: String) async {
        guard ChineseQuerySuggester.syllables(of: query) != nil else {
            suggestions = []
            return
        }
        try? await Task.sleep(nanoseconds: Self.debounceNanoseconds)
        guard !Task.isCancelled else { return }
        // Hàm tra là đồng bộ: gọi thẳng từ `.task` vẫn chạy trên main ⇒ đẩy sang luồng nền rồi quay lại gán.
        let limit = Self.suggestionLimit
        let result = await Task.detached(priority: .userInitiated) {
            ChineseQuerySuggester.suggestions(for: query, limit: limit)
        }.value
        guard !Task.isCancelled else { return }
        suggestions = result
    }
}
