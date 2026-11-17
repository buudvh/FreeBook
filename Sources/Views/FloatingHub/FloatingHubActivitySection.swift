import SwiftUI

/// Mục **"Đang chạy"** của sheet hub (1.3.967, anh Bửu duyệt mockup "A · Mục Đang chạy"): nằm dưới bốn dòng cố định, mỗi
/// tác vụ nền có tiến độ (`FloatingHubActivity.items()`) một ô — tên, chi tiết, thanh tiến độ — **không giới hạn số ô**
/// (anh Bửu: "lỡ có nhiều hơn thì sao"); sheet dài quá màn thì cuộn (`FloatingHubSheet.compactPage`). Dòng đầu
/// "Đang chạy (N) · M đang chờ". Chạm một ô ⇒ trang Thông báo trong sheet (nơi có nút Huỷ / chi tiết từng tập).
///
/// Tự observe các nguồn tiến độ (`DownloadManager` phát ~10 lần/giây lúc tải) ⇒ chỉ khối này vẽ lại theo nhịp tiến độ, và
/// chỉ khi sheet đang mở; nút hub vẫn chỉ đọc số từ `NotificationInboxPresenceReader`. Khuôn của
/// `NotificationInboxView.ActivityRows`.
struct FloatingHubActivitySection: View {
    @ObservedObject private var downloads = DownloadManager.shared
    @ObservedObject private var imports = BookImportProgressCenter.shared
    @ObservedObject private var backup = BackupCoordinator.shared
    @ObservedObject private var models = ModelDownloadCenter.shared
    @ObservedObject private var merge = DictionaryMergeTask.shared
    @ObservedObject private var rephoneticizeNghi = RephoneticizeTask.nghiTTS
    @ObservedObject private var rephoneticizeVieNeu = RephoneticizeTask.vieNeu

    let onSelect: () -> Void

    var body: some View {
        let items = FloatingHubActivity.items()
        let pending = FloatingHubActivity.counts().pending
        if !items.isEmpty || pending > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Text(caption(running: items.count, pending: pending))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .padding(.leading, 4)
                ForEach(items) { item in
                    row(item)
                }
            }
        }
    }

    private func caption(running: Int, pending: Int) -> String {
        guard running > 0 else { return "\(pending) tác vụ đang chờ" }
        return pending > 0 ? "Đang chạy (\(running)) · \(pending) đang chờ" : "Đang chạy (\(running))"
    }

    /// Cùng khung dòng với `FloatingHubMenuRow` (icon 17 pt khung 28, chữ 15 / 12, ô `hubSheetPanelRow`), thêm thanh.
    private func row(_ item: FloatingHubActivity.Item) -> some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(item.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    ProgressView(value: item.fraction)
                        .progressViewStyle(.linear)
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 8)
            .padding(.trailing, 4)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hubSheetPanelRow()
        .accessibilityHint(Text("Mở Thông báo"))
    }
}
