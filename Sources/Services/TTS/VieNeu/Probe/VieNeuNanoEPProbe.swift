import Foundation
import Observation

/// Trạng thái phép thử P1 **"So EP cho Nano"** ở màn thử VieNeu Turbo: tải / xoá gói graph tĩnh, chạy các cấu hình
/// (ORT CPU, Core ML CPU-only / GPU / Neural Engine, XNNPACK), giữ báo cáo + WAV để chia sẻ.
///
/// Không đụng đường đọc truyện. View chỉ đọc; phần tính ở `VieNeuNanoEPWorker`, chạy trong `Task.detached`.
@MainActor
@Observable
final class VieNeuNanoEPProbe {
    let package: VieNeuNanoStaticPackage?

    private(set) var isPackageReady = false
    private(set) var packageBytes: Int64 = 0
    private(set) var isDownloading = false
    /// `nil` = chưa biết tổng (vòng xoay), còn lại 0…1.
    private(set) var downloadFraction: Double?
    private(set) var downloadMessage = ""
    private(set) var isRunning = false
    private(set) var statusLine = ""
    private(set) var summaryLines: [String] = []
    private(set) var errorMessage: String?
    private(set) var wavURLs: [URL] = []
    private(set) var hasReport = false

    @ObservationIgnored private var report = ""
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var computeTask: Task<VieNeuNanoEPWorker.Outcome, Error>?

    init() {
        package = try? VieNeuNanoStaticPackage()
        refresh()
    }

    var canRun: Bool { isPackageReady && !isRunning && !isDownloading }

    func refresh() {
        isPackageReady = package?.isComplete ?? false
        packageBytes = package?.bytesOnDisk ?? 0
    }

    // MARK: - Gói

    func download() {
        guard !isDownloading, !isRunning, let package else { return }
        isDownloading = true
        errorMessage = nil
        downloadFraction = nil
        downloadMessage = "Đang tải manifest…"
        let onProgress: @Sendable (String, Int64, Int64) -> Void = { [weak self] name, done, total in
            Task { @MainActor [weak self] in self?.updateDownload(name: name, done: done, total: total) }
        }
        Task { [weak self] in
            do {
                try await package.download(progress: onProgress)
            } catch {
                self?.errorMessage = "Tải gói thất bại: \(error.localizedDescription)"
                AppLogger.shared.log("❌ [VieNeuProbe] Tải gói lỗi: \(error.localizedDescription)")
            }
            self?.isDownloading = false
            self?.downloadFraction = nil
            self?.downloadMessage = ""
            self?.refresh()
        }
    }

    func deletePackage() {
        guard !isRunning, !isDownloading, let package else { return }
        do {
            try package.deleteAll()
            wavURLs = []
            summaryLines = []
            hasReport = false
            report = ""
        } catch {
            errorMessage = "Xoá gói thất bại: \(error.localizedDescription)"
        }
        refresh()
    }

    private func updateDownload(name: String, done: Int64, total: Int64) {
        guard isDownloading else { return }
        downloadFraction = total > 0 ? min(1, Double(done) / Double(total)) : nil
        downloadMessage = "Đang tải \(name)…"
    }

    // MARK: - Chạy

    /// `prepare` (màn thử) dừng TTS, nhả Turbo + engine Nano để đủ RAM — chạy xong mới bắt đầu tính.
    func start(prepare: @escaping @MainActor () async -> Void) {
        guard canRun, let package, let manifest = package.manifest else { return }
        isRunning = true
        errorMessage = nil
        summaryLines = []
        wavURLs = []
        hasReport = false
        report = ""
        statusLine = "Đang chuẩn bị (dừng TTS, nhả model đang nạp)…"
        AppLogger.shared.log("🎙️ [VieNeuProbe] Bắt đầu So EP — \(ProcessMemoryProbe.snapshot().summary)")
        runTask = Task { [weak self] in
            await prepare()
            let progress: @Sendable (String) -> Void = { [weak self] line in
                Task { @MainActor [weak self] in
                    guard let self, self.isRunning else { return }
                    self.statusLine = line
                }
            }
            let compute = Task.detached(priority: .userInitiated) {
                try VieNeuNanoEPWorker.runAll(package: package, manifest: manifest, progress: progress)
            }
            self?.computeTask = compute
            do {
                let outcome = try await compute.value
                self?.finish(outcome)
            } catch is CancellationError {
                self?.statusLine = "Đã dừng."
            } catch {
                self?.errorMessage = "So EP lỗi: \(error.localizedDescription)"
                AppLogger.shared.log("❌ [VieNeuProbe] So EP lỗi: \(error.localizedDescription)")
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
        statusLine = "Đang dừng sau lượt chạy hiện tại…"
    }

    private func finish(_ outcome: VieNeuNanoEPWorker.Outcome) {
        report = outcome.report
        summaryLines = outcome.summary
        wavURLs = outcome.wavURLs
        hasReport = true
        statusLine = "Xong — chia sẻ file kết quả để gửi."
    }

    /// Thân file `.txt` (`VieNeuTurboReportFile` thêm phần đầu: app, máy, giờ).
    func reportText() -> String {
        report.isEmpty ? (errorMessage ?? statusLine) : report
    }
}
