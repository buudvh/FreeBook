import SwiftUI

/// Nhánh âm thanh của router `BookContentDestination` (Kệ, Lịch sử, Bộ sưu tập, Tìm trên kệ, mở lại lúc khởi động, chạm
/// bài ở Chi tiết): **cùng màn nghe** với lối item danh sách, nằm trong `fullScreenCover` sẵn có của chỗ gọi (như
/// `VideoWatchRouteView`) — đóng / thu nhỏ bằng `dismiss` của cover, nhạc vẫn phát (đĩa góc dưới).
///
/// Album mở **một lần** lúc màn hiện (cần `modelContainer` của environment) từ `AudioListenRequest(launch:)`: id của
/// launch là id `Book` thật nên dùng nguyên; `chapterIndex` = bài, `initialParagraphIndex` = giây. Lượt mở lại lúc khởi
/// động (`ReaderSessionRestoreStore.beginRestoreAttempt` đã ghi `bookId`) ⇒ `autoplay: false`: dừng sẵn ở bài + giây đã
/// lưu. Cờ `didOpen` chặn mở lại khi màn hiện lại (trình duyệt "Mở link lỗi" / "Trang nguồn" che rồi đóng) — mở lại lúc
/// đó sẽ kéo người nghe về bài của launch.
struct AudioListenRouteView: View {
    let launch: BookContentLaunch

    @Environment(\.modelContext) private var modelContext
    @State private var didOpen = false

    var body: some View {
        ZStack {
            // Màn nghe tự vẽ nền (trượt xuống khi thu nhỏ để lộ màn phía sau) ⇒ ở đây chỉ phủ tối trước khi mở album.
            Color.black.opacity(didOpen ? 0 : 1).ignoresSafeArea()
            if didOpen {
                AudioPlayerScreen()
            }
        }
        .presentationBackground(.clear)
        .onAppear {
            guard !didOpen else { return }
            let autoplay = !ReaderSessionRestoreStore.consumePausedVideoStart(bookId: launch.bookId)
            AudioPlayerPresenter.openInPlace(
                AudioListenRequest(launch: launch),
                modelContainer: modelContext.container,
                autoplay: autoplay
            )
            didOpen = true
        }
    }
}
