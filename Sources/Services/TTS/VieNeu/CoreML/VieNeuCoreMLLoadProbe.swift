import Foundation
import Observation

/// Trạng thái phép đo P2a **"Đo nạp Core ML"** ở màn thử VieNeu Turbo — phần tính ở `VieNeuCoreMLLoadWorker`, chạy
/// trong `Task.detached(priority: .userInitiated)` (như trình đọc). Lượt ngắn (vài phút, màn giữ sáng) nên không có
/// Chạy tiếp; bị ngắt giữa phép thử bỏ trọng số thì file đổi tên được trả về ở lần mở màn thử / lần chạy sau.
///
/// Dùng chung gói + bản biên dịch của "Đo tự động" (`VieNeuCoreMLPackage`); không tải, không biên dịch thêm.
@MainActor
@Observable
final class VieNeuCoreMLLoadProbe {
    let package: VieNeuCoreMLPackage?

    /// Gói đủ file và đã có bản biên dịch (lượt Đo tự động đã chạy qua bước chuẩn bị).
    private(set) var isReady = false
    private(set) var isRunning = false
    private(set) var statusLine = ""
    private(set) var summaryLines: [String] = []
    private(set) var errorMessage: String?
    private(set) var hasReport = false

    @ObservationIgnored private var report = ""
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var computeTask: Task<VieNeuCoreMLLoadWorker.Outcome, Error>?

    init() {
        package = try? VieNeuCoreMLPackage()
        if let package {
            VieNeuCoreMLCacheInventory.restoreTrimmed(package.cacheDirectory)
        }
        refresh()
    }

    var canRun: Bool { isReady && !isRunning }

    func refresh() {
        guard !isRunning else { return }
        guard let package else {
            isReady = false
            return
        }
        isReady = package.isComplete && package.cacheBytes > 0
    }

    /// `prepare` (màn thử) dừng TTS + các lượt khác, nhả Turbo và engine Nano — chạy xong mới đo, để CPU của tiến trình
    /// chỉ là phần nạp.
    func start(prepare: @escaping @MainActor () async -> Void) {
        guard canRun, let package, let manifest = package.manifest else { return }
        isRunning = true
        errorMessage = nil
        summaryLines = []
        hasReport = false
        report = ""
        statusLine = "Đang chuẩn bị (dừng TTS, nhả model đang nạp)…"
        AppLogger.shared.log("🎙️ [VieNeuCoreMLLoad] Bắt đầu đo nạp — \(ProcessMemoryProbe.snapshot().summary)")
        runTask = Task { [weak self] in
            await prepare()
            // Bấm Dừng trong lúc chuẩn bị: task tách rời không thừa hưởng huỷ — đừng bắt đầu đo.
            guard !Task.isCancelled else {
                self?.statusLine = "Đã dừng."
                self?.isRunning = false
                self?.refresh()
                return
            }
            let progress: @Sendable (String) -> Void = { [weak self] line in
                Task { @MainActor [weak self] in
                    guard let self, self.isRunning else { return }
                    self.statusLine = line
                }
            }
            let compute = Task.detached(priority: .userInitiated) {
                try VieNeuCoreMLLoadWorker.run(package: package, manifest: manifest, progress: progress)
            }
            self?.computeTask = compute
            do {
                let outcome = try await compute.value
                self?.finish(outcome)
            } catch is CancellationError {
                self?.statusLine = "Đã dừng (file trọng số đã trả về)."
            } catch {
                self?.errorMessage = "Đo nạp lỗi: \(error.localizedDescription)"
                AppLogger.shared.log("❌ [VieNeuCoreMLLoad] Đo nạp lỗi: \(error.localizedDescription)")
            }
            self?.isRunning = false
            self?.computeTask = nil
            self?.refresh()
        }
    }

    func stop() {
        guard isRunning else { return }
        computeTask?.cancel()
        runTask?.cancel()
        statusLine = "Đang dừng sau bước hiện tại…"
    }

    private func finish(_ outcome: VieNeuCoreMLLoadWorker.Outcome) {
        report = outcome.report
        summaryLines = outcome.summary
        hasReport = true
        statusLine = "Xong — chia sẻ file kết quả để gửi."
    }

    /// Thân file `.txt` (`VieNeuTurboReportFile` thêm phần đầu: app, máy, giờ).
    func reportText() -> String {
        report.isEmpty ? (errorMessage ?? statusLine) : report
    }
}
