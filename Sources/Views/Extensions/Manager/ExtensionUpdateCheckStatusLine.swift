import SwiftUI

/// Dòng trạng thái của `ExtensionUpdateCheckCoordinator` (1.3.673): đang chạy ⇒ vòng quay; xong ⇒ giờ kiểm tra; có kho
/// lỗi ⇒ chữ cam + "Thử lại". Dùng ở tab "Tất cả tiện ích" và trang Danh sách kho. Bản cập nhật tìm được hiện ở banner
/// cam "Cập nhật tất cả" sẵn có, không ở đây.
struct ExtensionUpdateCheckStatusLine: View {
    private var checker: ExtensionUpdateCheckCoordinator { .shared }

    /// Có gì để vẽ không — nơi gọi bỏ hẳn hàng/section khi `false`.
    @MainActor
    static var hasContent: Bool {
        let checker = ExtensionUpdateCheckCoordinator.shared
        return checker.isBusy || checker.lastOutcome != nil
    }

    var body: some View {
        HStack(spacing: 6) {
            if checker.isChecking {
                ProgressView()
                    .controlSize(.small)
                Text("Đang kiểm tra cập nhật…")
                    .foregroundColor(.secondary)
            } else if checker.isAddingRepository {
                ProgressView()
                    .controlSize(.small)
                Text("Đang tải dữ liệu kho…")
                    .foregroundColor(.secondary)
            } else if let outcome = checker.lastOutcome {
                if outcome.failedCount == 0 {
                    Text("Đã kiểm tra cập nhật lúc \(outcome.finishedAt.formatted(date: .omitted, time: .shortened))")
                        .foregroundColor(.secondary)
                } else {
                    Text(failureText(outcome))
                        .foregroundColor(.orange)
                    Button("Thử lại") { checker.checkNow() }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
    }

    private func failureText(_ outcome: ExtensionUpdateCheckCoordinator.Outcome) -> String {
        outcome.failedCount >= outcome.repositoryCount
            ? "Không kiểm tra được cập nhật"
            : "Không tải được \(outcome.failedCount)/\(outcome.repositoryCount) kho"
    }
}
