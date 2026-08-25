import SwiftUI

/// Ô thử nhanh: dán một câu Trung → xem text sau rewrite và **rule nào khớp ở offset nào**.
///
/// Đây là công cụ debug chính khi rule không nổ như mong đợi. Chạy bỏ qua công tắc bật/tắt để thử
/// được ngay cả khi đang tắt rule trong Cài đặt.
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
            }

            if didRun {
                Section(header: Text("Sau khi áp rule")) {
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
    }

    private func run() {
        didRun = true
        hits = []
        let text = input

        guard let result = QuickTranslationRuleEngine.preview(text) else {
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
