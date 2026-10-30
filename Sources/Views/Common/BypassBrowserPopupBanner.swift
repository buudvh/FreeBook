import SwiftUI

/// Dải báo **"Đã chặn cửa sổ bật lên"** của trình duyệt người dùng (plan §3.1), đọc `store.blockedPopup`. Nằm ở đầu
/// cụm nổi phía dưới: trên viên Import (nếu có) và thanh kính dưới, nên không bị thanh che.
///
/// - Dòng phụ: tên miền đích; cửa sổ trống (`isBlank`) ⇒ `(cửa sổ trống)` và **không** có nút Mở.
/// - **Mở** ⇒ `store.openBlockedPopup()` (mở tab mới); **✕** ⇒ `store.dismissBlockedPopup()`.
/// - Tự ẩn sau ~5 s. Hẹn giờ gắn theo `id` của đúng popup đang báo: popup mới thay thế thì hẹn giờ cũ bị huỷ,
///   và chỉ xoá dải báo khi nó vẫn là popup đó (`dismissBlockedPopup()` xoá vô điều kiện).
///
/// Phong cách tối của thanh địa chỉ (`systemGray6`, chữ trắng); ép bảng màu tối cho riêng dải này để chữ trắng
/// luôn đọc được.
struct BypassBrowserPopupBanner: View {
    @ObservedObject var store: BypassBrowserTabStore

    private static let autoHideNanoseconds: UInt64 = 5_000_000_000

    var body: some View {
        ZStack {
            if let popup = store.blockedPopup {
                banner(for: popup)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: popup.id) {
                        await autoHide(popupId: popup.id)
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.blockedPopup?.id)
    }

    private func banner(for popup: BypassBrowserBlockedPopup) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "xmark.shield.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Đã chặn cửa sổ bật lên")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(subtitle(for: popup))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            if !popup.isBlank {
                Button {
                    store.openBlockedPopup()
                } label: {
                    Text("Mở")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .frame(minWidth: 52, minHeight: 32)
                        .background(Color.white.opacity(0.18), in: Capsule())
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button {
                store.dismissBlockedPopup()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Đóng thông báo")
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .environment(\.colorScheme, .dark)
    }

    private func subtitle(for popup: BypassBrowserBlockedPopup) -> String {
        if popup.isBlank { return "(cửa sổ trống)" }
        return popup.host ?? popup.url?.absoluteString ?? ""
    }

    /// `Task.sleep` ném lỗi khi bị huỷ (popup khác thay thế / dải báo rời màn) ⇒ thoát, không xoá gì.
    private func autoHide(popupId: UUID) async {
        do {
            try await Task.sleep(nanoseconds: Self.autoHideNanoseconds)
        } catch {
            return
        }
        guard store.blockedPopup?.id == popupId else { return }
        store.dismissBlockedPopup()
    }
}
