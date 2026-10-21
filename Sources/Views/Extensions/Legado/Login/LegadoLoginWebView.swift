import SwiftUI

/// **Đăng nhập trên web** của nguồn Legado (spec §10.2): trình duyệt nhỏ Huỷ / URL / Xong. "Xong" ⇒ cookie của các tên
/// miền đã ghé được gộp vào kho cookie của nguồn qua `LegadoLoginService.importWebCookies` (kèm mốc "kiểm tra lúc");
/// "Huỷ" ⇒ không lưu gì.
///
/// `importsCookies == false` dùng cho liên kết `http(s)` trong `action` của form (trang đăng ký, hướng dẫn…): chỉ xem,
/// không nhập cookie.
struct LegadoLoginWebView: View {
    let request: LegadoBrowserRequest
    let source: LegadoEngineSource
    var importsCookies = true
    /// `true` khi đã nhập cookie.
    let onFinish: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LegadoBrowserSheet(request: request) { snapshot, cancelled in
            let shouldImport = importsCookies && !cancelled
            Task { @MainActor in
                if shouldImport {
                    await LegadoLoginService.importWebCookies(snapshot.cookies, source: source)
                }
                onFinish(shouldImport)
                dismiss()
            }
        }
    }
}
