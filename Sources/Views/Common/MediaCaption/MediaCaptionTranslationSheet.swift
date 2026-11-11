import SwiftUI

/// Sheet **Dịch phụ đề** (ngăn kéo `⋯` của trình phát phim) / **Dịch lời** (ngăn kéo `…` của màn nghe): cấu hình dịch
/// VietPhrase và phồn→giản của phim/album đang mở + của nguồn, bám mục dịch của `ReaderSettingsView` (picker phân đoạn).
///
/// - Dịch · Phim/album này: Theo nguồn / Bật / Tắt (`setBookOverride`) — Dịch · Nguồn: Toàn cục / Bật / Tắt
///   (`setSourceOverride`). Cùng kho với truyện chữ nên cổng dịch y như Reader.
/// - Phồn → giản · Phim/album này: Theo nguồn / Bật / Tắt (khoá theo truyện, ba trạng thái) — · Nguồn: Tắt / Bật. Chỉ
///   phụ đề, lời và tên nhóm tập phim đọc (`convertsTraditionalToSimplified(bookId:packageId:)`).
///
/// Chọn là ghi ngay vào `TranslationConfigStore`; sheet đóng mà kết quả (bật dịch, phồn→giản) khác lúc mở ⇒ `onChanged`
/// để màn dịch lại phụ đề / lời đang mở (không nạp lại phim / bài). Mở từ màn trình bày bằng UIKit (`VideoPlayerPresenter`,
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
    }

    /// Kết quả cấu hình áp cho phim/album — chụp lúc mở, so lúc đóng.
    private struct Resolved: Equatable {
        let isEnabled: Bool
        let convertsTraditional: Bool
    }

    let medium: Medium
    let bookId: String
    let packageId: String
    let sourceName: String
    let onChanged: () -> Void

    @State private var bookOverride: ScopeOverride
    @State private var sourceOverride: ScopeOverride
    @State private var bookTraditional: ScopeOverride
    @State private var sourceTraditional: Bool
    @State private var resolved: Resolved
    private let initial: Resolved

    /// Đọc trạng thái lưu ngay trong `init` (không trong `onAppear`): gán `@State` lúc hiện sẽ kích `onChange` ⇒ ghi lại
    /// cùng giá trị và bắn thông báo đổi cấu hình thừa.
    init(medium: Medium, bookId: String, packageId: String, sourceName: String, onChanged: @escaping () -> Void) {
        self.medium = medium
        self.bookId = bookId
        self.packageId = packageId
        self.sourceName = sourceName
        self.onChanged = onChanged
        let store = TranslationConfigStore.shared
        _bookOverride = State(initialValue: store.getBookOverride(bookId: bookId))
        _sourceOverride = State(initialValue: store.getSourceOverride(packageId: packageId))
        _bookTraditional = State(initialValue: store.traditionalOverride(bookId: bookId))
        _sourceTraditional = State(initialValue: store.sourceConvertsTraditional(packageId: packageId))
        let current = Self.resolve(bookId: bookId, packageId: packageId)
        _resolved = State(initialValue: current)
        initial = current
    }

    private var store: TranslationConfigStore { .shared }

    private var sourceLabel: String { sourceName.isEmpty ? "Nguồn" : "Nguồn (\(sourceName))" }

    var body: some View {
        NavigationStack {
            Form {
                translationSection
                traditionalSection
            }
            .pageTitle(medium.title)
        }
        .preferredColorScheme(.dark)
        .appAccentTint()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onDisappear {
            guard Self.resolve(bookId: bookId, packageId: packageId) != initial else { return }
            onChanged()
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
                Text("Đổi chữ phồn thể sang giản thể trước khi dịch \(medium.contentNoun) (mặc định tắt)."),
                Text("Chỉ áp cho phim và nhạc; trình đọc truyện chữ giữ cài đặt riêng của nó.")
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

    private func refresh() {
        let current = Self.resolve(bookId: bookId, packageId: packageId)
        if current != resolved { resolved = current }
    }

    private static func resolve(bookId: String, packageId: String) -> Resolved {
        let store = TranslationConfigStore.shared
        return Resolved(
            isEnabled: store.isTranslationEnabled(bookId: bookId, packageId: packageId),
            convertsTraditional: store.convertsTraditionalToSimplified(bookId: bookId, packageId: packageId)
        )
    }
}
