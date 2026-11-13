import Foundation
import Observation

/// Trạng thái phép đo **"Đo nạp Core ML"** ở màn thử VieNeu Turbo (P2a 1.3.912, P2b-0 1.3.913, P2b-1 1.3.915) — phần
/// tính ở `VieNeuCoreMLLoadWorker`, chạy trong `Task.detached(priority: .userInitiated)` (như trình đọc). Lượt ngắn (vài
/// phút, màn giữ sáng) nên không có Chạy tiếp. File trọng số mà bản 1.3.912 đổi tên lúc bị ngắt được trả về khi mở màn thử.
///
/// P2b-1: mỗi lượt **làm mới gói trước** (`VieNeuCoreMLPackage.download` — tải phần đổi theo sha256; có file mới thì xoá
/// cache biên dịch cũ), nên không cần chạy "Đo tự động" trước. Dùng chung gói + cache với "Đo tự động".
@MainActor
@Observable
final class VieNeuCoreMLLoadProbe {
    enum ProbeError: LocalizedError {
        case manifestUnreadable

        var errorDescription: String? {
            switch self {
            case .manifestUnreadable: return "Không đọc được manifest gói Core ML sau khi tải — thử lại."
            }
        }
    }

    let package: VieNeuCoreMLPackage?

    /// Dựng được thư mục gói (lượt đo tự tải gói nếu thiếu / cũ).
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
        isReady = package != nil
    }

    /// `prepare` (màn thử) dừng TTS + các lượt khác, nhả Turbo và engine Nano — chạy xong mới tải gói / đo, để CPU của
    /// tiến trình chỉ là phần nạp.
    func start(prepare: @escaping @MainActor () async -> Void) {
        guard canRun, let package else { return }
        isRunning = true
        errorMessage = nil
        summaryLines = []
        hasReport = false
        report = ""
        statusLine = "Đang chuẩn bị (dừng TTS, nhả model đang nạp)…"
        AppLogger.shared.log("🎙️ [VieNeuCoreMLLoad] Bắt đầu đo nạp — \(ProcessMemoryProbe.snapshot().summary)")
        runTask = Task { [weak self] in
            await prepare()
            do {
                // Bấm Dừng trong lúc chuẩn bị: đừng tải / đo.
                try Task.checkCancellation()
                self?.statusLine = "Đang kiểm gói Core ML…"
                let download = try await package.download { [weak self] name, done, total in
                    Task { @MainActor [weak self] in
                        guard let self, self.isRunning else { return }
                        let percent = total > 0 ? Int(Double(done) / Double(total) * 100) : 0
                        self.statusLine = "Kiểm / tải gói Core ML \(percent)%: \(name)…"
                    }
                }
                guard let manifest = package.manifest else { throw ProbeError.manifestUnreadable }
                let note = download.downloadedFiles == 0
                    ? "gói không đổi"
                    : "tải lại \(download.downloadedFiles) file (\(ByteCountFormatter.string(fromByteCount: download.downloadedBytes, countStyle: .file)))"
                        + (download.clearedCache ? ", đã xoá bản biên dịch cũ" : "")
                try Task.checkCancellation()
                let progress: @Sendable (String) -> Void = { [weak self] line in
                    Task { @MainActor [weak self] in
                        guard let self, self.isRunning else { return }
                        self.statusLine = line
                    }
                }
                let compute = Task.detached(priority: .userInitiated) {
                    try VieNeuCoreMLLoadWorker.run(package: package, manifest: manifest, downloadNote: note, progress: progress)
                }
                self?.computeTask = compute
                let outcome = try await compute.value
                self?.finish(outcome)
            } catch is CancellationError {
                self?.statusLine = "Đã dừng."
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
