import SwiftUI

/// Làm mờ bìa nội dung nhạy cảm (NSFW) khi bật công tắc "Mờ bìa NSFW" (1.3.1019, anh Bửu duyệt mockup): góc phải hàng
/// tiêu đề sheet Kiểu hiển thị (`BookListLayoutSheet`) và Cài đặt › Giao diện › Nội dung nhạy cảm. Một khoá chung cho cả
/// app, mặc định **tắt**.
///
/// Hai cách biết bìa là NSFW:
/// - `BookCoverView` tự xét truyện qua `isNsfw` (`RepositoryFilterPolicy.isNsfwBook`: tự đánh dấu hoặc nguồn NSFW) ⇒ Kệ,
///   Lịch sử, Bộ sưu tập, Tìm trong Kệ, tab Tải, sheet nhấn giữ, Chi tiết (cả bìa lớn), đầu mục lục, widget TTS.
/// - `RemoteCoverImage` (danh sách tạm của một nguồn) đọc cờ môi trường `coversAreNsfw` do màn của nguồn đặt bằng
///   `.nsfwCoverContext(_:)` ⇒ Khám phá, Thể loại / Xem thêm, Tìm kiếm, đề xuất ở Chi tiết. Màn xem phim, màn nghe,
///   playlist, avatar bình luận không đặt cờ nên không mờ.
///
/// Luôn gắn `.blur` (bán kính 0 khi không mờ) thay vì rẽ nhánh `if`: đổi nhánh là đổi danh tính view ⇒ `@State` ảnh của ô
/// bìa dựng lại, bìa nháy placeholder mỗi lần bật / tắt.
struct NsfwCoverBlurModifier: ViewModifier {
    /// Khoá `@AppStorage` — chữ thường đầu để `BackupSettingsArchiver` tự sao lưu.
    static let defaultsKey = "nsfwCoverBlurEnabled"

    struct ContextKey: EnvironmentKey {
        static let defaultValue = false
    }

    /// Cỡ khung bìa — bán kính mờ theo cạnh ngắn (ô 44pt mờ ~6, bìa lớn Chi tiết ~20).
    let size: CGSize
    /// Xét thêm theo chính bìa; **chỉ gọi khi công tắc bật** (tra kho tiện ích đắt hơn đọc cờ).
    let isNsfw: () -> Bool

    @AppStorage(NsfwCoverBlurModifier.defaultsKey) private var isEnabled = false
    @Environment(\.coversAreNsfw) private var contextIsNsfw

    func body(content: Content) -> some View {
        let blurs = isEnabled && (contextIsNsfw || isNsfw())
        content.blur(radius: blurs ? max(6, min(size.width, size.height) * 0.12) : 0, opaque: blurs)
    }
}

extension EnvironmentValues {
    /// Bìa trong nhánh này thuộc nguồn / truyện NSFW (`NsfwCoverBlurModifier`).
    var coversAreNsfw: Bool {
        get { self[NsfwCoverBlurModifier.ContextKey.self] }
        set { self[NsfwCoverBlurModifier.ContextKey.self] = newValue }
    }
}

extension View {
    /// Làm mờ bìa này khi bật "Mờ bìa NSFW" và bìa là NSFW (`isNsfw` hoặc cờ môi trường `coversAreNsfw`). Gắn **trước**
    /// `.clipped()` / `clipShape` của khung bìa để phần mờ tràn ra ngoài bị cắt.
    func nsfwCoverBlur(size: CGSize, isNsfw: @escaping () -> Bool = { false }) -> some View {
        modifier(NsfwCoverBlurModifier(size: size, isNsfw: isNsfw))
    }

    /// Đánh dấu mọi bìa `RemoteCoverImage` trong nhánh là của nguồn / truyện NSFW (màn của một nguồn).
    func nsfwCoverContext(_ isNsfw: Bool) -> some View {
        environment(\.coversAreNsfw, isNsfw)
    }
}
