import SwiftUI

/// Hàng nút phát dưới đầu trang chi tiết playlist: "Phát tất cả" (nền đặc màu nhấn, theo thứ tự) và "Phát ngẫu nhiên"
/// (viền / chữ màu nhấn, xáo cả playlist). `onPlay(shuffled)`. Mỗi nút một kiểu riêng (không phải kiểu mặc định) nên trong
/// hàng `List` bấm nút nào chỉ nút đó chạy.
struct PlaylistPlayButtonsRow: View {
    let isDisabled: Bool
    let onPlay: (_ shuffled: Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onPlay(false)
            } label: {
                Label("Phát tất cả", systemImage: "play.fill")
                    .lineLimit(1)
            }
            .buttonStyle(.appFilled)

            Button {
                onPlay(true)
            } label: {
                Label("Phát ngẫu nhiên", systemImage: "shuffle")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.6), lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tint)
        }
        .disabled(isDisabled)
        .padding(.vertical, 4)
    }
}
