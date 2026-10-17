import SwiftUI

/// Menu nhấn giữ trên dòng tiện ích của Kho: đánh dấu / bỏ đánh dấu 18+ (`Extension.nsfwOverride`). Chỉ tiện ích
/// **đã cài** mới có bản ghi để lưu lựa chọn; mục catalog chưa cài không có menu này.
extension RepositoryManagerView {
    @ViewBuilder
    internal func nsfwContextMenu(_ ext: Extension) -> some View {
        if ext.isInstalled {
            let isNsfw = ExtensionNsfwCache.shared.isNsfw(ext)
            Button {
                ExtensionConfigView.saveNsfwOverride(packageId: ext.packageId, name: ext.name, !isNsfw)
            } label: {
                Label(isNsfw ? "Bỏ đánh dấu 18+" : "Đánh dấu 18+", systemImage: isNsfw ? "eye" : "eye.slash")
            }
            if ext.nsfwOverride != nil {
                Button {
                    ExtensionConfigView.saveNsfwOverride(packageId: ext.packageId, name: ext.name, nil)
                } label: {
                    Label("Dùng nhận diện tự động", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }
}
