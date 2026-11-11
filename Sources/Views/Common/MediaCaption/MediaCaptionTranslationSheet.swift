import SwiftUI

/// Sheet **Dịch phụ đề** (ngăn kéo `⋯` của trình phát phim) / **Dịch lời** (ngăn kéo `…` của màn nghe): cấu hình dịch
/// VietPhrase và phồn→giản của phim/album đang mở + của nguồn, bám mục dịch của `ReaderSettingsView` (picker phân đoạn).
///
/// - Dịch · Phim/album này: Theo nguồn / Bật / Tắt (`setBookOverride`) — Dịch · Nguồn: Toàn cục / Bật / Tắt
///   (`setSourceOverride`). Cùng kho với truyện chữ nên cổng dịch y như Reader.
/// - Phồn → giản · Phim/album này: Theo nguồn / Bật / Tắt (khoá theo truyện, ba trạng thái) — · Nguồn: Tắt / Bật. Bước
///   riêng chạy **trước** khi dịch và chạy **cả khi tắt dịch** (`ChineseTextPipeline`): phụ đề / lời, tên phim / album,
///   tên tập / bài, tác giả hiện chữ đã chuyển ("Gốc" = chữ đã chuyển). Phụ đề cứng (OCR) vẫn chỉ đọc khi bật dịch.
/// - Bộ dịch · Phim/album này / · Nguồn: BỘ DỊCH + NGÔN NGỮ như popup dịch truyện (`MediaCaptionEngineRow`, ghi
///   `TranslationEngineStore` ở hai cấp trên — cùng hai cấp với công tắc dịch). Tiện ích dịch dịch phụ đề / lời theo lô,
///   dòng lỗi lùi QT; phụ đề cứng luôn QT.
///
/// Chọn là ghi ngay vào `TranslationConfigStore`; sheet đóng mà người dùng đã đổi bất kỳ lựa chọn nào ⇒ `onChanged` để màn
/// chuyển / dịch lại phụ đề / lời và tên đang mở (không nạp lại phim / bài). Không so "cấu hình lúc mở": màn cha vẽ lại (xoay máy, hết bài…)
/// là `init` chạy lại, và tập / bài mới nạp lúc sheet đang mở đã dịch theo cấu hình giữa chừng. Hai id chụp vào `@State`
/// một lần: phim / album tự sang lúc sheet đang mở thì lựa chọn vẫn ghi cho đúng mục đang hiện trên sheet.
/// Mở từ màn trình bày bằng UIKit (`VideoPlayerPresenter`,
/// `AudioPlayerPresenter`) ⇒ tự gắn `.preferredColorScheme(.dark)` + `.appAccentTint()` như `MediaSleepTimerSheet`.
/// Không có nút chỉ để đóng: vuốt xuống.
struct MediaCaptionTranslationSheet: View {
    typealias ScopeOverride = TranslationConfigStore.ScopeOverride

    enum Medium {
        case video
        case audio

        var title: String { self == .video ? "Dịch phụ đề" : "Dịch lời" }
        var itemLabel: String { self == .video ? "Phim này" : "Album này" }
        var contentNoun: String { self == .video ? "phụ đề" : "lời bài hát" }
        var namesNoun: String { self == .video ? "tên phim, tên tập" : "tên album, tên bài, nghệ sĩ" }

        /// Giải thích của mục "Bộ dịch" (nút "?").
        var engineHelpTexts: [Text] {
            var texts = [
                Text("Ai dịch \(contentNoun) khi đang bật dịch: QT có sẵn hoặc tiện ích dịch đã cài, kèm ngôn ngữ nguồn → đích — như popup dịch của truyện chữ."),
                Text("\(itemLabel) ⇒ nguồn ⇒ toàn cục. Tiện ích lỗi thì dòng đó dịch bằng QT.")
            ]
            if self == .video {
                texts.append(Text("Phụ đề in sẵn trong hình (Đọc phụ đề cứng) luôn dịch bằng QT."))
            }
            return texts
        }
    }

    /// Kết quả cấu hình áp cho phim/album — dòng "Hiện tại" của sheet.
    private struct Resolved: Equatable {
        let isEnabled: Bool
        let convertsTraditional: Bool
    }

    let medium: Medium
    let sourceName: String
    let onChanged: () -> Void

    /// Chụp một lần (giá trị khởi tạo của `@State` chỉ dùng ở lần dựng đầu, `init` chạy lại thì bỏ qua).
    @State private var bookId: String
    @State private var packageId: String
    @State private var bookOverride: ScopeOverride
    @State private var sourceOverride: ScopeOverride
    @State private var bookTraditional: ScopeOverride
    @State private var sourceTraditional: Bool
    @State private var resolved: Resolved
    /// Người dùng đã đổi ít nhất một lựa chọn ⇒ đóng sheet thì dịch lại.
    @State private var didChange = false

    /// Đọc trạng thái lưu ngay trong `init` (không trong `onAppear`): gán `@State` lúc hiện sẽ kích `onChange` ⇒ ghi lại
    /// cùng giá trị và bắn thông báo đổi cấu hình thừa.
    init(medium: Medium, bookId: String, packageId: String, sourceName: String, onChanged: @escaping () -> Void) {
        self.medium = medium
        self.sourceName = sourceName
        self.onChanged = onChanged
        let store = TranslationConfigStore.shared
        _bookId = State(initialValue: bookId)
        _packageId = State(initialValue: packageId)
        _bookOverride = State(initialValue: store.getBookOverride(bookId: bookId))
        _sourceOverride = State(initialValue: store.getSourceOverride(packageId: packageId))
        _bookTraditional = State(initialValue: store.traditionalOverride(bookId: bookId))
        _sourceTraditional = State(initialValue: store.sourceConvertsTraditional(packageId: packageId))
        _resolved = State(initialValue: Self.resolve(bookId: bookId, packageId: packageId))
    }

    private var store: TranslationConfigStore { .shared }

    private var sourceLabel: String { sourceName.isEmpty ? "Nguồn" : "Nguồn (\(sourceName))" }

    var body: some View {
        NavigationStack {
            Form {
                translationSection
                engineSection
                traditionalSection
            }
            .pageTitle(medium.title)
        }
        .preferredColorScheme(.dark)
        .appAccentTint()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onDisappear {
            if didChange { onChanged() }
        }
    }

    // MARK: - Mục

    private var translationSection: some View {
        Section {
            HStack {
                Text("Hiện tại")
                Spacer()
                Text(resolved.isEnabled ? "Đang bật" : "Đang tắt")
                    .fontWeight(.semibold)
                    .foregroundStyle(resolved.isEnabled ? Color.green : Color.secondary)
            }
            scopePicker(medium.itemLabel, selection: $bookOverride, inheritedTitle: "Theo nguồn")
                .onChange(of: bookOverride) { _, mode in
                    store.setBookOverride(bookId: bookId, mode: mode)
                    refresh()
                }
            scopePicker(sourceLabel, selection: $sourceOverride, inheritedTitle: "Toàn cục")
                .onChange(of: sourceOverride) { _, mode in
                    store.setSourceOverride(packageId: packageId, mode: mode)
                    refresh()
                }
        } header: {
            SectionHelpHeader("Dịch Quick Translate", texts: [
                Text("Dịch \(medium.contentNoun) có chữ Hán sang tiếng Việt, giống truyện chữ: \(medium.itemLabel.lowercased()) > nguồn > nguồn tự nhận tiếng Trung > toàn cục."),
                Text("Nguồn không khai tiếng Trung mặc định không dịch — chọn Bật ở đây.")
            ])
        }
    }

    private var engineSection: some View {
        Section {
            MediaCaptionEngineRow(
                scope: .book, label: medium.itemLabel, bookId: bookId, packageId: packageId, onChanged: markChanged
            )
            MediaCaptionEngineRow(
                scope: .source, label: sourceLabel, bookId: bookId, packageId: packageId, onChanged: markChanged
            )
        } header: {
            SectionHelpHeader("Bộ dịch", texts: medium.engineHelpTexts)
        }
    }

    private var traditionalSection: some View {
        Section {
            scopePicker(medium.itemLabel, selection: $bookTraditional, inheritedTitle: "Theo nguồn")
                .onChange(of: bookTraditional) { _, mode in
                    store.setTraditionalOverride(bookId: bookId, mode: mode)
                    refresh()
                }
            VStack(alignment: .leading, spacing: 6) {
                Text(sourceLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(sourceLabel, selection: $sourceTraditional) {
                    Text("Tắt").tag(false)
                    Text("Bật").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .onChange(of: sourceTraditional) { _, enabled in
                store.setSourceConvertsTraditional(packageId: packageId, enabled: enabled)
                refresh()
            }
        } header: {
            SectionHelpHeader("Phồn → giản", texts: [
                Text("Đổi chữ phồn thể sang giản thể cho \(medium.contentNoun) và \(medium.namesNoun) (mặc định tắt)."),
                Text("Chạy cả khi tắt dịch: kiểu Gốc và dòng gốc của Song ngữ hiện chữ đã chuyển. Bật dịch thì chuyển xong mới dịch."),
                Text("Cùng công tắc với popup dịch của truyện chữ / truyện tranh: phim / album này ⇒ nguồn ⇒ Tất cả.")
            ])
        }
    }

    private func scopePicker(_ label: String, selection: Binding<ScopeOverride>, inheritedTitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(label, selection: selection) {
                Text(inheritedTitle).tag(ScopeOverride.inherited)
                Text("Bật").tag(ScopeOverride.enabled)
                Text("Tắt").tag(ScopeOverride.disabled)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: - Kết quả

    /// Bộ dịch vừa ghi (`MediaCaptionEngineRow`) ⇒ đóng sheet thì dịch lại.
    private func markChanged() {
        if !didChange { didChange = true }
    }

    /// Sau mỗi lựa chọn của người dùng (bốn `onChange`): đánh dấu cần dịch lại + cập nhật dòng "Hiện tại".
    private func refresh() {
        if !didChange { didChange = true }
        let current = Self.resolve(bookId: bookId, packageId: packageId)
        if current != resolved { resolved = current }
    }

    /// Cùng luật với chỗ chạy thật (`MediaCaptionTranslator.prepare`, tên hiển thị): `ChineseTextPipeline.options`.
    private static func resolve(bookId: String, packageId: String) -> Resolved {
        let options = ChineseTextPipeline.options(bookId: bookId, packageId: packageId)
        return Resolved(isEnabled: options.translates, convertsTraditional: options.converts)
    }
}
