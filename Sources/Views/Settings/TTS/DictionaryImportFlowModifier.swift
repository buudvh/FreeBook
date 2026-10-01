import SwiftUI

/// Luồng **nhập từ điển từ file**: hỏi *Trộn* hay *Thay thế toàn bộ*, rồi mở màn chọn từng mục trùng khoá.
///
/// Gom vào một `ViewModifier` dùng chung vì hai màn từ điển (NghiTTS + VieNeu) có **cùng** luồng nhưng khác
/// store: để trong từng View thì phải chép `@State` + dialog + sheet hai lần, mà `TTSDictionaryEditView` lại
/// đang bị ràng buộc ratchet-down (chỉ được giảm dòng).
///
/// Nhận **URL** chứ không nhận bảng đã parse: màn chọn mục trùng phải mở **ngay** khi bấm, còn việc đọc +
/// parse file (tới ~30k mục) chạy ngầm phía sau skeleton.
///
/// ## ⚠️ Vì sao cờ `isModeDialogPresented` do **caller** sở hữu, không phải `@State` ở đây
/// Bản đầu tiên dùng `.onChange(of: fileURL)` để mở hộp thoại, và **nó không hiện**. Nguyên nhân: `onPick`
/// của `DocumentPicker` chạy trong **completion của lượt dismiss** sheet chọn file, nên cờ được bật **đúng
/// lúc** sheet đang chạy animation đóng — UIKit/SwiftUI **nuốt im lặng** một presentation bắt đầu giữa lượt
/// dismiss của modal khác. Hệ quả: không hộp thoại nào hiện, mà `fileURL` vẫn còn giá trị nên chọn lại đúng
/// file đó cũng **không** kích hoạt lại (`.onChange` thấy giá trị không đổi).
///
/// Cách chữa: bật cờ từ `onDismiss` của sheet chọn file — hook này chỉ chạy **sau khi** animation đóng xong.
/// Vì hook đó nằm ở View gọi, cờ phải do View gọi sở hữu và truyền vào đây.
@MainActor
struct DictionaryImportFlowModifier: ViewModifier {
    @Binding var fileURL: URL?
    /// Xem doc ở đầu type. View gọi bật cờ này trong `onDismiss` của sheet chọn file.
    @Binding var isModeDialogPresented: Bool
    let title: String
    /// Phải `@Sendable`: nó được capture trong `Task.detached` của `replaceAll()`.
    let normalizedKey: @Sendable (String) -> String
    let current: [String: String]
    /// Nhánh **Thay thế toàn bộ** — caller tự ghi (kèm sao lưu của nó).
    let onReplace: ([String: String]) -> Void
    /// Nhánh **Trộn** — caller ghi bảng đã trộn.
    let onApplyMerged: ([String: String]) -> Void

    @State private var showingConflictSheet = false
    @State private var isReplacing = false
    @State private var errorMessage: String?

    /// Khai `init` **tường minh**: các `@State` ở trên là `private`, nên `init` memberwise do compiler sinh
    /// sẽ mang mức truy cập `private` và **không** gọi được từ `extension View` bên dưới.
    init(
        fileURL: Binding<URL?>,
        isModeDialogPresented: Binding<Bool>,
        title: String,
        normalizedKey: @escaping @Sendable (String) -> String,
        current: [String: String],
        onReplace: @escaping ([String: String]) -> Void,
        onApplyMerged: @escaping ([String: String]) -> Void
    ) {
        self._fileURL = fileURL
        self._isModeDialogPresented = isModeDialogPresented
        self.title = title
        self.normalizedKey = normalizedKey
        self.current = current
        self.onReplace = onReplace
        self.onApplyMerged = onApplyMerged
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Nhập từ điển bằng cách nào?",
                isPresented: $isModeDialogPresented,
                titleVisibility: .visible
            ) {
                Button("Trộn — chọn từng mục trùng") { showingConflictSheet = true }
                Button("Thay thế toàn bộ", role: .destructive) { replaceAll() }
                Button("Huỷ", role: .cancel) { clearRequest() }
            } message: {
                Text("**Trộn** giữ từ điển đang có rồi hỏi bạn từng mục trùng khoá nhưng khác nghĩa. **Thay thế toàn bộ** xoá sạch từ điển hiện tại — có sao lưu `.bak-import`.")
            }
            .sheet(isPresented: $showingConflictSheet, onDismiss: clearRequest) {
                if let url = fileURL {
                    DictionaryImportConflictView(
                        fileURL: url,
                        title: title,
                        normalizedKey: normalizedKey,
                        current: current,
                        onApply: onApplyMerged
                    )
                }
            }
            .overlay { replacingOverlay }
            .alert("Nhập từ điển thất bại", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Đóng", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }

    @ViewBuilder
    private var replacingOverlay: some View {
        if isReplacing {
            ProgressView("Đang thay thế từ điển…")
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func clearRequest() {
        fileURL = nil
    }

    /// Nhánh **Thay thế toàn bộ**: đọc + parse **ngoài main** rồi giao bảng cho caller ghi.
    private func replaceAll() {
        guard let url = fileURL else { return }
        isReplacing = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                () -> (words: [String: String]?, message: String?) in
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                do {
                    return (try DictionaryImportParser.parse(url: url), nil)
                } catch {
                    return (nil, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                }
            }.value

            isReplacing = false
            if let words = outcome.words {
                onReplace(words)
            } else {
                errorMessage = outcome.message ?? "File không phải từ điển hợp lệ."
            }
            clearRequest()
        }
    }
}

extension View {
    /// Gắn luồng nhập từ điển vào một màn. Xem `DictionaryImportFlowModifier`.
    ///
    /// - Important: View gọi **phải** bật `isModeDialogPresented` trong `onDismiss` của sheet chọn file —
    ///   bật ngay trong `onPick` sẽ bị nuốt (xem doc ở đầu `DictionaryImportFlowModifier`).
    func dictionaryImportFlow(
        fileURL: Binding<URL?>,
        isModeDialogPresented: Binding<Bool>,
        title: String,
        normalizedKey: @escaping @Sendable (String) -> String,
        current: [String: String],
        onReplace: @escaping ([String: String]) -> Void,
        onApplyMerged: @escaping ([String: String]) -> Void
    ) -> some View {
        modifier(DictionaryImportFlowModifier(
            fileURL: fileURL,
            isModeDialogPresented: isModeDialogPresented,
            title: title,
            normalizedKey: normalizedKey,
            current: current,
            onReplace: onReplace,
            onApplyMerged: onApplyMerged
        ))
    }
}
