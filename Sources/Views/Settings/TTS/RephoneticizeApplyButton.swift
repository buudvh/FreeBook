import SwiftUI

/// Nút **"Nhập vào từ điển"** ở kết quả "Phiên âm lại" — dùng chung cho card màn **Thông báo** và banner
/// màn **từ điển**, để hai chỗ không bao giờ lệch nhau.
///
/// ## Hộp thoại *Trộn / Thay thế toàn bộ* thuộc **bước áp**, không thuộc nhập file
/// 1.3.462 gắn hộp thoại này vào đường **nhập từ điển từ file** — sai ý người dùng. Nó thuộc về nút này:
/// bấm "Nhập vào từ điển" mới hỏi, còn nhập file thì âm thầm theo hành vi cũ của từng màn.
///
/// ## Vì sao là một `View` riêng thay vì chép vào hai chỗ
/// Hai chỗ cần đúng **một** định nghĩa "Trộn là gì, Thay thế là gì". Chép ra hai bản thì một bên dễ quên
/// bước sao lưu `.bak-rephoneticize` — và đó là lượt ghi đè toàn bộ từ điển (NghiTTS ~30k mục).
@MainActor
struct RephoneticizeApplyButton: View {
    @ObservedObject var task: RephoneticizeTask
    /// Nhãn nút. Mặc định "Nhập vào từ điển".
    let title: String
    /// Gọi sau khi **áp** (cả hai nhánh) để màn nạp lại danh sách từ điển.
    let onChanged: () -> Void

    @State private var isApplying = false
    @State private var errorMessage = ""
    @State private var showingModeDialog = false
    @State private var showingMergeSheet = false

    /// Xem `DictionaryImportConflictView.accent`: **không** dùng `Color.accentColor` vì app đặt
    /// `.tint(.white)` toàn cục (`MainTabView.swift:38`).
    private let accent = Color(red: 0.204, green: 0.780, blue: 0.349)

    /// Khai `init` tường minh: các `@State` trên là `private`, nên `init` memberwise do compiler sinh sẽ
    /// mang mức truy cập `private` và không gọi được từ file khác.
    init(task: RephoneticizeTask, title: String = "Nhập vào từ điển", onChanged: @escaping () -> Void) {
        self._task = ObservedObject(wrappedValue: task)
        self.title = title
        self.onChanged = onChanged
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            button

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.red)
            }
        }
        .frame(maxWidth: .infinity)
        .confirmationDialog(
            "Áp kết quả bằng cách nào?",
            isPresented: $showingModeDialog,
            titleVisibility: .visible
        ) {
            Button("Trộn — chọn từng mục") { showingMergeSheet = true }
            Button("Thay thế toàn bộ", role: .destructive) { replaceAll() }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("**Trộn** giữ từ điển đang có rồi hỏi bạn từng mục trùng khoá nhưng khác nghĩa; khoá mới được thêm tự động. **Thay thế toàn bộ** xoá sạch từ điển hiện tại — cả hai đều có sao lưu `.bak-rephoneticize`.")
        }
        .sheet(isPresented: $showingMergeSheet) {
            if let url = task.resultFileURL {
                DictionaryImportConflictView(
                    fileURL: url,
                    title: "Chọn mục cần thay",
                    normalizedKey: task.normalizedKey,
                    currentProvider: task.currentWordsProvider,
                    onApply: applyMerged
                )
            }
        }
    }

    private var button: some View {
        Button { showingModeDialog = true } label: {
            Group {
                if isApplying {
                    ProgressView()
                } else {
                    Text(title)
                }
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.white)
        }
        .buttonStyle(.borderedProminent)
        .tint(accent)
        .disabled(isApplying)
    }

    // MARK: - Hai nhánh áp

    /// Nhánh **Trộn**: màn chọn mục đã dựng sẵn bảng cuối ⇒ ở đây chỉ việc ghi (có sao lưu).
    private func applyMerged(_ words: [String: String]) {
        run {
            try await task.applyMerged(words)
        }
    }

    /// Nhánh **Thay thế toàn bộ**: đọc thẳng file kết quả rồi ghi đè (có sao lưu).
    private func replaceAll() {
        run {
            try await task.apply()
        }
    }

    /// Một khung duy nhất cho cả hai nhánh: chặn bấm kép, gom lỗi, rồi báo `onChanged`.
    private func run(_ body: @escaping () async throws -> Void) {
        guard !isApplying else { return }
        isApplying = true
        errorMessage = ""
        Task {
            do {
                try await body()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Nhập thất bại: \(error.localizedDescription)"
            }
            isApplying = false
            onChanged()
        }
    }
}
