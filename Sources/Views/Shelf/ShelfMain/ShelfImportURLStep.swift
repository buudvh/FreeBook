import SwiftUI

/// Bước "Từ URL" của sheet "Nhập truyện": dán / gõ link trang truyện rồi dò tiện ích nhận link bằng
/// `ExtensionUrlMatcher` — cùng bộ dò (và cùng tập tiện ích, bỏ nguồn Legado) với nút "Nhập" của trình duyệt.
///
/// - Chỉ dò khi bấm "Mở link", nhấn Go trên bàn phím, hoặc dán bằng nút dán: dò theo từng phím gõ thì dòng "chưa có
///   tiện ích" nháy liên tục khi link còn dở.
/// - 1 tiện ích khớp ⇒ báo `openBook` ngay; nhiều ⇒ liệt kê để chọn; 0 ⇒ báo + nút mở link trong trình duyệt (trình
///   duyệt nhập truyện của Kệ, vẫn có nút "Nhập").
struct ShelfImportURLStep: View {
    let onChoose: (ShelfImportSheet.Choice) -> Void

    /// Kết quả một lần dò khi **không** đi thẳng được tới Chi tiết.
    private enum Outcome {
        case noMatch(url: String)
        case multiple(url: String, matches: [ExtensionUrlMatcher.Match])
    }

    @State private var urlText = ""
    @State private var outcome: Outcome? = nil
    /// Chữ trong ô lúc dò ra `outcome`. Ô đổi ⇒ kết quả cũ thôi hiện — so chữ thay vì `onChange`, vì `onChange` chạy
    /// **sau** lượt dán + dò và sẽ xoá luôn kết quả vừa dò.
    @State private var outcomeInput = ""
    @FocusState private var isFieldFocused: Bool

    private var visibleOutcome: Outcome? {
        outcomeInput == urlText ? outcome : nil
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    TextField("Dán link trang truyện", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($isFieldFocused)
                        .onSubmit { resolve(urlText) }

                    Button(action: pasteAndResolve) {
                        AppGlyph.paste.image(size: 17)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Dán link")
                }

                Button {
                    resolve(urlText)
                } label: {
                    Text("Mở link")
                        .frame(maxWidth: .infinity)
                }
                .disabled(Self.normalizedLink(urlText).isEmpty)
            }

            outcomeSection
        }
        .listStyle(.insetGrouped)
        .backPageTitle("Từ URL")
    }

    @ViewBuilder
    private var outcomeSection: some View {
        switch visibleOutcome {
        case .multiple(let url, let matches):
            Section("Chọn tiện ích") {
                ForEach(matches) { match in
                    Button {
                        onChoose(.openBook(detailUrl: url, packageId: match.ext.packageId, sourceName: match.ext.name))
                    } label: {
                        HStack(spacing: 12) {
                            ExtensionIconView(localPath: match.ext.localPath, iconUrl: match.ext.iconUrl, size: 28)
                            Text(match.ext.name)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        case .noMatch(let url):
            Section {
                Text("Chưa có tiện ích nào nhận link này")
                    .foregroundColor(.secondary)
                Button {
                    onChoose(.openBrowser(urlString: url))
                } label: {
                    Label("Mở trong trình duyệt", systemImage: "safari")
                }
            }
        case nil:
            EmptyView()
        }
    }

    private func pasteAndResolve() {
        guard let clip = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clip.isEmpty else { return }
        urlText = clip
        resolve(clip)
    }

    /// Dò tiện ích cho `input` (chữ đang trong ô). 1 khớp ⇒ đi thẳng tới Chi tiết, còn lại ⇒ hiện kết quả dưới ô.
    private func resolve(_ input: String) {
        let link = Self.normalizedLink(input)
        guard !link.isEmpty else { return }
        let candidates = ExtensionUrlMatcher.candidates(from: ExtensionLibraryRepository.shared.installed)
        let matches = ExtensionUrlMatcher.matches(for: link, in: candidates)
        if matches.count == 1, let match = matches.first {
            onChoose(.openBook(detailUrl: link, packageId: match.ext.packageId, sourceName: match.ext.name))
            return
        }
        isFieldFocused = false
        outcomeInput = input
        outcome = matches.isEmpty ? .noMatch(url: link) : .multiple(url: link, matches: matches)
    }

    /// Bỏ khoảng trắng / xuống dòng hai đầu; link thiếu scheme (`truyen.com/abc`) ⇒ thêm `https://` vì bộ dò chỉ nhận
    /// link http(s).
    static func normalizedLink(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.contains("://") ? trimmed : "https://" + trimmed
    }
}
