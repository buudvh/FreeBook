import SwiftUI

/// Dải báo "Có bản mới" của Kệ sách — cùng kiểu dải "truyện mất nguồn" (`MissingSourceRebindBanner`), đặt ngay dưới nó.
///
/// Dải **không** có nút cập nhật: bấm vào dải ⇒ sheet thay đổi (`AppUpdateSheet`), người dùng xem rồi mới đi cập nhật.
/// × ⇒ ẩn tới khi có bản mới hơn nữa (hàng ở Cài đặt › Thông Tin vẫn còn). Trạng thái nằm ở `AppUpdateRepository`.
struct AppUpdateBanner: View {
    /// Chỉ hiện ở tab Kệ sách.
    let isVisible: Bool

    @State private var sheetUpdate: AppUpdateInfo? = nil

    private var repository: AppUpdateRepository { .shared }

    var body: some View {
        let showsBanner = isVisible && repository.showsBanner
        VStack(spacing: 0) {
            if showsBanner, let update = repository.pendingUpdate {
                banner(update)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showsBanner)
        .sheet(item: $sheetUpdate) { update in
            AppUpdateSheet(update: update)
        }
    }

    private func banner(_ update: AppUpdateInfo) -> some View {
        HStack(spacing: 10) {
            Button {
                sheetUpdate = update
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.square")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text("Có bản mới \(update.version) · xem thay đổi")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Có bản mới \(update.version), xem thay đổi")

            Button {
                repository.dismissBanner()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ẩn")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
