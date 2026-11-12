import SwiftUI

/// Phần gợi ý dưới danh sách bài ở trang Danh sách của màn nghe (kiểu "Có thể bạn muốn nghe" của Zing MP3): mỗi nhóm
/// `suggests` của tiện ích (tới `AudioSuggestionStore.maxGroups`) là một tiêu đề + các dòng `AudioSuggestionRow`.
///
/// - Dữ liệu chỉ đọc từ `AudioSuggestionStore` (cùng kết quả tự phát dùng, không gọi nguồn lại); trang Danh sách gọi
///   `loadForDisplay` khi hiện. Chưa tải xong / lỗi / không có gợi ý ⇒ không vẽ gì.
/// - Chạm dòng ⇒ `ContentDetailRouter.openIfVideo` với tiện ích của album: tiện ích âm thanh ⇒ `AudioPlayerPresenter.present`
///   — màn nghe đang mở nên đổi album tại chỗ, không chồng màn.
/// - Công tắc "Tự phát bài gợi ý" bật ⇒ mục `AudioAutoNextCoordinator` sẽ tự phát (đã trừ mục đã phát trong chuỗi) có
///   nhãn "Tiếp theo"; tắt / đang lặp / hẹn "Hết bài" ⇒ không nhãn.
/// - Icon "Thêm vào playlist" cuối mỗi dòng (1.3.810) ⇒ mọi bài của album gợi ý vào `PlaylistAddSheet`.
struct AudioSuggestionSection: View {
    /// Mặc định bật — khớp `AudioAutoNextPolicy.isEnabled`; đọc bằng `@AppStorage` để nhãn đổi ngay khi bật / tắt.
    @AppStorage(AudioAutoNextPolicy.defaultsKey) private var autoNextSuggest = AudioAutoNextPolicy.defaultValue

    /// Nhóm gợi ý dài (Zing trả tới 100 bài) chỉ hiện chừng này dòng; mục "Tiếp theo" luôn được hiện.
    private static let maxRowsPerGroup = 20

    private var session: AudioPlaybackSession { .shared }
    private var store: AudioSuggestionStore { .shared }

    var body: some View {
        let groups = store.bookId == session.bookId ? store.groups : []
        if !groups.isEmpty {
            let upNext = upNextLink(groups)
            let nameOptions = session.displayNames.options
            VStack(alignment: .leading, spacing: 2) {
                ForEach(groups) { group in
                    Text(ChineseTextPipeline.meta(group.title, nameOptions))
                        .font(.headline)
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.top, 20)
                        .padding(.bottom, 4)
                    ForEach(rows(of: group, upNext: upNext)) { item in
                        AudioSuggestionRow(
                            item: item,
                            isUpNext: group.id == 0 && item.link == upNext,
                            nameOptions: nameOptions,
                            onSelect: { open(item) },
                            makeAlbum: { album(of: item) }
                        )
                    }
                }
            }
        }
    }

    /// Link mục sẽ tự phát (chỉ nhóm đầu — nhóm tự phát dùng); công tắc tắt ⇒ `nil`.
    private func upNextLink(_ groups: [AudioSuggestionStore.SuggestionGroup]) -> String? {
        guard autoNextSuggest, let first = groups.first, first.id == 0 else { return nil }
        return AudioAutoNextCoordinator.shared.upNextLink(in: session, firstGroupItems: first.items)
    }

    private func rows(of group: AudioSuggestionStore.SuggestionGroup, upNext: String?) -> [ExtensionItemResult] {
        var rows = Array(group.items.prefix(Self.maxRowsPerGroup))
        if group.id == 0, let upNext, !rows.contains(where: { $0.link == upNext }),
           let item = group.items.first(where: { $0.link == upNext }) {
            rows.append(item)
        }
        return rows
    }

    /// Album của một gợi ý cho icon "Thêm vào playlist" (cùng tiện ích với album đang nghe); thiếu container ⇒ `nil`.
    private func album(of item: ExtensionItemResult) -> PlaylistAlbumInfo? {
        guard let container = session.modelContainer, !session.packageId.isEmpty else {
            AppLogger.shared.log("❌ [AudioPlayerUI] Thiếu ModelContainer / tiện ích ⇒ không thêm được gợi ý «\(item.name)» vào playlist")
            return nil
        }
        return PlaylistItemMapper.album(
            of: item,
            packageId: session.packageId,
            sourceName: session.request?.sourceName ?? "",
            in: container.mainContext
        )
    }

    private func open(_ item: ExtensionItemResult) {
        guard let container = session.modelContainer else {
            AppLogger.shared.log("❌ [AudioPlayerUI] Thiếu ModelContainer ⇒ không mở được mục gợi ý «\(item.name)»")
            return
        }
        AppLogger.shared.log("🎵 [AudioPlayerUI] Chọn mục gợi ý «\(item.name)» ở trang Danh sách")
        let opened = ContentDetailRouter.openIfVideo(
            item,
            packageId: session.packageId,
            sourceName: session.request?.sourceName ?? "",
            modelContainer: container
        )
        if !opened {
            AppLogger.shared.log("⚠️ [AudioPlayerUI] Mục gợi ý không phải phim / âm thanh ⇒ không mở từ màn nghe được")
        }
    }
}
