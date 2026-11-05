import SwiftUI

/// Nhánh `.video` của router `BookContentDestination` (Kệ, Lịch sử, Bộ sưu tập, Tìm trên kệ, mở lại lúc khởi động, chạm
/// tập ở Chi tiết): **cùng màn xem** với item danh sách (`VideoPlayerScreen(watch:)`), nằm trong `fullScreenCover` sẵn có
/// của chỗ gọi — đóng bằng `dismiss` của cover.
///
/// Model dựng **một lần** lúc màn hiện (cần `modelContainer` của environment, `init` không có) từ
/// `VideoWatchRequest(launch:)`: id của launch là id `Book` thật nên dùng nguyên; tập / giây của launch là tập muốn mở.
/// Tự phát theo công tắc như mọi lối vào; lượt mở lại lúc khởi động vẫn dừng sẵn (`ReaderSessionRestoreStore`).
struct VideoWatchRouteView: View {
    let launch: BookContentLaunch

    @Environment(\.modelContext) private var modelContext
    @State private var model: VideoWatchModel?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                VideoPlayerScreen(watch: model)
            }
        }
        .onAppear {
            guard model == nil else { return }
            model = VideoWatchModel(request: VideoWatchRequest(launch: launch), modelContainer: modelContext.container)
        }
    }
}
