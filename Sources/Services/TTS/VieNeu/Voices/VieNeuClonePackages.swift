import Foundation

/// **Gói cần cho nhân bản giọng VieNeu** (1.3.901) — dùng chung cho sheet nhân bản và nút "Tạo bản Turbo":
/// - Nano: model Nano (8 file — giọng tạo xong mới đọc được, `constants.npz` cũng cần lúc nhân bản) + gói nhân bản Nano
///   (`speaker_encoder` / `codec_encoder` / `reference_encoder`).
/// - Turbo: model Turbo (GGUF + manifest + `sea_g2p.bin`) + gói nhân bản Turbo (`speaker_encoder` + `denoiser`). Luôn tải
///   đủ hai file kể cả khi tắt khử nhiễu — một lượt tải, khỏi tải lại lúc bật khử nhiễu lần sau.
///
/// Tải qua `ModelDownloadCenter` (các lượt VieNeu xếp hàng lần lượt, nên `speaker_encoder.onnx` dùng chung không bị hai
/// lượt cùng ghi). Hàm `missingBytes` chỉ kiểm file tồn tại — rẻ, gọi khi đổi lựa chọn chứ không trong `body`.
@MainActor
enum VieNeuClonePackages {
    enum PackageError: LocalizedError {
        case blocked
        case failed(String)
        case incomplete

        var errorDescription: String? {
            switch self {
            case .blocked: return "Màn thử VieNeu Turbo đang tải model — chờ lượt đó xong rồi lưu."
            case .failed(let reason): return "Tải gói thất bại: \(reason)"
            case .incomplete: return "Chưa tải đủ gói cần thiết (lượt tải đã bị huỷ?)."
            }
        }
    }

    /// Byte còn phải tải cho lựa chọn (file dùng chung chỉ tính một lần).
    static func missingBytes(nano: Bool, turbo: Bool) -> Int64 {
        guard let nanoStore = try? VieNeuModelStore() else { return 0 }
        var names = Set<String>()
        if nano { names.formUnion(VieNeuModelStore.requiredNames + VieNeuModelStore.cloneGraphNames) }
        if turbo { names.formUnion(["sea_g2p.bin"] + VieNeuModelStore.turboCloneGraphNames) }
        var bytes = nanoStore.missingBytes(of: Array(names))
        if turbo, let turboStore = try? VieNeuTurboModelStore(), !turboStore.hasModel {
            bytes += VieNeuTurboModelStore.modelByteCount
        }
        return bytes
    }

    /// Đủ gói chưa (kiểm file trên máy).
    static func isReady(nano: Bool, turbo: Bool) -> Bool {
        guard let nanoStore = try? VieNeuModelStore() else { return false }
        if nano, !(nanoStore.isReady && nanoStore.hasCloneGraphs) { return false }
        if turbo {
            guard let turboStore = try? VieNeuTurboModelStore() else { return false }
            let turboReady = turboStore.hasModel && turboStore.hasManifest && nanoStore.exists("sea_g2p.bin")
            if !(turboReady && nanoStore.hasTurboCloneGraphs) { return false }
        }
        return true
    }

    /// Các đích của một lượt `ensure`: `all` để cộng tiến độ; `owned` = đích **chính lượt này khởi tạo** — huỷ lượt lưu chỉ
    /// được huỷ các đích này, không huỷ lượt tải người dùng tự bấm ở sheet chọn giọng (lượt đó chỉ được chờ ké).
    struct Jobs {
        var all: [String] = []
        var owned: [String] = []
    }

    /// Bắt đầu mọi lượt tải còn thiếu, báo các đích qua `onStart` (để View cộng tiến độ / để huỷ), rồi chờ lần lượt. Lượt
    /// nào lỗi / bị huỷ ⇒ ném; xong hết vẫn kiểm lại file trên máy.
    static func ensure(nano: Bool, turbo: Bool, onStart: (Jobs) -> Void) async throws {
        typealias Target = ModelDownloadCenter.Target
        let center = ModelDownloadCenter.shared
        guard let nanoStore = try? VieNeuModelStore() else { throw PackageError.incomplete }
        var jobs: [(id: String, task: Task<Void, Never>?, owned: Bool)] = []
        func add(_ id: String, _ start: () -> Task<Void, Never>?) {
            let alreadyRunning = center.isRunning(id: id)
            jobs.append((id, start(), !alreadyRunning))
        }
        if nano {
            if !nanoStore.isReady { add(Target.vieNeuModel) { center.startVieNeuModel() } }
            if !nanoStore.hasCloneGraphs { add(Target.vieNeuClone) { center.startVieNeuCloneGraphs() } }
        }
        if turbo, let turboStore = try? VieNeuTurboModelStore() {
            if !turboStore.hasModel || !turboStore.hasManifest || !nanoStore.exists("sea_g2p.bin") {
                add(Target.vieNeuTurboModel) { center.startVieNeuTurbo(voiceId: nil, title: "Model VieNeu Turbo") }
            }
            if !nanoStore.hasTurboCloneGraphs { add(Target.vieNeuTurboClone) { center.startVieNeuTurboClonePack() } }
        }
        let owned = jobs.filter { $0.owned && $0.task != nil }.map { $0.id }
        guard !jobs.contains(where: { $0.task == nil }) else {
            owned.forEach { center.cancel(id: $0) }
            throw PackageError.blocked
        }
        onStart(Jobs(all: jobs.map { $0.id }, owned: owned))
        for job in jobs {
            let state = await center.waitForJob(id: job.id)
            if case .failed(let reason) = state { throw PackageError.failed(reason) }
        }
        guard isReady(nano: nano, turbo: turbo) else { throw PackageError.incomplete }
    }

    /// Tiến độ cộng dồn của các đích (byte đã tải / `total`), từ dòng của `ModelDownloadCenter`.
    static func completedBytes(targets: [String], in entries: [ModelDownloadCenter.Entry]) -> Int64 {
        entries.filter { targets.contains($0.id) }.reduce(Int64(0)) { $0 + $1.completedBytes }
    }
}
