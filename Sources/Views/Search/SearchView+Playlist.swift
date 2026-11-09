import SwiftUI

extension SearchView {
    /// ⋮ "Thêm vào playlist / Thêm vào kệ" (1.3.810) cho kết quả của một nguồn âm thanh / phim — tìm nhiều nguồn: mỗi
    /// nguồn một lần; tìm một nguồn: nguồn đang chọn. Đang đổi nguồn (chạm item = chọn nguồn mới) ⇒ không có.
    func playlistContext(for ext: Extension?) -> PlaylistListAddContext? {
        guard changeSourceTargetBook == nil, let ext else { return nil }
        return PlaylistListAddContext.make(packageId: ext.packageId, sourceName: ext.name, modelContainer: modelContext.container)
    }
}
