import SwiftUI

/// Sheet **"Từ điển truyện"** của trình phát phim (ngăn kéo `⋯`, 1.3.840) — như Reader / truyện tranh: `BookDictionaryView`
/// dạng sheet theo `bookId` của phim đang phát (phim đang phát luôn có `Book`, kể cả ẩn — `ensureHistoryBook`).
///
/// Sửa name / VP ⇒ `.translationDictionariesDidUpdate` ⇒ phụ đề cứng tự dịch lại (`VideoHardSubtitleEngine+Translation`).
/// Đóng sheet ⇒ dịch lại phụ đề mềm đã nạp (`retranslateSubtitles`, không nạp lại phim). Trình bày bằng UIKit
/// (`VideoPlayerPresenter`) ⇒ tự gắn `.preferredColorScheme(.dark)` + `.appAccentTint()` như `MediaCaptionTranslationSheet`.
struct VideoBookDictionarySheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let session: VideoPlaybackSession

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: { session.retranslateSubtitles() }) {
            if let launch = session.launch {
                NavigationStack {
                    BookDictionaryView(
                        bookId: launch.bookId,
                        bookName: launch.bookTitle ?? session.bookTitle,
                        isPresentedAsSheet: true
                    )
                }
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
                .appAccentTint()
            }
        }
    }
}
