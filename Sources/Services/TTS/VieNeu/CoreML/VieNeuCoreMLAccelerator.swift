import CryptoKit
import Foundation
import Observation

/// Trạng thái + việc tải / chuẩn bị của **"Tăng tốc Core ML"** cho trình đọc Nano (P2c, cách B) — mục ở Cài đặt VieNeu
/// TTS đọc ở đây. Backend dùng thật nằm ở `VieNeuCoreMLReaderRoute` (gọi được từ luồng tổng hợp).
///
/// Một lần sau khi bật: tải gói ghim commit (`VieNeuCoreMLPackage.revision`, ~267 MB) → biên dịch 7 graph (~20 s, định
/// dạng 3) → **tự kiểm golden** → ghi dấu `reader-verified.json` → gắn backend cho trình đọc. Tự kiểm không qua ⇒ không
/// gắn, trình đọc giữ ORT (chất lượng y hệt là ràng buộc cứng). Các lần mở app sau: engine Nano khởi động thì nạp sẵn +
/// chạy nháp (`VieNeuCoreMLReaderRoute.warmUpIfEnabled`), không biên dịch / tự kiểm lại.
///
/// Dùng chung gói + cache với màn thử (Đo tự động, Đo nạp Core ML): xoá / tải lại ở đó thì dấu tự kiểm bị xoá theo
/// (`VieNeuCoreMLPackage.deleteCache`) và màn thử nhả backend của trình đọc trước.
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
    /// Công tắc ở Cài đặt (mặc định tắt — thử nghiệm). Đổi qua `setEnabled(_:)`.
    private(set) var isEnabled: Bool
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
        isEnabled = VieNeuCoreMLReaderRoute.isEnabled
        refresh()
    }

    var isBusy: Bool { phase != .idle }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: VieNeuCoreMLReaderRoute.enabledKey)
        if enabled {
            if isVerified { Self.warmUpInBackground() }
        } else {
            VieNeuCoreMLReaderRoute.shared.release(reason: "tắt Tăng tốc Core ML")
        }
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
    }

    // MARK: - Chuẩn bị

    /// Tải (phần đổi, theo sha256) → biên dịch 7 graph → tự kiểm → ghi dấu → gắn backend cho trình đọc.
    func prepare() {
        guard !isBusy, let package else { return }
        errorMessage = nil
        downloadFraction = nil
        phase = .downloading
        statusLine = "Đang kiểm gói Core ML…"
        task = Task { [weak self] in
            do {
                VieNeuCoreMLReaderRoute.shared.release(reason: "chuẩn bị lại")
                try await package.download { [weak self] name, done, total in
                    Task { @MainActor [weak self] in
                        guard let self, self.phase == .downloading else { return }
                        self.downloadFraction = total > 0 ? min(1, Double(done) / Double(total)) : nil
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
                AppLogger.shared.log("❌ [VieNeuCoreML] Chuẩn bị lỗi: \(error.localizedDescription)")
            }
            self?.phase = .idle
            self?.downloadFraction = nil
            self?.refresh()
        }
    }

    func cancel() {
        task?.cancel()
        statusLine = "Đang dừng sau bước hiện tại…"
    }

    /// Nút Xoá ở Cài đặt: nhả backend rồi xoá gói + bản biên dịch (giữ báo cáo của màn thử).
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

    /// Bật lại công tắc khi gói đã sẵn ⇒ nạp sẵn + chạy nháp ngay (không chờ lần engine khởi động sau).
    private static func warmUpInBackground() {
        Task.detached(priority: .utility) {
            VieNeuTTSService.shared?.warmUpCoreMLForReader()
        }
    }
}
