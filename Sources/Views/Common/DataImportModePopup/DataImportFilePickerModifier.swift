import SwiftUI
import UniformTypeIdentifiers

/// Nhập **file** dữ liệu key–value: mở bộ chọn file **trước**, chọn xong mới hiện popup chọn cách nhập kèm **tên file** ở
/// dòng dưới tiêu đề (1.3.1011, anh Bửu: "hiện tại popup option nhập file hiển thị trước khi nhập file, sửa lại hiển thị
/// sau khi nhập file — hiển thị tên file nhập ở phần mô tả dưới tiêu đề nhập"). Gộp `DocumentPickerPresenter` +
/// `.dataImportModePopup` để mọi màn nhập dùng một khuôn.
///
/// ```swift
/// .dataImportFilePicker(isPresented: $showingImporter, allowedContentTypes: [.plainText, .text],
///                       title: "Nhập VietPhrase.txt") { url, mode in
///     importFile(url, mode: mode)
/// }
/// // Hàng "Nhập file…" của ngăn kéo chỉ còn: showingImporter = true
/// ```
///
/// - Bộ chọn file chạy chế độ bản sao (`asCopy`) ⇒ `url` nằm trong thư mục tạm của app, đọc được sau khi popup đóng, không
///   cần quyền truy cập theo phạm vi.
/// - Popup chỉ hiện **sau khi** bộ chọn file đóng hẳn (`isPresented` của bộ chọn về `false` — `onFinished` của
///   `DocumentPickerHostViewController` chạy ở nhịp sau khi host đã gỡ): trình bày cover lúc host còn đang đóng thì UIKit
///   bỏ qua.
/// - Huỷ chọn file ⇒ không có popup. Chạm ra ngoài popup ⇒ bỏ file đã chọn, không nhập. `onImport` chạy sau khi popup đóng
///   hẳn (chỗ gọi hiện toast / sheet ngay được).
struct DataImportFilePickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    let allowedContentTypes: [UTType]
    let title: String
    let modes: [DataImportMode]
    let initialMode: DataImportMode
    let onImport: (URL, DataImportMode) -> Void

    /// File vừa chọn — chờ bộ chọn đóng hẳn rồi hỏi cách nhập.
    @State private var pickedURL: URL?
    @State private var showingModes = false

    func body(content: Content) -> some View {
        content
            .background(
                DocumentPickerPresenter(
                    isPresented: $isPresented,
                    allowedContentTypes: allowedContentTypes,
                    allowsMultipleSelection: false,
                    onPick: { urls in pickedURL = urls.first },
                    onCancel: { pickedURL = nil }
                )
            )
            .onChange(of: isPresented) { _, presented in
                guard !presented, pickedURL != nil else { return }
                showingModes = true
            }
            .dataImportModePopup(
                isPresented: $showingModes,
                title: title,
                message: pickedURL?.lastPathComponent,
                confirmTitle: "Nhập",
                modes: modes,
                initialMode: initialMode
            ) { mode in
                guard let url = pickedURL else { return }
                pickedURL = nil
                onImport(url, mode)
            }
            .onChange(of: showingModes) { _, shown in
                // Đóng popup không bấm "Nhập" (chạm ra ngoài) ⇒ bỏ file. Đường bấm "Nhập" đã lấy `pickedURL` trong
                // `onConfirm` (chạy trước lượt `onChange` này) nên ở đây đã là `nil`.
                if !shown { pickedURL = nil }
            }
    }
}

extension View {
    /// Chọn file trước, rồi popup chọn cách nhập (tên file dưới tiêu đề) — xem `DataImportFilePickerModifier`.
    func dataImportFilePicker(
        isPresented: Binding<Bool>,
        allowedContentTypes: [UTType],
        title: String,
        modes: [DataImportMode] = DataImportMode.allCases,
        initialMode: DataImportMode = .overwriteExisting,
        onImport: @escaping (URL, DataImportMode) -> Void
    ) -> some View {
        modifier(DataImportFilePickerModifier(
            isPresented: isPresented,
            allowedContentTypes: allowedContentTypes,
            title: title,
            modes: modes,
            initialMode: initialMode,
            onImport: onImport
        ))
    }
}
