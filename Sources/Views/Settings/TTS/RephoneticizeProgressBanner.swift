import SwiftUI

/// Banner **tiến độ "Phiên âm lại từ điển"** hiện ngay trên màn từ điển phiên âm — cùng nội dung với card ở
/// màn Thông báo (`NotificationInboxView+Rephoneticize.swift`), nhưng gọn và nằm ngay chỗ người dùng vừa bấm.
///
/// ## Vì sao là `ViewModifier` chứ không viết thẳng vào View
/// `VieNeuJapaneseDictionaryView.swift` đang **397/400** dòng và `TTSDictionaryEditView.swift` **530**
/// (baseline 641) ⇒ thêm thẳng vào đó là chạm trần. Modifier chỉ cần **một dòng** ở mỗi màn.
///
/// ## Không chạm đĩa
/// Mọi con số đọc từ `@Published` **đã nằm trong RAM** của `RephoneticizeTask` (`phase`, `meta`,
/// `lastOutcome`) — cùng nguyên tắc với card ở màn Thông báo (bài học 1.3.448: parse file lớn trong `body`
/// làm đơ app + nghẽn TTS).
@MainActor
struct RephoneticizeProgressBanner: ViewModifier {
    @ObservedObject var task: RephoneticizeTask
    /// Gọi sau khi **áp** hoặc **bỏ** kết quả để màn nạp lại danh sách từ điển.
    let onChanged: () -> Void

    @State private var isApplying = false
    @State private var errorMessage = ""

    /// Khai `init` tường minh: hai `@State` trên là `private` nên `init` memberwise do compiler sinh sẽ mang
    /// mức truy cập `private`, không gọi được từ `extension View` bên dưới.
    init(task: RephoneticizeTask, onChanged: @escaping () -> Void) {
        self._task = ObservedObject(wrappedValue: task)
        self.onChanged = onChanged
    }

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if task.isVisible {
                banner
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial)
            }
        }
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(task.statusText)
                    .font(.caption)
                    .foregroundStyle(task.isFailed ? Color.red : Color.secondary)
            }

            if let progress = task.runningProgress {
                ProgressView(value: progress)
            }

            if task.hasResult {
                resultActions
            } else if task.isFailed {
                Button("Thử lại") { task.start() }
                    .buttonStyle(.bordered)
                    .font(.footnote)
            }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.red)
            }
        }
    }

    /// Cùng hai hành động như card ở màn Thông báo: áp kết quả, hoặc bỏ. Nút **Xuất file** chỉ có ở Thông
    /// báo — ở đây banner phải gọn để không che danh sách từ điển.
    private var resultActions: some View {
        HStack(spacing: 8) {
            Button {
                applyResult()
            } label: {
                Group {
                    if isApplying {
                        ProgressView()
                    } else {
                        Text("Nhập vào từ điển")
                    }
                }
                .frame(maxWidth: .infinity)
                .foregroundColor(.white)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.204, green: 0.780, blue: 0.349))
            .disabled(isApplying)

            Button(role: .destructive) {
                task.discardResult()
                onChanged()
            } label: {
                Text("Bỏ qua").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .font(.footnote)
    }

    private func applyResult() {
        guard !isApplying else { return }
        isApplying = true
        errorMessage = ""
        Task {
            do {
                try await task.apply()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Nhập thất bại: \(error.localizedDescription)"
            }
            isApplying = false
            onChanged()
        }
    }
}

extension View {
    /// Gắn banner tiến độ "Phiên âm lại" vào màn từ điển phiên âm. Xem `RephoneticizeProgressBanner`.
    func rephoneticizeProgress(task: RephoneticizeTask, onChanged: @escaping () -> Void) -> some View {
        modifier(RephoneticizeProgressBanner(task: task, onChanged: onChanged))
    }
}
