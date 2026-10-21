import Foundation

/// Phiên engine có người dùng đang nhìn hay không (spec §10.8 "ngữ cảnh không có người dùng").
///
/// Mặc định **không** (an toàn cho tải nền, tải trước chương, kiểm tra hàng loạt, bộ nghiệm thu): `java.startBrowser`
/// chỉ ghi log, `startBrowserAwait` trả phản hồi rỗng (`code() == 0`), `getVerificationCode` trả `""`.
///
/// Lối vào do người dùng bấm (mở trang sách, đọc chương đang mở, đăng nhập, khám phá) bọc lời gọi:
/// ```swift
/// try await LegadoInteraction.$isInteractive.withValue(true) {
///     try await SourceRuntime.shared.detail(...)
/// }
/// ```
/// `LegadoEngineSession.run` đọc giá trị này (task-local, đi theo `Task {}` con nhưng **không** theo `Task.detached`)
/// trước khi tạo thread engine; trong `body` vẫn sửa được `session.allowsUserInteraction`.
enum LegadoInteraction {
    @TaskLocal static var isInteractive = false
}
