import SwiftUI

/// Ô thử nhanh: dán một câu Trung → xem text sau rewrite và **rule nào khớp ở offset nào**.
///
/// Đây là công cụ debug chính khi rule không nổ như mong đợi. Người dùng có thể chạy theo cấu hình
/// token hiện hành hoặc tạm coi mọi token là bật; cả hai vẫn bỏ qua công tắc tổng Quick Translate.
struct QuickTranslationRuleTesterView: View {
    private struct Hit: Identifiable {
        let id = UUID()
        let sourceLine: Int
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
        Form {
            Section(header: Text("Câu tiếng Trung")) {
                TextEditor(text: $input)
                    .frame(minHeight: 90)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                Button("Chạy thử") { run() }
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                // Màn này mở từ Cài đặt nên không có truyện nào đang mở ⇒ `preview` chạy với
                // `bookId: nil`. Phải nói ra, không thì một rule lưu ở bộ riêng (nút `+` trong Reader
                // mặc định lưu vào đó) sẽ "có trong Danh sách rule mà không ăn ở đây" — không giải
                // thích được từ phía người dùng.
                Text("Chỉ áp **bộ rule chung**. Rule riêng của truyện, công tắc token riêng và thứ tự ưu tiên riêng **không** được tính ở đây — muốn thử những thứ đó thì mở panel Dịch trong lúc đọc truyện đó.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section("Chế độ token") {
                Picker("Áp dụng token", selection: $previewMode) {
                    Text("Theo cấu hình token")
                        .tag(QuickTranslationRuleEngine.PreviewMode.respectTokenConfiguration)
                    Text("Bỏ qua cấu hình token")
                        .tag(QuickTranslationRuleEngine.PreviewMode.ignoreTokenConfiguration)
                }
                .pickerStyle(.menu)

                Text("Cả hai chế độ đều thử rule trực tiếp, không phụ thuộc công tắc tổng Quick Translate. Nhưng ô thử **tôn trọng file tắt rule**: rule đã tắt sẽ không khớp ở đây, đúng như khi đọc.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if didRun {
                Section(header: Text("Sau khi áp rule")) {
                    Text(output.isEmpty ? "(rỗng)" : output)
                        .font(.footnote)
                        .textSelection(.enabled)
                }

                Section(header: Text("Rule đã khớp (\(hits.count))")) {
                    if hits.isEmpty {
                        Text("Không rule nào khớp ở chế độ hiện tại. Kiểm tra literal neo và khoảng độ dài token.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    ForEach(hits) { hit in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("dòng \(hit.sourceLine) · offset \(hit.offset)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(hit.pattern)
                                .font(.system(.caption, design: .monospaced))
                            Text("\(hit.source)  →  \(hit.rendered)")
                                .font(.footnote)
                                .foregroundColor(.accentColor)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Thử nhanh rule")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: previewMode) { _, _ in
            if didRun { run() }
        }
    }

    private func run() {
        didRun = true
        hits = []
        let text = input

        guard let result = QuickTranslationRuleEngine.preview(text, mode: previewMode) else {
            output = text
            return
        }
        output = result.text

        let nsText = text as NSString
        let nsOutput = result.text as NSString
        let patterns = Dictionary(
            (QuickTranslationRuleStore.shared.currentSnapshot?.rules ?? []).map { ($0.sourceLine, $0.pattern) },
            uniquingKeysWith: { first, _ in first }
        )

        hits = result.segments.compactMap { segment in
            guard let sourceLine = segment.sourceLine,
                  NSMaxRange(segment.sourceRange) <= nsText.length,
                  NSMaxRange(segment.outputRange) <= nsOutput.length else { return nil }
            return Hit(
                sourceLine: sourceLine,
                source: nsText.substring(with: segment.sourceRange),
                rendered: nsOutput.substring(with: segment.outputRange),
                offset: segment.sourceRange.location,
                pattern: patterns[sourceLine] ?? ""
            )
        }
    }
}
