import SwiftUI

/// View hiển thị nội dung tin nhắn AI với định dạng Markdown (code block, tiêu đề, bullet, in đậm/nghiêng).
public struct AIMarkdownMessageView: View {
    let content: String
    let isUser: Bool

    /// Tin dài (vd. danh sách tên riêng hàng trăm dòng) chỉ dựng chừng này đoạn **cuối**, rồi tự nạp thêm
    /// từng đợt khi cuộn lên gần mép trên. Mỗi đoạn là một `Text` markdown trong `VStack` không lazy (chat
    /// cố ý không dùng `LazyVStack` vì xung đột `.defaultScrollAnchor(.bottom)`), nên dựng cả danh sách mỗi
    /// nhịp stream 50 ms chiếm main thread — kéo giật cả TTS. Nạp từ đáy lên vì chat neo đáy: phần thêm vào
    /// nằm phía trên vùng đang xem, và lúc stream thì luôn thấy dòng mới nhất.
    private static let pageSize = 100

    @State private var copiedBlockIndex: Int? = nil
    @State private var visibleBlockCount = AIMarkdownMessageView.pageSize

    public init(content: String, isUser: Bool) {
        self.content = content
        self.isUser = isUser
    }

    public var body: some View {
        if isUser {
            Text(content)
                .font(.body)
                .foregroundColor(.white)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                let blocks = parseMarkdownBlocks(content)
                let start = max(0, blocks.count - visibleBlockCount)
                if start > 0 {
                    loadMoreSentinel
                }
                ForEach(start..<blocks.count, id: \.self) { idx in
                    renderBlock(blocks[idx], index: idx)
                }
            }
        }
    }

    /// Vòng xoay nhỏ ở mép trên phần đã dựng. Preference là `Bool` nên `onPreferenceChange` chỉ chạy khi
    /// trạng thái hiện/khuất **đổi**: mỗi lần lọt vào vùng nhìn (nới 300 pt) nạp đúng một đợt, không dây chuyền
    /// khi nó vẫn đứng yên trong khung sau lượt nạp.
    private var loadMoreSentinel: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: LoadMoreVisibilityKey.self,
                        value: proxy.bounds(of: .scrollView).map {
                            $0.insetBy(dx: 0, dy: -300).intersects(CGRect(origin: .zero, size: proxy.size))
                        } ?? false
                    )
                }
            )
            .onPreferenceChange(LoadMoreVisibilityKey.self) { isVisible in
                if isVisible {
                    visibleBlockCount += Self.pageSize
                }
            }
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock, index: Int) -> some View {
        switch block {
        case .header(let text, let level):
            Text(LocalizedStringKey(text))
                .font(level == 1 ? .title3.bold() : .headline.bold())
                .foregroundColor(.primary)
                .padding(.top, 4)

        case .codeBlock(let code, let lang):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if !lang.isEmpty {
                        Text(lang)
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        UIPasteboard.general.string = code
                        copiedBlockIndex = index
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedBlockIndex == index {
                                copiedBlockIndex = nil
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedBlockIndex == index ? "checkmark" : "doc.on.doc")
                            Text(copiedBlockIndex == index ? "Đã chép" : "Chép")
                        }
                        .font(.caption2.bold())
                        .foregroundColor(copiedBlockIndex == index ? .green : .accentColor)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(.subheadline, design: .monospaced))
                        .padding(10)
                }
            }
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)

        case .bulletItem(let text):
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .foregroundColor(.accentColor)
                    .font(.body.bold())
                Text(LocalizedStringKey(text))
                    .font(.body)
                    .foregroundColor(.primary)
            }

        case .paragraph(let text):
            Text(LocalizedStringKey(text))
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func parseMarkdownBlocks(_ raw: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = raw.components(separatedBy: "\n")
        var inCodeBlock = false
        var codeLang = ""
        var codeLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    // Đóng code block
                    blocks.append(.codeBlock(code: codeLines.joined(separator: "\n"), lang: codeLang))
                    codeLines.removeAll()
                    codeLang = ""
                    inCodeBlock = false
                } else {
                    // Mở code block
                    inCodeBlock = true
                    codeLang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                continue
            }

            if inCodeBlock {
                codeLines.append(line)
                continue
            }

            if trimmed.isEmpty {
                continue
            }

            if trimmed.hasPrefix("### ") {
                blocks.append(.header(text: String(trimmed.dropFirst(4)), level: 3))
            } else if trimmed.hasPrefix("## ") {
                blocks.append(.header(text: String(trimmed.dropFirst(3)), level: 2))
            } else if trimmed.hasPrefix("# ") {
                blocks.append(.header(text: String(trimmed.dropFirst(2)), level: 1))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                blocks.append(.bulletItem(text: content))
            } else {
                blocks.append(.paragraph(text: line))
            }
        }

        if inCodeBlock && !codeLines.isEmpty {
            blocks.append(.codeBlock(code: codeLines.joined(separator: "\n"), lang: codeLang))
        }

        return blocks
    }

    private enum MarkdownBlock {
        case header(text: String, level: Int)
        case codeBlock(code: String, lang: String)
        case bulletItem(text: String)
        case paragraph(text: String)
    }

    private struct LoadMoreVisibilityKey: PreferenceKey {
        static var defaultValue = false
        static func reduce(value: inout Bool, nextValue: () -> Bool) {
            value = value || nextValue()
        }
    }
}
