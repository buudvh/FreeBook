import SwiftUI

/// Trình bày popup **chọn cách nhập** giữa màn (`DataImportModePopup`, 1.3.982). Mọi chỗ nhập dữ liệu dạng key–value
/// (từ điển, rule dịch, phiên âm, thay thế ký tự, lọc rác, quy tắc mục lục, công cụ tra cứu…) đi qua đây, theo thứ tự
/// **chọn cách nhập trước ⇒ bấm nút cuối ⇒ chỗ gọi mở bộ chọn file**.
///
/// ```swift
/// .dataImportModePopup(isPresented: $showingImportModes, title: "Nhập VietPhrase.txt") { mode in
///     pendingImportMode = mode
///     showingFileImporter = true          // trình bày được ngay: popup đã đóng hẳn
/// }
/// // Không chọn file (nhập từ truyện khác…): đổi chữ nút cuối.
/// .dataImportModePopup(isPresented: $askMode, title: "Nhập từ \(book.title)",
///                      confirmTitle: "Nhập", confirmSystemImage: "arrow.down.doc") { mode in … }
/// ```
///
/// - Cơ chế: `fullScreenCover` nền trong (`presentationBackground(.clear)`), mở / đóng **không** hiệu ứng trượt (transaction
///   tắt animation); thẻ tự hiện mờ dần. Cover phủ cả thanh điều hướng nên lớp tối che hết, nút header không bấm nhầm được.
/// - `onConfirm(mode)` chạy **sau khi** cover đóng hẳn (`onDismiss`) — UIKit không cho trình bày bộ chọn file từ màn đang
///   đóng, nên chỗ gọi mở bộ chọn file / sheet ngay trong `onConfirm` là được.
/// - Chạm ra ngoài thẻ ⇒ đóng, không gọi `onConfirm`; `isPresented` tự về `false` ở mọi đường đóng.
/// - Mặc định chọn `.overwriteExisting` ("Gộp"): "Thay thế toàn bộ" xoá dữ liệu cũ nên không để sẵn.
/// - Danh sách chỉ có khoá (vd danh sách rule tắt): "Gộp" và "Chỉ thêm key mới" cho cùng kết quả — vẫn hiện đủ ba cho
///   đồng bộ (anh Bửu: "nhập luôn có 3 option").
struct DataImportModePopupModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let confirmTitle: String
    let confirmSystemImage: String
    let modes: [DataImportMode]
    let initialMode: DataImportMode
    let onConfirm: (DataImportMode) -> Void

    @State private var coverShown = false
    /// Chế độ đã chọn bằng nút cuối — chờ cover đóng hẳn mới giao cho chỗ gọi.
    @State private var confirmedMode: DataImportMode?

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, shown in
                guard shown != coverShown else { return }
                if shown { confirmedMode = nil }
                Self.withoutAnimation { coverShown = shown }
            }
            .fullScreenCover(isPresented: $coverShown, onDismiss: handleDismiss) {
                DataImportModePopup(
                    title: title,
                    confirmTitle: confirmTitle,
                    confirmSystemImage: confirmSystemImage,
                    modes: modes,
                    initialMode: initialMode,
                    onConfirm: { mode in
                        confirmedMode = mode
                        close()
                    },
                    onCancel: close
                )
                .presentationBackground(.clear)
            }
    }

    private func close() {
        Self.withoutAnimation { coverShown = false }
    }

    private func handleDismiss() {
        if isPresented { isPresented = false }
        guard let mode = confirmedMode else { return }
        confirmedMode = nil
        onConfirm(mode)
    }

    private static func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }
}

extension View {
    /// Popup giữa màn chọn một trong ba `DataImportMode` rồi bấm nút cuối (mặc định "Nhập file") — xem
    /// `DataImportModePopupModifier`. `onConfirm` chạy sau khi popup đóng hẳn.
    func dataImportModePopup(
        isPresented: Binding<Bool>,
        title: String,
        confirmTitle: String = "Nhập file",
        confirmSystemImage: String = "square.and.arrow.down",
        modes: [DataImportMode] = DataImportMode.allCases,
        initialMode: DataImportMode = .overwriteExisting,
        onConfirm: @escaping (DataImportMode) -> Void
    ) -> some View {
        modifier(DataImportModePopupModifier(
            isPresented: isPresented,
            title: title,
            confirmTitle: confirmTitle,
            confirmSystemImage: confirmSystemImage,
            modes: modes,
            initialMode: initialMode,
            onConfirm: onConfirm
        ))
    }
}
