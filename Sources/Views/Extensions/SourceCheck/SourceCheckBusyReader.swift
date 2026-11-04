import SwiftUI

/// Đọc "bộ chạy đang có lượt kiểm tra chạy ở nền" (`MinimizedSourceCheckCoordinator.isBusy`) để khoá lối mở lượt kiểm
/// tra mới (1.3.704): hàng ⋯ Kiểm tra nguồn / Kiểm tra tiện ích, "Kiểm tra nguồn này", nút Kiểm tra ở Cấu hình tiện ích.
/// Tự observe coordinator nên dùng được cả trong ngăn kéo ⋯ (cửa sổ nổi riêng, không nhận state của màn bên dưới).
///
/// Lối vào bị khoá phải vừa mờ vừa có chữ cho biết lý do — `MinimizedSourceCheck.busyLabel` (hàng rộng) hoặc
/// `shortBusyLabel` (nút nhỏ).
struct SourceCheckBusyReader<Content: View>: View {
    let kind: MinimizedSourceCheck.Kind
    @ViewBuilder let content: (Bool) -> Content

    @ObservedObject private var coordinator = MinimizedSourceCheckCoordinator.shared

    var body: some View {
        content(coordinator.isBusy(kind))
    }
}
