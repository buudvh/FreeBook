import SwiftUI

/// Màn **thuộc một nguồn** (Chi tiết truyện, danh sách thể loại, tìm trong một nguồn) tự đóng khi công tắc NSFW toàn
/// app bị tắt trong lúc màn còn mở — thường là màn nằm lại ở tab khác khi người dùng tắt NSFW ở Cài đặt / Kho.
///
/// - Chỉ đóng màn đã **thấy NSFW bật** lúc đang mở (bật lúc mở, hoặc bật trong lúc mở): màn mở khi NSFW đang tắt (sách
///   NSFW trên Kệ vẫn mở được) không bị đụng, trừ khi người dùng bật rồi tắt lại. Áp cả cho sách trên Kệ (người dùng
///   chốt 2026-10-24).
/// - `packageId` chụp ở lần xuất hiện đầu: Khám phá đổi nguồn khi NSFW tắt, màn thể loại đang mở được dựng lại với
///   nguồn **mới** — đọc giá trị sống thì không bao giờ đóng.
/// - Xét cả ở `onAppear`: màn ở tab không hiển thị / nằm dưới stack có thể chưa nhận `onChange` tới khi hiện lại.
///   `dismiss()` đẩy sang lượt main kế tiếp để không chạy giữa lúc chuyển cảnh.
struct NsfwSourceScreenGuard: ViewModifier {
    let packageId: String?
    /// Đọc **sống** (không chụp): Tìm kiếm chỉ là màn của một nguồn khi đang ở chế độ một nguồn.
    let isEnabled: Bool

    @AppStorage(RepositoryFilterPolicy.includeNsfwDefaultsKey) private var includeNsfw = false
    @Environment(\.dismiss) private var dismiss
    @State private var capturedPackageId: String?
    @State private var sawNsfwOn = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                if capturedPackageId == nil { capturedPackageId = packageId ?? "" }
                if includeNsfw { sawNsfwOn = true }
                closeIfHidden()
            }
            .onChange(of: includeNsfw) { _, isOn in
                if isOn {
                    sawNsfwOn = true
                } else {
                    closeIfHidden()
                }
            }
            .onChange(of: isEnabled) { _, _ in closeIfHidden() }
    }

    private func closeIfHidden() {
        guard isEnabled, sawNsfwOn, !includeNsfw,
              let id = capturedPackageId, !id.isEmpty,
              RepositoryFilterPolicy.isNsfwSource(packageId: id) else { return }
        sawNsfwOn = false
        AppLogger.shared.log("[NSFW] Công tắc NSFW vừa tắt ⇒ đóng màn của nguồn NSFW")
        DispatchQueue.main.async { dismiss() }
    }
}

extension View {
    /// Xem `NsfwSourceScreenGuard`. `packageId` rỗng/`nil` hoặc `isEnabled == false` ⇒ không làm gì.
    func closesWhenNsfwHidden(packageId: String?, isEnabled: Bool = true) -> some View {
        modifier(NsfwSourceScreenGuard(packageId: packageId, isEnabled: isEnabled))
    }
}
