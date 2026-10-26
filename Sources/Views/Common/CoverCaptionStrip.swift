import SwiftUI

/// Dải chữ ở đáy bìa — một kiểu dùng chung cho kiểu "Chỉ bìa" (Kệ, Khám phá) và bìa ở header danh sách chương của
/// Reader, để chữ trên bìa đọc rõ như nhau ở mọi nơi.
///
/// - Nền: trong suốt → đen 75% trên đoạn `fadeHeight` phía trên chữ, rồi 75% → 95% sau chữ — tức đã đậm ngay từ dòng
///   đầu, không để dòng tên trên rơi vào phần nền còn mỏng. Phần chuyển **không** chiếm chỗ trong bố cục (nền tràn lên
///   trên bằng padding âm), nên nơi dùng xếp badge ngay trên dải như cũ; badge phải vẽ đè lên dải (`zIndex`).
/// - Nền tối thay vì `.ultraThinMaterial`: hiệu ứng làm mờ trên từng ô lưới tốn GPU khi cuộn nhanh. Bóng chữ chỉ gắn
///   trên từng `Text` (nhỏ, bán kính 1.5) — lưới nhiều cột mà giật thì bỏ bóng trước tiên, giữ nền đậm.
/// - Nơi dùng đặt dải trong `overlay(alignment: .bottom)` **trước** `clipShape` để nền tràn lên bị cắt theo bìa.
struct CoverCaptionStrip: View {
    /// Bìa dọc 2:3 trong lưới.
    static let regularFadeHeight: CGFloat = 44
    /// Bìa thấp (ngang 16:9) hoặc bìa nhỏ: phần chuyển cao như cũ thì che gần hết bìa.
    static let compactFadeHeight: CGFloat = 22

    var title: String? = nil
    var subtitle: String? = nil
    var titleLineLimit: Int = 2
    var fadeHeight: CGFloat = CoverCaptionStrip.regularFadeHeight

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(titleLineLimit)
                    .multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.9), radius: 1.5, x: 0, y: 1)
            }
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.9), radius: 1.5, x: 0, y: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .padding(.bottom, 5)
        .background(alignment: .bottom) {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0), Color.black.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: fadeHeight)
                LinearGradient(
                    colors: [Color.black.opacity(0.75), Color.black.opacity(0.95)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .padding(.top, -fadeHeight)
        }
        .allowsHitTesting(false)
    }
}
