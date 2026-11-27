import SwiftUI

/// Trình bày popup **chọn cách nhập** giữa màn (`DataImportModePopup`, 1.3.982). Nhập **file** thì đừng gọi thẳng — dùng
/// `.dataImportFilePicker(...)` (`DataImportFilePickerModifier`, 1.3.1011): chọn file trước, popup hiện sau kèm tên file.
/// Gọi thẳng modifier này cho chỗ nhập không qua file (nhập từ truyện khác, chia sẻ sang truyện khác…) — chọn nguồn
/// trước rồi mới hỏi cách nhập, truyền tên nguồn vào `message`. Ngoại lệ do anh Bửu chốt: lọc rác không hỏi — nhập chỉ
/// thêm mẫu chưa có (1.3.988).
///
/// ```swift
/// .dataImportModePopup(isPresented: $askMode, title: "Nhập từ truyện khác", message: book.title,
///                      confirmTitle: "Nhập", confirmSystemImage: "arrow.down.doc") { mode in … }
/// ```
///
/// - Cơ chế: `fullScreenCover` nền trong (`presentationBackground(.clear)`), mở / đóng **không** hiệu ứng trượt (transaction
///   tắt animation); thẻ tự hiện mờ dần. Cover phủ cả thanh điều hướng nên lớp tối che hết, nút header không bấm nhầm được.
/// - `onConfirm(mode)` chạy **sau khi** cover đóng hẳn (`onDismiss`) — chỗ gọi trình bày sheet / bộ chọn ngay trong đó được.
/// - Chạm ra ngoài thẻ ⇒ đóng, không gọi `onConfirm`; `isPresented` tự về `false` ở mọi đường đóng.
/// - Mặc định chọn `.overwriteExisting` ("Gộp"): "Thay thế toàn bộ" xoá dữ liệu cũ nên không để sẵn.
/// - Danh sách chỉ có khoá (vd danh sách rule tắt): "Gộp" và "Chỉ thêm key mới" cho cùng kết quả — vẫn hiện đủ ba cho
///   đồng bộ (anh Bửu: "nhập luôn có 3 option").
/// - Không phải nhập (Lưu ở màn duyệt name, plan 2026-11-27-phan-loai-name L16): `messageSystemImage` + `explanations`
///   cho icon dòng dưới tiêu đề và lời giải thích ba chế độ theo ngữ cảnh; bỏ trống ⇒ icon file + lời của `DataImportMode`.
struct DataImportModePopupModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    /// Dòng dưới tiêu đề (tên file / tên nguồn); `nil` ⇒ "Chọn cách nhập".
    let message: String?
    let messageSystemImage: String
    let explanations: [DataImportMode: String]
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
                    message: message,
                    messageSystemImage: messageSystemImage,
                    explanations: explanations,
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
    /// Popup giữa màn chọn một trong ba `DataImportMode` rồi bấm nút cuối (mặc định "Nhập") — xem
    /// `DataImportModePopupModifier`. `onConfirm` chạy sau khi popup đóng hẳn. Nhập file ⇒ `.dataImportFilePicker`.
    func dataImportModePopup(
        isPresented: Binding<Bool>,
        title: String,
        message: String? = nil,
        messageSystemImage: String = DataImportModePopup.fileMessageIcon,
        explanations: [DataImportMode: String] = [:],
        confirmTitle: String = "Nhập",
        confirmSystemImage: String = "square.and.arrow.down",
        modes: [DataImportMode] = DataImportMode.allCases,
        initialMode: DataImportMode = .overwriteExisting,
        onConfirm: @escaping (DataImportMode) -> Void
    ) -> some View {
        modifier(DataImportModePopupModifier(
            isPresented: isPresented,
            title: title,
            message: message,
            messageSystemImage: messageSystemImage,
            explanations: explanations,
            confirmTitle: confirmTitle,
            confirmSystemImage: confirmSystemImage,
            modes: modes,
            initialMode: initialMode,
            onConfirm: onConfirm
        ))
    }
}
