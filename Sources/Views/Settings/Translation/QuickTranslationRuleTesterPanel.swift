import SwiftUI

/// Ruột ô thử rule: dán một câu Trung → xem text sau rewrite và **rule nào khớp ở offset nào**. Chỉ gồm các `Section`
/// — chỗ dùng bọc trong `Form`: trang đẩy "Thử nhanh một câu" (`QuickTranslationRuleTesterView`, có chọn chế độ token)
/// và sheet "Thử rule" mở từ đầu danh sách rule (`QuickTranslationRuleTesterSheet`).
///
/// Bộ rule áp theo `scope` của chỗ mở (`QuickTranslationRuleEngine.preview(_:scope:contextBookId:mode:)`): chung ⇒ bộ
/// chung; tên chương ⇒ bộ tên chương + chung; riêng ⇒ bộ riêng của truyện + chung, với `bookId` của truyện. Danh sách
/// chung / tên chương **mở từ Reader** (`contextBookId`) kèm thêm bộ riêng của truyện đang đọc — kết quả như lúc đọc
/// truyện đó (anh Bửu chốt "Kèm bộ riêng"); mở từ Cài đặt thì không. Mẫu của từng hit tra
/// theo cặp (bộ, dòng) của đoạn (`Segment.scopeRank`) — trước đây chỉ tra trong bộ chung nên hit của bộ riêng hiện sai
/// mẫu hoặc trống.
struct QuickTranslationRuleTesterPanel: View {
    let scope: QuickTranslationRuleScope
    /// Truyện đang đọc khi danh sách chung / tên chương mở từ Reader; `nil` = mở từ Cài đặt.
    var contextBookId: String? = nil
    /// Trang đẩy có section chọn chế độ token; sheet gọn chỉ chạy theo cấu hình token hiện hành.
    var showsTokenModePicker = false

    /// Truyện mà ô thử áp bộ riêng + cấu hình riêng: chính truyện của bộ riêng, không thì truyện đang đọc.
    private var testBookId: String? {
        scope.bookId ?? contextBookId.flatMap { $0.isEmpty ? nil : $0 }
    }

    private struct Hit: Identifiable {
        let id = UUID()
        let sourceLine: Int
        let scopeLabel: String
        let source: String
        let rendered: String
        let offset: Int
        let pattern: String
    }

    @State private var input = ""
    @State private var output = ""
    @State private var hits: [Hit] = []
    @State private var didRun = false
    @State private var previewMode: QuickTranslationRuleEngine.PreviewMode = .respectTokenConfiguration

    var body: some View {
        Section {
            TextEditor(text: $input)
                .frame(minHeight: 90)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)

            Button("Chạy thử") { run() }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            SectionHelpHeader("Câu tiếng Trung", paragraphs: scopeHelp)
        }

        if showsTokenModePicker {
            Section {
                Picker("Áp dụng token", selection: $previewMode) {
                    Text("Theo cấu hình token")
                        .tag(QuickTranslationRuleEngine.PreviewMode.respectTokenConfiguration)
                    Text("Bỏ qua cấu hình token")
                        .tag(QuickTranslationRuleEngine.PreviewMode.ignoreTokenConfiguration)
                }
                .pickerStyle(.menu)
            } header: {
                SectionHelpHeader("Chế độ token", paragraphs: ["Cả hai chế độ đều thử rule trực tiếp, không phụ thuộc công tắc tổng Quick Translate. Nhưng ô thử **tôn trọng file tắt rule**: rule đã tắt sẽ không khớp ở đây, đúng như khi đọc."])
            }
            .onChange(of: previewMode) { _, _ in
                if didRun { run() }
            }
        }

        if didRun {
            Section(header: Text("Kết quả")) {
                Text(output.isEmpty ? "(rỗng)" : output)
                    .font(.footnote)
                    .textSelection(.enabled)
            }

            Section(header: Text("Rule đã khớp (\(hits.count))")) {
                if hits.isEmpty {
                    Text("Không rule nào khớp. Kiểm tra literal neo và khoảng độ dài token.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                ForEach(hits) { hit in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("dòng \(hit.sourceLine) · offset \(hit.offset) · \(hit.scopeLabel)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(hit.pattern)
                            .font(.system(.caption, design: .monospaced))
                        Text("\(hit.source)  →  \(hit.rendered)")
                            .font(.footnote)
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    /// Nói rõ bộ nào được tính — không thì rule ở bộ khác "có trong danh sách mà không ăn ở đây".
    private var scopeHelp: [LocalizedStringKey] {
        if scope.bookId == nil, testBookId != nil {
            // Chuỗi chèn vào `LocalizedStringKey` hiện nguyên văn (không đọc markdown) ⇒ không đặt `**` ở đây.
            let sets = scope.isChapterTitle ? "bộ rule riêng của truyện đang đọc + bộ tên chương + bộ chung" : "bộ rule riêng của truyện đang đọc + bộ chung"
            return ["Mở từ trình đọc nên thử như lúc đọc truyện đó: áp \(sets), theo file tắt, công tắc token, thứ tự ưu tiên và bộ ngoặc của truyện. Mẫu đã khớp ghi rõ thuộc bộ nào.",
                    "Ô thử bỏ qua công tắc tổng Quick Translate nhưng **tôn trọng file tắt rule**."]
        }
        switch scope {
        case .global:
            return ["Chỉ áp **bộ rule chung**. Rule riêng của truyện, bộ tên chương, công tắc token riêng và thứ tự ưu tiên riêng **không** được tính ở đây — muốn thử những thứ đó thì dùng nút Thử rule ở danh sách rule riêng / tên chương.",
                    "Ô thử bỏ qua công tắc tổng Quick Translate nhưng **tôn trọng file tắt rule**."]
        case .chapterTitle:
            return ["Thử như khi dịch **tên chương**: áp bộ rule tên chương + bộ rule chung (tên chương thắng chung khi hoà mọi tiêu chí khác). Rule riêng của truyện không được tính.",
                    "Ô thử bỏ qua công tắc tổng Quick Translate nhưng **tôn trọng file tắt rule**."]
        case .book:
            return ["Thử như khi đọc truyện này: áp bộ rule **riêng** của truyện + bộ rule chung, theo file tắt, công tắc token, thứ tự ưu tiên và bộ ngoặc của truyện. Bộ tên chương không áp (ô thử dịch một câu nội dung).",
                    "Ô thử bỏ qua công tắc tổng Quick Translate nhưng **tôn trọng file tắt rule**."]
        }
    }

    private func run() {
        didRun = true
        hits = []
        let text = input

        guard let result = QuickTranslationRuleEngine.preview(text, scope: scope, contextBookId: contextBookId, mode: previewMode) else {
            output = text
            return
        }
        output = result.text

        let nsText = text as NSString
        let nsOutput = result.text as NSString
        let patterns = patternsByRank()

        hits = result.segments.compactMap { segment in
            guard let sourceLine = segment.sourceLine,
                  NSMaxRange(segment.sourceRange) <= nsText.length,
                  NSMaxRange(segment.outputRange) <= nsOutput.length else { return nil }
            let rank = segment.scopeRank ?? QuickTranslationRuleScope.globalRank
            return Hit(
                sourceLine: sourceLine,
                scopeLabel: Self.scopeLabel(rank: rank),
                source: nsText.substring(with: segment.sourceRange),
                rendered: nsOutput.substring(with: segment.outputRange),
                offset: segment.sourceRange.location,
                pattern: patterns[rank]?[sourceLine] ?? ""
            )
        }
    }

    /// `[scopeRank: [sourceLine: mẫu]]` của đúng các bộ `preview` vừa áp.
    private func patternsByRank() -> [Int: [Int: String]] {
        func index(_ snapshot: QuickTranslationRuleSnapshot?) -> [Int: String] {
            Dictionary((snapshot?.rules ?? []).map { ($0.sourceLine, $0.pattern) }, uniquingKeysWith: { first, _ in first })
        }
        var result: [Int: [Int: String]] = [
            QuickTranslationRuleScope.globalRank: index(QuickTranslationRuleStore.shared.currentSnapshot)
        ]
        if scope.isChapterTitle {
            result[QuickTranslationRuleScope.chapterTitleRank] = index(QuickTranslationRuleChapterStore.shared.currentSnapshot)
        }
        if let bookId = testBookId {
            result[QuickTranslationRuleScope.bookRank] = index(QuickTranslationRuleBookStore.shared.snapshot(for: bookId))
        }
        return result
    }

    private static func scopeLabel(rank: Int) -> String {
        switch rank {
        case QuickTranslationRuleScope.bookRank: return "bộ riêng"
        case QuickTranslationRuleScope.chapterTitleRank: return "bộ tên chương"
        default: return "bộ chung"
        }
    }
}
