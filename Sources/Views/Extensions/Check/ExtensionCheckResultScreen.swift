import SwiftUI

/// Màn xem **một** tiện ích của lượt Kiểm tra hàng loạt (đẩy từ `ExtensionCheckView`): danh sách từng script
/// (`ExtensionCheckDetailContent`), nút "Chạy lại" tiện ích này, và trình duyệt "Mở link lỗi" — đóng trình duyệt ⇒ tự
/// chạy lại tiện ích này (`ExtensionCheckRunner.retry`).
///
/// Tự thăm dò runner mỗi giây khi lượt đang chạy: màn hàng loạt bên dưới đã ẩn nên `task` thăm dò của nó bị huỷ.
struct ExtensionCheckResultScreen: View {
    let packageId: String
    let name: String

    @State private var report: ExtensionCheckReport?
    @State private var openingLink: SourceErrorLink?
    @State private var pollGeneration = 0
    @State private var message: String?

    private var isRunning: Bool { report?.state == .running }

    var body: some View {
        VStack(spacing: 8) {
            ExtensionCheckDetailContent(result: report?.result(packageId: packageId), openingLink: $openingLink)
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            Button(action: retry) {
                Label(isRunning ? "Đang chạy…" : "Chạy lại tiện ích này", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundColor(.blue)
                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(isRunning)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: pollGeneration) { await poll() }
        .errorLinkBrowser(link: $openingLink, packageId: packageId, onRetry: retry)
    }

    private func poll() async {
        while !Task.isCancelled {
            report = await ExtensionCheckRunner.shared.status()
            if report?.state != .running { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func retry() {
        Task { @MainActor in
            do {
                report = try await ExtensionCheckRunner.shared.retry(packageId: packageId)
                message = nil
                pollGeneration += 1
            } catch let error as ExtensionCheckRunner.StartError {
                message = error.message
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
