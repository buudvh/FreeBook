import SwiftUI

/// Hub **"Cài đặt NghiTTS"** — một chỗ cho mọi thứ thuộc engine NghiTTS (Piper): thông tin model (engine, giọng đã tải,
/// thư viện phiên âm), danh sách giọng đã tải kèm dung lượng, và 3 lối vào quản lý (trước đây 3 nav rời ở tab Cài đặt).
/// **Chỉ hiện thông tin** — phần "Nghe thử" (chữ / giọng / tốc độ / phát) đã bỏ; tải / xoá giọng ở "Quản lý Model giọng
/// đọc" (`TTSModelManagerView`).
///
/// Dung lượng đọc đĩa ở nền (`ModelSnapshot`, `.task` + `Task.detached`), không trong `body`; `.task` chạy lại mỗi lần
/// màn hiện ra (kể cả khi quay về từ màn quản lý model) nên số liệu theo kịp lượt tải / xoá.
struct NghiTTSSettingsHubView: View {
    @State var snapshot: ModelSnapshot?

    var body: some View {
        Form { Group {
            modelSection
            voicesSection
            managementSection
        }.glassSheetRows() }
        .backPageTitle("Cài đặt NghiTTS")
        .task { await reloadSnapshot() }
    }

    private func reloadSnapshot() async {
        let loaded = await Task.detached(priority: .userInitiated) {
            Self.loadModelSnapshot()
        }.value
        snapshot = loaded
    }
}
