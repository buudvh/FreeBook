import CryptoKit
import Foundation
import Observation

/// Trạng thái + việc tải / chuẩn bị của **"Tăng tốc Core ML"** cho trình đọc Nano (P2c, cách B; **luôn bật** từ 1.3.919) —
/// hàng giọng Nano của sheet chọn giọng, hàng "Giọng đọc" và trang Cài đặt VieNeu TTS đọc ở đây. Backend dùng thật nằm ở
/// `VieNeuCoreMLReaderRoute` (gọi được từ luồng tổng hợp).
///
/// Một lần, tự chạy (`prepareIfNeeded`) khi tải xong gói Nano (`ModelDownloadCenter`) hoặc lúc engine Nano khởi động mà gói
/// chưa qua tự kiểm: tải gói ghim commit (`VieNeuCoreMLPackage.revision`, ~267 MB) → biên dịch 7 graph (~20 s, định
/// dạng 3) → **tự kiểm golden** → ghi dấu `reader-verified.json` → gắn backend cho trình đọc. Tự kiểm không qua ⇒ không
/// gắn, trình đọc giữ ORT (chất lượng y hệt là ràng buộc cứng). Các lần mở app sau: engine Nano khởi động thì nạp sẵn +
/// chạy nháp (`VieNeuCoreMLReaderRoute.warmUpIfReady`), không biên dịch / tự kiểm lại. Tải gói mới (file đổi) hay xoá gói
/// đều xoá dấu tự kiểm theo (`VieNeuCoreMLPackage.deleteCache`).
@MainActor
@Observable
final class VieNeuCoreMLAccelerator {
    static let shared = VieNeuCoreMLAccelerator()

    enum Phase: Equatable {
        case idle
        case downloading
        case preparing
    }

    /// Dấu "đã qua tự kiểm": gói + bản biên dịch nào đã được kiểm.
    struct VerifiedMarker: Codable {
        let revision: String
        let manifestSha256: String
        let compiledEntries: Int
        let verifiedAt: Date
        let appVersion: String
    }

    enum PrepareError: LocalizedError {
        case manifestUnreadable
        case selfTestFailed

        var errorDescription: String? {
            switch self {
            case .manifestUnreadable: return "Không đọc được manifest gói Core ML sau khi tải — thử lại."
            case .selfTestFailed: return "Tự kiểm chất lượng Core ML không qua — trình đọc giữ ORT. Gửi log cho Javis."
            }
        }
    }

    let package: VieNeuCoreMLPackage?
    /// Byte đã kiểm / tải của gói và tổng gói, lúc `phase == .downloading` — cho dòng "tải 52% · 139 / 267 MB".
    private(set) var downloadedBytes: Int64 = 0
    private(set) var downloadTotalBytes: Int64 = 0
    /// Bước đang chạy lúc `phase == .preparing` ("biên dịch 3/7", "tự kiểm chất lượng") + phần đã xong (nếu biết).
    private(set) var preparingStage = "biên dịch"
    private(set) var preparingFraction: Double?
    /// Số bản biên dịch đang có trong cache (đọc ở `refresh`).
    private(set) var compiledCount = 0
    /// Lượt **tự** chuẩn bị trong tiến trình này đã lỗi ⇒ không tự thử lại tới lần mở app sau (tự kiểm hỏng cố định thì
    /// khỏi biên dịch + tự kiểm lại mỗi lần engine khởi động).
    @ObservationIgnored private var autoPrepareFailed = false
    private(set) var phase: Phase = .idle
    private(set) var statusLine = ""
    private(set) var downloadFraction: Double?
    private(set) var errorMessage: String?
    private(set) var isPackageComplete = false
    private(set) var isVerified = false
    private(set) var packageBytes: Int64 = 0
    private(set) var cacheBytes: Int64 = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    private init() {
        package = try? VieNeuCoreMLPackage()
        refresh()
    }

    var isBusy: Bool { phase != .idle }

    /// Core ML luôn bật (1.3.919): model Nano đã đủ mà gói chưa qua tự kiểm ⇒ tải + biên dịch + tự kiểm ở nền. Gọi khi tải
    /// xong gói Nano (`ModelDownloadCenter`) và khi engine Nano khởi động (`VieNeuCoreMLReaderRoute.warmUpIfReady`).
    func prepareIfNeeded(reason: String) {
        refresh()
        guard !isBusy, !isVerified, !autoPrepareFailed, (try? VieNeuModelStore())?.isReady == true else { return }
        AppLogger.shared.log("🎙️ [VieNeuCoreML] Tự chuẩn bị Tăng tốc Core ML (\(reason))")
        prepare(isAutomatic: true)
    }

    /// Dòng phụ ngắn cho hàng giọng Nano / hàng "Giọng đọc" / trang Cài đặt VieNeu lúc đang chuẩn bị; `nil` khi rảnh.
    var stageText: String? {
        switch phase {
        case .idle:
            return nil
        case .downloading:
            guard downloadTotalBytes > 0 else { return "Tăng tốc Core ML · kiểm gói" }
            let percent = Int((Double(downloadedBytes) / Double(downloadTotalBytes) * 100).rounded())
            return "Tăng tốc Core ML · tải \(percent)% · \(Self.megabytes(downloadedBytes)) / \(Self.megabytes(downloadTotalBytes))"
        case .preparing:
            return "Tăng tốc Core ML · \(preparingStage)"
        }
    }

    /// Phần đã xong của bước đang chạy (thanh mảnh dưới `stageText`); `nil` = chưa biết (thanh chạy vô định).
    var stageFraction: Double? {
        switch phase {
        case .idle: return nil
        case .downloading: return downloadTotalBytes > 0 ? min(1, Double(downloadedBytes) / Double(downloadTotalBytes)) : nil
        case .preparing: return preparingFraction
        }
    }

    nonisolated private static func megabytes(_ bytes: Int64) -> String {
        String(format: "%.0f MB", Double(bytes) / 1_000_000)
    }

    /// "Biên dịch / nạp 3/7: ve T96…" ⇒ ("biên dịch 3/7", 3/7); "Tự kiểm…" ⇒ ("tự kiểm chất lượng", nil).
    nonisolated private static func stage(from line: String) -> (text: String, fraction: Double?) {
        let prefix = "Biên dịch / nạp "
        if line.hasPrefix(prefix), let colon = line.firstIndex(of: ":") {
            let step = String(line[line.index(line.startIndex, offsetBy: prefix.count)..<colon])
            let parts = step.split(separator: "/").compactMap { Double($0) }
            let fraction = parts.count == 2 && parts[1] > 0 ? parts[0] / parts[1] : nil
            return ("biên dịch \(step)", fraction)
        }
        if line.contains("Tự kiểm") { return ("tự kiểm chất lượng", nil) }
        return ("chuẩn bị", nil)
    }

    func refresh() {
        guard !isBusy else { return }
        guard let package else {
            isPackageComplete = false
            isVerified = false
            return
        }
        isPackageComplete = package.isComplete
        isVerified = Self.isVerified(package: package)
        packageBytes = package.packageBytes
        cacheBytes = package.cacheBytes
        compiledCount = VieNeuCoreMLCacheInventory.scan(package.cacheDirectory).filter { $0.compiledURL != nil }.count
    }

    // MARK: - Chuẩn bị

    /// Tải (phần đổi, theo sha256) → biên dịch 7 graph → tự kiểm → ghi dấu → gắn backend cho trình đọc.
    func prepare(isAutomatic: Bool = false) {
        guard !isBusy, let package else { return }
        errorMessage = nil
        downloadFraction = nil
        downloadedBytes = 0
        downloadTotalBytes = 0
        preparingStage = "biên dịch"
        preparingFraction = nil
        phase = .downloading
        statusLine = "Đang kiểm gói Core ML…"
        task = Task { [weak self] in
            do {
                VieNeuCoreMLReaderRoute.shared.release(reason: "chuẩn bị lại")
                try await package.download { [weak self] name, done, total in
                    Task { @MainActor [weak self] in
                        guard let self, self.phase == .downloading else { return }
                        self.downloadFraction = total > 0 ? min(1, Double(done) / Double(total)) : nil
                        self.downloadedBytes = done
                        self.downloadTotalBytes = total
                        self.statusLine = "Kiểm / tải gói: \(name)…"
                    }
                }
                guard let manifest = package.manifest else { throw PrepareError.manifestUnreadable }
                self?.phase = .preparing
                self?.downloadFraction = nil
                let progress: @Sendable (String) -> Void = { [weak self] line in
                    Task { @MainActor [weak self] in
                        guard let self, self.phase == .preparing else { return }
                        self.statusLine = line
                        let stage = Self.stage(from: line)
                        self.preparingStage = stage.text
                        self.preparingFraction = stage.fraction
                    }
                }
                let backend = try await Task.detached(priority: .userInitiated) {
                    try Self.compileAndVerify(package: package, manifest: manifest, progress: progress)
                }.value
                VieNeuCoreMLReaderRoute.shared.install(backend)
                // Tự kiểm vừa chạy mọi khung nhưng không đánh dấu "đã chạy nháp" ⇒ chạy nháp cho trạng thái giống lúc mở app
                // (và log có dòng "Nạp sẵn + chạy nháp"); session đã nạp nên chỉ tốn vài chục ms mỗi khung.
                Self.warmUpInBackground()
                self?.statusLine = "Sẵn sàng — trình đọc dùng Core ML khi đọc Nano."
            } catch is CancellationError {
                self?.statusLine = "Đã dừng."
            } catch {
                self?.errorMessage = error.localizedDescription
                self?.statusLine = ""
                if isAutomatic { self?.autoPrepareFailed = true }
                // Biên dịch / tự kiểm hỏng ⇒ bỏ bản biên dịch dở (app bị tắt giữa chừng cũng để lại mục hỏng) để lần sau
                // biên dịch sạch; gói tải về giữ nguyên.
                if self?.phase == .preparing {
                    VieNeuCoreMLReaderRoute.shared.release(reason: "chuẩn bị lỗi")
                    package.deleteCache()
                }
                AppLogger.shared.log("❌ [VieNeuCoreML] Chuẩn bị lỗi: \(error.localizedDescription)")
            }
            self?.phase = .idle
            self?.downloadFraction = nil
            self?.downloadedBytes = 0
            self?.downloadTotalBytes = 0
            self?.preparingFraction = nil
            self?.refresh()
        }
    }

    func cancel() {
        task?.cancel()
        statusLine = "Đang dừng sau bước hiện tại…"
    }

    /// "Xoá dữ liệu Nano" (nhấn giữ giọng Nano ở sheet chọn giọng): nhả backend rồi xoá gói + bản biên dịch. Đang chuẩn bị
    /// ⇒ bỏ qua (bên gọi `cancel()` trước).
    func deleteData() {
        guard !isBusy, let package else { return }
        VieNeuCoreMLReaderRoute.shared.release(reason: "xoá gói Core ML")
        package.deletePackageAndCache()
        statusLine = ""
        errorMessage = nil
        refresh()
    }

    /// Biên dịch / nạp đủ graph rồi tự kiểm golden; qua thì ghi dấu và trả backend (session đã nạp, đã chạy).
    nonisolated static func compileAndVerify(
        package: VieNeuCoreMLPackage,
        manifest: VieNeuCoreMLPackage.Manifest,
        progress: @Sendable (String) -> Void
    ) throws -> VieNeuCoreMLFlowBackend {
        let graphs = manifest.veBuckets.sorted().map { ("ve", $0) } + manifest.codecBuckets.sorted().map { ("codec", $0) }
        let backend = VieNeuCoreMLFlowBackend(package: package, manifest: manifest, sessionCap: graphs.count, isReader: true)
        let started = ProcessInfo.processInfo.systemUptime
        for (index, (kind, bucket)) in graphs.enumerated() {
            try Task.checkCancellation()
            progress("Biên dịch / nạp \(index + 1)/\(graphs.count): \(kind) T\(bucket)…")
            try backend.loadSession(kind: kind, bucket: bucket)
        }
        let compileSeconds = ProcessInfo.processInfo.systemUptime - started
        progress("Tự kiểm chất lượng…")
        let verification = try VieNeuCoreMLPreparer.verify(backend: backend, progress: progress)
        for line in verification.lines { AppLogger.shared.log("🎙️ [VieNeuCoreML] Tự kiểm: \(line)") }
        guard verification.passed else {
            backend.releaseSessions()
            throw PrepareError.selfTestFailed
        }
        backend.resetStats()
        let compiled = VieNeuCoreMLCacheInventory.scan(package.cacheDirectory).filter { $0.compiledURL != nil }.count
        try writeMarker(package: package, compiledEntries: compiled)
        AppLogger.shared.log(String(
            format: "🎙️ [VieNeuCoreML] Chuẩn bị xong: %ld graph trong %.1f s, %ld bản biên dịch, qua tự kiểm",
            graphs.count, compileSeconds, compiled
        ))
        return backend
    }

    // MARK: - Dấu tự kiểm

    /// Gói hiện tại đủ file, bản biên dịch còn đủ, và đã qua tự kiểm với **đúng** manifest + commit này.
    nonisolated static func isVerified(package: VieNeuCoreMLPackage) -> Bool {
        guard package.isComplete,
              let data = try? Data(contentsOf: package.readerVerifiedMarkerURL),
              let marker = try? JSONDecoder().decode(VerifiedMarker.self, from: data),
              marker.revision == VieNeuCoreMLPackage.revision,
              marker.manifestSha256 == manifestSha256(package) else { return false }
        let compiled = VieNeuCoreMLCacheInventory.scan(package.cacheDirectory).filter { $0.compiledURL != nil }.count
        return compiled >= marker.compiledEntries
    }

    nonisolated private static func writeMarker(package: VieNeuCoreMLPackage, compiledEntries: Int) throws {
        let marker = VerifiedMarker(
            revision: VieNeuCoreMLPackage.revision, manifestSha256: manifestSha256(package),
            compiledEntries: compiledEntries, verifiedAt: Date(), appVersion: AppVersionInfo.display
        )
        try FileManager.default.createDirectory(at: package.resultsURL, withIntermediateDirectories: true)
        try JSONEncoder().encode(marker).write(to: package.readerVerifiedMarkerURL, options: .atomic)
    }

    nonisolated private static func manifestSha256(_ package: VieNeuCoreMLPackage) -> String {
        guard let data = try? Data(contentsOf: package.url(VieNeuCoreMLPackage.manifestName)) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Chuẩn bị xong ⇒ nạp sẵn + chạy nháp ngay (không chờ lần engine khởi động sau).
    private static func warmUpInBackground() {
        Task.detached(priority: .utility) {
            VieNeuTTSService.shared?.warmUpCoreMLForReader()
        }
    }
}
