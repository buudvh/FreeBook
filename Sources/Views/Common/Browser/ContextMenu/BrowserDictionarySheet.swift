import SwiftUI

/// Sheet "Tra từ điển" của trình duyệt (mockup "Mới 7"): tiêu đề = từ đang tra; "Câu" = token của câu chứa từ (token
/// đang tra viền sáng, chạm token khác để tra); "Hán Việt", "VietPhrase", "Names" theo màu chip của Reader (từ điển
/// chung, badge C). Chỉ tra, không sửa nghĩa. Mọi phép tra chạy ngoài main (`BrowserDictionaryLookup`).
struct BrowserDictionarySheet: View {
    let request: BrowserLookupRequest

    @State private var lookup: BrowserDictionaryLookup?
    @State private var isLoading = true
    /// Lượt tra mới nhất — chạm token liên tiếp thì kết quả cũ về muộn không đè kết quả mới.
    @State private var generation = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
            .pageTitle(title)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .task { await resolve() }
    }

    private var title: String {
        guard let word = lookup?.word, !word.isEmpty else { return "Tra từ điển" }
        return word
    }

    @ViewBuilder
    private var content: some View {
        if let lookup {
            VStack(alignment: .leading, spacing: 14) {
                section("Câu") {
                    FlowLayout(spacing: 5) {
                        ForEach(lookup.tokens) { token in
                            tokenView(token, isFocused: lookup.isFocused(token))
                        }
                    }
                }
                section("Hán Việt") {
                    if let hanViet = lookup.hanViet, !hanViet.isEmpty {
                        chips([SuggestionChip(text: hanViet, category: .hanViet)])
                    } else {
                        emptyText
                    }
                }
                section("VietPhrase") { chipsOrEmpty(lookup.vietPhrase) }
                section("Names") { chipsOrEmpty(lookup.names) }
            }
        } else if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        } else {
            Text("Không tra được vùng chọn")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        }
    }

    // MARK: - Khối giao diện

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tokenView(_ token: TranslationWordToken, isFocused: Bool) -> some View {
        Button {
            focus(token)
        } label: {
            Text(token.originalText.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Color.primary.opacity(isFocused ? 0.18 : 0.07),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay {
                    if isFocused {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.6), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isFocused ? .isSelected : [])
    }

    @ViewBuilder
    private func chipsOrEmpty(_ items: [SuggestionChip]) -> some View {
        if items.isEmpty {
            emptyText
        } else {
            chips(items)
        }
    }

    /// Chip kiểu Reader (`MeaningSuggestionChipRow`) nhưng xuống dòng thay vì cuộn ngang, không bấm được (chỉ tra).
    /// Chừa `ChipCornerBadge.inset` phía trên/phải cho badge nhô ra.
    private func chips(_ items: [SuggestionChip]) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(items) { chip in
                Text(chip.text)
                    .font(.system(size: 14.5))
                    .foregroundColor(chip.category.textColor)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.12, green: 0.12, blue: 0.15), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(chip.category.borderColor, lineWidth: 1.3))
                    .overlay(alignment: .topTrailing) {
                        if let scope = chip.scope {
                            ChipCornerBadge(scope: scope)
                        }
                    }
                    .textSelection(.enabled)
            }
        }
        .padding(.top, ChipCornerBadge.inset)
        .padding(.trailing, ChipCornerBadge.inset)
    }

    private var emptyText: some View {
        Text("Không có")
            .font(.system(size: 13.5))
            .foregroundStyle(.tertiary)
    }

    // MARK: - Tra

    private func resolve() async {
        let request = self.request
        let result = await Task.detached(priority: .userInitiated) {
            BrowserDictionaryLookup.resolve(request)
        }.value
        lookup = result
        isLoading = false
    }

    private func focus(_ token: TranslationWordToken) {
        guard let current = lookup else { return }
        let word = token.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isFocused(token), current.word == word { return }
        generation += 1
        let ticket = generation
        Task {
            let next = await Task.detached(priority: .userInitiated) {
                current.focusing(token)
            }.value
            guard ticket == generation else { return }
            lookup = next
        }
    }
}
